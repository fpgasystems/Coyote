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