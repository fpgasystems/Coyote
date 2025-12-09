logic                        runTx;
logic [15:0]                 numSessions;
logic [31:0]                 pkgWordCount;
logic [31:0]                 serverIpAddress;
logic [31:0]                 userFrequency;
logic [31:0]                 timeInSeconds;
logic [31:0]                 totalWord;

logic                        runTx_host;
logic [15:0]                 numSessions_host;
logic [31:0]                 pkgWordCount_host;
logic [31:0]                 serverIpAddress_host;
logic [31:0]                 userFrequency_host;
logic [31:0]                 timeInSeconds_host;
logic [31:0]                 totalWord_host;

logic [3:0]                  client_state;
logic [3:0]                  client_state_host;


tcp_perf_client inst_perf_client(
    // .m_axis_listen_port_TVALID     (tcp_listen_req.valid),
    // .m_axis_listen_port_TREADY     (tcp_listen_req.ready),
    // .m_axis_listen_port_TDATA      (tcp_listen_req.data),
    // .s_axis_listen_port_status_TVALID     (tcp_listen_rsp.valid),
    // .s_axis_listen_port_status_TREADY     (tcp_listen_rsp.ready),
    // .s_axis_listen_port_status_TDATA      (tcp_listen_rsp.data),
    .m_axis_open_connection_TVALID (tcp_open_req.valid),
    .m_axis_open_connection_TREADY (tcp_open_req.ready),
    .m_axis_open_connection_TDATA  (tcp_open_req.data),
    .s_axis_open_status_TVALID     (tcp_open_rsp.valid),
    .s_axis_open_status_TREADY     (tcp_open_rsp.ready),
    .s_axis_open_status_TDATA      (tcp_open_rsp.data),
    .m_axis_close_connection_TVALID(tcp_close_req.valid),
    .m_axis_close_connection_TREADY(tcp_close_req.ready),
    .m_axis_close_connection_TDATA (tcp_close_req.data),
    
    // .s_axis_notifications_TVALID    (tcp_notify.valid),
    // .s_axis_notifications_TREADY   (tcp_notify.ready),
    // .s_axis_notifications_TDATA     (tcp_notify.data),
    // .m_axis_read_package_TVALID        (tcp_rd_pkg.valid),
    // .m_axis_read_package_TREADY        (tcp_rd_pkg.ready),
    // .m_axis_read_package_TDATA         (tcp_rd_pkg.data),
    // .s_axis_rx_metadata_TVALID         (tcp_rx_meta.valid),
    // .s_axis_rx_metadata_TREADY         (tcp_rx_meta.ready),
    // .s_axis_rx_metadata_TDATA          (tcp_rx_meta.data),
    // .s_axis_rx_data_TVALID         (axis_tcp_recv.tvalid),
    // .s_axis_rx_data_TREADY         (axis_tcp_recv.tready),
    // .s_axis_rx_data_TDATA          (axis_tcp_recv.tdata),
    // .s_axis_rx_data_TKEEP          (axis_tcp_recv.tkeep),
    // .s_axis_rx_data_TLAST          (axis_tcp_recv.tlast),
    // .s_axis_rx_data_TSTRB          (0),
    .m_axis_tx_meta_TVALID         (tcp_tx_meta.valid),
    .m_axis_tx_meta_TREADY         (tcp_tx_meta.ready),
    .m_axis_tx_meta_TDATA          (tcp_tx_meta.data),
    .m_axis_tx_data_TVALID         (axis_tcp_send.tvalid),
    .m_axis_tx_data_TREADY         (axis_tcp_send.tready),
    .m_axis_tx_data_TDATA          (axis_tcp_send.tdata),
    .m_axis_tx_data_TKEEP          (axis_tcp_send.tkeep),
    .m_axis_tx_data_TLAST          (axis_tcp_send.tlast),
    .s_axis_tx_status_TVALID       (tcp_tx_stat.valid),
    .s_axis_tx_status_TREADY       (tcp_tx_stat.ready),
    .s_axis_tx_status_TDATA        (tcp_tx_stat.data),
    .runTx                             (runTx),
    .numSessions                       (numSessions),                         
    .pkgWordCount                      (pkgWordCount),     
    .serverIpAddress                   (serverIpAddress),
    .userFrequency                     (userFrequency),
    .timeInSeconds                     (timeInSeconds),       
    .totalWord                         (totalWord),
    .state_debug                       (client_state),

    .ap_clk(aclk),
    .ap_rst_n(aresetn)
);


   

// Listen Port Host Control (ListenPort)
perf_tcp_axi_ctrl_parser inst_axi_ctrl(
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),

    .runTx(runTx_host),
    .numSessions(numSessions_host),
    .pkgWordCount(pkgWordCount_host),
    .serverIpAddress(serverIpAddress_host),
    .userFrequency(userFrequency_host),
    .timeInSeconds(timeInSeconds_host),
    .state(client_state_host),
    .totalWord(totalWord_host)
);


// 1 cycle FF
always_ff @(posedge aclk) begin
    if(!aresetn) begin
        runTx <= 0;
        numSessions <= 0;
        pkgWordCount <= 0;
        serverIpAddress <= 0;
        userFrequency <= 0;
        timeInSeconds <= 0;
        totalWord_host <= 0;
        client_state_host <= 0;    

    end
    else begin
        runTx <= runTx_host;
        numSessions <= numSessions_host;
        pkgWordCount <= pkgWordCount_host;
        serverIpAddress <= serverIpAddress_host;
        userFrequency <= userFrequency_host;
        timeInSeconds <= timeInSeconds_host;
        totalWord_host <= totalWord;   
        client_state_host <= client_state;    
    end
end





// Tie off
always_comb axis_host_recv[0].tie_off_s();
always_comb axis_host_send[0].tie_off_m();

// Tie off TCP unused ports
always_comb tcp_listen_req.tie_off_m();
always_comb tcp_listen_rsp.tie_off_s();

always_comb tcp_notify.tie_off_s();
always_comb tcp_rd_pkg.tie_off_m();
always_comb tcp_rx_meta.tie_off_s();
always_comb axis_tcp_recv.tie_off_s();

// Tie-off unused signals to avoid synthesis problems
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
// always_comb axi_ctrl.tie_off_s();

ila_perf_tcp inst_ila_perf_tcp (
    .clk(aclk),
    .probe0  (tcp_open_req.valid),
    .probe1  (tcp_open_req.ready),
    .probe2  (tcp_open_req.data),
    .probe3  (tcp_open_rsp.valid),
    .probe4  (tcp_open_rsp.ready),
    .probe5  (tcp_open_rsp.data),
    .probe6  (tcp_close_req.valid),
    .probe7  (tcp_close_req.ready),
    .probe8  (tcp_close_req.data),
    .probe9  (tcp_tx_meta.valid),
    .probe10 (tcp_tx_meta.ready),
    .probe11 (tcp_tx_meta.data),
    .probe12 (tcp_tx_stat.valid),
    .probe13 (tcp_tx_stat.ready),
    .probe14 (tcp_tx_stat.data),
    .probe15 (axis_tcp_send.tvalid),
    .probe16 (axis_tcp_send.tready),
    .probe17 (axis_tcp_send.tdata),
    .probe18 (axis_tcp_send.tlast),
    .probe19 (client_state)
);

