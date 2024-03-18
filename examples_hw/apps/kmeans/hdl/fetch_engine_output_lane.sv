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

module fetch_engine_output_lane (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low

	input wire 									start_operator,

	input RuntimeParam 							rp,
	input wire 									rx_fifo_valid,
	input wire [511:0] 							rx_fifo_dout,
	output wire 								rx_fifo_re,

	//interface to kmeans module

    output wire [511:0] 						tuple_cl,
    output wire 								tuple_cl_valid,
    output reg 									tuple_cl_last,
    input wire 									tuple_cl_ready,


    output wire [511:0]							centroid_cl,
    output wire 								centroid_cl_valid,
    output reg 									centroid_cl_last,
    input wire 									centroid_cl_ready
	
);

	reg is_centroid, is_tuple; 
	
	//read counter
	reg [31:0] rd_cnt;
	reg rd_cnt_en, rd_cnt_clr;

	//count how many iterations of data have been sent
	reg [15:0] rd_iteration_cnt;
	reg rd_iteration_cnt_en, rd_iteration_cnt_clr;

	assign rx_fifo_re = rx_fifo_valid & ((is_centroid & centroid_cl_ready) | (is_tuple & tuple_cl_ready));

	//data path for tuple
	assign tuple_cl_valid = is_tuple & rx_fifo_valid & tuple_cl_ready;
	assign tuple_cl = is_tuple ? rx_fifo_dout : '0;

	//data path for centroid
	assign centroid_cl_valid = is_centroid & rx_fifo_valid & centroid_cl_ready;
	assign centroid_cl = is_centroid ? rx_fifo_dout : '0;

	//fsm to count the number of centroid/tuple cachelines and set last bit 
	typedef enum logic[1:0] {IDLE, CENTROID, TUPLE} state;
	state currentState, nextState;

	always_comb begin : proc_fsm
		//default
		rd_cnt_en = 0;
		rd_cnt_clr = 0;

		is_centroid = 0;
		is_tuple = 0;

		rd_iteration_cnt_en = 0;
		rd_iteration_cnt_clr = 0;	

		tuple_cl_last = 0;
		centroid_cl_last = 0;

		nextState = currentState;

		case (currentState)

			IDLE: begin
				if(start_operator) begin
					nextState = CENTROID;
				end
			end

			//sequentially read the centroids cacheline from the memory
			CENTROID: begin
				is_centroid = 1;
				if(rx_fifo_valid && centroid_cl_ready ) begin
					rd_cnt_en = 1;
					if(rd_cnt == (rp.num_cl_centroid-1)) begin
						rd_cnt_clr = 1;
						centroid_cl_last = 1;
						nextState = TUPLE;
					end
				end
			end

			//read the first few lines of every 32 cachelines from the memory
			TUPLE: begin
				is_tuple = 1;
				if(rx_fifo_valid && tuple_cl_ready) begin
					rd_cnt_en = 1;
					if(rd_cnt == rp.num_cl_tuple-1) begin
						rd_cnt_clr = 1;
						rd_iteration_cnt_en = 1;
						tuple_cl_last = 1;
						if(rd_iteration_cnt == rp.num_iteration-1) begin
							rd_iteration_cnt_clr = 1;
							nextState = IDLE;
						end
					end
				end
			end
		
			//default : /* default */;
		endcase 
	end

	always @ (posedge clk) begin
		if(~rst_n) begin
			rd_cnt <= '0;
			rd_iteration_cnt <= '0;
			currentState <= IDLE;
		end
		else begin
			currentState <= nextState;
			rd_cnt <= rd_cnt_clr?'0:(rd_cnt_en? (rd_cnt+1) : rd_cnt);
			rd_iteration_cnt <= rd_iteration_cnt_clr? '0: (rd_iteration_cnt_en? (rd_iteration_cnt+1): rd_iteration_cnt);
		end
	end


endmodule