/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
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

module qdma_reg_slice #(
    parameter integer                       N_STAGES = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    qdmaH2CIntf.s                           s_h2c_cmd,
    qdmaH2CIntf.m                           m_h2c_cmd,

    qdmaC2HIntf.s                           s_c2h_cmd,
    qdmaC2HIntf.m                           m_c2h_cmd,

    qdmaH2CS.s                              s_h2c_data,
    qdmaH2CS.m                              m_h2c_data,

    qdmaC2HS.s                              s_c2h_data,
    qdmaC2HS.m                              m_c2h_data
);  

// ================
// H2C Command
// ================
qdmaH2CIntf h2c_cmd_int [N_STAGES+1] ();

`QDMA_CMD_ASSIGN(s_h2c_cmd, h2c_cmd_int[0])
`QDMA_CMD_ASSIGN(h2c_cmd_int[N_STAGES], m_h2c_cmd)

for (genvar i = 0; i < N_STAGES; i++) begin
    register_slice_qdma_h2c_cmd inst_h2c_cmd_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(h2c_cmd_int[i].valid),
        .s_axis_tready(h2c_cmd_int[i].ready),
        .s_axis_tdata(h2c_cmd_int[i].req),
        .m_axis_tvalid(h2c_cmd_int[i+1].valid),
        .m_axis_tready(h2c_cmd_int[i+1].ready),
        .m_axis_tdata(h2c_cmd_int[i+1].req)
    );
end

// ================
// C2H Command
// ================
qdmaC2HIntf c2h_cmd_int [N_STAGES+1] ();

`QDMA_CMD_ASSIGN(s_c2h_cmd, c2h_cmd_int[0])
`QDMA_CMD_ASSIGN(c2h_cmd_int[N_STAGES], m_c2h_cmd)

for (genvar i = 0; i < N_STAGES; i++) begin
    register_slice_qdma_c2h_cmd inst_c2h_cmd_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(c2h_cmd_int[i].valid),
        .s_axis_tready(c2h_cmd_int[i].ready),
        .s_axis_tdata(c2h_cmd_int[i].req),
        .m_axis_tvalid(c2h_cmd_int[i+1].valid),
        .m_axis_tready(c2h_cmd_int[i+1].ready),
        .m_axis_tdata(c2h_cmd_int[i+1].req)
    );
end


// ================
// H2C Data
// ================
qdmaH2CS h2c_data_int [N_STAGES+1] ();

`QDMA_DATA_ASSIGN(s_h2c_data, h2c_data_int[0])
`QDMA_DATA_ASSIGN(h2c_data_int[N_STAGES], m_h2c_data)

for (genvar i = 0; i < N_STAGES; i++) begin
    register_slice_qdma_data inst_h2c_data_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(h2c_data_int[i].tvalid),
        .s_axis_tready(h2c_data_int[i].tready),
        .s_axis_tdata(h2c_data_int[i].payload),
        .s_axis_tlast(h2c_data_int[i].tlast),
        .m_axis_tvalid(h2c_data_int[i+1].tvalid),
        .m_axis_tready(h2c_data_int[i+1].tready),
        .m_axis_tdata(h2c_data_int[i+1].payload),
        .m_axis_tlast(h2c_data_int[i+1].tlast)
    );
end

// ================
// C2H Data
// ================
qdmaC2HS c2h_data_int [N_STAGES+1] ();

`QDMA_DATA_ASSIGN(s_c2h_data, c2h_data_int[0])
`QDMA_DATA_ASSIGN(c2h_data_int[N_STAGES], m_c2h_data)

for (genvar i = 0; i < N_STAGES; i++) begin
    register_slice_qdma_data inst_c2h_data_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(c2h_data_int[i].tvalid),
        .s_axis_tready(c2h_data_int[i].tready),
        .s_axis_tdata(c2h_data_int[i].payload),
        .s_axis_tlast(c2h_data_int[i].tlast),
        .m_axis_tvalid(c2h_data_int[i+1].tvalid),
        .m_axis_tready(c2h_data_int[i+1].tready),
        .m_axis_tdata(c2h_data_int[i+1].payload),
        .m_axis_tlast(c2h_data_int[i+1].tlast)
    );
end

endmodule
