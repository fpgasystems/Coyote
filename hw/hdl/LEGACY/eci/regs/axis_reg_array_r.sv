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


import eci_cmd_defs::*;

import lynxTypes::*;

module axis_reg_array_r #(
    parameter integer                   N_STAGES = 2  
) (
	input  logic 			            aclk,
	input  logic 			            aresetn,
	
	input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic [ECI_DATA_BITS-1:0]    s_axis_tdata,

    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic [ECI_DATA_BITS-1:0]      m_axis_tdata
);

logic [N_STAGES:0][ECI_DATA_BITS-1:0] axis_tdata;
logic [N_STAGES:0] axis_tvalid;
logic [N_STAGES:0] axis_tready;

assign axis_tdata[0] = s_axis_tdata;
assign axis_tvalid[0] = s_axis_tvalid;
assign s_axis_tready = axis_tready[0];

assign m_axis_tdata = axis_tdata[N_STAGES];
assign m_axis_tvalid = axis_tvalid[N_STAGES];
assign axis_tready[N_STAGES] = m_axis_tready;

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_register_slice_r inst_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tvalid[i]),
        .s_axis_tready(axis_tready[i]),
        .s_axis_tdata(axis_tdata[i]),
        .m_axis_tvalid(axis_tvalid[i+1]),
        .m_axis_tready(axis_tready[i+1]),
        .m_axis_tdata(axis_tdata[i+1])
    );
end

endmodule