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

module user_req_mux #(
    parameter integer                   ID_REG = 0  
) (
    // USER 
    metaIntf.s                          user_sq_rd,
    metaIntf.s                          user_sq_wr,

    //
    metaIntf.m                          user_local_rd,
    metaIntf.m                          user_local_wr,
`ifdef EN_NET
    metaIntf.m                          user_remote_rd,
    metaIntf.m                          user_remote_wr,
`endif

    input  logic    					aclk,    
	input  logic    					aresetn
);

// Override
metaIntf #(.STYPE(req_t)) user_sq_rd_or ();
metaIntf #(.STYPE(req_t)) user_sq_wr_or ();

always_comb begin
    user_sq_rd_or.valid = user_sq_rd.valid;
    user_sq_rd.ready = user_sq_rd_or.ready;
    user_sq_rd_or.data = user_sq_rd.data;
    user_sq_rd_or.data.actv = 1'b1;
    user_sq_rd_or.data.host = 1'b0;
    user_sq_rd_or.data.vfid = ID_REG;

    user_sq_wr_or.valid = user_sq_wr.valid;
    user_sq_wr.ready = user_sq_wr_or.ready;
    user_sq_wr_or.data = user_sq_wr.data;
    user_sq_wr_or.data.actv = 1'b1;
    user_sq_wr_or.data.host = 1'b0;
    user_sq_wr_or.data.vfid = ID_REG;
end

// Internal
metaIntf #(.STYPE(req_t)) user_sq_rd_int ();
metaIntf #(.STYPE(req_t)) user_sq_wr_int ();

metaIntf #(.STYPE(req_t)) user_local_rd_int ();
metaIntf #(.STYPE(req_t)) user_local_wr_int ();
`ifdef EN_NET
logic remote_strm_1;
logic remote_strm_2;

metaIntf #(.STYPE(dreq_t)) user_remote_rd_int ();
metaIntf #(.STYPE(dreq_t)) user_remote_wr_int ();
`endif

// Sink reg
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_sq_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(user_sq_rd_or), .m_meta(user_sq_rd_int));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_sq_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(user_sq_wr_or), .m_meta(user_sq_wr_int));

`ifdef EN_NET

assign remote_strm_1 = ~(is_strm_local(user_sq_rd_int.data.strm));
assign remote_strm_2 = ~(is_strm_local(user_sq_wr_int.data.strm));

always_comb begin
    user_sq_rd_int.ready = 1'b0;
    user_sq_wr_int.ready = 1'b0;

    user_local_rd_int.valid = 1'b0;
    user_local_wr_int.valid = 1'b0;
    user_remote_rd_int.valid = 1'b0;
    user_remote_wr_int.valid = 1'b0;

    if(user_sq_rd_int.valid) begin
        user_remote_rd_int.valid = remote_strm_1;
        user_local_rd_int.valid = ~remote_strm_1;
        
        user_sq_rd_int.ready = remote_strm_1 ? (user_remote_rd_int.ready) : (user_local_rd_int.ready);
    end

    if(user_sq_wr_int.valid) begin
        user_remote_wr_int.valid = remote_strm_2;
        user_local_wr_int.valid = ~remote_strm_2;

        user_sq_wr_int.ready = remote_strm_2 ? (user_remote_wr_int.ready) : (user_local_wr_int.ready);
    end
end

assign user_local_rd_int.data = user_sq_rd_int.data;
assign user_local_wr_int.data = user_sq_wr_int.data;
always_comb begin
    user_remote_rd_int.data.req_1 = user_sq_rd_int.data;
    user_remote_rd_int.data.req_2 = 0;

    user_remote_wr_int.data.req_1 = 0;
    user_remote_wr_int.data.req_2 = user_sq_wr_int.data;
end

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_rd_int), .m_meta(user_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_wr_int), .m_meta(user_local_wr));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(user_remote_rd_int), .m_meta(user_remote_rd));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(user_remote_wr_int), .m_meta(user_remote_wr));

`else

always_comb begin
    user_sq_rd_int.ready = 1'b0;
    user_sq_wr_int.ready = 1'b0;

    user_local_rd_int.valid = 1'b0;
    user_local_wr_int.valid = 1'b0;

    if(user_sq_rd_int.valid) begin
        user_local_rd_int.valid = 1'b1;

        user_sq_rd_int.ready = user_local_rd_int.ready;
    end

    if(user_sq_wr_int.valid) begin
        user_local_wr_int.valid = 1'b1;

        user_sq_wr_int.ready = user_local_wr_int.ready;
    end
end

assign user_local_rd_int.data = user_sq_rd_int.data;
assign user_local_wr_int.data = user_sq_wr_int.data;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_rd_int), .m_meta(user_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(user_local_wr_int), .m_meta(user_local_wr));

`endif 
    
endmodule
