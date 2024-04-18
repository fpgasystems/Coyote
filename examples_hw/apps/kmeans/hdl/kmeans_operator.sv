import kmeansTypes::*;
import lynxTypes::*;

module k_means_operator  
(
	input  logic                                    aclk,
    input  logic                                    aresetn,

    AXI4SR.s                                        axis_tuple,
    AXI4SR.s                                        axis_centroid,
    AXI4SR.m                                        axis_output,

    input  logic                                    start_operator,
    input logic                                     um_done,

    input  logic [NUM_CLUSTER_BITS:0]               num_clusters,
    input  logic [MAX_DEPTH_BITS:0]                 data_dim,
    input  logic [7:0]                              precision,
    input  logic [63:0]                             data_set_size,

    output logic [7:0][31:0]                        agg_div_debug_cnt,
    output logic [7:0][31:0]                        k_means_module_debug_cnt
);

    AXI4SR axis_int ();

	k_means_module k_means_module
	(
		.clk                        (aclk),
		.rst_n                      (aresetn),

        // Params
		.num_cluster                (num_clusters),
        .data_dim                   (data_dim),
        .precision                  (precision),
        .data_set_size              (data_set_size),
        // Control and status
        .start_operator             (start_operator),
		.um_done                    (um_done),

        // Stream in
		.tuple_cl                   (axis_tuple.tdata),
		.tuple_cl_valid             (axis_tuple.tvalid),
		.tuple_cl_last              (axis_tuple.tlast),
		.tuple_cl_ready             (axis_tuple.tready),
		.centroid_cl                (axis_centroid.tdata),
		.centroid_cl_valid          (axis_centroid.tvalid),
		.centroid_cl_last           (axis_centroid.tlast),
		.centroid_cl_ready          (axis_centroid.tready),

        // Stream out
		.updated_centroid           (axis_int.tdata),
		.updated_centroid_valid     (axis_int.tvalid),
		.updated_centroid_last      (axis_int.tlast),

		.agg_div_debug_cnt          (agg_div_debug_cnt),
		.k_means_module_debug_cnt   (k_means_module_debug_cnt)
	);
	
	assign axis_output.tvalid = axis_int.tvalid;
	assign axis_output.tlast = axis_int.tlast;
	assign axis_output.tdata = axis_int.tdata;
	assign axis_output.tkeep = ~0;
	
	/*
    axis_data_fifo_512 inst_axis_fifo (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(axis_int.tvalid),
        .s_axis_tready(),
        .s_axis_tdata(axis_int.tdata),
        .s_axis_tkeep(~0),
        .s_axis_tlast(axis_int.tlast),
        .m_axis_tvalid(axis_output.tvalid),
        .m_axis_tready(axis_output.tready),
        .m_axis_tdata(axis_output.tdata),
        .m_axis_tkeep(axis_output.tkeep),
        .m_axis_tlast(axis_output.tlast)
    );
    */

endmodule