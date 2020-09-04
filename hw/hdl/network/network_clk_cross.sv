import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module network_clk_cross (
    input  wire             aclk,
    input  wire             aresetn,
    input  wire             net_clk,
    input  wire             net_aresetn,

    // ACLK
    metaIntf.s              arp_lookup_request_aclk,
    metaIntf.m              arp_lookup_reply_aclk,
    metaIntf.s              set_ip_addr_aclk,
    metaIntf.s              set_board_number_aclk,
    metaIntf.s              qp_interface_aclk,
    metaIntf.s              conn_interface_aclk,

    metaIntf.s              rdma_req_host_aclk [N_REGIONS],
`ifdef EN_FVV
    metaIntf.s              rdma_req_card_aclk [N_REGIONS],
    metaIntf.m              rdma_req_fv_aclk [N_REGIONS],
`endif

    reqIntf.m               rdma_rd_cmd_aclk [N_REGIONS],
    reqIntf.m               rdma_wr_cmd_aclk [N_REGIONS],
    AXI4S.s                 axis_rdma_rd_data_aclk [N_REGIONS],
    AXI4S.m                 axis_rdma_wr_data_aclk [N_REGIONS],

    // NCLK
    metaIntf.m              arp_lookup_request_nclk,
    metaIntf.s              arp_lookup_reply_nclk,
    metaIntf.m              set_ip_addr_nclk,
    metaIntf.m              set_board_number_nclk,
    metaIntf.m              qp_interface_nclk,
    metaIntf.m              conn_interface_nclk,

    metaIntf.m              rdma_req_host_nclk,
`ifdef EN_FVV
    metaIntf.m              rdma_req_card_nclk,
    metaIntf.s              rdma_req_fv_nclk,
`endif

    rdmaIntf.s              rdma_rd_cmd_nclk,
    rdmaIntf.s              rdma_wr_cmd_nclk,
    AXI4S.m                 axis_rdma_rd_data_nclk,
    AXI4S.s                 axis_rdma_wr_data_nclk
);

//
// Crossings init
//

// ARP request
axis_clock_converter_32_0 inst_clk_cnvrt_arp_request (
    .s_axis_aresetn(aresetn),
    .m_axis_aresetn(net_aresetn),
    .s_axis_aclk(aclk),
    .m_axis_aclk(net_clk),
    .s_axis_tvalid(arp_lookup_request_aclk.valid),
    .s_axis_tready(arp_lookup_request_aclk.ready),
    .s_axis_tdata(arp_lookup_request_aclk.data),  
    .m_axis_tvalid(arp_lookup_request_nclk.valid),
    .m_axis_tready(arp_lookup_request_nclk.ready),
    .m_axis_tdata(arp_lookup_request_nclk.data)
);

// ARP reply
axis_clock_converter_56_0 inst_clk_cnvrt_arp_reply (
    .s_axis_aresetn(net_aresetn),
    .m_axis_aresetn(aresetn),
    .s_axis_aclk(net_clk),
    .m_axis_aclk(aclk),
    .s_axis_tvalid(arp_lookup_reply_nclk.valid),
    .s_axis_tready(arp_lookup_reply_nclk.ready),
    .s_axis_tdata(arp_lookup_reply_nclk.data),  
    .m_axis_tvalid(arp_lookup_reply_aclk.valid),
    .m_axis_tready(arp_lookup_reply_aclk.ready),
    .m_axis_tdata(arp_lookup_reply_aclk.data)
);

// Set IP address
axis_clock_converter_32_0 inst_clk_cnvrt_set_ip_addr (
    .s_axis_aresetn(aresetn),
    .m_axis_aresetn(net_aresetn),
    .s_axis_aclk(aclk),
    .m_axis_aclk(net_clk),
    .s_axis_tvalid(set_ip_addr_aclk.valid),
    .s_axis_tready(set_ip_addr_aclk.ready),
    .s_axis_tdata(set_ip_addr_aclk.data),  
    .m_axis_tvalid(set_ip_addr_nclk.valid),
    .m_axis_tready(set_ip_addr_nclk.ready),
    .m_axis_tdata(set_ip_addr_nclk.data)
);

