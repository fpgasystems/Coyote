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

module dcpl_static #(
    parameter integer                       N_STAGES_0 = 3,
    parameter integer                       N_STAGES_1 = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    input  logic                            s_decouple,

    input  logic [14:0]                     s_usr_irq,
    output logic [14:0]                     m_usr_irq,

    AXI4.s                                  s_axi_main,
    AXI4.m                                  m_axi_main,

    AXI4S.s                                 s_axis_dyn_out [N_SCHAN],
    AXI4S.m                                 m_axis_dyn_out [N_SCHAN],
    AXI4S.s                                 s_axis_dyn_in [N_SCHAN],
    AXI4S.m                                 m_axis_dyn_in [N_SCHAN],

    dmaIntf.s                               s_dma_rd_req [N_SCHAN],
    dmaIntf.m                               m_dma_rd_req [N_SCHAN],
    dmaIntf.s                               s_dma_wr_req [N_SCHAN],
    dmaIntf.m                               m_dma_wr_req [N_SCHAN],

    metaIntf.s                              s_wback,
    AXI4S.m                                 m_axis_wb,
    dmaIntf.m                               m_dma_wb_req
);  

    // Init after ccross
    logic [N_REG_STA_DCPL-1:0] decouple;
    logic [14:0] usr_irq;
    AXI4 axi_main  ();
    AXI4S axis_dyn_out [N_SCHAN] ();
    AXI4S axis_dyn_in [N_SCHAN] ();
    dmaIntf dma_rd_req [N_SCHAN] ();
    dmaIntf dma_wr_req [N_SCHAN] ();

    metaIntf #(.STYPE(wback_t)) wback ();
    AXI4S #(.AXI4S_DATA_BITS(32)) axis_wb ();
    AXI4S #(.AXI4S_DATA_BITS(32)) axis_wb_out ();
    dmaIntf dma_wb_req ();
    
    // Slicing decouple signal
    assign decouple[0] = s_decouple;

    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            for(int i = 1; i < N_REG_STA_DCPL; i++) 
                decouple[i] <= 1'b0;
        end 
        else begin
            for(int i = 1; i < N_REG_STA_DCPL; i++) 
                decouple[i] <= decouple[i-1];
        end
    end

    // Slicing    
    logic_reg_array_static #(.N_STAGES(N_STAGES_0), .DATA_BITS(15)) inst_s0_usr_irq (.aclk(aclk), .aresetn(aresetn), .s_data(usr_irq), .m_data(m_usr_irq));
    axi_reg_array_static #(.N_STAGES(N_STAGES_0)) inst_s0_axi_main (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi_main), .m_axi(axi_main));
    for(genvar i = 0; i < N_SCHAN; i++) begin
        axis_reg_array_static #(.N_STAGES(N_STAGES_0)) inst_s0_axis_dyn_out (.aclk(aclk), .aresetn(aresetn), .s_axis(s_axis_dyn_out[i]), .m_axis(axis_dyn_out[i]));
        axis_reg_array_static #(.N_STAGES(N_STAGES_0)) inst_s0_axis_dyn_in (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_dyn_in[i]), .m_axis(m_axis_dyn_in[i]));
        dma_reg_array_static #(.N_STAGES(N_STAGES_0)) inst_s0_dma_rd_req (.aclk(aclk), .aresetn(aresetn), .s_req(dma_rd_req[i]), .m_req(m_dma_rd_req[i]));
        dma_reg_array_static #(.N_STAGES(N_STAGES_0)) inst_s0_dma_wr_req (.aclk(aclk), .aresetn(aresetn), .s_req(dma_wr_req[i]), .m_req(m_dma_wr_req[i]));
    end
    
    axis_reg_array_static_32 #(.N_STAGES(N_STAGES_0)) inst_s0_axis_wb (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_wb), .m_axis(axis_wb_out));
    dma_reg_array_static #(.N_STAGES(N_STAGES_0)) inst_s0_dma_wb_req (.aclk(aclk), .aresetn(aresetn), .s_req(dma_wb_req), .m_req(m_dma_wb_req));

    wback_dma inst_wback_adj (.aclk(aclk), .aresetn(aresetn), .s_wback(wback), .m_dma_wr(dma_wb_req), .m_axis_wback(axis_wb));

    // Decoupling
    logic_decoupler_static #(.DATA_BITS(15)) inst_s1_usr_irq (.decouple(decouple[N_REG_STA_DCPL-1]), .s_data(s_usr_irq), .m_data(usr_irq));
    axi_decoupler_static inst_s1_axi_main (.decouple(decouple[N_REG_STA_DCPL-1]), .s_axi(axi_main), .m_axi(m_axi_main));

    for(genvar i = 0; i < N_SCHAN; i++) begin
        axis_decoupler_static inst_s1_axis_dyn_out (.decouple(decouple[N_REG_STA_DCPL-1]), .s_axis(axis_dyn_out[i]), .m_axis(m_axis_dyn_out[i]));
        axis_decoupler_static inst_s1_axis_dyn_in (.decouple(decouple[N_REG_STA_DCPL-1]), .s_axis(s_axis_dyn_in[i]), .m_axis(axis_dyn_in[i]));
        dma_decoupler_static inst_s1_dma_rd_req (.decouple(decouple[N_REG_STA_DCPL-1]), .s_req(s_dma_rd_req[i]), .m_req(dma_rd_req[i]));
        dma_decoupler_static inst_s1_dma_wr_req (.decouple(decouple[N_REG_STA_DCPL-1]), .s_req(s_dma_wr_req[i]), .m_req(dma_wr_req[i]));
    end

    meta_decoupler_static inst_s1_wb (.decouple(decouple[N_REG_STA_DCPL-1]), .s_meta(s_wback), .m_meta(wback));
    
    // Out wb
    assign m_axis_wb.tvalid = axis_wb_out.tvalid;
    assign m_axis_wb.tlast  = axis_wb_out.tlast;
    assign m_axis_wb.tdata[AXI_DATA_BITS-1:32] = 0;
    assign m_axis_wb.tdata[31:0] = axis_wb_out.tdata;
    assign m_axis_wb.tkeep[AXI_DATA_BITS/8-1:32/8] = 0;
    assign m_axis_wb.tkeep[32/8-1:0] = axis_wb_out.tkeep;
    assign axis_wb_out.tready = m_axis_wb.tready;
    
endmodule
