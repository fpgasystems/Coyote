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

module dist_processor #(parameter INDEX_PROCESSOR = 0)
(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire [5:0]                            		numBits_minus_1,
	input wire [MAX_DEPTH_BITS:0]						data_dim_minus_1,
	input wire 											enable,

	//----------- bit serial data---------------//
	input wire 											bs_data_valid_i, 
	input wire [NUM_BANK-1:0]							bs_data_i, 

	//-----------input centroid----------------------//
	input wire [NUM_BANK-1:0][31:0]      				centroid_i,

	input wire [47:0]									centroid_norm_half,

	//---------------previous processor assignment result---//
	input wire 											min_dist_valid_i,
	input wire signed [47:0] 							min_dist_i, 
	input wire [NUM_CLUSTER_BITS:0] 					cluster_i, 
	
	//--------------current processor assignment result--------//
	output wire 										min_dist_valid_o,
	output wire signed [47:0] 							min_dist_o,
	output wire [NUM_CLUSTER_BITS:0] 					cluster_o
);

//////////////////////////////input register//////////////////////////////////////////////

reg 						rst_n_reg;
reg 						enable_reg;
always @(posedge clk ) begin
	rst_n_reg <= rst_n;
	enable_reg <= enable;
end


///////////////////Calculate distance///////////////////////////////

wire signed [47:0] 					distance;
wire 								dist_valid;		

bit_serial_mul_accu bit_serial_mul_accu
(
	.clk            (clk),
	.rst_n          (rst_n_reg),
	.numBits_minus_1(numBits_minus_1),
	.data_dim_minus_1(data_dim_minus_1),
	.x_norm_half    (centroid_norm_half),
	.x              (centroid_i),
	.a_valid        (bs_data_valid_i),
	.a              (bs_data_i),
	.result         (distance),
	.result_valid   (dist_valid)
	);


////////////////////////min dist selection/////////////////////////////

reg 										min_dist_valid_reg;
reg  signed [47:0] 							min_dist_reg;
reg [NUM_CLUSTER_BITS:0] 					cluster_reg;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		min_dist_valid_reg <= 1'b0;
	end
	else begin
		min_dist_reg <= '0;
		cluster_reg <= '0;
		min_dist_valid_reg <= dist_valid;
		if(dist_valid & min_dist_valid_i) begin //dist valid and min dist valid should be set at the same cycle
			min_dist_reg <= ((distance<=min_dist_i) & enable_reg) ?  distance : min_dist_i;
			cluster_reg <= ((distance<=min_dist_i) & enable_reg) ? INDEX_PROCESSOR : cluster_i;
		end
	end
end

assign min_dist_valid_o = min_dist_valid_reg;
assign min_dist_o = min_dist_reg;
assign cluster_o = cluster_reg;


endmodule
