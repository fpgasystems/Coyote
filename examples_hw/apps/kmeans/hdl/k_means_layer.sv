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

module k_means_layer #(parameter CLUSTER_ID = 0)(
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire [MAX_DEPTH_BITS:0] 			data_dim_minus_1, 
	input wire [5:0]                     	numBits_minus_1,
	input wire [NUM_CLUSTER_BITS:0] 		num_cluster_minus_1,

	input wire [63:0]						centroid_norm_half,
	input wire 								centroid_norm_half_valid,

	//interface with previous kmeans layer
    input wire [NUM_BANK*32-1:0]			centroid_chunk_i,
    input wire 								centroid_chunk_valid_i,
    input wire 								last_chunk_of_one_centroid_i,
    input wire 								last_chunk_of_all_centroid_i,

    //interface with next kmeans layer
    output reg [NUM_BANK*32-1:0]			centroid_chunk_o,
    output reg 								centroid_chunk_valid_o,
    output reg 								last_chunk_of_one_centroid_o,
    output reg 								last_chunk_of_all_centroid_o,

    //input interface with previous k-means layer
    input wire [NUM_PIPELINE-1:0][NUM_BANK-1:0]		tuple_bit_i,
    input wire 										tuple_bit_valid_i,
    input wire 										last_bit_of_bank_dimension_i,
    input wire 										last_bit_of_one_tuple_i,

    //output interface with next kmeans layer
    //tuple bits stream through each layer
    output reg [NUM_PIPELINE-1:0][NUM_BANK-1:0]		tuple_bit_o,
    output wire 									tuple_bit_valid_o,
    output wire 									last_bit_of_bank_dimension_o,
    output wire 									last_bit_of_one_tuple_o,

    //---------------previous assignment result---//
	input wire [NUM_PIPELINE-1:0]									min_dist_valid_i,
	input wire signed [47:0] 										min_dist_i[NUM_PIPELINE-1:0], 
	input wire [NUM_PIPELINE-1:0][NUM_CLUSTER_BITS:0] 				cluster_i, 
	
	//--------------current assignment result--------//
	output wire [NUM_PIPELINE-1:0]									min_dist_valid_o,
	output wire signed [47:0] 										min_dist_o[NUM_PIPELINE-1:0],
	output wire [NUM_PIPELINE-1:0][NUM_CLUSTER_BITS:0] 				cluster_o


	
);

reg 							rst_n_reg;
reg [63:0]						centroid_norm_half_reg;
wire [71:0] 					centroid_norm_half_wire;
reg [47:0] 						centroid_norm_half_shift;
reg [3:0][47:0] 				centroid_norm_half_shift_reg;

