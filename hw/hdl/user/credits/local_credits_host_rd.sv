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

`include "axi_macros.svh"
`include "lynx_macros.svh"

module local_credits_host_rd #(
    parameter N_DESTS                   = 1,
    parameter QDEPTH                    = 4
) (
    metaIntf.s                          s_req,
    metaIntf.m                          m_req,

    AXI4S.s                             s_axis,
    AXI4SR.m                            m_axis [N_DESTS],

    input  logic    					aclk,    
	input  logic    					aresetn
);

`ifdef EN_CRED_LOCAL

    // Mux
    metaIntf #(.STYPE(req_t)) req_dest [N_DESTS] ();

    dest_req_mux #(.N_DESTS(N_DESTS)) inst_mux (.aclk(aclk), .aresetn(aresetn), .s_req(s_req), .m_req(req_dest));

    //
    metaIntf #(.STYPE(req_t)) req_q [N_DESTS] ();
    metaIntf #(.STYPE(req_t)) req_parsed [N_DESTS] ();
    metaIntf #(.STYPE(req_t)) req_cred [N_DESTS] ();
    logic [N_DESTS-1:0] xfer;
    metaIntf #(.STYPE(mux_user_t)) mux ();

    AXI4SR axis_int [N_DESTS] ();
    AXI4SR axis_int_2 [N_DESTS] ();

    // 
    for(genvar i = 0; i < N_DESTS; i++) begin
        // Queues
        queue_meta #(.QDEPTH(QDEPTH)) inst_queue_sink (.aclk(aclk), .aresetn(aresetn), .s_meta(req_dest[i]), .m_meta(req_q[i]));
        
        // Parsing
        req_parser inst_parser (.aclk(aclk), .aresetn(aresetn), .s_req(req_q[i]), .m_req(req_parsed[i]));

        // Credits
        req_credits_rd inst_credits (.aclk(aclk), .aresetn(aresetn), .s_req(req_parsed[i]), .m_req(req_cred[i]), .xfer(xfer[i]));
    end

    // Arbiter
    dest_req_arb #(.N_DESTS(N_DESTS)) inst_arb (.aclk(aclk), .aresetn(aresetn), .s_req(req_cred), .m_req(m_req), .mux(mux));

    axis_mux_user_rd #(
        .N_DESTS(N_DESTS)
    ) inst_mux_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis(s_axis),
        .m_axis(axis_int),
        .mux(mux)
    );

    for(genvar i = 0; i < N_DESTS; i++) begin
        axisr_reg inst_dq_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_int[i]), .m_axis(axis_int_2[i]));

        axisr_data_fifo_512 inst_dq (
            .s_axis_aresetn(aresetn),
            .s_axis_aclk(aclk),
            .s_axis_tvalid(axis_int_2[i].tvalid),
            .s_axis_tready(axis_int_2[i].tready),
            .s_axis_tdata (axis_int_2[i].tdata),
            .s_axis_tkeep (axis_int_2[i].tkeep),
            .s_axis_tlast (axis_int_2[i].tlast),
            .s_axis_tid   (axis_int_2[i].tid),
            .m_axis_tvalid(m_axis[i].tvalid),
            .m_axis_tready(m_axis[i].tready),
            .m_axis_tdata (m_axis[i].tdata),
            .m_axis_tkeep (m_axis[i].tkeep),
            .m_axis_tlast (m_axis[i].tlast),
            .m_axis_tid   (m_axis[i].tid)
        );

        assign xfer[i] = m_axis[i].tvalid & m_axis[i].tready;
    end

`else

    // Mux
    metaIntf #(.STYPE(req_t)) req_q ();
    metaIntf #(.STYPE(mux_user_t)) mux ();

    AXI4SR axis_int [N_DESTS] ();
    AXI4SR axis_int_2 [N_DESTS] ();

    //
    queue_meta #(.QDEPTH(QDEPTH)) inst_queue_sink (.aclk(aclk), .aresetn(aresetn), .s_meta(s_req), .m_meta(req_q));

    dest_req_seq inst_dest_seq (.aclk(aclk), .aresetn(aresetn), .s_req(req_q), .m_req(m_req), .mux(mux));

    axis_mux_user_rd #(
        .N_DESTS(N_DESTS)
    ) inst_mux_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis(s_axis),
        .m_axis(axis_int),
        .mux(mux)
    );

    for(genvar i = 0; i < N_DESTS; i++) begin
        axisr_reg inst_dq_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_int[i]), .m_axis(axis_int_2[i]));

        axisr_data_fifo_512 inst_dq (
            .s_axis_aresetn(aresetn),
            .s_axis_aclk(aclk),
            .s_axis_tvalid(axis_int_2[i].tvalid),
            .s_axis_tready(axis_int_2[i].tready),
            .s_axis_tdata (axis_int_2[i].tdata),
            .s_axis_tkeep (axis_int_2[i].tkeep),
            .s_axis_tlast (axis_int_2[i].tlast),
            .s_axis_tid   (axis_int_2[i].tid),
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