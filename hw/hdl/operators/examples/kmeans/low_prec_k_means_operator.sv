
// -------------------------------------------------------------------------------
// -- Title      : K_means
// -- Project    : Semester project k_means
// -------------------------------------------------------------------------------
// -- File       : 
// -- Author     : He Zhenhao
// -- Company    : ETH Zurich
// -- Created    : 
// -- Last update: 2018-01-18
// -- Platform   : 
// -- Standard   : SystemVerilog
// -------------------------------------------------------------------------------
// -- Description: k-means operator supporting concurrent execution of different k values
// -------------------------------------------------------------------------------
// -- Revisions  :
// -- Date        Version  Author  Description
// -- 2017-11-17  1.0      He   	Functionally correct
// -- 2017-11-20  2.0      He       single pipeline with aggregation, functionally correct
// -- 2017-11-23  3.0      He       buffer+pipe_processor+accumulation as pipeline module
//									should further examin the correctness when read buffer almost full
// -- 2017-11-29  4.0      He       parallel pipeline under same k
// -- 2018-01-18  5.0      He 		concurrent execution under different k, cleaned up code
// -------------------------------------------------------------------------------
import kmeansTypes::*;

module low_prec_k_means_operator  
(
	input wire clk,    // Clock
	//input clk_en, // Clock Enable
	input wire rst_n,  // Asynchronous reset active low
	input   logic                                   start_um,
    input   logic [511:0]                          	um_params,
    output  logic                                   um_done,
    // TX RD
    output  logic  [57:0]                            um_tx_rd_addr,
    output  logic  [7:0]                             um_tx_rd_tag,
    output  logic                                    um_tx_rd_valid,
    input   logic                                    um_tx_rd_ready,
    // TX WR
    output  logic  [57:0]                            um_tx_wr_addr,
    output  logic  [7:0]                             um_tx_wr_tag,
    output  logic                                    um_tx_wr_valid,
    output  logic  [511:0]                           um_tx_data,
    input   logic                                    um_tx_wr_ready,
    // RX RD
    input   logic [7:0]                             um_rx_rd_tag,
    input   logic [511:0]                           um_rx_data,
    input   logic                                   um_rx_rd_valid,
    output  logic 				    				um_rx_rd_ready,
    // RX WR 
    input   logic                                   um_rx_wr_valid,
    input   logic [7:0]                             um_rx_wr_tag,

    output logic [255:0] 			  				um_state_counters,
    output logic 				    				um_state_counters_valid
	
);

	RuntimeParam 						rp, rp_reg;
	reg 								start_um_reg;

	wire [511:0] 						tuple_cl;
	wire 								tuple_cl_valid;
	wire 								tuple_cl_last;

	wire [511:0]						centroid_cl;
	wire 								centroid_cl_valid;
	wire 								centroid_cl_last;

	wire 								tuple_cl_ready, centroid_cl_ready;

	wire [511:0]					update;
	wire 							update_valid;
	wire 							update_last;

	reg 							rst_n_reg, rst_n_reg2;

	wire [1:0][31:0]				fetch_engine_debug_cnt;
	wire [2:0][31:0] 				formatter_debug_cnt;
	wire [7:0][31:0]				agg_div_debug_cnt;
	wire [31:0]						wr_engine_debug_cnt;
	wire [7:0][31:0]				k_means_module_debug_cnt;

	wire 							start_operator;
	reg 							um_done_reg;

	reg [NUM_CLUSTER_BITS:0] 		num_cluster;// the actual number of cluster that will be used 
	reg [MAX_DEPTH_BITS:0] 			data_dim; //input the actual dimension of the data
	// reg [7:0]						precision;
	reg [63:0] 						data_set_size;


	// //store the runtime parameters
	runtimeParam_Manager rp_Manager(
		.clk         (clk),
		.rst_n       (rst_n_reg2),
		.start_um    (start_um),
		.um_params   (um_params),
		.runtimeParam(rp),
		.start_operator(start_operator)
		);

	fetch_engine fetch_engine
	(
		.clk              (clk),
		.rst_n            (rst_n_reg2),
		.start_operator   (start_operator),
		.rp               (rp_reg),
		.um_tx_rd_addr    (um_tx_rd_addr),
		.um_tx_rd_tag     (um_tx_rd_tag),
		.um_tx_rd_valid   (um_tx_rd_valid),
		.um_tx_rd_ready   (um_tx_rd_ready),
		.um_rx_rd_tag     (um_rx_rd_tag),
		.um_rx_data       (um_rx_data),
		.um_rx_rd_valid   (um_rx_rd_valid),
		.um_rx_rd_ready   (um_rx_rd_ready),

		.tuple_cl         (tuple_cl),
		.tuple_cl_valid   (tuple_cl_valid),
		.tuple_cl_last    (tuple_cl_last),
		.tuple_cl_ready   (tuple_cl_ready),
		.centroid_cl      (centroid_cl),
		.centroid_cl_valid(centroid_cl_valid),
		.centroid_cl_last (centroid_cl_last),
		.centroid_cl_ready (centroid_cl_ready),
		.fetch_engine_debug_cnt(fetch_engine_debug_cnt)
		);


	k_means_module k_means_module
	(
		.clk               (clk),
		.rst_n             (rst_n_reg2),

		.start_operator    (start_operator),
		.um_done           (um_done),

		.data_set_size     (data_set_size),
		.num_cluster       (num_cluster),
		.data_dim          (data_dim),
		// .precision         (precision),

		.tuple_cl                (tuple_cl),
		.tuple_cl_valid          (tuple_cl_valid),
		.tuple_cl_last           (tuple_cl_last),
		.tuple_cl_ready          (tuple_cl_ready),
		.centroid_cl             (centroid_cl),
		.centroid_cl_valid       (centroid_cl_valid),
		.centroid_cl_last        (centroid_cl_last),
		.centroid_cl_ready       (centroid_cl_ready),

		.updated_centroid        (update),
		.updated_centroid_valid  (update_valid),
		.updated_centroid_last   (update_last),

		.agg_div_debug_cnt (agg_div_debug_cnt),
		.k_means_module_debug_cnt(k_means_module_debug_cnt)
		);

	wr_engine wr_engine
	(
		.clk            (clk),
		.rst_n          (rst_n_reg2),
		.rp             (rp_reg),
		.start_operator (start_operator),
		.um_tx_wr_addr  (um_tx_wr_addr),
		.um_tx_wr_tag   (um_tx_wr_tag),
		.um_tx_wr_valid (um_tx_wr_valid),
		.um_tx_data     (um_tx_data),
		.um_tx_wr_ready (um_tx_wr_ready),
		.um_done        (um_done),
		.update             (update),
		.update_valid       (update_valid),
		.update_last        (update_last),
		.wr_engine_debug_cnt(wr_engine_debug_cnt)
		);


