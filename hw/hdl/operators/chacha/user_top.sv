`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn,

    // AXI4 control
    AXI4L.s                     axi_ctrl,

    // Descriptor bypass
    reqIntf.m			      rd_req_ul,
    reqIntf.m			      wr_req_ul,

    // RDMA commands
    reqIntf.s			      rd_req_rdma,
    reqIntf.s 			      wr_req_rdma,

    // AXI4S RDMA
    AXI4S.m                     axis_rdma_src,
    AXI4S.s                     axis_rdma_sink,
    // AXI4S host
    AXI4S.m                     axis_host_src,
    AXI4S.s                     axis_host_sink
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
always_comb axi_ctrl.tie_off_s();
//always_comb rd_req_ul.tie_off_m();
//always_comb wr_req_ul.tie_off_m();
//always_comb rd_req_rdma.tie_off_s();
//always_comb wr_req_rdma.tie_off_s();
//always_comb axis_rdma_src.tie_off_m();
//always_comb axis_rdma_sink.tie_off_s();
//always_comb axis_host_src.tie_off_m();
//always_comb axis_host_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */
assign rd_req_ul.valid   = rd_req_rdma.valid;
assign rd_req_ul.req     = rd_req_rdma.req;
assign rd_req_rdma.ready = rd_req_ul.ready;

assign wr_req_ul.valid   = wr_req_rdma.valid;
assign wr_req_ul.req     = wr_req_rdma.req;
assign wr_req_rdma.ready = wr_req_ul.ready;

logic cc_valid_in;
logic cc_ready_in;
logic cc_valid_out;
logic [511:0] cc_data_in;
logic [511:0] cc_data_out;

logic last_C;

chacha_core(
    .clk(aclk),
    .reset_n(aresetn),
    .init(cc_valid_in),
    .next(0),
    .key(0),
    .keylen(0),
    .iv(0),
    .ctr(0),
    .rounds(8),
    .data_in(cc_data_in),
    .ready(cc_ready_in),
    .data_out(cc_data_out),
    .data_out_valid(cc_valid_out)
)

assign fifo_in.tready = fifo_out.tready && cc_ready_in;

assign cc_valid_in = fifo_out.tready && cc_ready_in && fifo_in.tvalid;
assign cc_data_in = fifo_in.tdata;

assign fifo_out.tvalid = cc_valid_out;
assign fifo_out.tdata = cc_data_out;
assign fifo_out.tkeep = ~0;
assign fifo_out.tlast = last_C;

always_ff @(posedge aclk) begin
    last_C <= cc_valid_in ? fifo_in.tlast : last_C;
end

axis_data_fifo_chacha inst_fifo_in (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(axis_host_sink.tvalid),
  .s_axis_tready(axis_host_sink.tready),
  .s_axis_tdata(axis_host_sink.tdata),
  .s_axis_tkeep(axis_host_sink.tkeep),
  .s_axis_tlast(axis_host_sink.tlast),
  .m_axis_tvalid(fifo_in.tvalid),
  .m_axis_tready(fifo_in.tready),
  .m_axis_tdata(fifo_in.tdata),
  .m_axis_tkeep(fifo_in.tkeep),
  .m_axis_tlast(fifo_in.tlast)
);

axis_data_fifo_chacha inst_fifo_in (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(fifo_out.tvalid),
  .s_axis_tready(fifo_out.tready),
  .s_axis_tdata(fifo_out.tdata),
  .s_axis_tkeep(fifo_out.tkeep),
  .s_axis_tlast(fifo_out.tlast),
  .m_axis_tvalid(axis_rdma_src.tvalid),
  .m_axis_tready(axis_rdma_src.tready),
  .m_axis_tdata(axis_rdma_src.tdata),
  .m_axis_tkeep(axis_rdma_src.tkeep),
  .m_axis_tlast(axis_rdma_src.tlast)
);

endmodule

