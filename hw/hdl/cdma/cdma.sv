/*
 * CDMA
 */

import lynxTypes::*;

module cdma (
    input  logic                        aclk,
    input  logic                        aresetn,

    dmaIntf.s                           rdCDMA,
    dmaIntf.s                           wrCDMA,

    AXI4.m                              axi_ddr_in,

    AXI4S.s                             axis_ddr_in,
    AXI4S.m                             axis_ddr_out
);

// Decoupling
dmaIntf rdCDMA_int ();
dmaIntf wrCDMA_int ();

// RD ------------------------------------------------------------------------------------------
// CDMA completion
assign rdCDMA.done = rdCDMA_int.done;

// Request queue
queue_stream #(.QTYPE(dma_req_t)) inst_rddma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(rdCDMA.valid),
  .rdy_snk(rdCDMA.ready),
  .data_snk(rdCDMA.req),
  .val_src(rdCDMA_int.valid),
  .rdy_src(rdCDMA_int.ready),
  .data_src(rdCDMA_int.req)
);

// WR ------------------------------------------------------------------------------------------
// CDMA completion
assign wrCDMA.done = wrCDMA_int.done;

queue_stream #(.QTYPE(dma_req_t)) inst_wrdma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wrCDMA.valid),
  .rdy_snk(wrCDMA.ready),
  .data_snk(wrCDMA.req),
  .val_src(wrCDMA_int.valid),
  .rdy_src(wrCDMA_int.ready),
  .data_src(wrCDMA_int.req)
);

// 
// CDMA
//

// RD channel
axi_dma_rd axi_dma_rd_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    // CS
    .ctrl_valid(rdCDMA_int.valid),
    .stat_ready(rdCDMA_int.ready),
    .ctrl_addr(rdCDMA_int.req.paddr),
    .ctrl_len(rdCDMA_int.req.len),
    .ctrl_ctl(rdCDMA_int.req.ctl),
    .stat_done(rdCDMA_int.done),

    // AXI
    .arvalid(axi_ddr_in.arvalid),
    .arready(axi_ddr_in.arready),
    .araddr(axi_ddr_in.araddr),
    .arid(axi_ddr_in.arid),
    .arlen(axi_ddr_in.arlen),
    .arsize(axi_ddr_in.arsize),
    .arburst(axi_ddr_in.arburst),
    .arlock(axi_ddr_in.arlock),
    .arcache(axi_ddr_in.arcache),
    .arprot(axi_ddr_in.arprot),
    .rvalid(axi_ddr_in.rvalid),
    .rready(axi_ddr_in.rready),
    .rdata(axi_ddr_in.rdata),
    .rlast(axi_ddr_in.rlast),
    .rid(axi_ddr_in.rid),
    .rresp(axi_ddr_in.rresp),

    // AXIS
    .axis_out_tdata(axis_ddr_out.tdata),
    .axis_out_tkeep(axis_ddr_out.tkeep),
    .axis_out_tvalid(axis_ddr_out.tvalid),
    .axis_out_tready(axis_ddr_out.tready),
    .axis_out_tlast(axis_ddr_out.tlast)
);

// Tie-off RD
assign axi_ddr_in.arqos = 0;
assign axi_ddr_in.arregion = 0;

// WR channel
axi_dma_wr axi_dma_wr_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    // CS
    .ctrl_valid(wrCDMA_int.valid),
    .stat_ready(wrCDMA_int.ready),
    .ctrl_addr(wrCDMA_int.req.paddr),
    .ctrl_len(wrCDMA_int.req.len),
    .ctrl_ctl(wrCDMA_int.req.ctl),
    .stat_done(wrCDMA_int.done),

    // AXI
    .awvalid(axi_ddr_in.awvalid),
    .awready(axi_ddr_in.awready),
    .awaddr(axi_ddr_in.awaddr),
    .awid(axi_ddr_in.awid),
    .awlen(axi_ddr_in.awlen),
    .awsize(axi_ddr_in.awsize),
    .awburst(axi_ddr_in.awburst),
    .awlock(axi_ddr_in.awlock),
    .awcache(axi_ddr_in.awcache),
    .awprot(axi_ddr_in.awprot),
    .wdata(axi_ddr_in.wdata),
    .wstrb(axi_ddr_in.wstrb),
    .wlast(axi_ddr_in.wlast),
    .wvalid(axi_ddr_in.wvalid),
    .wready(axi_ddr_in.wready),
    .bid(axi_ddr_in.bid),
    .bresp(axi_ddr_in.bresp),
    .bvalid(axi_ddr_in.bvalid),
    .bready(axi_ddr_in.bready),

    // AXIS
    .axis_in_tdata(axis_ddr_in.tdata),
    .axis_in_tkeep(axis_ddr_in.tkeep),
    .axis_in_tvalid(axis_ddr_in.tvalid),
    .axis_in_tready(axis_ddr_in.tready),
    .axis_in_tlast(axis_ddr_in.tlast)
);

// Tie-off WR
assign axi_ddr_in.awqos = 0;
assign axi_ddr_in.awregion = 0;

endmodule