// Set board number
axis_clock_converter_8_0 inst_clk_cnvrt_set_board_number (
    .s_axis_aresetn(aresetn),
    .m_axis_aresetn(net_aresetn),
    .s_axis_aclk(aclk),
    .m_axis_aclk(net_clk),
    .s_axis_tvalid(set_board_number_aclk.valid),
    .s_axis_tready(set_board_number_aclk.ready),
    .s_axis_tdata(set_board_number_aclk.data),  
    .m_axis_tvalid(set_board_number_nclk.valid),
    .m_axis_tready(set_board_number_nclk.ready),
    .m_axis_tdata(set_board_number_nclk.data)
);

// Qp interface clock crossing
axis_clock_converter_144_0 inst_clk_cnvrt_qp_interface (
    .s_axis_aresetn(aresetn),
    .m_axis_aresetn(net_aresetn),
    .s_axis_aclk(aclk),
    .m_axis_aclk(net_clk),
    .s_axis_tvalid(qp_interface_aclk.valid),
    .s_axis_tready(qp_interface_aclk.ready),
    .s_axis_tdata(qp_interface_aclk.data),  
    .m_axis_tvalid(qp_interface_nclk.valid),
    .m_axis_tready(qp_interface_nclk.ready),
    .m_axis_tdata(qp_interface_nclk.data)
);

// Connection interface clock crossing
axis_clock_converter_184_0 inst_clk_cnvrt_conn_interface (
    .s_axis_aresetn(aresetn),
    .m_axis_aresetn(net_aresetn),
    .s_axis_aclk(aclk),
    .m_axis_aclk(net_clk),
    .s_axis_tvalid(conn_interface_aclk.valid),
    .s_axis_tready(conn_interface_aclk.ready),
    .s_axis_tdata(conn_interface_aclk.data),  
    .m_axis_tvalid(conn_interface_nclk.valid),
    .m_axis_tready(conn_interface_nclk.ready),
    .m_axis_tdata(conn_interface_nclk.data)
);

//
// Crossings commands
//

// Arbitration RDMA requests host
metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_host_arb ();

`ifdef MULT_REGIONS
    network_meta_tx_arbiter #(
        .DATA_BITS(FV_REQ_BITS)
    ) inst_rdma_req_host_arbiter (
        .aclk(aclk),
        .aresetn(aresetn),
        .meta_snk(rdma_req_host_aclk),
        .meta_src(rdma_req_host_arb),
        .id()
    );
`else
    `META_ASSIGN(rdma_req_host_aclk[0], rdma_req_host_arb)
`endif

axis_data_fifo_req_rdma_256 inst_rdma_req_host_cross (
    .m_axis_aclk(net_clk),
    .s_axis_aclk(aclk),
    .s_axis_aresetn(aresetn),
    .s_axis_tvalid(rdma_req_host_arb.valid),
    .s_axis_tready(rdma_req_host_arb.ready),
    .s_axis_tdata(rdma_req_host_arb.data),
    .m_axis_tvalid(rdma_req_host_nclk.valid),
    .m_axis_tready(rdma_req_host_nclk.ready),
    .m_axis_tdata(rdma_req_host_nclk.data)
);

`ifdef EN_FVV

// Arbitration RDMA requests card
metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_card_arb ();

`ifdef MULT_REGIONS
    network_meta_tx_arbiter #(
        .DATA_BITS(FV_REQ_BITS)
    ) inst_rdma_req_card_arbiter (
        .aclk(aclk),
        .aresetn(aresetn),
        .meta_snk(rdma_req_card_aclk),
        .meta_src(rdma_req_card_arb),
        .id()
    );
`else
    `META_ASSIGN(rdma_req_card_aclk[0], rdma_req_card_arb)
