/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Constants
// TODO: Think about increasing key rounds to 11
localparam integer KEY_ROUNDS = 4;
localparam integer N_AES_PIPELINES = 4;     // 512 (input data width) / 128 (AES block data width)

// Control registers for key
logic key_start;
logic [128-1:0] key_slv;
rdma_aes_slv inst_rdma_aes_slv (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .key_out(key_slv),
    .keyStart(key_start)
);

// Inflate decryption key
logic [128*KEY_ROUNDS-1:0] key_dec;
key_top #(
    .OPERATION(1)  
) inst_key_top_dec (
    .clk(aclk),
    .reset_n(aresetn),
    
    .stall(1'b0),

    .key_in(key_slv),
    .keyVal_in(keyStart),
    .keyVal_out(),
    .key_out(key_dec)
);

// AES pipeline - receive (decrypt)
aes_top #(
    .NPAR(N_AES_PIPELINES),
    .MODE(0),       // 0 - ECB, 1 - CTR, 2 - CBC
    .OPERATION(1)   // 0 - encryption, 1 - decryption
) inst_aes_top_dec (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_host_send[0].tready),

    .key_in(key_dec),

    .last_in(axis_rrsp_recv[0].tlast),
    .last_out(axis_host_send[0].tlast),

    .keep_in(axis_rrsp_recv[0].tkeep),
    .keep_out(axis_host_send[0].tkeep),

    .dVal_in(axis_rrsp_recv[0].tvalid),
    .dVal_out(axis_host_send[0].tvalid),

    .data_in(axis_rrsp_recv[0].tdata),
    .data_out(axis_host_send[0].tdata),

    .cntr_in(0)
);
assign axis_rrsp_recv[0].tready = axis_host_send[0].tready;

// Inflate encryption key
logic [128*KEY_ROUNDS-1:0] key_enc;
key_top #(
    .OPERATION(1)  
) inst_key_top_enc (
    .clk(aclk),
    .reset_n(aresetn),
    
    .stall(1'b0),

    .key_in(key_slv),
    .keyVal_in(keyStart),
    .keyVal_out(),
    .key_out(key_enc)
);

// AES pipeline - send (encrypt)
aes_top #(
    .NPAR(N_AES_PIPELINES),
    .MODE(0),       // 0 - ECB, 1 - CTR, 2 - CBC
    .OPERATION(0)   // 0 - encryption, 1 - decryption
) inst_aes_top_enc (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_rreq_send[0].tready),

    .key_in(key_enc),
    
    .last_in(axis_host_recv[0].tlast),
    .last_out(axis_rreq_send[0].tlast),
    
    .keep_in(axis_host_recv[0].tkeep),
    .keep_out(axis_rreq_send[0].tkeep),

    .dVal_in(axis_host_recv[0].tvalid),
    .dVal_out(axis_rreq_send[0].tvalid),
    
    .data_in(axis_host_recv[0].tdata),
    .data_out(axis_rreq_send[0].tdata),
    
    .cntr_in(0)
);
assign axis_host_recv[0].tready = axis_rreq_send[0].tready;

// Tie off unused signals
always_comb notify.tie_off_m();
always_comb cq_wr.tie_off_s();
always_comb cq_rd.tie_off_s();
always_comb sq_rd.tie_off_s();
always_comb sq_wr.tie_off_s();

// Debug ILA
ila_rdma_aes inst_ila_rdma_aes (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),  // 1
    .probe1(axis_host_recv[0].tready),  // 1
    .probe2(axis_host_recv[0].tlast),   // 1
    .probe3(axis_host_recv[0].tdata),   // 512
    .probe4(axis_host_send[0].tvalid),  // 1
    .probe5(axis_host_send[0].tready),  // 1
    .probe6(axis_host_send[0].tlast),   // 1
    .probe7(axis_host_send[0].tdata)    // 512
);