assign centroid_norm_half_wire = {centroid_norm_half_reg, 8'b0};

always @ (posedge clk) begin
	rst_n_reg <= rst_n;
	if(centroid_norm_half_valid) begin
		centroid_norm_half_reg <= centroid_norm_half;
	end

	case (numBits_minus_1)
        5'h00: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 1 );
        5'h01: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 2 );
        5'h02: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 3 );
        5'h03: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 4 );
        5'h04: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 5 );
        5'h05: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 6 );
        5'h06: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 7 );
        5'h07: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 8 );
        5'h08: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 9 );
        5'h09: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 10);
        5'h0a: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 11);
        5'h0b: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 12);
        5'h0c: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 13);
        5'h0d: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 14);
        5'h0e: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 15);
        5'h0f: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 16);
        5'h10: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 17);
        5'h11: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 18);
        5'h12: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 19);
        5'h13: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 20);
        5'h14: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 21);
        5'h15: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 22);
        5'h16: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 23);
        5'h17: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 24);
        5'h18: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 25);
        5'h19: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 26);
        5'h1a: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 27);
        5'h1b: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 28);
        5'h1c: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 29);
        5'h1d: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 30);
        5'h1e: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 31);
        5'h1f: centroid_norm_half_shift          <= (centroid_norm_half_wire >>> 32);
    endcase 

end


reg [MAX_DEPTH_BITS-1:0] 	raddr;
reg [MAX_DEPTH_BITS-1:0]	waddr;
wire [NUM_BANK*32-1:0] 		centroid_from_bram;
wire 						write_en;
reg 						enable;
wire 						read_en;

reg [NUM_CLUSTER_BITS:0] 	cluster_cnt;

//stores the centroid chunk
dual_port_ram #(.DATA_WIDTH(NUM_BANK*32), .ADDR_WIDTH(MAX_DEPTH_BITS))
	processor_mem
	(
	.clk  (clk),
	.we   (write_en),
	.re   (1'b1),
	.raddr(raddr),
	.waddr(waddr),
	.din  (centroid_chunk_i),
	.dout (centroid_from_bram)
		);	

//write only when cluster cnt equals
assign write_en = centroid_chunk_valid_i & (cluster_cnt == CLUSTER_ID); 
//read only when last bit of number of bank of dimensions
assign read_en = tuple_bit_valid_i & last_bit_of_bank_dimension_i;

//bram read and write address calculation
always_ff @(posedge clk) begin : proc_addr
	if (~rst_n_reg) begin
		waddr <= '0;
		cluster_cnt <= '0;
		raddr <= '0;
		enable <= 1'b0;
	end
	else begin
		if(centroid_chunk_valid_i) begin
			if(last_chunk_of_one_centroid_i) begin
				cluster_cnt <= cluster_cnt + 1'b1;
				if(last_chunk_of_all_centroid_i) begin
					cluster_cnt <= '0;
				end
			end
		end

		if (write_en) begin
			waddr <= waddr + 1'b1;
			if ( last_chunk_of_one_centroid_i) begin
				waddr <= '0;
			end
		end

		if(read_en) begin
			raddr <= raddr + 1'b1;
			if( last_bit_of_one_tuple_i) begin
				raddr <= '0;
			end
		end

		enable <= (CLUSTER_ID <= num_cluster_minus_1);
	end
end

//-----------------------------One cycle later-------------------------------//
//-------------------bram centroid valid one cycle after the read----------------//

reg [NUM_PIPELINE-1:0][NUM_BANK-1:0]		tuple_bit_reg;
reg 										tuple_bit_valid_reg;
reg 										last_bit_of_bank_dimension_reg;
reg 										last_bit_of_one_tuple_reg;

always @ (posedge clk) begin

	tuple_bit_reg <= tuple_bit_i;
	tuple_bit_valid_reg <= tuple_bit_valid_i;
	last_bit_of_bank_dimension_reg <= last_bit_of_bank_dimension_i;
	last_bit_of_one_tuple_reg <= last_bit_of_one_tuple_i;

	//register the updated centroid and forward to next layer
	centroid_chunk_o <= centroid_chunk_i;
	centroid_chunk_valid_o <= centroid_chunk_valid_i;
	last_chunk_of_all_centroid_o <= last_chunk_of_all_centroid_i;
	last_chunk_of_one_centroid_o <= last_chunk_of_one_centroid_i;
end

//forward the tuple bit streams to next layer
assign tuple_bit_o = tuple_bit_reg;
assign tuple_bit_valid_o = tuple_bit_valid_reg;
assign last_bit_of_bank_dimension_o = last_bit_of_bank_dimension_reg;
assign last_bit_of_one_tuple_o = last_bit_of_one_tuple_reg;


//-------------------------One cycle later---------------------------------//
//----------------------register the bram centroid one cycle---------------//
reg [1:0][NUM_BANK*32-1:0] 					centroid_from_bram_reg;
reg [NUM_PIPELINE-1:0][NUM_BANK-1:0]		tuple_bit_reg2;
reg 										tuple_bit_valid_reg2;
always @ (posedge clk) begin
	if(~rst_n_reg) begin
		tuple_bit_valid_reg2 <= '0;
	end
	else begin
		centroid_from_bram_reg[0] <= centroid_from_bram;
		centroid_from_bram_reg[1] <= centroid_from_bram;

		centroid_norm_half_shift_reg[0] <= centroid_norm_half_shift;
		centroid_norm_half_shift_reg[1] <= centroid_norm_half_shift;
		centroid_norm_half_shift_reg[2] <= centroid_norm_half_shift;
		centroid_norm_half_shift_reg[3] <= centroid_norm_half_shift;

		tuple_bit_reg2 <= tuple_bit_reg;
		tuple_bit_valid_reg2 <= tuple_bit_valid_reg;
	end
end

genvar i;
generate
	for (i = 0; i < NUM_PIPELINE; i++) begin: PARALLEL_DP
		if(i<16) begin
			dist_processor #(.INDEX_PROCESSOR(CLUSTER_ID)) dist_processor
			(
				.clk               (clk),
				.rst_n             (rst_n),
				.numBits_minus_1   (numBits_minus_1),
				.data_dim_minus_1  (data_dim_minus_1),
				.enable            (enable),
				.bs_data_valid_i   (tuple_bit_valid_reg2),
				.bs_data_i         (tuple_bit_reg2[i]),
				.centroid_i        (centroid_from_bram_reg[0]),
				.centroid_norm_half(centroid_norm_half_shift_reg[0]),
				.min_dist_valid_i  (min_dist_valid_i[i]),
				.min_dist_i        (min_dist_i[i]),
				.cluster_i         (cluster_i[i]),
				.min_dist_valid_o  (min_dist_valid_o[i]),
				.min_dist_o        (min_dist_o[i]),
				.cluster_o         (cluster_o[i])
			);
		end
		else if(i<32) begin
			dist_processor #(.INDEX_PROCESSOR(CLUSTER_ID)) dist_processor
			(
				.clk               (clk),
				.rst_n             (rst_n),
				.numBits_minus_1   (numBits_minus_1),
				.data_dim_minus_1  (data_dim_minus_1),
				.enable            (enable),
				.bs_data_valid_i   (tuple_bit_valid_reg2),
				.bs_data_i         (tuple_bit_reg2[i]),
				.centroid_i        (centroid_from_bram_reg[0]),
				.centroid_norm_half(centroid_norm_half_shift_reg[1]),
				.min_dist_valid_i  (min_dist_valid_i[i]),
				.min_dist_i        (min_dist_i[i]),
				.cluster_i         (cluster_i[i]),
				.min_dist_valid_o  (min_dist_valid_o[i]),
				.min_dist_o        (min_dist_o[i]),
				.cluster_o         (cluster_o[i])
			);
		end
		else if(i<48) begin
			dist_processor #(.INDEX_PROCESSOR(CLUSTER_ID)) dist_processor
			(
				.clk               (clk),
				.rst_n             (rst_n),
				.numBits_minus_1   (numBits_minus_1),
				.data_dim_minus_1  (data_dim_minus_1),
				.enable            (enable),
				.bs_data_valid_i   (tuple_bit_valid_reg2),
				.bs_data_i         (tuple_bit_reg2[i]),
				.centroid_i        (centroid_from_bram_reg[1]),
				.centroid_norm_half(centroid_norm_half_shift_reg[2]),
				.min_dist_valid_i  (min_dist_valid_i[i]),
				.min_dist_i        (min_dist_i[i]),
				.cluster_i         (cluster_i[i]),
				.min_dist_valid_o  (min_dist_valid_o[i]),
				.min_dist_o        (min_dist_o[i]),
				.cluster_o         (cluster_o[i])
			);
		end
		else if(i<NUM_PIPELINE) begin
			dist_processor #(.INDEX_PROCESSOR(CLUSTER_ID)) dist_processor
			(
				.clk               (clk),
				.rst_n             (rst_n),
				.numBits_minus_1   (numBits_minus_1),
				.data_dim_minus_1  (data_dim_minus_1),
				.enable            (enable),
				.bs_data_valid_i   (tuple_bit_valid_reg2),
				.bs_data_i         (tuple_bit_reg2[i]),
				.centroid_i        (centroid_from_bram_reg[1]),
				.centroid_norm_half(centroid_norm_half_shift_reg[3]),
				.min_dist_valid_i  (min_dist_valid_i[i]),
				.min_dist_i        (min_dist_i[i]),
				.cluster_i         (cluster_i[i]),
				.min_dist_valid_o  (min_dist_valid_o[i]),
				.min_dist_o        (min_dist_o[i]),
				.cluster_o         (cluster_o[i])
			);
		end
		
	end
endgenerate





endmodule // k_means_layer