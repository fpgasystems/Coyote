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

`ifndef LYNX_MACROS_SVH_
`define LYNX_MACROS_SVH_

`define DMA_REQ_ASSIGN(s, m)            			\
	assign m.req		= s.req;					\
	assign s.rsp 		= m.rsp;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;					
	
`define DMA_ISR_REQ_ASSIGN(s, m)            		\
	assign m.req		= s.req;					\
	assign s.rsp		= m.rsp;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;						

`define META_ASSIGN(s, m)              				\
	assign m.data		= s.data;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;

`define DMA_REQ_ASSIGN_I2S(s, m)                    \
    assign ``m``_req		= ``s``.req;		    \
	assign ``s``.rsp 		= ``m``_rsp;		    \
	assign ``m``_valid 		= ``s``.valid; 		    \
	assign ``s``.ready 		= ``m``_ready;	

`define DMA_REQ_ASSIGN_S2I(s, m)                    \
    assign ``m``.req		= ``s``_req;		    \
	assign ``s``_rsp 		= ``m``.rsp;		    \
	assign ``m``.valid 		= ``s``_valid; 		    \
	assign ``s``_ready 		= ``m``.ready;	

`define DMA_ISR_REQ_ASSIGN_I2S(s, m)                \
    assign ``m``_req		= ``s``.req;		    \
	assign ``s``.rsp 		= ``m``_rsp;		    \
	assign ``m``_valid 		= ``s``.valid; 		    \
	assign ``s``.ready 		= ``m``_ready;	

`define DMA_ISR_REQ_ASSIGN_S2I(s, m)                \
    assign ``m``.req		= ``s``_req;		    \
	assign ``s``_rsp 		= ``m``.rsp;		    \
	assign ``m``.valid 		= ``s``_valid; 		    \
	assign ``s``_ready 		= ``m``.ready;	

`define META_ASSIGN_I2S(s, m)              		    \
	assign ``m``_data		= ``s``.data;			\
	assign ``m``_valid 		= ``s``.valid; 			\
	assign ``s``.ready 		= ``m``_ready;

`define META_ASSIGN_S2I(s, m)              		    \
	assign ``m``.data		= ``s``_data;			\
	assign ``m``.valid 		= ``s``_valid; 			\
	assign ``s``_ready 		= ``m``.ready;
	
`endif