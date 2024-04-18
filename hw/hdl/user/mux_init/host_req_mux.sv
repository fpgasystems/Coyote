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

module host_req_mux (
    // HOST 
    metaIntf.s                          host_sq,

    metaIntf.m                          host_local_rd,
    metaIntf.m                          host_local_wr,
`ifdef EN_NET
    metaIntf.m                          host_remote_rd,
    metaIntf.m                          host_remote_wr,
`endif 

    input  logic    					aclk,    
	input  logic    					aresetn
);

metaIntf #(.STYPE(dreq_t)) host_sq_int ();
metaIntf #(.STYPE(req_t))  host_local_rd_int ();
metaIntf #(.STYPE(req_t))  host_local_wr_int ();
`ifdef EN_NET
logic remote_strm_1;
logic remote_strm_2;

metaIntf #(.STYPE(dreq_t))  host_remote_rd_int ();
metaIntf #(.STYPE(dreq_t))  host_remote_wr_int ();
`endif 

// Sink reg
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_sq  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_sq), .m_meta(host_sq_int));

`ifdef EN_NET

assign remote_strm_1 = ~(is_strm_local(host_sq_int.data.req_1.strm));
assign remote_strm_2 = ~(is_strm_local(host_sq_int.data.req_2.strm));

always_comb begin
    host_sq_int.ready = 1'b0;

    host_local_rd_int.valid = 1'b0;
    host_local_wr_int.valid = 1'b0;
    host_remote_rd_int.valid = 1'b0;
    host_remote_wr_int.valid = 1'b0;

    host_local_rd_int.data = host_sq_int.data.req_1;
    host_local_rd_int.data.actv = 1'b1;
    host_local_wr_int.data = host_sq_int.data.req_2;
    host_local_wr_int.data.actv = 1'b1;

    host_remote_rd_int.data = host_sq_int.data;
    host_remote_rd_int.data.req_1.actv = 1'b1;
    host_remote_rd_int.data.req_2.actv = 1'b0;
    host_remote_wr_int.data = host_sq_int.data;
    host_remote_wr_int.data.req_1.actv = 1'b0;
    host_remote_wr_int.data.req_2.actv = 1'b1;

    if(host_sq_int.valid) begin
        if(host_sq_int.data.req_1.actv & host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_rd_int.ready & host_local_wr_int.ready;
    
            host_local_rd_int.valid = host_sq_int.ready;
            host_local_wr_int.valid = host_sq_int.ready;
        end
        else if(host_sq_int.data.req_1.actv) begin // rd, local
            host_sq_int.ready = remote_strm_1 ? (host_remote_rd_int.ready) : (host_local_rd_int.ready);

            host_remote_rd_int.valid = remote_strm_1;
            host_local_rd_int.valid = ~remote_strm_1;
        end
        else if(host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = remote_strm_2 ? (host_remote_wr_int.ready & host_local_rd_int.ready) : (host_local_wr_int.ready);
            
            host_remote_wr_int.valid = remote_strm_2;
            host_local_rd_int.valid = remote_strm_2;
            host_local_wr_int.valid = ~remote_strm_2;
        end
    end
end

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_rd_int), .m_meta(host_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_wr_int), .m_meta(host_local_wr));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(host_remote_rd_int), .m_meta(host_remote_rd));
meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_remote_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(host_remote_wr_int), .m_meta(host_remote_wr));

`else

always_comb begin
    host_sq_int.ready = 1'b0;

    host_local_rd_int.valid = 1'b0;
    host_local_wr_int.valid = 1'b0;

    if(host_sq_int.valid) begin
        if(host_sq_int.data.req_1.actv & host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_rd_int.ready & host_local_wr_int.ready;
            
            host_local_rd_int.valid = host_sq_int.ready;
            host_local_wr_int.valid = host_sq_int.ready;
        end
        else if(host_sq_int.data.req_1.actv) begin
            host_sq_int.ready = host_local_rd_int.ready;

            host_local_rd_int.valid = 1'b1;
        end
        else if(host_sq_int.data.req_2.actv) begin
            host_sq_int.ready = host_local_wr_int.ready;

            host_local_wr_int.valid = 1'b1;
        end
    end
end

assign host_local_rd_int.data = host_sq_int.data.req_1;
assign host_local_wr_int.data = host_sq_int.data.req_2;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_rd  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_rd_int), .m_meta(host_local_rd));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_local_wr  (.aclk(aclk), .aresetn(aresetn), .s_meta(host_local_wr_int), .m_meta(host_local_wr));

`endif 
    
endmodule