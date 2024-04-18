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
 
import kmeansTypes::*;

module Formatter (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire [NUM_CLUSTER_BITS:0] 		num_cluster,// the actual number of cluster that will be used 
	input wire [MAX_DEPTH_BITS:0] 			data_dim, //input the actual dimension of the data
	input wire [7:0]						precision,

	//interface to fetch engine
    input wire [511:0] 						tuple_cl,
    input wire 								tuple_cl_valid,

    input wire [511:0]						centroid_cl, //not in bit-weaving format
    input wire 								centroid_cl_valid,

    output wire								centroid_cl_ready,

    //interface to pipeline
    output wire [NUM_BANK*32-1:0]				centroid_chunk,
    output wire 								centroid_chunk_valid,
	output wire 								last_chunk_of_all_centroid,
    output wire  								last_chunk_of_one_centroid,

    //interface to pipelines
    output reg [NUM_PIPELINE-1:0][NUM_BANK-1:0]		tuple_bit,
    output reg 										tuple_bit_valid,
	output reg 										last_bit_of_bank_dimension,
	output reg 					 					last_bit_of_one_tuple,

	//debug counters
	output wire [2:0] [31:0]				formatter_debug_cnt	
	
);


reg 	rst_n_reg;
wire 	c_lane_ready;

always @ (posedge clk) begin
	rst_n_reg <= rst_n;
end

assign centroid_cl_ready = c_lane_ready;

//--------------------split the centroid cache line---------------------//
//-------------------------ask zeke to check this-----------------------//


c_lane_splitter c_lane_splitter
(
	.clk                 (clk),
	.rst_n               (rst_n_reg),
	.num_cluster         (num_cluster),
	.data_dim            (data_dim),
	.centroid_cl         (centroid_cl),
	.centroid_cl_valid   (centroid_cl_valid),
	.c_lane_ready        (c_lane_ready),
	.centroid_chunk      (centroid_chunk),
	.centroid_chunk_valid(centroid_chunk_valid),
	.last_chunk_of_all_centroid(last_chunk_of_all_centroid),
	.last_chunk_of_one_centroid(last_chunk_of_one_centroid)	);


//----------------------re-group the bits of samples----------------------//
reg [7:0] numBits_index;
reg [MAX_DEPTH_BITS:0] data_dim_index;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		numBits_index <= '0;
        data_dim_index <= '0;
        last_bit_of_bank_dimension <= 1'b0;
        last_bit_of_one_tuple <= 1'b0;
	end
	else begin
		last_bit_of_bank_dimension <= 1'b0;
		last_bit_of_one_tuple <= 1'b0;
		tuple_bit_valid <= 1'b0;
		
		if(tuple_cl_valid) begin
			for (integer i = 0; i < NUM_PIPELINE; i++) begin
				for (integer j = 0; j < NUM_BANK; j++) begin
					tuple_bit[i][j] <= tuple_cl[j*NUM_PIPELINE+i];
				end
			end
			tuple_bit_valid <= tuple_cl_valid;

			numBits_index <= numBits_index + 1'b1;
            if(numBits_index == precision-1) begin
                numBits_index <= '0;
                last_bit_of_bank_dimension <= 1'b1;
                data_dim_index <= data_dim_index + NUM_BANK; //reduction of NUM_BANK dimensions
                if(data_dim_index + NUM_BANK >= data_dim-1) begin
                    data_dim_index <= '0;
                    last_bit_of_one_tuple <= 1'b1;
                end
            end
		end
	end
end



endmodule
