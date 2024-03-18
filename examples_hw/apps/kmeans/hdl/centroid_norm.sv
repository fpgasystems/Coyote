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

module centroid_norm (
	input clk,    // Clock
	input rst_n,  // Asynchronous reset active low

    input wire [MAX_DEPTH_BITS:0]           data_dim,
	input wire [NUM_CLUSTER_BITS:0] 		num_cluster,

	input wire [NUM_BANK*32-1:0]			centroid_chunk_i,
    input wire 								centroid_chunk_valid_i,

    output reg [NUM_CLUSTER-1:0][63:0]		centroid_norm_half,
    output reg 								centroid_norm_half_valid
	
);

reg 							rst_n_reg;
wire [NUM_BANK-1:0][63:0]		mult_result;
wire 							mult_result_valid;
reg 							centroid_chunk_valid_reg, centroid_chunk_valid_reg2;

wire [NUM_BANK-1:0][63:0] 		add_tree_in; 
//--------------------------mult takes two cycle-----------------//
//---------------------------register the valid-------------------//


always @ (posedge clk) begin
	rst_n_reg <= rst_n;
	centroid_chunk_valid_reg <= centroid_chunk_valid_i;
	centroid_chunk_valid_reg2 <= centroid_chunk_valid_reg;
end
assign mult_result_valid = centroid_chunk_valid_reg2;

genvar n;
generate
	for (n = 0; n < NUM_BANK; n++) begin : DSP_MUL

        mult_gen_0 inst_mult_gen (
            .CLK(clk),

            .A(centroid_chunk_i[n*32 +: 32]),
            .B(centroid_chunk_i[n*32 +: 32]),
            .P(mult_result[n])
        );

/*
		lpm_mult #(
		.lpm_widtha(32),
		.lpm_widthb(32),
	 	.lpm_widthp(64),
		.lpm_pipeline(2),
		.lpm_representation("UNSIGNED")
		// .LPM_REPRESENTATION("UNSIGNED")
		)
	 	lpm_mult
	 	(
	 	.clock(clk),
	 	.clken(1'b1),
	 	.aclr(1'b0),
	 	.sclr(1'b0),
	 	.dataa(centroid_chunk_i[n*32 +: 32]),
	 	.datab(centroid_chunk_i[n*32 +: 32]),
	 	.sum(),
	 	.result(mult_result[n])
	 		);
*/
	 	assign add_tree_in[n] = mult_result[n];
	end
endgenerate


//----------------------------next cycle--------------------------//
wire [63:0]			add_tree_out;
wire 				add_tree_out_valid;


kmeans_adder_tree_low_resource #(.TREE_DEPTH(NUM_BANK_BITS), .BIT_WIDTH(64))
kmeans_adder_tree_low_resource
(
    .clk           (clk),
    .rst_n         (rst_n_reg),
    .v_input       (add_tree_in),
    .v_input_valid (mult_result_valid),
    .v_output      (add_tree_out),
    .v_output_valid(add_tree_out_valid)
    );

//-----------------------accumulation-----------------------------//
reg [63:0]						add_tree_accu;
reg 							add_tree_accu_valid;
reg 							add_tree_out_finish;
reg [MAX_DEPTH_BITS:0]          data_dim_cnt;
reg [NUM_CLUSTER_BITS:0] 		num_cluster_cnt;
reg [NUM_CLUSTER_BITS:0] 		num_cluster_cnt_reg;

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		data_dim_cnt <= '0;
		num_cluster_cnt <= '0;
	end
	else begin
		add_tree_accu_valid <= 1'b0;
		add_tree_out_finish <= 1'b0;

		if(add_tree_out_valid) begin
			data_dim_cnt <= data_dim_cnt + NUM_BANK;
			if(data_dim_cnt+NUM_BANK >= data_dim) begin
				data_dim_cnt <= '0;
				add_tree_accu_valid <= 1'b1;
				num_cluster_cnt <= num_cluster_cnt + 1'b1;
				if(num_cluster_cnt == num_cluster-1) begin
					num_cluster_cnt <= '0;
					add_tree_out_finish <= 1'b1;
				end
			end


			if(data_dim_cnt == 0) begin
				add_tree_accu <= add_tree_out;
			end
			else begin
				add_tree_accu <= add_tree_accu + add_tree_out;
			end
		end
	end
end

//-----------------------output assignment-------------------------//

always @ (posedge clk) begin
	if(~rst_n_reg) begin
		centroid_norm_half_valid <= 1'b0;
		num_cluster_cnt_reg <= '0;
	end
	else begin
		num_cluster_cnt_reg <= num_cluster_cnt;

		if(add_tree_accu_valid) begin
			centroid_norm_half[num_cluster_cnt_reg] <= (add_tree_accu >> 1);
		end
		
		centroid_norm_half_valid <= add_tree_out_finish;
	end
end


endmodule