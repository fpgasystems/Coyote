/*
 * Copyright 2019 - 2020 Systems Group, ETH Zurich
 *
 * This hardware operator is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

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
	input wire [7:0]						precision,
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



reg start_operator_reg, um_done_reg = 0, rst_n_reg, running_kmeans;
reg [MAX_DEPTH_BITS:0] data_dim_minus_1;
reg [5:0] numBits_minus_1;
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
		numBits_minus_1 <= '0;
		num_cluster_minus_1 <= '0;
		if(running_kmeans) begin
			data_dim_minus_1 <= data_dim - 1;
			numBits_minus_1 <= precision - 1;
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
wire [NUM_BANK*32-1:0]						centroid_chunk;
wire 										centroid_chunk_valid;
wire 										last_chunk_of_all_centroid;
wire  										last_chunk_of_one_centroid;

wire [NUM_PIPELINE-1:0][NUM_BANK-1:0]		tuple_bit;
wire 										tuple_bit_valid;
wire 										last_bit_of_bank_dimension;
wire 					 					last_bit_of_one_tuple;

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
	.precision           (precision),
	.tuple_cl            (tuple_cl),
	.tuple_cl_valid      (tuple_cl_valid),
	.centroid_cl         (formatter_centroid_input),
	.centroid_cl_valid   (formatter_centroid_input_valid),
	.centroid_cl_ready    (centroid_cl_ready),
	.centroid_chunk      (centroid_chunk),
	.centroid_chunk_valid(centroid_chunk_valid),
	.last_chunk_of_all_centroid(last_chunk_of_all_centroid),
	.last_chunk_of_one_centroid(last_chunk_of_one_centroid),
	.tuple_bit           (tuple_bit),
	.tuple_bit_valid     (tuple_bit_valid),
	.last_bit_of_bank_dimension(last_bit_of_bank_dimension),
	.last_bit_of_one_tuple     (last_bit_of_one_tuple),
	.formatter_debug_cnt ()
	);

//------------------------Centroid norm calculation----------------------------//
wire [NUM_CLUSTER-1:0][63:0]		centroid_norm_half;
wire 								centroid_norm_half_valid;

centroid_norm centroid_norm
(
	.clk                     (clk),
	.rst_n                   (rst_n),
	.data_dim                (data_dim),
	.num_cluster             (num_cluster),
	.centroid_chunk_i        (centroid_chunk),
	.centroid_chunk_valid_i  (centroid_chunk_valid),
	.centroid_norm_half      (centroid_norm_half),
	.centroid_norm_half_valid(centroid_norm_half_valid)
	);

//request mem data when norm of all centroids have been calculated
reg request_mem_data;
always @ (posedge clk) begin
	if(~rst_n_reg) begin
		request_mem_data <= 1'b0;
	end
	else begin
		if(centroid_norm_half_valid) begin
			request_mem_data <= 1'b1;
		end
		else if(tuple_cl_valid & tuple_cl_last) begin
			request_mem_data <= 1'b0;
		end
	end
end

assign tuple_cl_ready = request_mem_data;
//----------------------Assignment calculation---------------------------------//
wire [NUM_CLUSTER:0][32*NUM_BANK-1:0]			centroid_chunk_pip;
wire [NUM_CLUSTER:0]							centroid_chunk_valid_pip;
wire [NUM_CLUSTER:0]							last_chunk_of_one_centroid_pip;
wire [NUM_CLUSTER:0]							last_chunk_of_all_centroid_pip;


wire [NUM_PIPELINE-1:0][NUM_BANK-1:0] 			tuple_bit_pip [NUM_CLUSTER:0]; //not sure the array type instantiation is valid
wire [NUM_CLUSTER:0] 							tuple_bit_valid_pip;
wire [NUM_CLUSTER:0] 							last_bit_of_bank_dimension_pip;
wire [NUM_CLUSTER:0] 							last_bit_of_one_tuple_pip;


wire signed [47:0] 								min_dist_pip[NUM_CLUSTER:0][NUM_PIPELINE-1:0]; 
wire [NUM_CLUSTER:0][NUM_PIPELINE-1:0]			min_dist_valid_pip;
wire [NUM_PIPELINE-1:0][NUM_CLUSTER_BITS:0]		assign_cluster_pip[NUM_CLUSTER:0]; 		
			

assign centroid_chunk_pip[0] = centroid_chunk;
assign centroid_chunk_valid_pip[0] = centroid_chunk_valid;
assign last_chunk_of_one_centroid_pip[0] = last_chunk_of_one_centroid;
assign last_chunk_of_all_centroid_pip[0] = last_chunk_of_all_centroid;

assign tuple_bit_pip[0] = tuple_bit;
assign tuple_bit_valid_pip[0] = tuple_bit_valid;
assign last_bit_of_bank_dimension_pip[0] = last_bit_of_bank_dimension;
assign last_bit_of_one_tuple_pip[0] = last_bit_of_one_tuple;

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
			.numBits_minus_1             (numBits_minus_1),
			.num_cluster_minus_1         (num_cluster_minus_1),
			.centroid_chunk_i            (centroid_chunk_pip[n]),
			.centroid_chunk_valid_i      (centroid_chunk_valid_pip[n]),
			.last_chunk_of_one_centroid_i(last_chunk_of_one_centroid_pip[n]),
			.last_chunk_of_all_centroid_i(last_chunk_of_all_centroid_pip[n]),

			.centroid_norm_half          (centroid_norm_half[n]),
			.centroid_norm_half_valid    (centroid_norm_half_valid),

			.centroid_chunk_o            (centroid_chunk_pip[n+1]),
			.centroid_chunk_valid_o      (centroid_chunk_valid_pip[n+1]),
			.last_chunk_of_one_centroid_o(last_chunk_of_one_centroid_pip[n+1]),
			.last_chunk_of_all_centroid_o(last_chunk_of_all_centroid_pip[n+1]),

			.tuple_bit_i                 (tuple_bit_pip[n]),
			.tuple_bit_valid_i           (tuple_bit_valid_pip[n]),
			.last_bit_of_bank_dimension_i(last_bit_of_bank_dimension_pip[n]),
			.last_bit_of_one_tuple_i     (last_bit_of_one_tuple_pip[n]),

			.tuple_bit_o                 (tuple_bit_pip[n+1]),
			.tuple_bit_valid_o           (tuple_bit_valid_pip[n+1]),
			.last_bit_of_bank_dimension_o(last_bit_of_bank_dimension_pip[n+1]),
			.last_bit_of_one_tuple_o     (last_bit_of_one_tuple_pip[n+1]),

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


wire [NUM_BANK-1:0][MAX_DIM_WIDTH-1:0]	debug_output [NUM_PIPELINE-1:0];
wire 									debug_output_valid[NUM_PIPELINE-1:0];

genvar k;
generate
	for (k = 0; k < NUM_PIPELINE; k++) begin: Accumulation
		k_means_accumulation #(.PIPELINE_INDEX(k)) k_means_accumulation
		(
			.clk                  (clk),
			.rst_n                (rst_n_reg),
			.data_valid_accu_i    (tuple_bit_valid_pip[NUM_CLUSTER]),
			.data_accu_i          (tuple_bit_pip[NUM_CLUSTER][k]),
			.min_dist_accu_valid_i(min_dist_valid_pip[NUM_CLUSTER][k]),
			.min_dist_accu_i      (min_dist_pip[NUM_CLUSTER][k]),
			.cluster_accu_i       (assign_cluster_pip[NUM_CLUSTER][k]),
			.terminate_accu_i     (pipeline_finish),
			.data_dim_accu_i      (data_dim),
			.num_cluster_accu_i   (num_cluster),
			.numBits_minus_1      (numBits_minus_1),
			.agg_ready_i          (agg_ready),
			.accu_finish_o        (accu_finish[k]),
			.agg_data_o           (agg_data_pip[k]),
			.agg_valid_o          (agg_valid_pip[k]),

			.debug_output         (debug_output[k]),
			.debug_output_valid   (debug_output_valid[k])

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




endmodule
`default_nettype wire






