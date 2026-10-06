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

// Test design for meta_reg, meta_ccross and meta_queue. Every beat of host stream 0 is split over
// chains of different widths, each a meta_reg, a meta_ccross and a meta_queue in series, and put
// back together on host stream 0: chain 0 carries tlast, chain 1 tid, and the others the low 408
// bits of tdata. The upper tdata bits come back as zero.
//
// Every width but 96 lacks an IP of its own in at least one of the three modules: 1, 6 (tid),
// 11, 13, 34 (mux_user_t with PID_BITS = 8), 38 (irq_not_t), 56, 72 and 88 (tcp_notify_t).

localparam integer N_CHAINS = 10;
localparam integer CHAIN_BITS [N_CHAINS] = '{1, PID_BITS, 11, 13, 34, 38, 56, 72, 88, 96};

function automatic integer chain_offs(input integer n);
    chain_offs = 0;
    for (int i = 0; i < n; i++) chain_offs += CHAIN_BITS[i];
endfunction

localparam integer ALL_BITS = chain_offs(N_CHAINS);
localparam integer CARRIED_BITS = ALL_BITS - 1 - PID_BITS;

// The clock converter IP's output valid is undefined until its reset has crossed both clock
// domains, which takes longer than the test bench holds aresetn: the chains get a reset of their
// own, released RESET_CYCLES later
localparam integer RESET_CYCLES = 64;

logic [$clog2(RESET_CYCLES+1)-1:0] reset_cnt;
logic chain_aresetn;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        reset_cnt <= '0;
        chain_aresetn <= 1'b0;
    end
    else if (reset_cnt != RESET_CYCLES) begin
        reset_cnt <= reset_cnt + 1;
    end
    else begin
        chain_aresetn <= 1'b1;
    end
end

logic [ALL_BITS-1:0] in_bits;
logic [ALL_BITS-1:0] out_bits;
logic [N_CHAINS-1:0] in_ready;
logic [N_CHAINS-1:0] out_valid;

assign in_bits = {axis_host_recv[0].tdata[CARRIED_BITS-1:0], axis_host_recv[0].tid, axis_host_recv[0].tlast};

for (genvar i = 0; i < N_CHAINS; i++) begin : chain
    localparam integer W = CHAIN_BITS[i];
    localparam integer OFFS = chain_offs(i);

    metaIntf #(.STYPE(logic[W-1:0])) s_chain (.aclk(aclk), .aresetn(chain_aresetn));
    metaIntf #(.STYPE(logic[W-1:0])) reg_out (.aclk(aclk), .aresetn(chain_aresetn));
    metaIntf #(.STYPE(logic[W-1:0])) ccross_out (.aclk(aclk), .aresetn(chain_aresetn));
    metaIntf #(.STYPE(logic[W-1:0])) m_chain (.aclk(aclk), .aresetn(chain_aresetn));

    // A beat enters every chain at once, and leaves them all at once
    assign s_chain.valid = chain_aresetn & axis_host_recv[0].tvalid & (&(in_ready | N_CHAINS'(1 << i)));
    assign s_chain.data = in_bits[OFFS +: W];
    assign in_ready[i] = s_chain.ready;

    meta_reg #(.DATA_BITS(W)) inst_reg (.aclk(aclk), .aresetn(chain_aresetn), .s_meta(s_chain), .m_meta(reg_out));
    meta_ccross #(.DATA_BITS(W)) inst_ccross (
        .s_aclk(aclk), .s_aresetn(chain_aresetn), .m_aclk(aclk), .m_aresetn(chain_aresetn), .s_meta(reg_out), .m_meta(ccross_out)
    );
    meta_queue #(.DATA_BITS(W)) inst_queue (.aclk(aclk), .aresetn(chain_aresetn), .s_meta(ccross_out), .m_meta(m_chain));

    assign m_chain.ready = axis_host_send[0].tready & (&(out_valid | N_CHAINS'(1 << i)));
    assign out_valid[i] = m_chain.valid;
    assign out_bits[OFFS +: W] = m_chain.data;
end

assign axis_host_recv[0].tready = chain_aresetn & (&in_ready);

assign axis_host_send[0].tvalid = chain_aresetn & (&out_valid);
assign axis_host_send[0].tdata = {{(AXI_DATA_BITS - CARRIED_BITS){1'b0}}, out_bits[ALL_BITS-1:1+PID_BITS]};
assign axis_host_send[0].tkeep = '1;
assign axis_host_send[0].tid = out_bits[PID_BITS:1];
assign axis_host_send[0].tlast = out_bits[0];

// Tie-off unused
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb axi_ctrl.tie_off_s();
