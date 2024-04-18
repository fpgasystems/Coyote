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

module req_arb_2_1 (
    // HOST 
    metaIntf.s                          s_req_0,
    metaIntf.s                          s_req_1,

    metaIntf.m                          m_req,

    input  logic    					aclk,    
	input  logic    					aresetn
);

metaIntf #(.STYPE(req_t)) req_int ();

logic rr_reg;

// RR
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 'X;
	end else begin
        if(req_int.valid & req_int.ready) begin 
            rr_reg <= rr_reg ^ 1'b1;
        end
	end
end

// DP
always_comb begin
    s_req_0.ready = 1'b0;
    s_req_1.ready = 1'b0;

    req_int.valid = 1'b0;
    req_int.data = 0;

    if(rr_reg) begin
        if(s_req_0.valid) begin
            s_req_0.ready = req_int.ready;
            req_int.valid = s_req_0.valid;
            req_int.data = s_req_0.data;
        end
        else if(s_req_1.valid) begin
            s_req_1.ready = req_int.ready;
            req_int.valid = s_req_1.valid;
            req_int.data = s_req_1.data;
        end
    end
    else begin
        if(s_req_1.valid) begin
            s_req_1.ready = req_int.ready;
            req_int.valid = s_req_1.valid;
            req_int.data = s_req_1.data;
        end
        else if(s_req_0.valid) begin
            s_req_0.ready = req_int.ready;
            req_int.valid = s_req_0.valid;
            req_int.data = s_req_0.data;
        end
    end
end

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_out  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int), .m_meta(m_req));
    
endmodule