//////////////////////set state counters//////////////////////////////////
	reg [7:0][31:0] 	state_counters, state_counters_reg, state_counters_reg2;

	always @ (posedge clk) begin
		state_counters[0] <= fetch_engine_debug_cnt[0];
		state_counters[1] <= fetch_engine_debug_cnt[1];
		state_counters[2] <= formatter_debug_cnt[0];
		state_counters[3] <= formatter_debug_cnt[1];
		state_counters[4] <= formatter_debug_cnt[2];
		state_counters[5] <= agg_div_debug_cnt[0];
		state_counters[6] <= agg_div_debug_cnt[1];
		state_counters[7] <= wr_engine_debug_cnt;
		// state_counters <= agg_div_debug_cnt;

		state_counters_reg <= state_counters;
		state_counters_reg2 <= state_counters_reg;
	end

	assign um_state_counters={	
								state_counters_reg2[7],
								state_counters_reg2[6],
								state_counters_reg2[5],
								state_counters_reg2[4],
								state_counters_reg2[3],
								state_counters_reg2[2],
								state_counters_reg2[1],
								state_counters_reg2[0]
								};

/////////////////////////////////////////////////////////////////////////////

	always_ff @(posedge clk) begin : proc_rst_reg
		rst_n_reg <= rst_n;
		rst_n_reg2 <= rst_n_reg & ~um_done_reg;
		um_done_reg <= um_done;
		start_um_reg <= start_um;
		rp_reg <= rp;
		num_cluster <= rp_reg.num_cluster;
		// precision <= rp_reg.precision;
		data_dim <= rp_reg.data_dim;
		data_set_size <= rp.data_set_size;
	end



endmodule

	
