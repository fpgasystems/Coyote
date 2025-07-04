/**
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

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

/////////////////////////////////////////////////////////
//               CONTROL REGISTERS                    //
///////////////////////////////////////////////////////
// Parses the encryption key, set by the user from the software, using setCSR(...)
// For more details, see hdl/aes_axi_ctrl_parser.sv and the user software
logic key_valid;
logic [AXI_DATA_BITS:0] key;

aes_axi_ctrl_parser inst_aes_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .key(key),
    .key_valid(key_valid)
);

/////////////////////////////////////////////////////////
//               ENCRYPTION MODULE                    //
///////////////////////////////////////////////////////

// AES module
/* Since the AES module works on 128-bit text chunks, but our input streams are 512 bits  
 * we specify the NPAR parameter to 4, which means that the AES module will process
 * 4 chunks of 128 bits in parallel. An alternative is to use a data width converter
 * on the input and output streams, which is covered in Example 9 for AES CBC encryption
 */
aes_top #(
    .NPAR(AXI_DATA_BITS / 128)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_host_send[0].tready),

    .key_in(key),
    .keyVal_in(key_valid),
    .keyVal_out(),

    .data_in(axis_host_recv[0].tdata),
    .dVal_in(axis_host_recv[0].tvalid),
    .keep_in(axis_host_recv[0].tkeep),
    .last_in(axis_host_recv[0].tlast),
    .id_in(axis_host_recv[0].tid),

    .data_out(axis_host_send[0].tdata),
    .dVal_out(axis_host_send[0].tvalid),
    .keep_out(axis_host_send[0].tkeep),
    .last_out(axis_host_send[0].tlast),
    .id_out(axis_host_send[0].tid)
);

assign axis_host_recv[0].tready = axis_host_send[0].tready;

// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// Debug ILA
ila_aes inst_ila_aes (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),  // 1 bit
    .probe1(axis_host_recv[0].tready),  // 1 bit
    .probe2(axis_host_recv[0].tlast),   // 1 bit
    .probe3(axis_host_recv[0].tdata),   // 512 bits
    .probe4(axis_host_send[0].tvalid),  // 1 bit
    .probe5(axis_host_send[0].tready),  // 1 bit
    .probe6(axis_host_send[0].tlast),   // 1 bit
    .probe7(axis_host_send[0].tdata)    // 512 bits
);