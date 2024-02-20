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

module meta_arb_2_1 #(
    parameter integer                   QDEPTH = 4  
) (
    // HOST 
    metaIntf.s                          s_meta_0,
    metaIntf.s                          s_meta_1,

    metaIntf.m                          m_meta,

    input  logic    					aclk,    
	input  logic    					aresetn
);

logic rr_reg;

// RR
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 'X;
	end else begin
        if(m_meta.valid & m_meta.ready) begin 
            rr_reg <= rr_reg ^ 1'b1;
        end
	end
end

// DP
always_comb begin
    s_meta_0.ready = 1'b0;
    s_meta_1.ready = 1'b0;

    m_meta.valid = 1'b0;
    m_meta.data = 0;

    if(rr_reg) begin
        if(s_meta_0.valid) begin
            s_meta_0.ready = m_meta.ready;
            m_meta.valid = s_meta_0.valid;
            m_meta.data = s_meta_0.data;
        end
        else if(s_meta_1.valid) begin
            s_meta_1.ready = m_meta.ready;
            m_meta.valid = s_meta_1.valid;
            m_meta.data = s_meta_1.data;
        end
    end
    else begin
        if(s_meta_1.valid) begin
            s_meta_1.ready = m_meta.ready;
            m_meta.valid = s_meta_1.valid;
            m_meta.data = s_meta_1.data;
        end
        else if(s_meta_0.valid) begin
            s_meta_0.ready = m_meta.ready;
            m_meta.valid = s_meta_0.valid;
            m_meta.data = s_meta_0.data;
        end
    end
end
    
endmodule