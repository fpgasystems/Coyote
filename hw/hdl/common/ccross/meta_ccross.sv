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

module meta_ccross #(
	parameter integer DATA_BITS		= 32
) (
	input logic 			s_aclk,
	input logic 			s_aresetn,
	input logic 			m_aclk,
	input logic 			m_aresetn,
	
	metaIntf.s 				s_meta,
	metaIntf.m 				m_meta
);

// TODO: Where is this needed ?
if(DATA_BITS == 6) begin
	meta_clock_converter_8 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 11) begin
	meta_clock_converter_16 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
if(DATA_BITS == 13) begin
	meta_clock_converter_16 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end

//
//
// 

if(DATA_BITS == 8) begin
	meta_clock_converter_8 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 16) begin
	meta_clock_converter_16 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 32) begin
	meta_clock_converter_32 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 64) begin
	meta_clock_converter_64 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 72) begin
	meta_clock_converter_72 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 96) begin
	meta_clock_converter_96 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 128) begin
	meta_clock_converter_128 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 256) begin
	meta_clock_converter_256 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end
else if(DATA_BITS == 512) begin
	meta_clock_converter_512 inst_reg_slice (
		.s_axis_aclk(s_aclk),
		.s_axis_aresetn(s_aresetn),
		.m_axis_aclk(m_aclk),
		.m_axis_aresetn(m_aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_meta.data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_meta.data)
	);
end

endmodule