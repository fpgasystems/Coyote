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

module dreq_mux_net_1_2 (
    // HOST 
    metaIntf.s                          s_req,

    metaIntf.m                          m_req_0, // rdma wr
    metaIntf.m                          m_req_1, // tcp wr

    input  logic    					aclk,    
	input  logic    					aresetn
);

metaIntf #(.STYPE(dreq_t)) req_int_0 ();
metaIntf #(.STYPE(req_t)) req_int_1 ();

// DP
always_comb begin
    s_req.ready = 1'b0;

    req_int_0.valid = 1'b0;
    req_int_1.valid = 1'b0;

    if(s_req.valid) begin
        if(s_req.data.req_2.strm == STRM_RDMA) begin
            req_int_0.valid = 1'b1;
            s_req.ready = req_int_0.ready;
        end
        else begin
            req_int_1.valid = 1'b1;
            s_req.ready = req_int_1.ready;
        end
    end
end

assign req_int_0.data = s_req.data;
assign req_int_1.data = s_req.data.req_2;

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_0  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int_0), .m_meta(m_req_0));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_1  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int_1), .m_meta(m_req_1));
    
endmodule