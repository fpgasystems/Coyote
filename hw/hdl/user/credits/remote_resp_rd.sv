/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
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

`timescale 1ns / 1ps

import lynxTypes::*;

module remote_resp_rd #(
    parameter N_DESTS                   = 1,
    parameter QDEPTH                    = 4
) (
    metaIntf.s                          s_rq,
    metaIntf.m                          m_rq,

    AXI4SR.s                            s_axis [N_DESTS],
    AXI4S.m                             m_axis,

    input  logic    					aclk,    
	input  logic    					aresetn
);

    // Mux
    metaIntf #(.STYPE(req_t)) req_q ();
    metaIntf #(.STYPE(mux_user_t)) mux ();

    AXI4S axis_int [N_DESTS] ();
    AXI4S axis_int_2 [N_DESTS] ();

    queue_meta #(.QDEPTH(QDEPTH)) inst_queue_sink (.aclk(aclk), .aresetn(aresetn), .s_meta(s_rq), .m_meta(req_q));

    //
    dest_req_seq inst_dest_seq (.aclk(aclk), .aresetn(aresetn), .s_req(req_q), .m_req(m_rq), .mux(mux));

    axis_mux_user_wr #(
        .N_DESTS(N_DESTS)
    ) inst_mux_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis(axis_int),
        .m_axis(m_axis),
        .mux(mux)
    );

    for(genvar i = 0; i < N_DESTS; i++) begin
        axis_reg inst_dq_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_int_2[i]), .m_axis(axis_int[i]));

        axis_data_fifo_512 inst_cq (
            .s_axis_aresetn(aresetn),
            .s_axis_aclk(aclk),
            .s_axis_tvalid(s_axis[i].tvalid),
            .s_axis_tready(s_axis[i].tready),
            .s_axis_tdata (s_axis[i].tdata),
            .s_axis_tkeep (s_axis[i].tkeep),
            .s_axis_tlast (s_axis[i].tlast),
            .m_axis_tvalid(axis_int_2[i].tvalid),
            .m_axis_tready(axis_int_2[i].tready),
            .m_axis_tdata (axis_int_2[i].tdata),
            .m_axis_tkeep (axis_int_2[i].tkeep),
            .m_axis_tlast (axis_int_2[i].tlast)
        );
    end

endmodule