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

module remote_credits_rd #(
    parameter N_DESTS                   = 1,
    parameter QDEPTH                    = 4
) (
    metaIntf.s                          s_req,
    metaIntf.m                          m_req,

    metaIntf.s                          s_rq,
    metaIntf.m                          m_rq,

    AXI4S.s                             s_axis,
    AXI4SR.m                            m_axis [N_DESTS],

    input  logic    					aclk,    
	input  logic    					aresetn
);

`ifdef EN_CRED_REMOTE

    // Mux
    metaIntf #(.STYPE(dreq_t)) req_dest [N_DESTS] ();

    dest_dreq_mux #(.N_DESTS(N_DESTS)) inst_mux (.aclk(aclk), .aresetn(aresetn), .s_req(s_req), .m_req(req_dest));

    //
    metaIntf #(.STYPE(dreq_t)) req_q [N_DESTS] ();
    metaIntf #(.STYPE(dreq_t)) req_parsed [N_DESTS] ();
    metaIntf #(.STYPE(dreq_t)) req_cred [N_DESTS] ();
    logic [N_DESTS-1:0] xfer;

    metaIntf #(.STYPE(logic[1+BLEN_BITS-1:0])) mux_out [N_DESTS] ();
    AXI4SR axis_resp_int [N_DESTS] ();
    AXI4SR axis_recv_int [N_DESTS] ();
    AXI4SR axis_resp_out [N_DESTS] ();
    AXI4SR axis_recv_out [N_DESTS] ();
    AXI4SR axis_out [N_DESTS] ();

    for(genvar i = 0; i < N_DESTS; i++) begin
        // Queues
        queue_meta #(.QDEPTH(QDEPTH)) inst_queue_sink (.aclk(aclk), .aresetn(aresetn), .s_meta(req_dest[i]), .m_meta(req_q[i]));
        
        // Parsing
        dreq_rdma_parser_rd inst_parser (.aclk(aclk), .aresetn(aresetn), .s_req(req_q[i]), .m_req(req_parsed[i]));

        // Credits
        dreq_credits_rd inst_credits (.aclk(aclk), .aresetn(aresetn), .s_req(req_parsed[i]), .m_req(req_cred[i]), .xfer(xfer[i]));
    end

    // Arbiter
    dest_dreq_rd_arb #(.N_DESTS(N_DESTS)) inst_arb (.aclk(aclk), .aresetn(aresetn), .s_req(req_cred), .m_req(m_req));

    // Mux data
    axis_mux_user_rq #(
        .N_DESTS(N_DESTS)
    ) inst_mux_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_rq(s_rq),
        .m_rq(m_rq),
        .m_mux(mux_out),
        .s_axis(s_axis),
        .m_axis_resp(axis_resp_int),
        .m_axis_recv(axis_recv_int)
    );

    for(genvar i = 0; i < N_DESTS; i++) begin
        axisr_data_fifo_512 inst_resp_cq (
            .s_axis_aresetn(aresetn),
            .s_axis_aclk(aclk),
            .s_axis_tvalid(axis_resp_int[i].tvalid),
            .s_axis_tready(axis_resp_int[i].tready),
            .s_axis_tdata (axis_resp_int[i].tdata),
            .s_axis_tkeep (axis_resp_int[i].tkeep),
            .s_axis_tlast (axis_resp_int[i].tlast),
            .s_axis_tid   (axis_resp_int[i].tid),
            .m_axis_tvalid(axis_resp_out[i].tvalid),
            .m_axis_tready(axis_resp_out[i].tready),
            .m_axis_tdata (axis_resp_out[i].tdata),
            .m_axis_tkeep (axis_resp_out[i].tkeep),
            .m_axis_tlast (axis_resp_out[i].tlast),
            .m_axis_tid   (axis_resp_out[i].tid)
        );

        axisr_data_fifo_512 inst_recv_cq (
            .s_axis_aresetn(aresetn),
            .s_axis_aclk(aclk),
            .s_axis_tvalid(axis_recv_int[i].tvalid),
            .s_axis_tready(axis_recv_int[i].tready),
            .s_axis_tdata (axis_recv_int[i].tdata),
            .s_axis_tkeep (axis_recv_int[i].tkeep),
            .s_axis_tlast (axis_recv_int[i].tlast),
            .s_axis_tid   (axis_recv_int[i].tid),
            .m_axis_tvalid(axis_recv_out[i].tvalid),
            .m_axis_tready(axis_recv_out[i].tready),
            .m_axis_tdata (axis_recv_out[i].tdata),
            .m_axis_tkeep (axis_recv_out[i].tkeep),
            .m_axis_tlast (axis_recv_out[i].tlast),
            .m_axis_tid   (axis_recv_out[i].tid)
        );

        axis_mux_user_out inst_mux_user_out (
            .aclk(aclk),
            .aresetn(aresetn),
            .mux(mux_out[i]),
            .s_axis_resp(axis_resp_out[i]),
            .s_axis_recv(axis_recv_out[i]),
            .m_axis(axis_out[i])
        );

        axisr_reg inst_out_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_out[i]), .m_axis(m_axis[i]));

        assign xfer[i] = axis_resp_out[i].tvalid & axis_resp_out[i].tready;
    end

`else

    //
    AXI4SR axis_out [N_DESTS] ();

    // Mux
    queue_meta #(.QDEPTH(QDEPTH)) inst_queue_sink (.aclk(aclk), .aresetn(aresetn), .s_meta(s_req), .m_meta(m_req));

    // Mux data
    axis_assign_rq #(
        .N_DESTS(N_DESTS)
    ) inst_assign_rq (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_rq(s_rq),
        .m_rq(m_rq),
        .s_axis(s_axis),
        .m_axis(axis_out)
    ); 

    for(genvar i = 0; i < N_DESTS; i++) begin
        axisr_data_fifo_512 inst_resp_cq (
            .s_axis_aresetn(aresetn),
            .s_axis_aclk(aclk),
            .s_axis_tvalid(axis_out[i].tvalid),
            .s_axis_tready(axis_out[i].tready),
            .s_axis_tdata (axis_out[i].tdata),
            .s_axis_tkeep (axis_out[i].tkeep),
            .s_axis_tlast (axis_out[i].tlast),
            .s_axis_tid   (axis_out[i].tid),
            .m_axis_tvalid(m_axis[i].tvalid),
            .m_axis_tready(m_axis[i].tready),
            .m_axis_tdata (m_axis[i].tdata),
            .m_axis_tkeep (m_axis[i].tkeep),
            .m_axis_tlast (m_axis[i].tlast),
            .m_axis_tid   (m_axis[i].tid)
        );
    end


`endif 

endmodule