`timescale 1ns / 1ps

import lynxTypes::*;

module static_clk_cnvrt #(
    parameter integer                   EN_CCROSS = 1,
    parameter integer                   N_STAGES = 2
) (
`ifdef EN_ACLK
    input  logic                        xclk,
    input  logic                        xresetn,
`endif
    input  logic                        aclk,
    input  logic                        aresetn,

    AXI4L.s                             s_axi_cnfg,
    AXI4L.m                             m_axi_cnfg,

    AXI4L.s                             s_axi_ctrl [N_REGIONS],
    AXI4L.m                             m_axi_ctrl [N_REGIONS],

`ifdef EN_AVX
    AXI4.s                              s_axim_ctrl [N_REGIONS],
    AXI4.m                              m_axim_ctrl [N_REGIONS],
`endif

    AXI4S.s                             s_axis_dyn_out [N_CHAN],
    AXI4S.m                             m_axis_dyn_out [N_CHAN],
    AXI4S.s                             s_axis_dyn_in [N_CHAN],
    AXI4S.m                             m_axis_dyn_in [N_CHAN],

    dmaIntf.s                           s_dma_rd_req [N_CHAN],
    dmaIntf.m                           m_dma_rd_req [N_CHAN],
    dmaIntf.s                           s_dma_wr_req [N_CHAN],
    dmaIntf.m                           m_dma_wr_req [N_CHAN]
);  

if(EN_CCROSS == 1) begin
    // Slicing
    AXI4S axis_dyn_out [N_CHAN] ();
    AXI4S axis_dyn_in [N_CHAN] ();
    dmaIntf dma_rd_req [N_CHAN] ();
    dmaIntf dma_wr_req [N_CHAN] ();

    // Just slices
    axil_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi_cnfg), .m_axi(m_axi_cnfg));

    for(genvar i = 0; i < N_REGIONS; i++) begin
        axil_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axi_ctrl[i]), .m_axi(m_axi_ctrl[i]));
    end

`ifdef EN_AVX
    for(genvar i = 0; i < N_REGIONS; i++) begin
        axim_reg_array #(.N_STAGES(N_STAGES)) (.aclk(aclk), .aresetn(aresetn), .s_axi(s_axim_ctrl[i]), .m_axi(m_axim_ctrl[i]));
    end
`endif 

    // Slices (to be ccrossed)
    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_reg_array #(.N_STAGES(N_STAGES)) (.aclk(xclk), .aresetn(xresetn), .s_axis(s_axis_dyn_out[i]), .m_axis(axis_dyn_out[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_reg_array #(.N_STAGES(N_STAGES)) (.aclk(xclk), .aresetn(xresetn), .s_axis(axis_dyn_in[i]), .m_axis(m_axis_dyn_in[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_reg_array #(.N_STAGES(N_STAGES)) (.aclk(xclk), .aresetn(xresetn), .s_req(dma_rd_req[i]), .m_req(m_dma_rd_req[i]));
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_reg_array #(.N_STAGES(N_STAGES)) (.aclk(xclk), .aresetn(xresetn), .s_req(dma_wr_req[i]), .m_req(m_dma_wr_req[i]));
    end

    // Clock conversion
    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_ccross inst_axis_dyn_out_ccross (
            .s_aclk(xclk),
            .s_aresetn(xresetn),
            .m_aclk(aclk),
            .m_aresetn(aresetn),
            .s_axis(axis_dyn_out[i]),
            .m_axis(m_axis_dyn_out[i])
        );
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        axis_ccross inst_axis_dyn_in_ccross (
            .s_aclk(aclk),
            .s_aresetn(aresetn),
            .m_aclk(xclk),
            .m_aresetn(xresetn),
            .s_axis(s_axis_dyn_in[i]),
            .m_axis(axis_dyn_in[i])
        );
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_req_ccross inst_dma_rd_req_ccross (
            .s_aclk(aclk),
            .s_aresetn(aresetn),
            .m_aclk(xclk),
            .m_aresetn(xresetn),
            .s_req(s_dma_rd_req[i]),
            .m_req(dma_rd_req[i])
        );
    end

    for(genvar i = 0; i < N_CHAN; i++) begin
        dma_req_ccross inst_dma_wr_req_ccross (
            .s_aclk(aclk),
            .s_aresetn(aresetn),
            .m_aclk(xclk),
            .m_aresetn(xresetn),
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
