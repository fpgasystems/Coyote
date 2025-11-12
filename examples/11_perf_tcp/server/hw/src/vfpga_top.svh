
tcp_perf_server inst_perf_server(
    // .m_axis_listen_port_TVALID     (tcp_listen_req.valid),
    // .m_axis_listen_port_TREADY     (tcp_listen_req.ready),
    // .m_axis_listen_port_TDATA      (tcp_listen_req.data),
    // .s_axis_listen_port_status_TVALID     (tcp_listen_rsp.valid),
    // .s_axis_listen_port_status_TREADY     (tcp_listen_rsp.ready),
    // .s_axis_listen_port_status_TDATA      (tcp_listen_rsp.data),
    // .m_axis_open_connection_tvalid (tcp_open_req.tvalid),
    // .m_axis_open_connection_tready (tcp_open_req.tready),
    // .m_axis_open_connection_tdata  (tcp_open_req.tdata),
    // .s_axis_open_status_tvalid     (tcp_open_rsp.tvalid),
    // .s_axis_open_status_tready     (tcp_open_rsp.tready),
    // .s_axis_open_status_tdata      (tcp_open_rsp.tdata),
    // .m_axis_close_connection_tvalid(tcp_close_req.tvalid),
    // .m_axis_close_connection_tready(tcp_close_req.tready),
    // .m_axis_close_connection_tdata (tcp_close_req.tdata),
    
    .s_axis_notifications_TVALID    (tcp_notify.valid),
    .s_axis_notifications_TREADY    (tcp_notify.ready),
    .s_axis_notifications_TDATA     (tcp_notify.data),
    .m_axis_read_package_TVALID        (tcp_rd_pkg.valid),
    .m_axis_read_package_TREADY        (tcp_rd_pkg.ready),
    .m_axis_read_package_TDATA         (tcp_rd_pkg.data),
    .s_axis_rx_metadata_TVALID         (tcp_rx_meta.valid),
    .s_axis_rx_metadata_TREADY         (tcp_rx_meta.ready),
    .s_axis_rx_metadata_TDATA          (tcp_rx_meta.data),
    .s_axis_rx_data_TVALID         (axis_tcp_recv.tvalid),
    .s_axis_rx_data_TREADY         (axis_tcp_recv.tready),
    .s_axis_rx_data_TDATA          (axis_tcp_recv.tdata),
    .s_axis_rx_data_TKEEP          (axis_tcp_recv.tkeep),
    .s_axis_rx_data_TLAST          (axis_tcp_recv.tlast),
    .s_axis_rx_data_TSTRB          (0),
    // .m_axis_tx_meta_tvalid         (tcp_tx_meta.valid),
    // .m_axis_tx_meta_tready         (tcp_tx_meta.ready),
    // .m_axis_tx_meta_tdata          (tcp_tx_meta.data),
    // .m_axis_tx_data_tvalid         (axis_tcp_send[0].tvalid),
    // .m_axis_tx_data_tready         (axis_tcp_send[0].tready),
    // .m_axis_tx_data_tdata          (axis_tcp_send[0].tdata),
    // .m_axis_tx_data_tkeep          (axis_tcp_send[0].tkeep),
    // .m_axis_tx_data_tlast          (axis_tcp_send[0].tlast),
    // .s_axis_tx_status_tvalid       (tcp_tx_stat.valid),
    // .s_axis_tx_status_tready       (tcp_tx_stat.ready),
    // .s_axis_tx_status_tdata        (tcp_tx_stat.data)

    .ap_clk(aclk),
    .ap_rst_n(aresetn)
);

logic [1:0]  listen_ctrl;        
logic [15:0] listen_port_addr;   
logic [1:0]  port_sts_rd;        

logic        listen_rsp_ready;   
logic [7:0]  listen_rsp_data;    
logic [31:0] listen_port_acc;    

// Listen Port Host Control (ListenPort)
perf_tcp_axi_ctrl_parser inst_axi_ctrl(
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .listen_rsp_ready(listen_rsp_ready),
    .listen_rsp_data (listen_rsp_data),
    .listen_port_acc (listen_port_acc),
    .listen_ctrl     (listen_ctrl),
    .listen_port_addr(listen_port_addr),
    .port_sts_rd     (port_sts_rd)
);


logic go_q, clr_q;
wire  go_pulse  = listen_ctrl[0]  & ~go_q;
wire  clr_pulse = port_sts_rd[0]  & ~clr_q;


logic        lsn_valid_r;
logic [15:0] lsn_port_r;

always_ff @(posedge aclk) begin
    if(!aresetn) begin
        go_q <= 1'b0;
        clr_q <= 1'b0;

        lsn_valid_r       <= 1'b0;
        lsn_port_r        <= '0;

        listen_rsp_ready  <= 1'b0;   
        listen_rsp_data   <= '0;     
        listen_port_acc   <= '0;     
    end 
    else begin
        go_q <= listen_ctrl[0];
        clr_q <= port_sts_rd[0];
        if (go_pulse) begin
            lsn_port_r       <= listen_port_addr; 
            lsn_valid_r      <= 1'b1;

            listen_rsp_ready <= 1'b0;
        end

        if (lsn_valid_r && tcp_listen_req.ready) begin
            lsn_valid_r <= 1'b0;
        end

        if (tcp_listen_rsp.valid) begin
            listen_rsp_ready <= 1'b1;                       
            listen_rsp_data  <= tcp_listen_rsp.data[7:0];   

            listen_port_acc  <= listen_port_acc + 1;
        end

        if (clr_pulse) begin
            listen_rsp_ready <= 1'b0;
        end
    end
end


assign tcp_listen_req.valid = lsn_valid_r;
assign tcp_listen_req.data  = lsn_port_r;
assign tcp_listen_rsp.ready = 1'b1; 

// There are two host streams, for both incoming and outgoing signals
// The second outgoing is unused in this example, so tie it off
always_comb axis_host_recv[0].tie_off_s();
// always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[0].tie_off_m();
// always_comb axis_host_send[1].tie_off_m();


// Tie off TCP unused ports
always_comb tcp_open_req.tie_off_m();
always_comb tcp_open_rsp.tie_off_s();
always_comb tcp_close_req.tie_off_m();

always_comb tcp_tx_meta.tie_off_m();
always_comb axis_tcp_send.tie_off_m();
always_comb tcp_tx_stat.tie_off_s();


// Tie-off unused signals to avoid synthesis problems
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
// always_comb axi_ctrl.tie_off_s();

ila_perf_tcp inst_ila_perf_tcp (
    .clk(aclk),
    .probe0  (tcp_listen_req.valid),
    .probe1  (tcp_listen_req.ready),
    .probe2  (tcp_listen_req.data),
    .probe3  (tcp_listen_rsp.valid),
    .probe4  (tcp_listen_rsp.ready),
    .probe5  (tcp_listen_rsp.data),
    .probe6  (tcp_notify.valid),
    .probe7  (tcp_notify.ready),
    .probe8  (tcp_notify.data),
    .probe9  (tcp_rd_pkg.valid),
    .probe10 (tcp_rd_pkg.ready),
    .probe11 (tcp_rd_pkg.data),
    .probe12 (tcp_rx_meta.valid),
    .probe13 (tcp_rx_meta.ready),
    .probe14 (tcp_rx_meta.data),
    .probe15 (axis_tcp_recv.tvalid),
    .probe16 (axis_tcp_recv.tready),
    .probe17 (axis_tcp_recv.tdata),
    .probe18 (axis_tcp_recv.tlast)
);

