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

module dma_req_ccross (
	input logic 			s_aclk,
	input logic 			s_aresetn,
	input logic 			m_aclk,
	input logic 			m_aresetn,
	
	dmaIntf.s			    s_req,
	dmaIntf.m			    m_req
);

axis_clock_converter_96 (
    .s_axis_aclk(s_aclk),
    .s_axis_aresetn(s_aresetn),
    .m_axis_aclk(m_aclk),
    .m_axis_aresetn(m_aresetn),
    .s_axis_tvalid(s_req.valid),
    .s_axis_tready(s_req.ready),
    .s_axis_tdata(s_req.req),
    .m_axis_tvalid(m_req.valid),
    .m_axis_tready(m_req.ready),
    .m_axis_tdata(m_req.req)
);

axis_clock_converter_dma_rsp inst_ccross_dma_rsp (
    .s_axis_aclk(m_aclk),
    .s_axis_aresetn(m_aresetn),
    .m_axis_aclk(s_aclk),
    .m_axis_aresetn(s_aresetn),
    .s_axis_tvalid(m_req.rsp.done),
    .s_axis_tready(),
    .s_axis_tuser(0),
    .m_axis_tvalid(s_req.rsp.done),
    .m_axis_tready(1'b1),
    .m_axis_tuser()
);

endmodule