`timescale 1ns / 1ps

import lynxTypes::*;
/*
module static_clk_cnvrt #(
    parameter integer                   EN_CCROSS = 1,
    parameter integer                   N_STAGES = 2
) (
`ifdef EN_ACLK
    input  logic                        dclk,
    input  logic                        dresetn,
`endif
    input  logic                        aclk,
    input  logic                        aresetn,

    AXI4L.s                             s_axi_cnfg,
    AXI4L.m                            m_axi_cnfg,

    AXI4L.s                             s_axi_ctrl [N_REGIONS],
    AXI4L.m                            m_axi_ctrl [N_REGIONS],

`ifdef EN_AVX
    AXI4.s                              s_axim_ctrl [N_REGIONS],
    AXI4.m                             m_axim_ctrl [N_REGIONS],
`endif

    AXI4S.s                             s_axis_dyn_out [N_CHAN],
    AXI4S.m                            m_axis_dyn_out [N_CHAN],
    AXI4S.s                             s_axis_dyn_in [N_CHAN],
    AXI4S.m                            m_axis_dyn_in [N_CHAN],

    dmaIntf.s                           s_dma_rd_req [N_CHAN],
    dmaIntf.m                          m_dma_rd_req [N_CHAN],
    dmaIntf.s                           s_dma_wr_req [N_CHAN],
    dmaIntf.m                          m_dma_wr_req [N_CHAN]
);  

if(EN_CCROSS == 1) begin
    // Slicing
    AXI4L axi_cnfg ();
    AXI4L axi_ctrl [N_REGIONS] ();
    `ifdef EN_AVX
    AXI4 #(.AXI4_DATA_BITS(AVX_DATA_BITS)) axim_ctrl [N_REGIONS] ();
    `endif
    AXI4S axis_dyn_out [N_CHAN] ();
    AXI4S axis_dyn_in [N_CHAN] ();
    dmaIntf dma_rd_req [N_CHAN] ();
    dmaIntf dma_wr_req [N_CHAN] ();

    axil_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_axi(s_axi_cnfg), .m_axi(axi_cnfg));

    for(genvar i = 0; i < N_REGIONS; i++) begin
        axil_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_axi(s_axi_ctrl[i]), .m_axi(axi_ctrl[i]));
    end

`ifdef EN_AVX
    for(genvar i = 0; i < N_REGIONS; i++) begin
        axim_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_axi(s_axim_ctrl[i]), .m_axi(axim_ctrl[i]));
    end
`endif 

    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_axis(s_axis_dyn_out[i]), .m_axis(axis_dyn_out[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_axis(axis_dyn_in[i]), .m_axis(m_axis_dyn_in[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_req(dma_rd_req[i]), .m_req(m_dma_rd_req[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_reg_array #(.N_STAGES(N_STAGES)) (.aclk(dclk), .aresetn(dresetn), .s_req(dma_wr_req[i]), .m_req(m_dma_wr_req[i]));
    end

    // AXI CNFG
    axil_ccross inst_axi_cnfg_ccross (
        .s_aclk(dclk),
        .s_aresetn(dresetn),
        .m_aclk(aclk),
        .m_aresetn(aresetn),
        .s_axi(axi_cnfg),
        .m_axi(m_axi_cnfg)
    );

    // AXI CTRL
    for(genvar i = 0; i < N_REGIONS; i++) begin
        axil_ccross inst_axi_ctrl_ccross (
            .s_aclk(dclk),
            .s_aresetn(dresetn),
            .m_aclk(aclk),
            .m_aresetn(aresetn),
            .s_axi(axi_ctrl[i]),
            .m_axi(m_axi_ctrl[i])
        );
    end

`ifdef EN_AVX
    // AXIM CTRL
    for(genvar i = 0; i < N_REGIONS; i++) begin
        axim_ccross inst_axim_ctrl_ccross (
            .s_aclk(dclk),
            .s_aresetn(dresetn),
            .m_aclk(aclk),
            .m_aresetn(aresetn),
            .s_axi(axim_ctrl[i]),
            .m_axi(m_axim_ctrl[i])
        );
    end
`endif

    // AXI DYN OUT
    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_ccross inst_axis_dyn_out_ccross (
            .s_aclk(dclk),
            .s_aresetn(dresetn),
            .m_aclk(aclk),
            .m_aresetn(aresetn),
            .s_axis(axis_dyn_out[i]),
            .m_axis(m_axis_dyn_out[i])
        );
    end

    // AXI DYN IN
    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_ccross inst_axis_dyn_in_ccross (
            .s_aclk(aclk),
            .s_aresetn(aresetn),
            .m_aclk(dclk),
            .m_aresetn(dresetn),
            .s_axis(s_axis_dyn_in[i]),
            .m_axis(axis_dyn_in[i])
        );
    end

    // DMA RD REQ
    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_req_ccross inst_dma_rd_req_ccross (
            .s_aclk(aclk),
            .s_aresetn(aresetn),
            .m_aclk(dclk),
            .m_aresetn(dresetn),
            .s_req(s_dma_rd_req[i]),
            .m_req(dma_rd_req[i])
        );
    end

    // DMA WR REQ
    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_req_ccross inst_dma_wr_req_ccross (
            .s_aclk(aclk),
            .s_aresetn(aresetn),
            .m_aclk(dclk),
            .m_aresetn(dresetn),
            .s_req(s_dma_wr_req[i]),
            .m_req(dma_wr_req[i])
        );
    end

end
else begin
    
    // Slicing
    axil_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi_cnfg), .m_axi(m_axi_cnfg));

    for(genvar i = 0; i < N_REGIONS; i++) begin
        axil_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi_ctrl[i]), .m_axi(m_axi_ctrl[i]));
    end

`ifdef EN_AVX
    for(genvar i = 0; i < N_REGIONS; i++) begin
        axim_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axim_ctrl[i]), .m_axi(m_axim_ctrl[i]));
    end
`endif 

    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axis(s_axis_dyn_out[i]), .m_axis(m_axis_dyn_out[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axis(s_axis_dyn_in[i]), .m_axis(m_axis_dyn_in[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_req(s_dma_rd_req[i]), .m_req(m_dma_rd_req[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_req(s_dma_wr_req[i]), .m_req(m_dma_wr_req[i]));
    end

end
    
endmodule
*/