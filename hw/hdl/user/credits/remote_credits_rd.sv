/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
    AXI4SR.m                            m_axis_resp [N_DESTS],
    AXI4SR.m                            m_axis_recv [N_DESTS],

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

    AXI4SR axis_resp_int [N_DESTS] ();
    AXI4SR axis_recv_int [N_DESTS] ();

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
            .m_axis_tvalid(m_axis_resp[i].tvalid),
            .m_axis_tready(m_axis_resp[i].tready),
            .m_axis_tdata (m_axis_resp[i].tdata),
            .m_axis_tkeep (m_axis_resp[i].tkeep),
            .m_axis_tlast (m_axis_resp[i].tlast),
            .m_axis_tid   (m_axis_resp[i].tid)
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
            .m_axis_tvalid(m_axis_recv[i].tvalid),
            .m_axis_tready(m_axis_recv[i].tready),
            .m_axis_tdata (m_axis_recv[i].tdata),
            .m_axis_tkeep (m_axis_recv[i].tkeep),
            .m_axis_tlast (m_axis_recv[i].tlast),
            .m_axis_tid   (m_axis_recv[i].tid)
        );

        assign xfer[i] = m_axis_resp[i].tvalid & m_axis_resp[i].tready;
    end

`else

    //
    AXI4SR axis_out [N_DESTS] ();

    // Mux
    queue_meta #(.QDEPTH(QDEPTH)) inst_queue_sink (.aclk(aclk), .aresetn(aresetn), .s_meta(s_req), .m_meta(m_req));

    AXI4SR axis_resp_int [N_DESTS] ();
    AXI4SR axis_recv_int [N_DESTS] ();

    // Mux data
    axis_mux_user_rq #(
        .N_DESTS(N_DESTS)
    ) inst_mux_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_rq(s_rq),
        .m_rq(m_rq),
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
            .m_axis_tvalid(m_axis_resp[i].tvalid),
            .m_axis_tready(m_axis_resp[i].tready),
            .m_axis_tdata (m_axis_resp[i].tdata),
            .m_axis_tkeep (m_axis_resp[i].tkeep),
            .m_axis_tlast (m_axis_resp[i].tlast),
            .m_axis_tid   (m_axis_resp[i].tid)
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
            .m_axis_tvalid(m_axis_recv[i].tvalid),
            .m_axis_tready(m_axis_recv[i].tready),
            .m_axis_tdata (m_axis_recv[i].tdata),
            .m_axis_tkeep (m_axis_recv[i].tkeep),
            .m_axis_tlast (m_axis_recv[i].tlast),
            .m_axis_tid   (m_axis_recv[i].tid)
        );
    end


`endif 

endmodule