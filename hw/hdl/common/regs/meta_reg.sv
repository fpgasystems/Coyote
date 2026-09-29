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

module meta_reg #(
	parameter DATA_BITS = 32
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s			s_meta,
	metaIntf.m			m_meta
);

// The vendor IPs exist in a few fixed widths only: the data travels zero-padded on the
// narrowest one that holds DATA_BITS. Selecting only on an exact width would instantiate nothing
// for any other width and leave the channel undriven, which synthesis merely warns about.
localparam integer IP_BITS = DATA_BITS <= 8 ? 8 :
                             DATA_BITS <= 16 ? 16 :
                             DATA_BITS <= 32 ? 32 :
                             DATA_BITS <= 56 ? 56 :
                             DATA_BITS <= 64 ? 64 :
                             DATA_BITS <= 72 ? 72 :
                             DATA_BITS <= 96 ? 96 :
                             DATA_BITS <= 128 ? 128 :
                             DATA_BITS <= 256 ? 256 :
                             DATA_BITS <= 512 ? 512 : 0;

// DATA_BITS wide when no IP fits, so that only the error below reports it
localparam integer PAD_BITS = IP_BITS == 0 ? DATA_BITS : IP_BITS;

logic [PAD_BITS-1:0] s_data;
logic [PAD_BITS-1:0] m_data;

always_comb begin
	s_data = '0;
	s_data[DATA_BITS-1:0] = s_meta.data;
end
assign m_meta.data = m_data[DATA_BITS-1:0];

if(IP_BITS == 8) begin
	axis_register_slice_meta_8 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 16) begin
	axis_register_slice_meta_16 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 32) begin
	axis_register_slice_meta_32 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 56) begin
	axis_register_slice_meta_56 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 64) begin
	axis_register_slice_meta_64 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 72) begin
	axis_register_slice_meta_72 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 96) begin
	axis_register_slice_meta_96 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 128) begin
	axis_register_slice_meta_128 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 256) begin
	axis_register_slice_meta_256 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else if(IP_BITS == 512) begin
	axis_register_slice_meta_512 inst_reg_slice (
		.aclk(aclk),
		.aresetn(aresetn),
		.s_axis_tvalid(s_meta.valid),
		.s_axis_tready(s_meta.ready),
		.s_axis_tdata(s_data),
		.m_axis_tvalid(m_meta.valid),
		.m_axis_tready(m_meta.ready),
		.m_axis_tdata(m_data)
	);
end
else begin
	$error("meta_reg: DATA_BITS = %0d is wider than the widest IP (512 bits)", DATA_BITS);
end

endmodule
