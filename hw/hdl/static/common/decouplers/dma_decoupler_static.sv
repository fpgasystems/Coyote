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

`include "lynx_macros.svh"

module dma_decoupler_static #(
    parameter integer               EN_DCPL = 1  
) (
	input  logic 	                decouple,

	dmaIntf.s						      s_req,
	dmaIntf.m					      m_req   
);

// ----------------------------------------------------------------------------------------------------------------------- 
// Decoupling  
// ----------------------------------------------------------------------------------------------------------------------- 
if(EN_DCPL == 1) begin

assign m_req.valid    	= decouple ? 1'b0 : s_req.valid;
assign s_req.ready    	= decouple ? 1'b0 : m_req.ready;
assign s_req.rsp 		= decouple ? 0 : m_req.rsp;

assign m_req.req 		= s_req.req;

end
else begin

`DMA_REQ_ASSIGN(s_req, m_req)

end

endmodule