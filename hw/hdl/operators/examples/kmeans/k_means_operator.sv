import kmeansTypes::*;
import lynxTypes::*;

module k_means_operator  
(
	input  logic                                    aclk,
    input  logic                                    aresetn,

    AXI4S.s                                         axis_tuple,
    AXI4S.s                                         axis_centroid,
    AXI4S.m                                         axis_output,

    input  logic                                    start_operator,
    output logic                                    um_done,

    input  logic [63:0]                             data_set_size,
    input  logic [NUM_CLUSTER_BITS:0]               num_clusters,
    input  logic [MAX_DEPTH_BITS:0]                 data_dim,

    output logic [7:0][31:0]                        agg_div_debug_cnt,
    output logic [7:0][31:0]                        k_means_module_debug_cnt
);

    AXI4S tmp ();

	k_means_module k_means_module
	(
		.clk                        (aclk),
		.rst_n                      (aresetn),

		.start_operator             (start_operator),
		.um_done                    (um_done),

		.data_set_size              (data_set_size),
		.num_cluster                (num_clusters),
		.data_dim                   (data_dim),
		// .precision               (precision),

		.tuple_cl                   (axis_tuple.tdata),
		.tuple_cl_valid             (axis_tuple.tvalid),
		.tuple_cl_last              (axis_tuple.tlast),
		.tuple_cl_ready             (axis_tuple.tready),
		.centroid_cl                (axis_centroid.tdata),
		.centroid_cl_valid          (axis_centroid.tvalid),
		.centroid_cl_last           (axis_centroid.tlast),
		.centroid_cl_ready          (axis_centroid.tready),

		.updated_centroid           (tmp.tdata),
		.updated_centroid_valid     (tmp.tvalid),
		.updated_centroid_last      (tmp.tlast),

		.agg_div_debug_cnt          (agg_div_debug_cnt),
		.k_means_module_debug_cnt   (k_means_module_debug_cnt)
	);
	
	
    axis_fifo_0 inst_axis_fifo (
        .s_aclk(aclk),
        .s_aresetn(aresetn),
        .s_axis_tvalid(tmp.tvalid),
        .s_axis_tready(),
        .s_axis_tdata(tmp.tdata),
        .s_axis_tkeep(~0),
        .s_axis_tlast(tmp.tlast),
        .m_axis_tvalid(axis_output.tvalid),
        .m_axis_tready(axis_output.tready),
        .m_axis_tdata(axis_output.tdata),
        .m_axis_tkeep(axis_output.tkeep),
        .m_axis_tlast(axis_output.tlast)
    );

endmodule