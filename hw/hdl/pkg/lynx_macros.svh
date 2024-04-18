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