`endif

axis_data_fifo_req_rdma_256 inst_rdma_req_card_cross (
    .m_axis_aclk(net_clk),
    .s_axis_aclk(aclk),
    .s_axis_aresetn(aresetn),
    .s_axis_tvalid(rdma_req_card_arb.valid),
    .s_axis_tready(rdma_req_card_arb.ready),
    .s_axis_tdata(rdma_req_card_arb.data),
    .m_axis_tvalid(rdma_req_card_nclk.valid),
    .m_axis_tready(rdma_req_card_nclk.ready),
    .m_axis_tdata(rdma_req_card_nclk.data)
);

// Arbitration Farview RDMA requests
metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_fv_arb ();

axis_data_fifo_req_rdma_256 inst_rdma_req_fv_cross (
    .m_axis_aclk(aclk),
    .s_axis_aclk(net_clk),
    .s_axis_aresetn(net_aresetn),
    .s_axis_tvalid(rdma_req_fv_nclk.valid),
    .s_axis_tready(rdma_req_fv_nclk.ready),
    .s_axis_tdata(rdma_req_fv_nclk.data),
    .m_axis_tvalid(rdma_req_fv_arb.valid),
    .m_axis_tready(rdma_req_fv_arb.ready),
    .m_axis_tdata(rdma_req_fv_arb.data)
);

`ifdef MULT_REGIONS
    network_meta_fv_arbiter #(
        .DATA_BITS(FV_REQ_BITS)
    ) inst_rdma_req_fv_arbiter (
        .aclk(aclk),
        .aresetn(aresetn),
        .meta_snk(rdma_req_fv_arb),
        .meta_src(rdma_req_fv_aclk)
    );
`else
    `META_ASSIGN(rdma_req_fv_arb, rdma_req_fv_aclk[0])
`endif

`endif

//
// Memory
//

// Read command and data crossing
//
rdmaIntf rdma_rd_cmd_arb();
AXI4S axis_rdma_rd_data_arb();

axis_data_fifo_cmd_rdma_96 inst_rdma_cmd_rd (
    .m_axis_aclk(aclk),
    .s_axis_aclk(net_clk),
    .s_axis_aresetn(net_aresetn),
    .s_axis_tvalid(rdma_rd_cmd_nclk.valid),
    .s_axis_tready(rdma_rd_cmd_nclk.ready),
    .s_axis_tdata(rdma_rd_cmd_nclk.req),
    .m_axis_tvalid(rdma_rd_cmd_arb.valid),
    .m_axis_tready(rdma_rd_cmd_arb.ready),
    .m_axis_tdata(rdma_rd_cmd_arb.req)
);

// Read data crossing
axis_data_fifo_rdma_512 inst_rdma_data_rd (
    .m_axis_aclk(net_clk),
    .s_axis_aclk(aclk),
    .s_axis_aresetn(aresetn),
    .s_axis_tvalid(axis_rdma_rd_data_arb.tvalid),
    .s_axis_tready(axis_rdma_rd_data_arb.tready),
    .s_axis_tdata(axis_rdma_rd_data_arb.tdata),
    .s_axis_tkeep(axis_rdma_rd_data_arb.tkeep),
    .s_axis_tlast(axis_rdma_rd_data_arb.tlast),
    .m_axis_tvalid(axis_rdma_rd_data_nclk.tvalid),
    .m_axis_tready(axis_rdma_rd_data_nclk.tready),
    .m_axis_tdata(axis_rdma_rd_data_nclk.tdata),
    .m_axis_tkeep(axis_rdma_rd_data_nclk.tkeep),
    .m_axis_tlast(axis_rdma_rd_data_nclk.tlast)
);

// Read command mux
`ifdef MULT_REGIONS
    network_mux_cmd_rd inst_mux_cmd_rd (
        .aclk(aclk),
        .aresetn(aresetn),
        .req_snk(rdma_rd_cmd_arb),
        .req_src(rdma_rd_cmd_aclk),
        .axis_rd_data_snk(axis_rdma_rd_data_aclk),
        .axis_rd_data_src(axis_rdma_rd_data_arb)
    );
`else
    assign rdma_rd_cmd_aclk[0].valid = rdma_rd_cmd_arb.valid;
    assign rdma_rd_cmd_arb.ready = rdma_rd_cmd_aclk[0].ready;
    assign rdma_rd_cmd_aclk[0].req = rdma_rd_cmd_arb.req;

    `AXIS_ASSIGN(axis_rdma_rd_data_aclk[0], axis_rdma_rd_data_arb)
`endif

// Write command crossing
//
rdmaIntf rdma_wr_cmd_arb();
AXI4S axis_rdma_wr_data_arb();

