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

module cq_arb #(
    parameter integer                   QDEPTH = 16  
) (
    metaIntf.s                          s_cq_bpss_rd,
    metaIntf.s                          s_cq_bpss_wr,
    metaIntf.s                          s_cq_rdma,

    metaIntf.m                          m_cq_rd,
    metaIntf.m                          m_cq_wr,

    input  logic    					aclk,    
	input  logic    					aresetn
);


metaIntf #(.STYPE(ack_t))  cq_bpss_rd_sink ();
metaIntf #(.STYPE(ack_t))  cq_bpss_rd_src ();
metaIntf #(.STYPE(ack_t))  cq_bpss_wr_sink ();
metaIntf #(.STYPE(ack_t))  cq_bpss_wr_src ();

assign cq_bpss_rd_sink.valid = s_cq_bpss_rd.valid;
assign s_cq_bpss_rd.ready = 1'b1;
assign cq_bpss_rd_sink.data = s_cq_bpss_rd.data;

assign cq_bpss_wr_sink.valid = s_cq_bpss_wr.valid;
assign s_cq_bpss_wr.ready = 1'b1;
assign cq_bpss_wr_sink.data = s_cq_bpss_wr.data;

metaIntf #(.STYPE(ack_t))  cq_rdma_rd_sink ();
metaIntf #(.STYPE(ack_t))  cq_rdma_rd_src ();
metaIntf #(.STYPE(ack_t))  cq_rdma_wr_sink ();
metaIntf #(.STYPE(ack_t))  cq_rdma_wr_src ();

assign cq_rdma_rd_sink.valid = s_cq_rdma.valid & is_opcode_rd_resp(s_cq_rdma.data.opcode);
assign s_cq_rdma.ready = 1'b1;
assign cq_rdma_rd_sink.data = s_cq_rdma.data;

assign cq_rdma_wr_sink.valid = s_cq_rdma.valid & is_opcode_ack(s_cq_rdma.data.opcode);
assign cq_rdma_wr_sink.data = s_cq_rdma.data;

queue_meta #(.QDEPTH(QDEPTH)) inst_bpss_rd_q (.aclk(aclk), .aresetn(aresetn), .s_meta(cq_bpss_rd_sink), .m_meta(cq_bpss_rd_src));
queue_meta #(.QDEPTH(QDEPTH)) inst_bpss_wr_q (.aclk(aclk), .aresetn(aresetn), .s_meta(cq_bpss_wr_sink), .m_meta(cq_bpss_wr_src));
queue_meta #(.QDEPTH(QDEPTH)) inst_rdma_rd_q (.aclk(aclk), .aresetn(aresetn), .s_meta(cq_rdma_rd_sink), .m_meta(cq_rdma_rd_src));
queue_meta #(.QDEPTH(QDEPTH)) inst_rdma_wr_q (.aclk(aclk), .aresetn(aresetn), .s_meta(cq_rdma_wr_sink), .m_meta(cq_rdma_wr_src));

metaIntf #(.STYPE(ack_t)) cq_int_rd ();
metaIntf #(.STYPE(ack_t)) cq_int_wr ();

logic rr_reg_rd;
logic rr_reg_wr;

// RR
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg_rd <= 'X;
        rr_reg_wr <= 'X;
	end else begin
        if(cq_int_rd.valid & cq_int_rd.ready) begin 
            rr_reg_rd <= rr_reg_rd ^ 1'b1;
        end
        if(cq_int_wr.valid & cq_int_wr.ready) begin 
            rr_reg_wr <= rr_reg_wr ^ 1'b1;
        end
	end
end

// DP
always_comb begin
    // RD
    cq_bpss_rd_src.ready = 1'b0;
    cq_rdma_rd_src.ready = 1'b0;

    cq_int_rd.valid = 1'b0;
    cq_int_rd.data = 0;

    if(rr_reg_rd) begin
        if(cq_bpss_rd_src.valid) begin
            cq_bpss_rd_src.ready = cq_int_rd.ready;
            cq_int_rd.valid = cq_bpss_rd_src.valid;
            cq_int_rd.data = cq_bpss_rd_src.data;
        end
        else if(cq_rdma_rd_src.valid) begin
            cq_rdma_rd_src.ready = cq_int_rd.ready;
            cq_int_rd.valid = cq_rdma_rd_src.valid;
            cq_int_rd.data = cq_rdma_rd_src.data;
        end
    end
    else begin
        if(cq_rdma_rd_src.valid) begin
            cq_rdma_rd_src.ready = cq_int_rd.ready;
            cq_int_rd.valid = cq_rdma_rd_src.valid;
            cq_int_rd.data = cq_rdma_rd_src.data;
        end
        else if(cq_bpss_rd_src.valid) begin
            cq_bpss_rd_src.ready = cq_int_rd.ready;
            cq_int_rd.valid = cq_bpss_rd_src.valid;
            cq_int_rd.data = cq_bpss_rd_src.data;
        end
    end

    // WR
    cq_bpss_wr_src.ready = 1'b0;
    cq_rdma_wr_src.ready = 1'b0;

    cq_int_wr.valid = 1'b0;
    cq_int_wr.data = 0;

    if(rr_reg_wr) begin
        if(cq_bpss_wr_src.valid) begin
            cq_bpss_wr_src.ready = cq_int_wr.ready;
            cq_int_wr.valid = cq_bpss_wr_src.valid;
            cq_int_wr.data = cq_bpss_wr_src.data;
        end
        else if(cq_rdma_wr_src.valid) begin
            cq_rdma_wr_src.ready = cq_int_wr.ready;
            cq_int_wr.valid = cq_rdma_wr_src.valid;
            cq_int_wr.data = cq_rdma_wr_src.data;
        end
    end
    else begin
        if(cq_rdma_wr_src.valid) begin
            cq_rdma_wr_src.ready = cq_int_wr.ready;
            cq_int_wr.valid = cq_rdma_wr_src.valid;
            cq_int_wr.data = cq_rdma_wr_src.data;
        end
        else if(cq_bpss_wr_src.valid) begin
            cq_bpss_wr_src.ready = cq_int_wr.ready;
            cq_int_wr.valid = cq_bpss_wr_src.valid;
            cq_int_wr.data = cq_bpss_wr_src.data;
        end
    end
end

meta_reg #(.DATA_BITS($bits(ack_t))) inst_reg_out_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(cq_int_rd), .m_meta(m_cq_rd));
meta_reg #(.DATA_BITS($bits(ack_t))) inst_reg_out_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(cq_int_wr), .m_meta(m_cq_wr));
    
endmodule