`timescale 1ns / 1ps

import lynxTypes::*;

module network_top (
    // Pcie
    input  wire                 aclk,
    input  wire                 aresetn,

    // Net
    input  wire                 sys_reset,  
    input  wire                 dclk,             
    input  wire                 gt_refclk_p,
    input  wire                 gt_refclk_n,

    // Phys.
`ifdef EN_RDMA_10G
    input  wire [0:0]          gt_rxp_in,         
    input  wire [0:0]          gt_rxn_in,            
    output wire [0:0]          gt_txp_out,
    output wire [0:0]          gt_txn_out,
`else
    input  wire [3:0]          gt_rxp_in,         
    input  wire [3:0]          gt_rxn_in,            
    output wire [3:0]          gt_txp_out,
    output wire [3:0]          gt_txn_out,
`endif

    // Init
    metaIntf.s                  arp_lookup_request,
    metaIntf.m                  arp_lookup_reply,
    metaIntf.s                  set_ip_addr,
    metaIntf.s                  set_board_number,
    metaIntf.s                  qp_interface,
    metaIntf.s                  conn_interface,

    // Commands
    metaIntf.s                  rdma_req_host [N_REGIONS],
`ifdef EN_FVV
    metaIntf.s                  rdma_req_card [N_REGIONS],
    metaIntf.m                  rdma_req_fv [N_REGIONS],
`endif

    // RDMA ctrl + data
    reqIntf.m                   rdma_rd_cmd [N_REGIONS],
    reqIntf.m                   rdma_wr_cmd [N_REGIONS],
    AXI4S.s                     axis_rdma_rd_data [N_REGIONS],
    AXI4S.m                     axis_rdma_wr_data [N_REGIONS]
);

/**
 * Clock Generation
 */
logic network_init;

// Network clock
logic net_aresetn;
logic net_clk;

// Network reset
BUFG bufg_aresetn(
    .I(network_init),
    .O(net_aresetn)
);

/**
 * Network module
 */
`ifdef EN_RDMA_10G
    AXI4S #(.AXI4S_DATA_BITS(64)) axis_net_rx_data_na();
    AXI4S #(.AXI4S_DATA_BITS(64)) axis_net_tx_data_na();
`else
    AXI4S axis_net_rx_data_na();
    AXI4S axis_net_tx_data_na();
`endif

AXI4S axis_net_rx_data();
AXI4S axis_net_tx_data();

network_module inst_network_module
(
    .dclk (dclk),
    .net_clk(net_clk),
    .sys_reset (sys_reset),
    .aresetn(net_aresetn),
    .network_init_done(network_init),
    
    .gt_refclk_p(gt_refclk_p),
    .gt_refclk_n(gt_refclk_n),
    
    .gt_rxp_in(gt_rxp_in),
    .gt_rxn_in(gt_rxn_in),
    .gt_txp_out(gt_txp_out),
    .gt_txn_out(gt_txn_out),
    
    .user_rx_reset(),
    .user_tx_reset(),
    .gtpowergood_out(),
    
    //master 0
    .m_axis_net_rx(axis_net_rx_data_na),
    .s_axis_net_tx(axis_net_tx_data_na)
);

/**
 * Width adjustments
 */
`ifdef EN_RDMA_10G   
    axis_64_to_512_converter net_rx_converter (
        .aclk(net_clk),
        .aresetn(net_aresetn),
        .s_axis_tvalid(axis_net_rx_data_na.tvalid),
        .s_axis_tready(axis_net_rx_data_na.tready),
        .s_axis_tdata(axis_net_rx_data_na.tdata),
        .s_axis_tkeep(axis_net_rx_data_na.tkeep),
        .s_axis_tlast(axis_net_rx_data_na.tlast),
        .s_axis_tdest(0),
        .m_axis_tvalid(axis_net_rx_data.tvalid),
        .m_axis_tready(axis_net_rx_data.tready),
        .m_axis_tdata(axis_net_rx_data.tdata),
        .m_axis_tkeep(axis_net_rx_data.tkeep),
        .m_axis_tlast(axis_net_rx_data.tlast),
        .m_axis_tdest()
    );
    axis_512_to_64_converter net_tx_converter (
        .aclk(net_clk),
        .aresetn(net_aresetn),
        .s_axis_tvalid(axis_net_tx_data.tvalid),
        .s_axis_tready(axis_net_tx_data.tready),
        .s_axis_tdata(axis_net_tx_data.tdata),
        .s_axis_tkeep(axis_net_tx_data.tkeep),
        .s_axis_tlast(axis_net_tx_data.tlast),
        .m_axis_tvalid(axis_net_tx_data_na.tvalid),
        .m_axis_tready(axis_net_tx_data_na.tready),
        .m_axis_tdata(axis_net_tx_data_na.tdata),
        .m_axis_tkeep(axis_net_tx_data_na.tkeep),
        .m_axis_tlast(axis_net_tx_data_na.tlast)
    );
