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