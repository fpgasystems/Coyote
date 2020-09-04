/*
 * CDMA
 */

import lynxTypes::*;

`timescale 1ns / 1ps

module cdma (
    input  wire                         aclk,
    input  wire                         aresetn,

    dmaIntf.s                           rdCDMA,
    dmaIntf.s                           wrCDMA,

    AXI4.m                              axi_ddr_in,

    AXI4S.s                             axis_ddr_in,
    AXI4S.m                             axis_ddr_out
);

// RD ------------------------------------------------------------------------------------------
dmaIntf rdCDMA_que ();
dmaIntf rdCDMA_int ();

logic rd_seq_snk_valid, rd_seq_snk_ready;
logic rd_seq_src_data;

logic tmp_last_rd;

// Request queue rd
queue_stream #(.QTYPE(dma_req_t)) inst_rddma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(rdCDMA.valid),
  .rdy_snk(rdCDMA.ready),
  .data_snk(rdCDMA.req),
  .val_src(rdCDMA_que.valid),
  .rdy_src(rdCDMA_que.ready),
  .data_src(rdCDMA_que.req)
);

// CTL sequencing rd
queue_stream #(.QTYPE(logic)) inst_ctl_seq_rd (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(rd_seq_snk_valid),
  .rdy_snk(rd_seq_snk_ready),
  .data_snk(rdCDMA_que.req.ctl),
  .val_src(),
  .rdy_src(rdCDMA_int.done),
  .data_src(rd_seq_src_data)
);

always_comb begin
    // =>
    rdCDMA_que.ready = rdCDMA_int.ready & rd_seq_snk_ready & rdCDMA_que.valid;
    rdCDMA_int.valid = rdCDMA_que.ready;
    rd_seq_snk_valid = rdCDMA_que.ready;

    rdCDMA_int.req = rdCDMA_que.req;

    // <= 
    rdCDMA_que.done = rdCDMA_int.done; // passthrough
    rdCDMA.done = rdCDMA_que.done & rd_seq_src_data;

    axis_ddr_out.tlast = tmp_last_rd & rd_seq_src_data;
end

// WR ------------------------------------------------------------------------------------------
dmaIntf wrCDMA_que ();
dmaIntf wrCDMA_int ();

logic wr_seq_snk_valid, wr_seq_snk_ready;
logic wr_seq_src_data;

// Request queue wr
queue_stream #(.QTYPE(dma_req_t)) inst_wrdma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wrCDMA.valid),
  .rdy_snk(wrCDMA.ready),
  .data_snk(wrCDMA.req),
  .val_src(wrCDMA_que.valid),
  .rdy_src(wrCDMA_que.ready),
  .data_src(wrCDMA_que.req)
);

// CTL sequencing wr
queue_stream #(.QTYPE(logic)) inst_ctl_seq_wr (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wr_seq_snk_valid),
  .rdy_snk(wr_seq_snk_ready),
  .data_snk(wrCDMA_que.req.ctl),
  .val_src(),
  .rdy_src(wrCDMA_int.done),
  .data_src(wr_seq_src_data)
);

always_comb begin
    // =>
    wrCDMA_que.ready = wrCDMA_int.ready & wr_seq_snk_ready & wrCDMA_que.valid;
    wrCDMA_int.valid = wrCDMA_que.ready;
    wr_seq_snk_valid = wrCDMA_que.ready;

    wrCDMA_int.req = wrCDMA_que.req;

    // <= 
    wrCDMA_que.done = wrCDMA_int.done; // passthrough
    wrCDMA.done = wrCDMA_que.done & wr_seq_src_data;
end

// 
// CDMA
//
axi_dma_rd #(
    .AXI_DATA_WIDTH(AXI_DATA_BITS),
    .AXI_ADDR_WIDTH(AXI_ADDR_BITS),
    .AXI_STRB_WIDTH(AXI_DATA_BITS/8),
    .AXI_MAX_BURST_LEN(64),
    .AXIS_DATA_WIDTH(AXI_DATA_BITS),
    .AXIS_KEEP_ENABLE(1),
    .AXIS_KEEP_WIDTH(AXI_DATA_BITS/8),
    .AXIS_LAST_ENABLE(1'b1),
    .LEN_WIDTH(LEN_BITS)
)
axi_dma_rd_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    /*
     * AXI read descriptor input
     */
    .s_axis_read_desc_addr(rdCDMA_int.req.paddr),
    .s_axis_read_desc_len(rdCDMA_int.req.len),
    .s_axis_read_desc_valid(rdCDMA_int.valid),
    .s_axis_read_desc_ready(rdCDMA_int.ready),

    /*
     * AXI read descriptor status output
     */
    .m_axis_read_desc_status_valid(rdCDMA_int.done),

    /*
     * AXI stream read data output
     */
    .m_axis_read_data_tdata(axis_ddr_out.tdata),
    .m_axis_read_data_tkeep(axis_ddr_out.tkeep),
    .m_axis_read_data_tvalid(axis_ddr_out.tvalid),
    .m_axis_read_data_tready(axis_ddr_out.tready),
    .m_axis_read_data_tlast(tmp_last_rd),

    /*
     * AXI master interface
     */
    .m_axi_arid(axi_ddr_in.arid),
    .m_axi_araddr(axi_ddr_in.araddr),
    .m_axi_arlen(axi_ddr_in.arlen),
    .m_axi_arsize(axi_ddr_in.arsize),
    .m_axi_arburst(axi_ddr_in.arburst),
    .m_axi_arlock(axi_ddr_in.arlock),
    .m_axi_arcache(axi_ddr_in.arcache),
    .m_axi_arprot(axi_ddr_in.arprot),
    .m_axi_arvalid(axi_ddr_in.arvalid),
    .m_axi_arready(axi_ddr_in.arready),
    .m_axi_rid(axi_ddr_in.rid),
    .m_axi_rdata(axi_ddr_in.rdata),
    .m_axi_rresp(axi_ddr_in.rresp),
    .m_axi_rlast(axi_ddr_in.rlast),
    .m_axi_rvalid(axi_ddr_in.rvalid),
    .m_axi_rready(axi_ddr_in.rready)
);

axi_dma_wr #(
    .AXI_DATA_WIDTH(AXI_DATA_BITS),
    .AXI_ADDR_WIDTH(AXI_ADDR_BITS),
    .AXI_STRB_WIDTH(AXI_DATA_BITS/8),
    .AXI_MAX_BURST_LEN(64),
    .AXIS_DATA_WIDTH(AXI_DATA_BITS),
    .AXIS_KEEP_ENABLE(1),
    .AXIS_KEEP_WIDTH(AXI_DATA_BITS/8),
    .AXIS_LAST_ENABLE(0),
    .LEN_WIDTH(LEN_BITS)
)
axi_dma_wr_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    /*
     * AXI write descriptor input
     */
    .s_axis_write_desc_addr(wrCDMA_int.req.paddr),
    .s_axis_write_desc_len(wrCDMA_int.req.len),
    .s_axis_write_desc_valid(wrCDMA_int.valid),
    .s_axis_write_desc_ready(wrCDMA_int.ready),

    /*
     * AXI write descriptor status output
     */
    .m_axis_write_desc_status_valid(wrCDMA_int.done),

    /*
     * AXI stream write data input
     */
    .s_axis_write_data_tdata(axis_ddr_in.tdata),
    .s_axis_write_data_tkeep(axis_ddr_in.tkeep),
    .s_axis_write_data_tvalid(axis_ddr_in.tvalid),
    .s_axis_write_data_tready(axis_ddr_in.tready),
    .s_axis_write_data_tlast(axis_ddr_in.tlast),

    /*
     * AXI master interface
     */
    .m_axi_awid(axi_ddr_in.awid),
    .m_axi_awaddr(axi_ddr_in.awaddr),
    .m_axi_awlen(axi_ddr_in.awlen),
    .m_axi_awsize(axi_ddr_in.awsize),
    .m_axi_awburst(axi_ddr_in.awburst),
    .m_axi_awlock(axi_ddr_in.awlock),
    .m_axi_awcache(axi_ddr_in.awcache),
    .m_axi_awprot(axi_ddr_in.awprot),
    .m_axi_awvalid(axi_ddr_in.awvalid),
    .m_axi_awready(axi_ddr_in.awready),
    .m_axi_wdata(axi_ddr_in.wdata),
    .m_axi_wstrb(axi_ddr_in.wstrb),
    .m_axi_wlast(axi_ddr_in.wlast),
    .m_axi_wvalid(axi_ddr_in.wvalid),
    .m_axi_wready(axi_ddr_in.wready),
    .m_axi_bid(axi_ddr_in.bid),
    .m_axi_bresp(axi_ddr_in.bresp),
    .m_axi_bvalid(axi_ddr_in.bvalid),
    .m_axi_bready(axi_ddr_in.bready)
);

endmodule
