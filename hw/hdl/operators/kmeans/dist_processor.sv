
import kmeansTypes::*;

module dist_processor #(parameter INDEX_PROCESSOR = 0)
(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire 											enable,

	//----------- bit serial data---------------//
	input wire 											data_valid_i, 
	input wire [31:0]									data_i, 
	input wire 											data_last_dim,

	//-----------input centroid----------------------//
	input wire [31:0]      								centroid_i,


	//---------------previous processor assignment result---//
	input wire 											min_dist_valid_i,
	input wire  [63:0] 									min_dist_i, 
	input wire [NUM_CLUSTER_BITS:0] 					cluster_i, 
	
	//--------------current processor assignment result--------//
	output wire 										min_dist_valid_o,
	output wire  [63:0] 								min_dist_o,
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

wire  [63:0] 						distance;
wire 								dist_valid;		

mul_accu mul_accu
(
	.clk         (clk),
	.rst_n       (rst_n_reg),
	.x           (centroid_i),
	.a_valid     (data_valid_i),
	.a           (data_i),
	.a_last_dim  (data_last_dim),
	.result      (distance),
	.result_valid(dist_valid)
	);


////////////////////////min dist selection/////////////////////////////

reg 										min_dist_valid_reg;
reg [63:0] 									min_dist_reg;
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
