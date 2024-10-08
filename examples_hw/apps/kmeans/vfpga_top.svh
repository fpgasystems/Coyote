//
// K Means top level header
//

// Reg inputs
AXI4SR axis_centroid ();
AXI4SR axis_tuple ();
AXI4SR axis_output ();

axisr_reg inst_centroid_reg (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_recv[0]), .m_axis(axis_centroid));
axisr_reg inst_tuple_reg    (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_recv[1]), .m_axis(axis_tuple));
axisr_reg inst_out_reg      (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_output), .m_axis(axis_card_send[0]));

// Slave
logic [NUM_CLUSTER_BITS:0] num_clusters;
logic [MAX_DEPTH_BITS:0] data_dim;
logic [63:0] data_set_size;
logic [7:0]  precision;

logic start_operator;
logic um_done;

k_means_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .num_clusters(num_clusters),
    .data_dim(data_dim),
    .data_set_size(data_set_size),
    .precision(precision),
    
    .start_operator(start_operator),
    .um_done(um_done),
    
    .select()
);

// Debug
logic [7:0][31:0] agg_div_debug_cnt;
logic [7:0][31:0] k_means_module_debug_cnt;


k_means_operator inst_top (
    .aclk(aclk),
    .aresetn(aresetn),

    .axis_tuple(axis_tuple),
    .axis_centroid(axis_centroid),
    .axis_output(axis_output),

    .start_operator(start_operator),
    .um_done(um_done),

    .num_clusters(num_clusters), // 3
    .data_dim(data_dim), // 10
    .precision(precision), // 8
    .data_set_size(data_set_size), // 64

    .agg_div_debug_cnt(agg_div_debug_cnt),
    .k_means_module_debug_cnt(k_means_module_debug_cnt)
);

ila_0 inst_ila_0 (
    .clk(aclk),
    .probe0(agg_div_debug_cnt), // 256
    .probe1(k_means_module_debug_cnt), // 256

    .probe2(axis_tuple.tvalid),
    .probe3(axis_tuple.tready),
    .probe4(axis_tuple.tlast),
    .probe5(axis_centroid.tvalid),
    .probe6(axis_centroid.tready),
    .probe7(axis_centroid.tlast),
    .probe8(axis_output.tvalid),
    .probe9(axis_output.tready),
    .probe10(axis_output.tlast),

    .probe11(start_operator),
    .probe12(um_done),

    .probe13(num_clusters), // 3
    .probe14(data_dim), // 10
    .probe15(precision), // 8
    .probe16(data_set_size) // 64
);