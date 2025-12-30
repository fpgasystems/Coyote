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

module req_mux_stream_1_2 (
    // HOST 
    metaIntf.s                          s_req,

    metaIntf.m                          m_req_0,
    metaIntf.m                          m_req_1,

    input  logic    					aclk,    
	input  logic    					aresetn
);

metaIntf #(.STYPE(req_t)) req_int_0 (.*);
metaIntf #(.STYPE(req_t)) req_int_1 (.*);

// DP
always_comb begin
    s_req.ready = 1'b0;

    req_int_0.valid = 1'b0;
    req_int_1.valid = 1'b0;

    if(s_req.valid) begin
        if(s_req.data.strm == STRM_HOST) begin
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
assign req_int_1.data = s_req.data;

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_0  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int_0), .m_meta(m_req_0));
meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_1  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_int_1), .m_meta(m_req_1));
    
endmodule