`else
    assign axis_net_rx_data.tvalid        = axis_net_rx_data_na.tvalid;
    assign axis_net_rx_data_na.tready     = axis_net_rx_data.tready;
    assign axis_net_rx_data.tdata         = axis_net_rx_data_na.tdata;
    assign axis_net_rx_data.tkeep         = axis_net_rx_data_na.tkeep;
    assign axis_net_rx_data.tlast         = axis_net_rx_data_na.tlast;
    
    assign axis_net_tx_data_na.tvalid     = axis_net_tx_data.tvalid;
    assign axis_net_tx_data.tready        = axis_net_tx_data_na.tready;
    assign axis_net_tx_data_na.tdata      = axis_net_tx_data.tdata;
    assign axis_net_tx_data_na.tkeep      = axis_net_tx_data.tkeep;
    assign axis_net_tx_data_na.tlast      = axis_net_tx_data.tlast;
`endif

// Slices
AXI4S axis_net_rx_data_r ();
AXI4S axis_net_tx_data_r ();
axis_reg inst_slice_rx (.aclk(net_clk), .aresetn(net_aresetn), .axis_in(axis_net_rx_data), .axis_out(axis_net_rx_data_r));
axis_reg inst_slice_tx (.aclk(net_clk), .aresetn(net_aresetn), .axis_in(axis_net_tx_data_r), .axis_out(axis_net_tx_data));

/**
 * Network stack
 */

// Decl.
metaIntf #(.DATA_BITS(32)) arp_lookup_request_nclk();
metaIntf #(.DATA_BITS(56)) arp_lookup_reply_nclk();
metaIntf #(.DATA_BITS(32)) set_ip_addr_nclk();
metaIntf #(.DATA_BITS(4)) set_board_number_nclk();
metaIntf #(.DATA_BITS(144)) qp_interface_nclk();
metaIntf #(.DATA_BITS(184)) conn_interface_nclk();

metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_host_nclk();
metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_card_nclk();
metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_fv_nclk();

rdmaIntf rdma_rd_cmd_nclk ();
rdmaIntf rdma_wr_cmd_nclk ();
AXI4S axis_rdma_rd_data_nclk ();
AXI4S axis_rdma_wr_data_nclk ();

network_stack inst_network_stack (
    .net_clk(net_clk),
    .net_aresetn(net_aresetn),

    .s_axis_net(axis_net_rx_data_r),
    .m_axis_net(axis_net_tx_data_r),

    .arp_lookup_request(arp_lookup_request_nclk),
    .arp_lookup_reply(arp_lookup_reply_nclk),
    .set_ip_addr(set_ip_addr_nclk),
    .set_board_number(set_board_number_nclk),
    .qp_interface(qp_interface_nclk),
    .conn_interface(conn_interface_nclk),

    .s_axis_host_meta(rdma_req_host_nclk),
    .s_axis_card_meta(rdma_req_card_nclk),
    .m_axis_rpc_meta(rdma_req_fv_nclk),

    .m_axis_roce_read_cmd(rdma_rd_cmd_nclk),
    .m_axis_roce_write_cmd(rdma_wr_cmd_nclk),
    .s_axis_roce_read_data(axis_rdma_rd_data_nclk),
    .m_axis_roce_write_data(axis_rdma_wr_data_nclk)
);

network_clk_cross inst_network_clk_cross (
    .aclk(aclk),
    .aresetn(aresetn),
    .net_clk(net_clk),
    .net_aresetn(net_aresetn),
    
    // ACLK
    .arp_lookup_request_aclk(arp_lookup_request),
    .arp_lookup_reply_aclk(arp_lookup_reply),
    .set_ip_addr_aclk(set_ip_addr),
    .set_board_number_aclk(set_board_number),
    .qp_interface_aclk(qp_interface),
    .conn_interface_aclk(conn_interface),

    .rdma_req_host_aclk(rdma_req_host),
`ifdef EN_FVV
    .rdma_req_card_aclk(rdma_req_card),
    .rdma_req_fv_aclk(rdma_req_fv),
`endif

    .rdma_rd_cmd_aclk(rdma_rd_cmd),
    .rdma_wr_cmd_aclk(rdma_wr_cmd),
    .axis_rdma_rd_data_aclk(axis_rdma_rd_data),
    .axis_rdma_wr_data_aclk(axis_rdma_wr_data),

    // NCLK
    .arp_lookup_request_nclk(arp_lookup_request_nclk),
    .arp_lookup_reply_nclk(arp_lookup_reply_nclk),
    .set_ip_addr_nclk(set_ip_addr_nclk),
    .set_board_number_nclk(set_board_number_nclk),
    .qp_interface_nclk(qp_interface_nclk),
    .conn_interface_nclk(conn_interface_nclk),

    .rdma_req_host_nclk(rdma_req_host_nclk),
`ifdef EN_FVV
    .rdma_req_card_nclk(rdma_req_card_nclk),
    .rdma_req_fv_nclk(rdma_req_fv_nclk),
`endif

    .rdma_rd_cmd_nclk(rdma_rd_cmd_nclk),
    .rdma_wr_cmd_nclk(rdma_wr_cmd_nclk),
    .axis_rdma_rd_data_nclk(axis_rdma_rd_data_nclk),
    .axis_rdma_wr_data_nclk(axis_rdma_wr_data_nclk)
);

`ifndef EN_FVV
assign rdma_req_card_nclk.valid = 1'b0;
assign rdma_req_fv_nclk.ready = 1'b1;
`endif


endmodule