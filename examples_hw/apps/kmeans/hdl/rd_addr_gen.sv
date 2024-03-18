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

module rd_addr_gen (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low
	
	input wire 									 start_operator,

	output reg  [57:0]                           um_tx_rd_addr,
    output reg   [7:0]                           um_tx_rd_tag,
    output reg                           		 um_tx_rd_valid,
    input  wire                                  um_tx_rd_ready,

    input wire 									 potential_overflow,

    input RuntimeParam 							 rp
	
);

	reg is_initialize, is_read_tuple; 
	
	//read counter
	reg [31:0] rd_cnt;
	reg rd_cnt_en, rd_cnt_clr;

	//count how many iterations of read signal have been sent
	reg [15:0] rd_iteration_cnt;
	reg rd_iteration_cnt_en, rd_iteration_cnt_clr;

	reg [63:0] addr_offset_tuple, addr_offset_centroid;

	reg [16:0] precision_cnt;

	reg  [57:0]                          um_tx_rd_addr_reg;
    reg                           		 um_tx_rd_valid_reg;

 	typedef enum logic[1:0] {IDLE, INITIALIZE, DATA_FETCH} state;
	state currentState, nextState;

	always_comb begin : proc_fsm
		//default
		rd_cnt_en = 0;
		rd_cnt_clr = 0;

		is_initialize = 0;
		is_read_tuple = 0;

		rd_iteration_cnt_en = 0;
		rd_iteration_cnt_clr = 0;	

		nextState = currentState;

		case (currentState)

			IDLE: begin
				if(start_operator) begin
					nextState = INITIALIZE;
				end
			end

			//sequentially read the centroids cacheline from the memory
			INITIALIZE: begin
				is_initialize = 1;
				if(um_tx_rd_ready  & ~potential_overflow) begin
					rd_cnt_en = 1;
					if(rd_cnt == (rp.num_cl_centroid-1)) begin
						rd_cnt_clr = 1;
						nextState = DATA_FETCH;
					end
				end
			end

			//read the first few lines of every 32 cachelines from the memory
			DATA_FETCH: begin
				is_read_tuple = 1;
				if(um_tx_rd_ready & ~potential_overflow) begin
					rd_cnt_en = 1;
					if(rd_cnt == rp.num_cl_tuple-1) begin
						rd_cnt_clr = 1;
						rd_iteration_cnt_en = 1;
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

	// assign um_tx_rd_valid = (is_initialize | is_read_tuple) & um_tx_rd_ready & !potential_overflow;
	// assign um_tx_rd_addr =  is_initialize ? (rp.addr_center + addr_offset_centroid): (is_read_tuple ? (rp.addr_data + addr_offset_tuple) : '0);
	// assign um_tx_rd_tag = '0;

	//output path
	 always @ (posedge clk) begin
	 	if(~rst_n) begin
	 		um_tx_rd_valid_reg <= '0;
	 	end
	 	else begin
	 		if(um_tx_rd_ready) begin
	 			um_tx_rd_valid_reg <= (is_initialize | is_read_tuple)& !potential_overflow ;
	 			um_tx_rd_addr_reg <=  is_initialize ? (rp.addr_center + addr_offset_centroid): (is_read_tuple ? (rp.addr_data + addr_offset_tuple) : '0);
	 		end	
	 	end

	 	um_tx_rd_tag <= '0;
	 end
	 assign um_tx_rd_valid = um_tx_rd_valid_reg & um_tx_rd_ready;
	 assign um_tx_rd_addr = um_tx_rd_addr_reg;

	always @ (posedge clk) begin
		if(~rst_n ) begin
			addr_offset_tuple <= '0;
			addr_offset_centroid <= '0;
			precision_cnt <= '0;
			rd_cnt <= '0;
			rd_iteration_cnt <= '0;
			currentState <= IDLE;
		end
		else begin
			currentState <= nextState;

			rd_cnt <= rd_cnt_clr?'0:(rd_cnt_en? (rd_cnt+1) : rd_cnt);
			rd_iteration_cnt <= rd_iteration_cnt_clr? '0: (rd_iteration_cnt_en? (rd_iteration_cnt+1): rd_iteration_cnt);

			//sequentially read the centroids cacheline from the memory			
			if(is_initialize & um_tx_rd_ready & ~potential_overflow) begin
				addr_offset_centroid <= addr_offset_centroid + 1'b1;
			end

			//count how many cachelines in every 32 lines have been requested
			if(is_read_tuple & um_tx_rd_ready  & ~potential_overflow) begin
				if(precision_cnt == (rp.precision-1)) begin
					precision_cnt <= '0;
				end
				else begin
					precision_cnt <= precision_cnt +1'b1;
				end
			end

			//read the first few lines of every 32 cachelines from the memory
			if(is_read_tuple & um_tx_rd_ready  & ~potential_overflow) begin
				//new iteration
				if(rd_cnt == rp.num_cl_tuple-1) begin
					// if(rd_iteration_cnt == rp.num_iteration-1) begin
						addr_offset_tuple <= '0;
					// end
				end
				//jump to next block
				else if(precision_cnt == (rp.precision-1)) begin
					addr_offset_tuple <= addr_offset_tuple + 32-rp.precision + 1;
				end
				//next cacheline
				else begin
					addr_offset_tuple <= addr_offset_tuple + 1'b1;
				end
			end
				
		end

	end
	
	

endmodule