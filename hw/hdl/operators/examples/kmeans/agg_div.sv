`default_nettype none
import kmeansTypes::*;

module agg_div
(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire 							   start_operator,

	input wire [MAX_DEPTH_BITS:0]          data_dim, //input the actual dimension of the data
  	input wire [NUM_CLUSTER_BITS:0]        num_cluster, //input the actual number of cluster

  	//interface with pipelines
 	// output wire                       	agg_ready,
  // 	input wire [NUM_PIPELINE-1:0]     	accu_finish,

  	input wire [63:0]                 	agg_data,
  	input wire                        	agg_valid,

  	//interface with the 
  	//input wire 							write_engine_ready,
  	//input wire 							update_ready,
  	output wire [MAX_DIM_WIDTH-1:0] 	update,
	output wire 						update_valid,
	output wire 						update_last,
	output wire 						update_last_dim,

	//debug counter
	output reg [7:0][31:0] 				agg_div_debug_cnt

);

	 wire [63:0]                div_sum;
	 wire [63:0]                div_count;
	 wire                       div_valid;
	 wire                       div_last_dim;
	 wire                       div_last;

	 wire [63:0]                sse;
	 wire                       sse_valid;
	 wire                       sse_converge;

	 wire 						div_dout_last_dim;
	 wire 						div_dout_last;
	 wire [MAX_DIM_WIDTH-1:0] 	div_dout; 
	 wire 						div_dout_valid;

	 reg [MAX_DEPTH_BITS:0]   	data_dim_reg;
	 reg [NUM_CLUSTER_BITS:0]   num_cluster_reg;

	 wire [7:0] [31:0] 			k_means_aggregation_debug_cnt;
	 wire [31:0]				k_means_division_debug_cnt;

	 reg 						rst_n_reg;
	 reg 						start_operator_reg;
	 always @ (posedge clk) begin
	 	rst_n_reg <= rst_n;
	 	start_operator_reg <= start_operator;
	 end
	
	k_means_aggregation agg (
		.clk         (clk),
		.rst_n       (rst_n_reg),
		.start_operator (start_operator_reg),
		.data_dim    (data_dim_reg),
		.num_cluster (num_cluster_reg),
		// .agg_ready   (agg_ready),
		// .accu_finish (accu_finish),
		.agg_data    (agg_data),
		.agg_valid   (agg_valid),
		.div_sum     (div_sum),
		.div_count   (div_count),
		.div_valid   (div_valid),
		.div_last_dim(div_last_dim),
		.div_last    (div_last),
		.sse         (sse),
		.sse_valid   (sse_valid),
		.sse_converge(sse_converge),
		.k_means_aggregation_debug_cnt(k_means_aggregation_debug_cnt)
		);

	k_means_division division
	(
		.clk              (clk),
		.rst_n            (rst_n_reg),
		.start_operator   (start_operator_reg),
		.div_sum          (div_sum),
		.div_count        (div_count),
		.div_valid        (div_valid),
		.div_last_dim     (div_last_dim),
		.div_last         (div_last),
		.div_dout_last_dim(div_dout_last_dim),
		.div_dout_last    (div_dout_last),
		.div_dout         (div_dout),
		.div_dout_valid   (div_dout_valid),
		.k_means_division_debug_cnt(k_means_division_debug_cnt)
	);


	div_buffer div_buffer(
		.clk              (clk),
		.rst_n            (rst_n_reg),
		.div_dout         (div_dout),
		.div_dout_valid   (div_dout_valid),
		.div_dout_last_dim(div_dout_last_dim),
		.div_dout_last    (div_dout_last),
		//.update_ready     (write_engine_ready&update_ready),
		.update           (update),
		.update_valid     (update_valid),
		.update_last      (update_last),
		.update_last_dim  (update_last_dim)
		);


	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			num_cluster_reg <= '0;
			data_dim_reg <= '0;
		end
		else begin 
			num_cluster_reg <= num_cluster;
			data_dim_reg <= data_dim;
		end

		// agg_div_debug_cnt[0] <= k_means_aggregation_debug_cnt[0];
		// agg_div_debug_cnt[1] <= k_means_division_debug_cnt;
		agg_div_debug_cnt <= k_means_aggregation_debug_cnt;
	end

	

endmodule
`default_nettype wire
