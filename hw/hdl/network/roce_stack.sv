import lynxTypes::*;

module roce_stack (
    input  logic                net_clk,
    input  logic                net_aresetn,

    // Network interface
    AXI4S.s                     s_axis_rx_data,
    AXI4S.m                     m_axis_tx_data,

    // User command
    metaIntf.s                  s_axis_tx_meta,

    // RPC command
    metaIntf.m                  m_axis_rx_rpc_params,

    // Memory
    rdmaIntf.m                  m_axis_mem_read_cmd,
    rdmaIntf.m                  m_axis_mem_write_cmd,
    AXI4S.s                     s_axis_mem_read_data,
    AXI4S.m                     m_axis_mem_write_data,

    // Control
    metaIntf.s                  s_axis_qp_interface,
    metaIntf.s                  s_axis_qp_conn_interface,
    input  logic [31:0]         local_ip_address,

    // Debug
    output logic                crc_drop_pkg_count_valid,
    output logic[31:0]          crc_drop_pkg_count_data,
    output logic                psn_drop_pkg_count_valid,
    output logic[31:0]          psn_drop_pkg_count_data
);

// Requests
logic [103:0] rd_cmd_data;
logic [103:0] wr_cmd_data;

assign m_axis_mem_read_cmd.req.vaddr    = rd_cmd_data[0+:VADDR_BITS];
assign m_axis_mem_read_cmd.req.len      = rd_cmd_data[64+:LEN_BITS];
assign m_axis_mem_read_cmd.req.sync     = 1'b0;
assign m_axis_mem_read_cmd.req.ctl      = rd_cmd_data[100+:1];
assign m_axis_mem_read_cmd.req.stream   = rd_cmd_data[64+LEN_BITS+:1];
assign m_axis_mem_read_cmd.req.id       = rd_cmd_data[96+:N_REQUEST_BITS];
assign m_axis_mem_read_cmd.req.host     = rd_cmd_data[101+:1];

assign m_axis_mem_write_cmd.req.vaddr   = wr_cmd_data[0+:VADDR_BITS];
assign m_axis_mem_write_cmd.req.len     = wr_cmd_data[64+:LEN_BITS];
assign m_axis_mem_write_cmd.req.sync    = 1'b0;
assign m_axis_mem_write_cmd.req.ctl     = wr_cmd_data[100+:1];
assign m_axis_mem_write_cmd.req.stream  = wr_cmd_data[64+LEN_BITS+:1];
assign m_axis_mem_write_cmd.req.id      = wr_cmd_data[96+:N_REQUEST_BITS];
assign m_axis_mem_write_cmd.req.host    = wr_cmd_data[101+:1];

rocev2_ip rocev2_inst(
    .ap_clk(net_clk), // input aclk
    .ap_rst_n(net_aresetn), // input aresetn
    
    // RX
    .s_axis_rx_data_TVALID(s_axis_rx_data.tvalid),
    .s_axis_rx_data_TREADY(s_axis_rx_data.tready),
    .s_axis_rx_data_TDATA(s_axis_rx_data.tdata),
    .s_axis_rx_data_TKEEP(s_axis_rx_data.tkeep),
    .s_axis_rx_data_TLAST(s_axis_rx_data.tlast),
    
    // TX
    .m_axis_tx_data_TVALID(m_axis_tx_data.tvalid),
    .m_axis_tx_data_TREADY(m_axis_tx_data.tready),
    .m_axis_tx_data_TDATA(m_axis_tx_data.tdata),
    .m_axis_tx_data_TKEEP(m_axis_tx_data.tkeep),
    .m_axis_tx_data_TLAST(m_axis_tx_data.tlast),
    
    // User commands    
    .s_axis_tx_meta_V_TVALID(s_axis_tx_meta.valid),
    .s_axis_tx_meta_V_TREADY(s_axis_tx_meta.ready),
    .s_axis_tx_meta_V_TDATA(s_axis_tx_meta.data), 

    // RPC commands
    .m_axis_rx_rpc_params_V_data_TVALID(m_axis_rx_rpc_params.valid),
    .m_axis_rx_rpc_params_V_data_TREADY(m_axis_rx_rpc_params.ready),
    .m_axis_rx_rpc_params_V_data_TDATA(m_axis_rx_rpc_params.data),
    
    // Memory
    // Write commands
    .m_axis_mem_write_cmd_V_data_TVALID(m_axis_mem_write_cmd.valid),
    .m_axis_mem_write_cmd_V_data_TREADY(m_axis_mem_write_cmd.ready),
    .m_axis_mem_write_cmd_V_data_TDATA(wr_cmd_data),
    // Read commands
    .m_axis_mem_read_cmd_V_data_TVALID(m_axis_mem_read_cmd.valid),
    .m_axis_mem_read_cmd_V_data_TREADY(m_axis_mem_read_cmd.ready),
    .m_axis_mem_read_cmd_V_data_TDATA(rd_cmd_data),
    // Write data
    .m_axis_mem_write_data_TVALID(m_axis_mem_write_data.tvalid),
    .m_axis_mem_write_data_TREADY(m_axis_mem_write_data.tready),
    .m_axis_mem_write_data_TDATA(m_axis_mem_write_data.tdata),
    .m_axis_mem_write_data_TKEEP(m_axis_mem_write_data.tkeep),
    .m_axis_mem_write_data_TLAST(m_axis_mem_write_data.tlast),
    // Read data
    .s_axis_mem_read_data_TVALID(s_axis_mem_read_data.tvalid),
    .s_axis_mem_read_data_TREADY(s_axis_mem_read_data.tready),
    .s_axis_mem_read_data_TDATA(s_axis_mem_read_data.tdata),
    .s_axis_mem_read_data_TKEEP(s_axis_mem_read_data.tkeep),
    .s_axis_mem_read_data_TLAST(s_axis_mem_read_data.tlast),

    // QP intf
    .s_axis_qp_interface_V_TVALID(s_axis_qp_interface.valid),
    .s_axis_qp_interface_V_TREADY(s_axis_qp_interface.ready),
    .s_axis_qp_interface_V_TDATA(s_axis_qp_interface.data),
    .s_axis_qp_conn_interface_V_TVALID(s_axis_qp_conn_interface.valid),
    .s_axis_qp_conn_interface_V_TREADY(s_axis_qp_conn_interface.ready),
    .s_axis_qp_conn_interface_V_TDATA(s_axis_qp_conn_interface.data),
    .local_ip_address_V({local_ip_address,local_ip_address,local_ip_address,local_ip_address}), //Use IPv4 addr

    // Debug
    .regCrcDropPkgCount_V(crc_drop_pkg_count_data),
    .regCrcDropPkgCount_V_ap_vld(crc_drop_pkg_count_valid),
    .regInvalidPsnDropCount_V(psn_drop_pkg_count_data),
    .regInvalidPsnDropCount_V_ap_vld(psn_drop_pkg_count_valid)
    
);

endmodule