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

`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module shell_data_cc #(
    parameter integer       N_STAGES_0 = 1,
    parameter integer       N_STAGES_1 = 1
) (
    input  logic [14:0]     s_usr_irq,
    output logic [14:0]     m_usr_irq,

    AXI4S.s                 s_axis_dyn_in [N_SCHAN],
    AXI4S.m                 m_axis_dyn_in [N_SCHAN],
    AXI4S.s                 s_axis_dyn_out [N_SCHAN],
    AXI4S.m                 m_axis_dyn_out [N_SCHAN],
    dmaIntf.s               s_dma_rd_req [N_SCHAN],
    dmaIntf.m               m_dma_rd_req [N_SCHAN],
    dmaIntf.s               s_dma_wr_req [N_SCHAN],
    dmaIntf.m               m_dma_wr_req [N_SCHAN],
    
`ifdef EN_WB
    metaIntf.s              s_wback,
    metaIntf.m              m_wback,
`endif

    input  logic            xclk,
    input  logic            xresetn,
    input  logic            aclk,
    input  logic            aresetn
);

logic [2-1:0][14:0] usr_irq;
AXI4S axis_dyn_in [N_SCHAN][2] ();
AXI4S axis_dyn_out [N_SCHAN][2] ();
dmaIntf dma_rd_req [N_SCHAN][2] ();
dmaIntf dma_wr_req [N_SCHAN][2] ();
`ifdef EN_WB
metaIntf #(.STYPE(wback_t)) wback [2] ();
`endif

// Slicing input
logic_reg_array #(.N_STAGES(N_STAGES_0), .DATA_BITS(15)) inst_s0_usr_irq (.aclk(xclk), .aresetn(xresetn), .s_data(usr_irq[0]), .m_data(m_usr_irq));

for(genvar i = 0; i < N_SCHAN; i++) begin
    axis_reg_array #(.N_STAGES(N_STAGES_0)) inst_s0_axis_dyn_out (.aclk(xclk), .aresetn(xresetn), .s_axis(s_axis_dyn_in[i]), .m_axis(axis_dyn_in[i][0]));
    axis_reg_array #(.N_STAGES(N_STAGES_0)) inst_s0_axis_dyn_in (.aclk(xclk), .aresetn(xresetn), .s_axis(axis_dyn_out[i][0]), .m_axis(m_axis_dyn_out[i]));
    dma_reg_array #(.N_STAGES(N_STAGES_0)) inst_s0_dma_rd_req (.aclk(xclk), .aresetn(xresetn), .s_req(dma_rd_req[i][0]), .m_req(m_dma_rd_req[i]));
    dma_reg_array #(.N_STAGES(N_STAGES_0)) inst_s0_dma_wr_req (.aclk(xclk), .aresetn(xresetn), .s_req(dma_wr_req[i][0]), .m_req(m_dma_wr_req[i]));
end

`ifdef EN_WB
    meta_reg_array #(.N_STAGES(N_STAGES_0), .DATA_BITS($bits(wback_t))) inst_s0_wback (.aclk(xclk), .aresetn(xresetn), .s_meta(wback[0]), .m_meta(m_wback));
`endif

// Ccross
logic_ccross #(.DATA_BITS(15)) inst_s2_usr_irq (.s_aclk(aclk), .s_aresetn(aresetn), .m_aclk(xclk), .m_aresetn(xresetn), .s_data(usr_irq[1]), .m_data(usr_irq[0]));

for(genvar i = 0; i < N_SCHAN; i++) begin
    axis_ccross inst_s2_axis_dyn_out (.s_aclk(xclk), .s_aresetn(xresetn), .m_aclk(aclk), .m_aresetn(aresetn), .s_axis(axis_dyn_in[i][0]), .m_axis(axis_dyn_in[i][1]));
    axis_ccross inst_s2_axis_dyn_in (.s_aclk(aclk), .s_aresetn(aresetn), .m_aclk(xclk), .m_aresetn(xresetn), .s_axis(axis_dyn_out[i][1]), .m_axis(axis_dyn_out[i][0]));
    dma_req_ccross inst_s2_dma_rd_req (.s_aclk(aclk), .s_aresetn(aresetn), .m_aclk(xclk), .m_aresetn(xresetn), .s_req(dma_rd_req[i][1]), .m_req(dma_rd_req[i][0]));
    dma_req_ccross inst_s2_dma_wr_req (.s_aclk(aclk), .s_aresetn(aresetn), .m_aclk(xclk), .m_aresetn(xresetn), .s_req(dma_wr_req[i][1]), .m_req(dma_wr_req[i][0]));
end 

`ifdef EN_WB
    meta_ccross #(.DATA_BITS($bits(wback_t))) inst_s2_wback (.s_aclk(aclk), .s_aresetn(aresetn), .m_aclk(xclk), .m_aresetn(xresetn), .s_meta(wback[1]), .m_meta(wback[0]));
`endif

// Slicing output
logic_reg_array #(.N_STAGES(N_STAGES_1), .DATA_BITS(15)) inst_s3_usr_irq (.aclk(aclk), .aresetn(aresetn), .s_data(s_usr_irq), .m_data(usr_irq[1]));

for(genvar i = 0; i < N_SCHAN; i++) begin
    axis_reg_array #(.N_STAGES(N_STAGES_1)) inst_s3_axis_dyn_out (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_dyn_in[i][1]), .m_axis(m_axis_dyn_in[i]));
    axis_reg_array #(.N_STAGES(N_STAGES_1)) inst_s3_axis_dyn_in (.aclk(aclk), .aresetn(aresetn), .s_axis(s_axis_dyn_out[i]), .m_axis(axis_dyn_out[i][1]));
    dma_reg_array #(.N_STAGES(N_STAGES_1)) inst_s3_dma_rd_req (.aclk(aclk), .aresetn(aresetn), .s_req(s_dma_rd_req[i]), .m_req(dma_rd_req[i][1]));
    dma_reg_array #(.N_STAGES(N_STAGES_1)) inst_s3_dma_wr_req (.aclk(aclk), .aresetn(aresetn), .s_req(s_dma_wr_req[i]), .m_req(dma_wr_req[i][1]));
end

`ifdef EN_WB
    meta_reg_array #(.N_STAGES(N_STAGES_1), .DATA_BITS($bits(wback_t))) inst_s3_wback (.aclk(aclk), .aresetn(aresetn), .s_meta(s_wback), .m_meta(wback[1]));
`endif
    
endmodule