axis_data_fifo_cmd_rdma_96 inst_rdma_cmd_wr (
    .m_axis_aclk(aclk),
    .s_axis_aclk(net_clk),
    .s_axis_aresetn(net_aresetn),
    .s_axis_tvalid(rdma_wr_cmd_nclk.valid),
    .s_axis_tready(rdma_wr_cmd_nclk.ready),
    .s_axis_tdata(rdma_wr_cmd_nclk.req),
    .m_axis_tvalid(rdma_wr_cmd_arb.valid),
    .m_axis_tready(rdma_wr_cmd_arb.ready),
    .m_axis_tdata(rdma_wr_cmd_arb.req)
);

// Write data crossing
axis_data_fifo_rdma_512 inst_rdma_data_wr (
    .m_axis_aclk(aclk),
    .s_axis_aclk(net_clk),
    .s_axis_aresetn(net_aresetn),
    .s_axis_tvalid(axis_rdma_wr_data_nclk.tvalid),
    .s_axis_tready(axis_rdma_wr_data_nclk.tready),
    .s_axis_tdata(axis_rdma_wr_data_nclk.tdata),
    .s_axis_tkeep(axis_rdma_wr_data_nclk.tkeep),
    .s_axis_tlast(axis_rdma_wr_data_nclk.tlast),
    .m_axis_tvalid(axis_rdma_wr_data_arb.tvalid),
    .m_axis_tready(axis_rdma_wr_data_arb.tready),
    .m_axis_tdata(axis_rdma_wr_data_arb.tdata),
    .m_axis_tkeep(axis_rdma_wr_data_arb.tkeep),
    .m_axis_tlast(axis_rdma_wr_data_arb.tlast)
);

// Write command mux
`ifdef MULT_REGIONS
    network_mux_cmd_wr inst_mux_cmd_wr (
        .aclk(aclk),
        .aresetn(aresetn),
        .req_snk(rdma_wr_cmd_arb),
        .req_src(rdma_wr_cmd_aclk),
        .axis_wr_data_snk(axis_rdma_wr_data_arb),
        .axis_wr_data_src(axis_rdma_wr_data_aclk)
    );
`else
    assign rdma_wr_cmd_aclk[0].valid = rdma_wr_cmd_arb.valid;
    assign rdma_wr_cmd_arb.ready = rdma_wr_cmd_aclk[0].ready;
    assign rdma_wr_cmd_aclk[0].req = rdma_wr_cmd_arb.req;

    `AXIS_ASSIGN(axis_rdma_wr_data_arb, axis_rdma_wr_data_aclk[0])
`endif

/*
logic [31:0] cnt_arb_req_out;

always_ff @(posedge aclk, negedge aresetn) begin
if (aresetn == 1'b0) begin
	cnt_arb_req_out <= 0;
end
else
	cnt_arb_req_out <= (rdma_req_arb.valid & rdma_req_arb.ready) ? cnt_arb_req_out + 1 : cnt_arb_req_out;
end

ila_5 inst_ila_55 (
    .clk(aclk),
    .probe0(cnt_arb_req_out),
    .probe1(cnt_arb_data)
);
*/

/*
ila_0 inst_ila_0 (
    .clk(aclk),
    .probe0(rdma_rd_cmd_arb.valid),
    .probe1(rdma_rd_cmd_arb.ready),
    .probe2(rdma_rd_cmd_arb.req.vaddr),
    .probe3(rdma_rd_cmd_arb.req.len),
    .probe4(rdma_rd_cmd_arb.req.ctl),
    .probe5(rdma_rd_cmd_arb.id),
    .probe6(rdma_wr_cmd_arb.valid),
    .probe7(rdma_wr_cmd_arb.ready),
    .probe8(rdma_wr_cmd_arb.req.vaddr),
    .probe9(rdma_wr_cmd_arb.req.len),
    .probe10(rdma_wr_cmd_arb.req.ctl),
    .probe11(rdma_wr_cmd_arb.id),
    .probe12(axis_rdma_rd_data_arb.tvalid),
    .probe13(axis_rdma_rd_data_arb.tready),
    .probe14(axis_rdma_rd_data_arb.tlast),
    .probe15(axis_rdma_wr_data_arb.tvalid),
    .probe16(axis_rdma_wr_data_arb.tready),
    .probe17(axis_rdma_wr_data_arb.tlast)
);
*/
endmodule