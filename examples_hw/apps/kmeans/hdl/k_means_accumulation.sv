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


module k_means_accumulation #(parameter PIPELINE_INDEX=0) ( 
	input clk,    // Clock
	input wire rst_n,  
	
	//pipeline processor interface
	input logic 									data_valid_accu_i,
	input logic [NUM_BANK-1:0]						data_accu_i,

	input logic 									min_dist_accu_valid_i,
	input logic signed [47:0]						min_dist_accu_i,
	input logic [NUM_CLUSTER_BITS:0]				cluster_accu_i,

	input logic 									terminate_accu_i,

	//runtime configration parameters
	input logic [MAX_DEPTH_BITS:0] 					data_dim_accu_i, //input the actual dimension of the data
	input logic [NUM_CLUSTER_BITS:0] 				num_cluster_accu_i, //input the actual number of cluster
    input logic [5:0]                            	numBits_minus_1,


	//aggregator interface
	input logic 									agg_ready_i,
	output logic 									accu_finish_o,
	output logic [63:0] 							agg_data_o,
	output logic 									agg_valid_o,

	output wire [NUM_BANK-1:0][MAX_DIM_WIDTH-1:0]	debug_output,
	output wire 									debug_output_valid

	//output reg [7:0][31:0] 							accu_debug_cnt

);

	//dual port BRAM signal
	logic [NUM_BANK*40-1:0] bram_din, bram_dout;
	logic [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-NUM_BANK_BITS-1:0] bram_addr_re, bram_addr_wr;
	logic bram_we;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////
//----------------------------------------Accumulation-------------------------------------------------------//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////First cycle////////////////////////////////////////////////

