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
  * EVEN IF ADVISED OF THE POSSIBILITY OF    SUCH DAMAGE.
  */


`timescale 1ns / 1ps

import lynxTypes::*;

module meta_queue #(
    parameter integer       DATA_BITS = 32
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	metaIntf.s			s_meta,
	metaIntf.m		    m_meta
);

if(DATA_BITS == 8) begin
	axis_data_fifo_meta_8 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 16) begin
	axis_data_fifo_meta_16 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 32) begin
	axis_data_fifo_meta_32 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 64) begin
	axis_data_fifo_meta_64 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 96) begin
	axis_data_fifo_meta_96 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 128) begin
	axis_data_fifo_meta_128 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 256) begin
	axis_data_fifo_meta_256 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end
else if(DATA_BITS == 512) begin
	axis_data_fifo_meta_512 inst_meta (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta.valid),
        .s_axis_tready(s_meta.ready),
        .s_axis_tdata(s_meta.data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data)
    );
end

endmodule

