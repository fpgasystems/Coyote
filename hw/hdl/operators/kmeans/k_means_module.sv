

`default_nettype none
import kmeansTypes::*;

module k_means_module 
(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire 								start_operator,
	input wire 								um_done,

	input wire [NUM_CLUSTER_BITS:0] 		num_cluster,// the actual number of cluster that will be used 
	input wire [MAX_DEPTH_BITS:0] 			data_dim, //input the actual dimension of the data
	input wire [63:0] 						data_set_size,

	//interface to fetch engine
    input wire [511:0] 						tuple_cl,
    input wire 								tuple_cl_valid,
    input wire 								tuple_cl_last,
    output wire 							tuple_cl_ready,

    input wire [511:0]						centroid_cl, //not in bit-weaving format
    input wire 								centroid_cl_valid,
    input wire 								centroid_cl_last,
    output wire								centroid_cl_ready,	
    
	//update to write engine and formatter
  	output wire [511:0] 					updated_centroid,
	output wire 							updated_centroid_valid,
	output wire 							updated_centroid_last,

	//debug counter
	output wire [7:0][31:0]					agg_div_debug_cnt,
	output wire [7:0][31:0]					k_means_module_debug_cnt

);



reg start_operator_reg, um_done_reg, rst_n_reg, running_kmeans;
reg [MAX_DEPTH_BITS:0] data_dim_minus_1;
reg [NUM_CLUSTER_BITS:0] num_cluster_minus_1;

always @ (posedge clk) begin
	rst_n_reg <= rst_n;

	if(~rst_n_reg) begin
		running_kmeans <= 1'b0;
		start_operator_reg <= 1'b0;
		um_done_reg <= 1'b0; 
	end
	else begin
		start_operator_reg <= start_operator;
		um_done_reg <= um_done;

		data_dim_minus_1 <= '0;
		num_cluster_minus_1 <= '0;
		if(running_kmeans) begin
			data_dim_minus_1 <= data_dim - 1;
			num_cluster_minus_1 <= num_cluster -1;
		end

		if(start_operator_reg) begin
			running_kmeans <= 1'b1;
		end
		else if(um_done_reg) begin
			running_kmeans <= 1'b0;
		end
	end
end

//--------------------------split the centroid cachelines-----------------//
//--------------------------re-group the tuple cachelines------------------//
wire [32-1:0]								centroid;
wire 										centroid_valid;
wire 										last_dim_of_all_centroid;
wire  										last_dim_of_one_centroid;

wire [NUM_PIPELINE-1:0][32-1:0]				tuple;
wire 										tuple_valid;
wire 									 	last_dim_of_one_tuple;

wire [511:0] 								formatter_centroid_input;
wire 										formatter_centroid_input_valid;

reg [511:0] update_cl;
reg 		update_cl_valid;
reg 		update_cl_last;

//multiplex receiving centroid from initial ones and updated ones
assign formatter_centroid_input = centroid_cl_valid ? centroid_cl : update_cl;
assign formatter_centroid_input_valid = centroid_cl_valid ? 1'b1 : update_cl_valid; 

Formatter Formatter
(
	.clk                 (clk),
	.rst_n               (rst_n),
	.num_cluster         (num_cluster),
	.data_dim            (data_dim),
	.tuple_cl            (tuple_cl),
	.tuple_cl_valid      (tuple_cl_valid),
	.centroid_cl         (formatter_centroid_input),
	.centroid_cl_valid   (formatter_centroid_input_valid),
	.centroid_cl_ready    (centroid_cl_ready),
	.centroid      (centroid),
	.centroid_valid(centroid_valid),
	.last_dim_of_all_centroid(last_dim_of_all_centroid),
	.last_dim_of_one_centroid(last_dim_of_one_centroid),
	.tuple           (tuple),
	.tuple_valid     (tuple_valid),
	.last_dim_of_one_tuple     (last_dim_of_one_tuple),
	.formatter_debug_cnt ()
	);



//request mem data when norm of all centroids have been calculated
reg request_mem_data;
always @ (posedge clk) begin
	if(~rst_n_reg) begin
		request_mem_data <= 1'b0;
	end
	else begin
		if(last_dim_of_one_centroid) begin
			request_mem_data <= 1'b1;
		end
		else if(tuple_cl_valid & tuple_cl_last) begin
			request_mem_data <= 1'b0;
		end
	end
end

assign tuple_cl_ready = request_mem_data;
//----------------------Assignment calculation---------------------------------//
wire [NUM_CLUSTER:0][32-1:0]					centroid_pip;
wire [NUM_CLUSTER:0]							centroid_valid_pip;
wire [NUM_CLUSTER:0]							last_dim_of_one_centroid_pip;
wire [NUM_CLUSTER:0]							last_dim_of_all_centroid_pip;


wire [NUM_PIPELINE-1:0][32-1:0] 				tuple_pip [NUM_CLUSTER:0]; //not sure the array type instantiation is valid
wire [NUM_CLUSTER:0] 							tuple_valid_pip;
wire [NUM_CLUSTER:0] 							last_dim_of_one_tuple_pip;


wire [63:0] 									min_dist_pip[NUM_CLUSTER:0][NUM_PIPELINE-1:0]; 
wire [NUM_CLUSTER:0][NUM_PIPELINE-1:0]			min_dist_valid_pip;
wire [NUM_PIPELINE-1:0][NUM_CLUSTER_BITS:0]		assign_cluster_pip[NUM_CLUSTER:0]; 		
			

assign centroid_pip[0] = centroid;
assign centroid_valid_pip[0] = centroid_valid;
assign last_dim_of_one_centroid_pip[0] = last_dim_of_one_centroid;
assign last_dim_of_all_centroid_pip[0] = last_dim_of_all_centroid;

assign tuple_pip[0] = tuple;
assign tuple_valid_pip[0] = tuple_valid;
assign last_dim_of_one_tuple_pip[0] = last_dim_of_one_tuple;

generate
	for (genvar m = 0; m < NUM_PIPELINE; m++) begin: min_dist_pip_assign
		assign min_dist_pip[0][m] = 48'h7fffffffffff;
		assign min_dist_valid_pip[0][m] = 1'b1; 
	end
endgenerate
assign assign_cluster_pip[0] = '0;

genvar n;
generate
	for ( n = 0; n < NUM_CLUSTER; n++) begin: k_means_layer
		k_means_layer #(.CLUSTER_ID(n)) k_means_layer
		(
			.clk                         (clk),
			.rst_n                       (rst_n_reg),
			.data_dim_minus_1            (data_dim_minus_1),
			.num_cluster_minus_1         (num_cluster_minus_1),

			.centroid_i            		 (centroid_pip[n]),
			.centroid_valid_i      		 (centroid_valid_pip[n]),
			.last_dim_of_one_centroid_i  (last_dim_of_one_centroid_pip[n]),
			.last_dim_of_all_centroid_i  (last_dim_of_all_centroid_pip[n]),
			

			.centroid_o            		 (centroid_pip[n+1]),
			.centroid_valid_o      		 (centroid_valid_pip[n+1]),
			.last_dim_of_one_centroid_o  (last_dim_of_one_centroid_pip[n+1]),
			.last_dim_of_all_centroid_o  (last_dim_of_all_centroid_pip[n+1]),

			.tuple_i                 	 (tuple_pip[n]),
			.tuple_valid_i           	 (tuple_valid_pip[n]),
			.last_dim_of_one_tuple_i     (last_dim_of_one_tuple_pip[n]),

			.tuple_o                 	 (tuple_pip[n+1]),
			.tuple_valid_o           	 (tuple_valid_pip[n+1]),
			.last_dim_of_one_tuple_o     (last_dim_of_one_tuple_pip[n+1]),

			.min_dist_valid_i            (min_dist_valid_pip[n]),
			.min_dist_i                  (min_dist_pip[n]),
			.cluster_i                   (assign_cluster_pip[n]),

			.min_dist_valid_o            (min_dist_valid_pip[n+1]),
			.min_dist_o                  (min_dist_pip[n+1]),
			.cluster_o                   (assign_cluster_pip[n+1])
			);
	end
endgenerate

//check termination criteria
reg [47:0]  expect_tuple_first_pip;
reg 		pipeline_finish;
reg [47:0]  min_dist_valid_pip_cnt;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		expect_tuple_first_pip <= '0;
		pipeline_finish <= 1'b0;
		min_dist_valid_pip_cnt <= '0;
	end
	else begin
		expect_tuple_first_pip <= '0;
		pipeline_finish <= 1'b0;
		if(running_kmeans) begin
			expect_tuple_first_pip <= (data_set_size + NUM_PIPELINE -1) >> NUM_PIPELINE_BITS;
			if(min_dist_valid_pip[NUM_CLUSTER][0]) begin
				min_dist_valid_pip_cnt <= min_dist_valid_pip_cnt + 1'b1;
				if(min_dist_valid_pip_cnt == expect_tuple_first_pip-1) begin
					min_dist_valid_pip_cnt <= '0;
					pipeline_finish <= 1'b1;
				end
			end
		end
	end
end



//-----------------------Accumulation-----------------------------------//
wire [NUM_PIPELINE-1:0] [63:0] 	agg_data_pip;
wire [NUM_PIPELINE-1:0] 		agg_valid_pip; 
wire [NUM_PIPELINE-1:0] 		accu_finish;
reg first_pipe_finish, agg_ready;


genvar k;
generate
	for (k = 0; k < NUM_PIPELINE; k++) begin: Accumulation
		k_means_accumulation #(.PIPELINE_INDEX(k)) k_means_accumulation
		(
			.clk                  (clk),
			.rst_n                (rst_n_reg),
			.data_valid_accu_i    (tuple_valid_pip[NUM_CLUSTER]),
			.data_accu_i          (tuple_pip[NUM_CLUSTER][k]),
			.min_dist_accu_valid_i(min_dist_valid_pip[NUM_CLUSTER][k]),
			.min_dist_accu_i      (min_dist_pip[NUM_CLUSTER][k]),
			.cluster_accu_i       (assign_cluster_pip[NUM_CLUSTER][k]),
			.terminate_accu_i     (pipeline_finish),
			.data_dim_accu_i      (data_dim),
			.num_cluster_accu_i   (num_cluster),
			.agg_ready_i          (agg_ready),
			.accu_finish_o        (accu_finish[k]),
			.agg_data_o           (agg_data_pip[k]),
			.agg_valid_o          (agg_valid_pip[k])

			);
	end
endgenerate

// check if all pipelines finish accumulation

always @ (posedge clk) begin
	if(~rst_n) begin
		first_pipe_finish <= 1'b0;
	end
	else begin
		first_pipe_finish <= accu_finish[0];
		agg_ready <= first_pipe_finish;
	end
end

//-------------------------adder tree-----------------------//
wire [63:0]						agg_div_din, adder_tree_dout;
wire 							agg_div_valid, adder_tree_dout_valid;

//adder tree currently doesn't work for single pipeline
kmeans_adder_tree adder_tree
(
	.clk           (clk),
	.rst_n         (rst_n),
	.v_input       (agg_data_pip),
	.v_input_valid (agg_valid_pip[0]),
	.v_output      (adder_tree_dout),
	.v_output_valid(adder_tree_dout_valid)); //all the kmeans pipeline will send agg data synchoronously

assign agg_div_din = (NUM_PIPELINE_BITS==0) ? agg_data_pip : adder_tree_dout;
assign agg_div_valid = (NUM_PIPELINE_BITS==0) ? (agg_valid_pip[0]) : adder_tree_dout_valid; 

//----------------------aggregation and division---------------//
wire [31:0] update;
wire update_last, update_valid, update_last_dim;

agg_div agg_div
(
	.clk               (clk),
	.rst_n             (rst_n),
	.start_operator   (start_operator_reg),
	.data_dim          (data_dim),
	.num_cluster       (num_cluster),
	.agg_data          (agg_div_din),
	.agg_valid         (agg_div_valid),
	.update            (update),
	.update_valid      (update_valid),
	.update_last       (update_last),
	.update_last_dim   (update_last_dim),
	.agg_div_debug_cnt (agg_div_debug_cnt)
	);

//------------------------re-group 32bit update to 512bit cl-------------//

reg [7:0]	re_group_cnt;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		re_group_cnt <= '0;
	end
	else begin
		update_cl_valid <= 1'b0;
		update_cl_last <= 1'b0;

		if(update_valid) begin
			update_cl[re_group_cnt*32 +: 32] <= update;
			re_group_cnt <= re_group_cnt + 1'b1;
			if(re_group_cnt == 15 ) begin
				re_group_cnt <= '0;
				update_cl_valid <= 1'b1;
			end
			if(update_last) begin
				re_group_cnt <= '0;
				update_cl_valid <= 1'b1;
				update_cl_last <= 1'b1;
			end
		end
	end
end

assign updated_centroid = update_cl;
assign updated_centroid_last = update_cl_last;
assign updated_centroid_valid = update_cl_valid;





//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------log file print--------------------------------------------------//
////////////////////////////////////////////////////////////////////////////////////////////////////
`define LOG_NULL
`ifdef LOG_FILE
	int file;
	reg file_finished;
	initial begin
		file = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/parallel_words.txt","w");
		if(file) 
			$display("parallel_words file open successfully\n");
		else 
			$display("Failed to open parallel_words file\n");	
	end

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			file_finished <= 1'b0;
		end
		else begin
			if(tuple_cl_valid) begin
				$fwrite(file,"16 dimension\n");
				for(integer j=0; j<NUM_PIPELINE; j++)
				begin
					$fwrite(file,"%d ", tuple_cl[32*j +: 32]);
				end
				$fwrite(file,"\n");
			end

		end
	end
`endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------log file print--------------------------------------------------//
////////////////////////////////////////////////////////////////////////////////////////////////////
`define LOG_NULL
`ifdef LOG_FILE
	int file2;
	wire [NUM_PIPELINE-1:0][47:0] printout;
	reg [31:0] valid_cnt;

	initial begin
		file2 = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/min_dist_pip.txt","w");
		if(file2) 
			$display("min_dist_pip file open successfully\n");
		else 
			$display("Failed to open min_dist_pip file\n");	
	end


	genvar l;
	generate
		for (l = 0; l < NUM_PIPELINE; l++) begin
			assign printout[l] = min_dist_pip[NUM_CLUSTER][l];
		end
	endgenerate

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			valid_cnt <= '0;
		end
		else begin
			if(min_dist_valid_pip[NUM_CLUSTER][0]) begin
				valid_cnt <= valid_cnt + 1'b1;

				$fwrite(file2,"16 data assignment\n");
				for(integer j=0; j<NUM_PIPELINE; j++)
				begin
					$fwrite(file2,"%d, min_dist: %d, cluster_id:%d", (valid_cnt*NUM_PIPELINE+j), printout[j], assign_cluster_pip[NUM_CLUSTER][j]);
					$fwrite(file2,"\n");
				end

			end

		end
	end
`endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////





endmodule
`default_nettype wire