//-------------------------input register----------------------------------//
	//runtime param reg
	logic [MAX_DEPTH_BITS:0] data_dim_accu_DP;
	logic [NUM_CLUSTER_BITS:0] num_cluster_accu_DP;

	//input reg
	logic rst_n_reg, min_dist_accu_valid_DP;
	logic signed [47:0]min_dist_accu_DP;
	logic [NUM_CLUSTER_BITS:0]cluster_accu_DP;
	logic [4:0] numBits_minus_1_DP;

	//register input signal
	always_ff @(posedge clk) begin : proc_rst_delay
		rst_n_reg <= rst_n;
		min_dist_accu_DP <= min_dist_accu_i;
		cluster_accu_DP <= cluster_accu_i;
		data_dim_accu_DP <= data_dim_accu_i;
		num_cluster_accu_DP <= num_cluster_accu_i;
		numBits_minus_1_DP <= numBits_minus_1;
		if (~rst_n_reg) begin
			min_dist_accu_valid_DP <= 1'b0;
		end
		else begin
			min_dist_accu_valid_DP <= min_dist_accu_valid_i;
		end
	end

	//group 8bits bit serial data to 8 32bits parallel data
	reg [5:0] re_group_cnt;
	reg [NUM_BANK*MAX_DIM_WIDTH-1:0] parallel_data;
	reg parallel_data_valid;

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			parallel_data_valid <= 0;
			re_group_cnt <= '0;
		end
		else begin
			parallel_data_valid <= 1'b0;

			if(data_valid_accu_i) begin
				re_group_cnt <= re_group_cnt + 1'b1;
				if(re_group_cnt == numBits_minus_1) begin
					re_group_cnt <= '0;
					parallel_data_valid <= 1'b1;
				end				
			end
		end
	end

	generate
		for (genvar n = 0; n < NUM_BANK; n++) begin: re_group
			always @ (posedge clk) begin
				if(data_valid_accu_i) begin
					if(re_group_cnt == 0) begin
						parallel_data [n*32+:32] <= {31'h0, data_accu_i[n]};
					end
					else begin 
						parallel_data [n*32+:32] <= (parallel_data[n*32+:32] << 1) + data_accu_i[n];
					end
				end
			end
		end
	endgenerate

	generate
		for (genvar i = 0; i < NUM_BANK; i++) begin: assign_debug_output
			assign debug_output[i] = parallel_data[i*32 +: 32];
		end
	endgenerate
	assign debug_output_valid = parallel_data_valid;

////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////Second Cycle//////////////////////////////////////////////

//----------------------Cluster FIFO and DATA FIFO------------------//

	//FIFO signal
	logic data_fifo_we, data_fifo_re, data_fifo_valid,data_fifo_empty, data_fifo_almostfull, data_fifo_full;
	logic [NUM_BANK*MAX_DIM_WIDTH-1:0] data_fifo_dout, data_fifo_din;

	//cluster fifo signals
	logic cluster_fifo_we, cluster_fifo_re, cluster_fifo_valid, cluster_fifo_empty, cluster_fifo_almostfull, cluster_fifo_full;
	logic [NUM_CLUSTER_BITS:0] cluster_fifo_dout;
	reg [MAX_DEPTH_BITS:0] dim_cnt_accu;


	quick_fifo #(.FIFO_WIDTH(NUM_BANK*MAX_DIM_WIDTH), .FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS), .FIFO_ALMOSTFULL_THRESHOLD(2**(BUFFER_DEPTH_BITS-1)))
	DATA_FIFO
	(
	.clk(clk),
	.reset_n(rst_n_reg),
	
    .we(data_fifo_we),
	.din(data_fifo_din),

	.re(data_fifo_re),
	.valid(data_fifo_valid),
	.dout(data_fifo_dout),

	.count(),
	.empty(data_fifo_empty),

	.full(data_fifo_full),
	.almostfull(data_fifo_almostfull)
		);

	assign data_fifo_din = parallel_data;
	assign data_fifo_we = parallel_data_valid & ~data_fifo_full ; //write in when not update, data valid 


	quick_fifo #(.FIFO_WIDTH(NUM_CLUSTER_BITS+1), .FIFO_DEPTH_BITS(BUFFER_DEPTH_BITS), .FIFO_ALMOSTFULL_THRESHOLD(2**(BUFFER_DEPTH_BITS-1)))
	CLUSTER_FIFO
	(
	.clk       (clk),
	.reset_n   (rst_n_reg),
	.we        (cluster_fifo_we),
	.din       (cluster_accu_DP),
	.re        (cluster_fifo_re),
	.valid     (cluster_fifo_valid),
	.dout      (cluster_fifo_dout),
	.count     (),
	.empty     (cluster_fifo_empty),
	.full      (cluster_fifo_full),
	.almostfull(cluster_fifo_almostfull)	);


	assign cluster_fifo_we = min_dist_accu_valid_DP & ~cluster_fifo_full;
	assign cluster_fifo_re = data_fifo_valid & cluster_fifo_valid & (dim_cnt_accu + NUM_BANK ==data_dim_accu_DP) ;

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			dim_cnt_accu <= '0; 
		end
		else begin
			if(data_fifo_valid & cluster_fifo_valid) begin
				dim_cnt_accu <= dim_cnt_accu + NUM_BANK;
				if(dim_cnt_accu + NUM_BANK == data_dim_accu_DP ) begin
					dim_cnt_accu <= '0;
				end
			end
		end
	end

	//---------------------------accu counter and sse----------------------------------//


	//accumulation counter signals
	logic [NUM_CLUSTER-1:0][63:0] accu_counter;
	logic accu_counter_clr;

	//signals for accumulate the square error
	logic signed [63:0] sse;
	logic sse_clr;

	//count the number of sample in each cluster
	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			accu_counter <= '0;
		end
		else begin
			if(accu_counter_clr) begin
				accu_counter <= '0;
			end
			else if(cluster_fifo_re) begin
				accu_counter[cluster_fifo_dout] <= accu_counter[cluster_fifo_dout] + 1'b1;
			end
		end
	end

	//aggregate the sse
	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			sse <= '0;
		end
		else begin
			if(sse_clr) begin
				sse <= '0;
			end
			else if(min_dist_accu_valid_DP) begin
				sse <= sse + min_dist_accu_DP;
			end
		end
	end


	////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////Third cycle//////////////////////////////////////////////////////

	//-------------------------------Accu read addr generation---------------------------------//
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-NUM_BANK_BITS-1:0] re_addr_accu;
	reg re_addr_accu_valid;
	always @ (posedge clk ) begin
		if(~rst_n_reg) begin
			re_addr_accu <= '0;
			re_addr_accu_valid <= 1'b0;
		end
		else begin 
			re_addr_accu_valid <= data_fifo_valid & cluster_fifo_valid;
			re_addr_accu <=  (cluster_fifo_dout << (MAX_DEPTH_BITS-NUM_BANK_BITS)) + (dim_cnt_accu>>NUM_BANK_BITS);
		end
	end


	////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////Fourth cycle//////////////////////////////////////////////////////

	//------------------------read the data from bram need one cycle-------------------//
	//---------------------------register the wr addr-------------------------------//
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-NUM_BANK_BITS-1:0] wr_addr_accu_reg;
	reg re_addr_accu_valid_reg;

	always @ (posedge clk) begin
		re_addr_accu_valid_reg <= re_addr_accu_valid;
		wr_addr_accu_reg <= re_addr_accu;
	end	

	assign data_fifo_re = re_addr_accu_valid_reg;

	////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////////////////Fifth cycle//////////////////////////////////////////////////////

	//----------------------------accumulation-------------------------------------//
	//---------------------------register the wr addr accu and wr_en---------------//

	wire [NUM_BANK-1:0] [39:0]  add_operand;
	reg [NUM_BANK*40-1:0] 		add_result;
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-NUM_BANK_BITS-1:0] wr_addr_accu_reg2;
	reg wr_en_accu;

	genvar n;
	generate
		for (n = 0; n < NUM_BANK; n++) begin
			assign add_operand[n] = {8'b0, data_fifo_dout[32*n +: 32]};

			always @ (posedge clk) begin
				add_result[40*n +: 40] <= add_operand[n] + bram_dout[40*n +: 40];
			end
		end
	endgenerate

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			wr_en_accu <= 1'b0;
		end
		else begin
			wr_addr_accu_reg2 <= wr_addr_accu_reg;
			wr_en_accu <= re_addr_accu_valid_reg;
		end
	end


///////////////////////////////////////////////////////////////////////////////////////////////////////////////
//----------------------------------------Aggregation-------------------------------------------------------//
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

	//-------------------------------check condition to go to aggregation stage-------------------------//	
	reg terminate_accu_reg, goto_agg, agg_ready_reg;
	//terminate flag
	always @ (posedge clk) begin

		if(~rst_n_reg) begin
			terminate_accu_reg <= 0;
			agg_ready_reg <= 1'b0;
		end
		else begin 
			goto_agg <= 1'b0;
			if(terminate_accu_reg & data_fifo_empty & cluster_fifo_empty) begin
				terminate_accu_reg <= 0;
				goto_agg <= 1'b1;
			end
			else if(terminate_accu_i) begin
				terminate_accu_reg <= terminate_accu_i;
			end

			agg_ready_reg <= agg_ready_i;
		end
	end

 	//-------------------FSM to control the sending sequences of the data---------------------------------//
 	reg accu_finish, is_agg_data_re, is_agg;
	reg [MAX_DEPTH_BITS:0] dim_cnt_agg;
	reg [NUM_CLUSTER_BITS:0] cluster_cnt_agg;
	reg [NUM_CLUSTER_BITS+MAX_DEPTH_BITS-NUM_BANK_BITS-1:0] re_addr_agg, wr_addr_agg;

	typedef enum reg [2:0]{AGG_IDLE, WAIT_AGG, AGG_DATA, WAIT_ONE_CYCLE, WAIT_SECOND_CYCLE,AGG_CLUSTER, AGG_SSE, TERMINATE} agg_state;

	agg_state state;

	always @ (posedge clk) begin

		if(~rst_n_reg) begin
			state <= AGG_IDLE;
			dim_cnt_agg <= '0;
			cluster_cnt_agg <= '0;
			re_addr_agg <= '0;
			wr_addr_agg <= '0;
		end
		else begin
			accu_finish <= 1'b0;
			accu_counter_clr <= 1'b0;

			is_agg_data_re <= 1'b0;
			is_agg <= 1'b0;

			sse_clr <= 1'b0;

			wr_addr_agg <= re_addr_agg;

			case (state)

				AGG_IDLE:begin
					if(goto_agg == 1) begin
						state <= WAIT_AGG;
					end
				end

				WAIT_AGG: begin
					accu_finish <= 1'b1;
					if(agg_ready_reg) begin
						state <= AGG_CLUSTER;
						is_agg <= 1'b1;
					end
				end

				//upon the start of aggregation state, give aggregation_valid signal and increment the addr_offset 
				AGG_DATA: begin
					is_agg_data_re <= 1;
					is_agg <= 1'b1;
					dim_cnt_agg <= dim_cnt_agg + 1'b1;
					if(dim_cnt_agg == data_dim_accu_DP -1 ) begin
						dim_cnt_agg <= '0;
						cluster_cnt_agg <= cluster_cnt_agg + 1'b1;
						if(cluster_cnt_agg == num_cluster_accu_DP-1) begin
							cluster_cnt_agg <= '0;
							state <= WAIT_ONE_CYCLE;
						end
					end

					re_addr_agg <= (cluster_cnt_agg << (MAX_DEPTH_BITS-NUM_BANK_BITS)) + (dim_cnt_agg>>NUM_BANK_BITS);

				end

				//wait one cycle to wait the data is read from memory
				WAIT_ONE_CYCLE: begin 
					is_agg <= 1'b1;
					state <= WAIT_SECOND_CYCLE;
					re_addr_agg <= '0;
				end

				WAIT_SECOND_CYCLE: begin
					state <= AGG_SSE;
					is_agg <= 1'b1;
				end

				AGG_CLUSTER: begin
					is_agg <= 1'b1;
					cluster_cnt_agg <= cluster_cnt_agg + 1'b1;
					if(cluster_cnt_agg == num_cluster_accu_DP-1) begin
						cluster_cnt_agg <= '0;
						state <= AGG_DATA;
					end
				end

				AGG_SSE: begin
					is_agg <= 1'b1;
					state <= TERMINATE; 
				end

				TERMINATE:begin 
					is_agg <= 1'b1;
					state <= AGG_IDLE;
					accu_counter_clr <= 1'b1;
					sse_clr <= 1'b1;
				end
			endcase
		end
	end
	

	//----------------ouput data path-----------------------//
	reg agg_data_re_valid;
	reg [NUM_BANK_BITS:0] sel_cnt;

	always @ (posedge clk) begin
		if(~rst_n_reg) begin
			agg_valid_o <= 1'b0;
			agg_data_re_valid <= 1'b0;
			sel_cnt <= '0;
		end
		else begin
			agg_data_re_valid <= is_agg_data_re; //takes one cycle to read from bram

			agg_data_o <= agg_data_re_valid ? {24'b0, bram_dout[sel_cnt*40 +: 40]} : (state == AGG_CLUSTER? accu_counter[cluster_cnt_agg] : (state == AGG_SSE? sse : '0 ) );
			agg_valid_o <= agg_data_re_valid | (state == AGG_CLUSTER) | (state == AGG_SSE);

			if(agg_data_re_valid) begin
				sel_cnt <= sel_cnt + 1'b1;
				if(sel_cnt == NUM_BANK-1) begin
					sel_cnt <= '0;
				end
			end

		end
	end

	assign accu_finish_o = accu_finish;

	

//-------------------------------ACCU BRAM ---------------------------------------//



	dual_port_ram #(.DATA_WIDTH(NUM_BANK*40), .ADDR_WIDTH(MAX_DEPTH_BITS+NUM_CLUSTER_BITS-NUM_BANK_BITS))
	accu_ram
	(
	.clk  (clk),
	.we   (bram_we),
	.re   (1'b1),
	.raddr(bram_addr_re),
	.waddr(bram_addr_wr),
	.din  (bram_din),
	.dout (bram_dout)
		);


	assign bram_addr_wr = is_agg ? wr_addr_agg : wr_addr_accu_reg2;
	assign bram_din = is_agg? '0: add_result;
	assign bram_addr_re = is_agg? re_addr_agg : re_addr_accu;
	assign bram_we = wr_en_accu | (agg_data_re_valid & sel_cnt == NUM_BANK-1);







endmodule
