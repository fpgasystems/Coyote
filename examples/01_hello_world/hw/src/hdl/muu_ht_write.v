//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//-- 
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//-- 
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//-- 
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------


`default_nettype none

module muu_HT_Write #(
	parameter KEY_WIDTH = 64,
	parameter HEADER_WIDTH = (16+32)*2, //vallen + val addr *2
	parameter VALPOINTER_WIDTH = (16+32), //vallen + val addr *2
	parameter META_WIDTH = 96,
	parameter DOUBLEHASH_WIDTH = 64,
	parameter MEMORY_WIDTH = 512,
	parameter FASTFORWARD_BITS = 5,
	parameter MEM_WRITE_WAIT = 512,
	parameter MEMADDR_WIDTH = 21,
	parameter IS_SIM = 0,
	parameter USER_BITS = 3
	)
    (
	// Clock
	input wire         clk,
	input wire         rst,

	input  wire [KEY_WIDTH+META_WIDTH+USER_BITS+DOUBLEHASH_WIDTH-1:0] input_data,
	input  wire         input_valid,
	output reg         input_ready,

	output reg [KEY_WIDTH+META_WIDTH+USER_BITS-1:0] feedback_data,
	output reg         feedback_valid,
	input  wire         feedback_ready,

	output reg [16+KEY_WIDTH+META_WIDTH+USER_BITS+VALPOINTER_WIDTH-1:0] output_data,
	output reg         output_valid,
	input  wire         output_ready,

	input wire [31:0] malloc_pointer,
	input wire 		  malloc_valid,
	input wire		malloc_failed,
	output reg 	  malloc_ready,
	
	output reg [31:0] free_pointer,
	output reg [15:0] free_size,
	output reg 		free_valid,
	input wire 			free_ready,
	output reg 		free_wipe,


	input wire [MEMORY_WIDTH-1:0]  rd_data,
	input wire         rd_valid,
	output  reg         rd_ready,	

	output reg [MEMORY_WIDTH-1:0] wr_data,
	output reg         wr_valid,
	input  wire         wr_ready,

	output reg [31:0] wrcmd_data,
	output reg         wrcmd_valid,
	input  wire         wrcmd_ready, 

	output reg [15:0] 	debug
);
`include "muu_ops.vh"


localparam [3:0]
	ST_IDLE   = 0,
	ST_CHECK_FF = 1,
	ST_CHECK_MEM  = 2,
	ST_CHECK_MEM_TWO = 3,
	ST_SKIP_MEM = 4,
	ST_SKIP_MEM_TWO = 5,
	ST_CUR_ENTRY = 6,
	ST_DECIDE  = 7,
	ST_WRITEDATA = 8,
	ST_SENDOUT = 9,
	ST_WIPE = 15;
reg [3:0] state;



reg [3:0] opmode;
wire op_needsmalloc;
reg op_retry;
reg op_addrchoice;

reg [32-1:0] fastforward_addr [0:2**FASTFORWARD_BITS];
 (* ram_style = "block" *) reg [USER_BITS+MEMORY_WIDTH-1:0] fastforward_mem [0:2**FASTFORWARD_BITS];
reg [FASTFORWARD_BITS-1:0] ff_head;
reg [FASTFORWARD_BITS-1:0] ff_tail;
reg [FASTFORWARD_BITS-1:0] ff_cnt;
reg [FASTFORWARD_BITS-1:0] pos_ff;

(* ram_style = "block" *) reg [USER_BITS+KEY_WIDTH+HEADER_WIDTH-1:0] kicked_keys [0:2**FASTFORWARD_BITS]; 
reg [FASTFORWARD_BITS-1:0] kk_head;
reg [FASTFORWARD_BITS-1:0] kk_tail;
reg [FASTFORWARD_BITS-1:0] kk_cnt;
reg [FASTFORWARD_BITS-1:0] pos_kk;

reg [1:0] found_ff;
reg [1:0] found_addr_ff;
reg [1:0] empty_ff;
reg [FASTFORWARD_BITS-1:0] found_ff_pos;
reg [1:0] found_ff_idx;
reg [1:0] empty_ff_idx;
reg found_kk;
reg [FASTFORWARD_BITS-1:0] found_kk_pos;
reg [1:0] found_mem;
reg [1:0] found_mem_idx;
reg [1:0] empty_mem;
reg [1:0] empty_mem_idx;

reg [31:0] oldpointer;

reg [MEMADDR_WIDTH-1:0] wipe_location;
reg wipe_start;

(* keep = "true", max_fanout = 4 *) reg[KEY_WIDTH+META_WIDTH+USER_BITS+DOUBLEHASH_WIDTH-1:0] inputReg;

reg [MEM_WRITE_WAIT-1:0] delayer;

wire [3:0] curr_opcode;
assign curr_opcode = (state==ST_IDLE) ? input_data[KEY_WIDTH+META_WIDTH-8 +: 4] : inputReg[KEY_WIDTH+META_WIDTH-8 +: 4];

wire [7:0] resp_opcode;
assign resp_opcode = (state==ST_IDLE) ? input_data[KEY_WIDTH+META_WIDTH-16 +: 8] : inputReg[KEY_WIDTH+META_WIDTH-16 +: 8];
wire silent_resp;
assign silent_resp = (resp_opcode==8'h80) ? 1 : 0;


assign op_needsmalloc = (opmode==HTOP_SETNEXT || opmode==HTOP_SETCUR) ? 1 : 0;

wire [3:0] curr_flags;
assign curr_flags = (state==ST_IDLE) ? input_data[KEY_WIDTH+META_WIDTH-4 +: 4] : inputReg[KEY_WIDTH+META_WIDTH-4 +: 4];

wire [MEMADDR_WIDTH-1:0] curr_hash1;
wire [MEMADDR_WIDTH-1:0] curr_hash2;
assign curr_hash1 = (state==ST_IDLE) ? input_data[KEY_WIDTH+META_WIDTH+USER_BITS +: MEMADDR_WIDTH] : inputReg[KEY_WIDTH+META_WIDTH+USER_BITS +: MEMADDR_WIDTH];
assign curr_hash2 = (state==ST_IDLE) ? input_data[KEY_WIDTH+META_WIDTH+USER_BITS+DOUBLEHASH_WIDTH/2 +: MEMADDR_WIDTH] : inputReg[KEY_WIDTH+META_WIDTH+USER_BITS+DOUBLEHASH_WIDTH/2 +: MEMADDR_WIDTH];

reg [MEMADDR_WIDTH-1:0] writebackAddr;
reg [2:0] writebackIdx;
reg [USER_BITS+KEY_WIDTH+HEADER_WIDTH-1:0] writebackEntry;
reg [MEMORY_WIDTH-1:0] writebackLine;
reg writebackKeyMatch;
reg writebackNeedsKick;
reg writebackToKK;

wire [USER_BITS-1:0] curr_user;
assign curr_user = (state==ST_IDLE) ? input_data[KEY_WIDTH+META_WIDTH +: USER_BITS] : inputReg[KEY_WIDTH+META_WIDTH +: USER_BITS];


integer c;
integer x;

reg[USER_BITS+MEMORY_WIDTH-1:0] fastforward_mem_pos_reg;
reg[USER_BITS+MEMORY_WIDTH-1:0] fastforward_mem_found_reg;
reg [USER_BITS+KEY_WIDTH+HEADER_WIDTH-1:0] kicked_keys_pos_reg;
reg [USER_BITS+KEY_WIDTH+HEADER_WIDTH-1:0] kicked_keys_found_reg;

reg[USER_BITS+MEMORY_WIDTH-1:0] fastforward_write_data; 
reg[7:0] fastforward_write_addr; 
reg fastforward_write_valid;

reg[USER_BITS+KEY_WIDTH+HEADER_WIDTH-1:0] kicked_keys_write_data;
reg[7:0] kicked_keys_write_addr; 
reg kicked_keys_write_valid;

reg[511:0] write_data_prep;

reg[MEMORY_WIDTH-1:0] rdMemWord [1:2];

reg mallocRegValid;
reg[31:0] mallocRegData;
reg mallocRegFail;

reg[15:0] inputValueSize;

reg rst_regd; 

always @(posedge clk) begin

	rst_regd <= rst;

	debug <= {resp_opcode, curr_opcode, state};

	if (rst_regd) begin
		// reset
		state <= ST_IDLE;
		ff_head <= 0;
		ff_tail <= 0;
		ff_cnt <= 0;
		kk_head <= 0;
		kk_tail <= 0;
		kk_cnt <= 0;
		delayer <= 0;

		rd_ready <= 0;
		wr_valid <= 0;
		wrcmd_valid <= 0;

		input_ready <= 0;

		free_valid <= 0;
		free_wipe <= 0;
		malloc_ready <= 0;
		output_valid <= 0;
		
		feedback_valid <= 0;

		kicked_keys_write_valid <= 0;
		fastforward_write_valid <= 0;

		malloc_ready <= 0;

		empty_ff_idx <= 0;
		empty_mem_idx <= 0;

	end
	else begin

		fastforward_mem_pos_reg <= fastforward_mem[pos_ff];		
		kicked_keys_pos_reg <= kicked_keys[pos_kk];

		kicked_keys_write_valid <= 0;
		fastforward_write_valid <= 0;

		if (kicked_keys_write_valid==1) begin
			kicked_keys[kicked_keys_write_addr] <= kicked_keys_write_data;
		end

		if (fastforward_write_valid==1) begin
			fastforward_mem[fastforward_write_addr] <= fastforward_write_data;
		end

		delayer <= {delayer[MEM_WRITE_WAIT-2:0],1'b0};

		if (delayer[MEM_WRITE_WAIT-1]==1 && ff_cnt>0) begin
			ff_cnt <= ff_cnt-1;
			ff_tail <= ff_tail+1;
		end

		if (output_valid==1 && output_ready==1) begin
			output_valid <= 0;
		end

		if (feedback_valid==1 && feedback_ready==1) begin
			feedback_valid <= 0;
		end

		if (free_valid==1 && free_ready==1) begin
			free_valid <= 0;
			free_wipe <= 0;
		end

		if (wrcmd_valid==1 && wrcmd_ready==1) begin
			wrcmd_valid <= 0;			
		end

		if (wr_valid==1 && wr_ready==1) begin
			wr_valid <= 0;
		end

		input_ready <= 0;

		malloc_ready <= 0;

		rd_ready <= 0;

		case (state)

			ST_WIPE: begin

				if (wrcmd_ready==1 && wrcmd_valid==1) begin
					wrcmd_valid <= 0;
				end

				if (wr_ready==1 && wr_valid==1) begin
					wr_valid <= 0;
				end


				if (wrcmd_ready==1 && wr_ready==1 && wrcmd_valid==0 && wr_valid==0) begin
					wipe_start <= 0;

					wrcmd_data[31:MEMADDR_WIDTH] <= 0;
					wrcmd_data[MEMADDR_WIDTH-1:0] <= wipe_location;	
					wrcmd_valid <= 1;

					wr_data <= 0;
					wr_valid <= 1;

					wipe_location <= wipe_location+1;

				end
				

				if (wipe_start==0 && wipe_location== (IS_SIM==0 ? 0 : 16) ) begin  // 16 for sim!

					if (ff_cnt>0 || kk_cnt>0) begin
						state <= ST_CHECK_FF;
						pos_ff <= ff_tail;
						pos_kk <= kk_tail;
					end else begin
						state <= ST_CHECK_MEM;						
					end

				end
			end

			ST_IDLE: begin
				if (input_valid==1) begin
					opmode <= curr_opcode;
					op_retry <= curr_flags[2];
					op_addrchoice <= curr_flags[3];

					inputReg <= input_data;

					input_ready <= 1;

					found_ff <= 0;
					found_addr_ff <= 0;
					found_kk <= 0;
					found_mem <= 0;
					empty_mem <= 0;
					empty_ff <= 0;

					if (curr_opcode!=HTOP_IGNORE && curr_opcode!=HTOP_IGNOREPROP) begin
						inputValueSize <= input_data[KEY_WIDTH+64 +: 16];
					end


					if (curr_opcode == HTOP_IGNORE || curr_opcode == HTOP_IGNOREPROP) begin					
						state <= ST_SENDOUT;

					end else if (curr_opcode == HTOP_FLUSH) begin
						state <= ST_WIPE;

						free_valid <= 1;
						free_wipe <= 1;

						wipe_start <= 1;
						wipe_location <= 0;
					end else begin

						if (ff_cnt>0 || kk_cnt>0) begin
							state <= ST_CHECK_FF;
							pos_ff <= ff_tail;
							pos_kk <= kk_tail;
						end else begin
							state <= ST_CHECK_MEM;						
						end

					end
				end
			end

			ST_CHECK_FF: begin
				if (pos_ff==(ff_head+1)%2**FASTFORWARD_BITS && pos_kk==(kk_head+1)%2**FASTFORWARD_BITS) begin
					if (found_addr_ff!=0) begin
						state <= ST_SKIP_MEM;
					end else begin
						state <= ST_CHECK_MEM;					
					end
				end else begin

					if (pos_ff!=(ff_head+1)%2**FASTFORWARD_BITS) begin
						pos_ff <= pos_ff+1;

						if (pos_ff!=ff_tail) begin
							if (fastforward_addr[pos_ff-1]==curr_hash1 && fastforward_mem_pos_reg[MEMORY_WIDTH+USER_BITS-1:MEMORY_WIDTH]==curr_user) begin
								found_addr_ff <= 1;
								found_ff_pos <= pos_ff-1;
								fastforward_mem_found_reg <= fastforward_mem_pos_reg;
								found_ff_idx <= 0;
								empty_ff <= 0;

								// compare to this data
								for (c=0; c<MEMORY_WIDTH/(KEY_WIDTH+HEADER_WIDTH); c=c+1) begin       
									if (fastforward_mem_pos_reg[(c)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==inputReg[KEY_WIDTH-1:0]) begin
										found_ff <= 1;
										found_ff_pos <= pos_ff-1;
										found_ff_idx <= c;
									end else begin
										found_ff <= 0;
									end

									if (fastforward_mem_pos_reg[(c)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==0) begin
										empty_ff_idx <= c;
										empty_ff <= 1;
									end
	    						end
							end

							if (fastforward_addr[pos_ff-1]==curr_hash2 && fastforward_mem_pos_reg[MEMORY_WIDTH+USER_BITS-1:MEMORY_WIDTH]==curr_user) begin
								found_addr_ff <= 2;
								found_ff_pos <= pos_ff-1;
								fastforward_mem_found_reg <= fastforward_mem_pos_reg;
								found_ff_idx <= 0;
								empty_ff <= 0;

								// compare to this data
								for (c=0; c<MEMORY_WIDTH/(KEY_WIDTH+HEADER_WIDTH); c=c+1) begin       
									if (fastforward_mem_pos_reg[(c)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==inputReg[KEY_WIDTH-1:0]) begin
										found_ff <= 2;
										found_ff_pos <= pos_ff-1;
										found_ff_idx <= c;
									end else begin
										found_ff <= 0;
									end

									if (fastforward_mem_pos_reg[(c)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==0) begin
										empty_ff_idx <= c;
										empty_ff <= 2;
									end
	    						end
							end
						end
					end

					if (pos_kk!=(kk_head+1)%2**FASTFORWARD_BITS) begin
						pos_kk <= pos_kk+1;

						
						if (pos_kk!=kk_tail) begin
							if (kicked_keys_pos_reg[KEY_WIDTH-1:0]==inputReg[KEY_WIDTH-1:0] && kicked_keys_pos_reg[KEY_WIDTH+HEADER_WIDTH +: USER_BITS]==curr_user && found_kk==0) begin
								// this is the same, do something

								found_kk <= 1;
								found_kk_pos <= pos_kk-1;
								kicked_keys_found_reg <= kicked_keys_pos_reg;

								if (op_retry==1 && (opmode==HTOP_SETNEXT || opmode==HTOP_SETCUR) && pos_kk==(kk_tail+1)%2**FASTFORWARD_BITS) begin
									oldpointer <= kicked_keys_pos_reg[KEY_WIDTH+31:KEY_WIDTH];
									kk_cnt <= kk_cnt-1;
									kk_tail <= kk_tail +1;
									found_kk <= 0;
								end
							end
						end
					end
				end

			end

			ST_SKIP_MEM: begin
				if (rd_valid==1  && (malloc_valid==1 || op_needsmalloc==0 || op_retry==1)) begin
					state <= ST_SKIP_MEM_TWO;

					malloc_ready <= (op_needsmalloc==1 && op_retry == 0) ? 1 : 0;

					rd_ready <= 1;

    				mallocRegValid <= malloc_valid;
    				mallocRegData <= malloc_pointer;
    				mallocRegFail <= malloc_failed;
				end
			end

			ST_SKIP_MEM_TWO: begin
				if (rd_ready==0 && rd_valid==1) begin
					state <= ST_CUR_ENTRY;
					rd_ready <= 1;

				end
			end


			ST_CHECK_MEM: begin
				if (rd_valid==1 && (malloc_valid==1 || op_needsmalloc==0 || op_retry==1)) begin
					// compare to this data

					for (x=0; x<MEMORY_WIDTH/(KEY_WIDTH+HEADER_WIDTH); x=x+1) begin       
						if (rd_data[(x)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==inputReg[KEY_WIDTH-1:0]) begin
							found_mem <= 1;
							found_mem_idx <= x;
						end
						if (rd_data[(x)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==0) begin
							empty_mem_idx <= x;
							empty_mem <= 1;
						end
    				end

    				malloc_ready <= (op_needsmalloc == 1 && op_retry==0) ? 1 : 0;

    				mallocRegValid <= malloc_valid;
    				mallocRegData <= malloc_pointer;
    				mallocRegFail <= malloc_failed;

    				rd_ready <= 1;

    				rdMemWord[1] <= rd_data;

					state <= ST_CHECK_MEM_TWO;
				end
			end

			ST_CHECK_MEM_TWO: begin
				if (rd_ready==0 && rd_valid==1) begin
					// compare to this data

					rdMemWord[2] <= rd_data;

					for (x=0; x<MEMORY_WIDTH/(KEY_WIDTH+HEADER_WIDTH); x=x+1) begin       
						if (rd_data[(x)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==inputReg[KEY_WIDTH-1:0]) begin
							found_mem <= 2;
							found_mem_idx <= x;


						end
						if (rd_data[(x)*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH]==0 && empty_mem==0) begin
							empty_mem_idx <= x;
							empty_mem <= 2;
						end
    				end

					state <= ST_CUR_ENTRY;
					rd_ready <= 1;
				end
			end

			ST_CUR_ENTRY: begin

				writebackNeedsKick <= 0;
				writebackToKK <= 0;
				
				if (found_kk!=0) begin

					writebackAddr <= found_kk_pos;
					writebackIdx <= 0;
					writebackEntry <= kicked_keys_found_reg;
					writebackKeyMatch <= 1;
					writebackLine <= 0;
					writebackToKK <= 1;

				end else if (found_addr_ff!=0) begin
				
					writebackEntry <= {curr_user , fastforward_mem_found_reg[found_ff_idx*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH+HEADER_WIDTH]};
					writebackLine <= fastforward_mem_found_reg;

					if (found_ff==1) begin
						writebackAddr <= curr_hash1;
						writebackIdx <= found_ff_idx;
						writebackKeyMatch <= 1;

					end else if (found_ff==2) begin
						writebackAddr <= curr_hash2;
						writebackIdx <= found_ff_idx;
						writebackKeyMatch <= 1;

					end else if (empty_ff==1) begin
						writebackAddr <= curr_hash1;
						writebackIdx <= empty_ff_idx;
						writebackEntry <= 0;
						writebackKeyMatch <= 0;

					end else if (empty_ff==2) begin
						writebackAddr <= curr_hash2;
						writebackIdx <= empty_ff_idx;
						writebackEntry <= 0;
						writebackKeyMatch <= 0;
					end else begin

						writebackAddr <= found_addr_ff==1 ? curr_hash1 : curr_hash2;

						if (ff_tail[1:0]<MEMORY_WIDTH/(KEY_WIDTH+HEADER_WIDTH)) begin						
							writebackIdx <= ff_tail[1:0];
							writebackEntry <= {curr_user, fastforward_mem_found_reg[ff_tail[1:0]*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH+HEADER_WIDTH]};
						end else begin
							writebackIdx <= 0;
							writebackEntry <= {curr_user, fastforward_mem_found_reg[0*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH+HEADER_WIDTH]};
						end

						writebackKeyMatch <= 0;
						writebackNeedsKick <= 1;
					end
														
					

				end else if (found_mem!=0) begin

					writebackAddr <= (found_mem==1) ? curr_hash1 : curr_hash2;
					writebackIdx <= found_mem_idx;
					writebackEntry <= {curr_user, rdMemWord[found_mem][found_mem_idx*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH+HEADER_WIDTH]};			
					writebackKeyMatch <= 1;
					writebackLine <= rdMemWord[found_mem];

				end else if (empty_mem!=0) begin

					writebackAddr <= (empty_mem==1) ? curr_hash1 : curr_hash2;
					writebackIdx <= empty_mem_idx;
					writebackLine <= rdMemWord[empty_mem];	
					writebackKeyMatch <= 0;
					writebackEntry <= 0;

				end	else begin

					writebackAddr <= curr_hash1;

					if (ff_tail[1:0]<MEMORY_WIDTH/(KEY_WIDTH+HEADER_WIDTH)) begin						
						writebackIdx <= ff_tail[1:0];
						writebackEntry <= {curr_user, rdMemWord[1][ff_tail[1:0]*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH+HEADER_WIDTH]};
					end else begin
						writebackIdx <= 0;
						writebackEntry <= {curr_user, rdMemWord[1][0*(KEY_WIDTH+HEADER_WIDTH) +: KEY_WIDTH+HEADER_WIDTH]};
					end

					writebackKeyMatch <= 0;
					writebackLine <= rdMemWord[1];	
					writebackNeedsKick <= 1;

				end		
				

				state <= ST_DECIDE;
				
			end

			ST_DECIDE : begin

				case (opmode)

					HTOP_GET,HTOP_GETCOND : begin

						output_valid <= 1;
						output_data[0 +: KEY_WIDTH+META_WIDTH+USER_BITS] <= inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS];					
						output_data[KEY_WIDTH+META_WIDTH+USER_BITS +: VALPOINTER_WIDTH] <= writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH];
						output_data[KEY_WIDTH+META_WIDTH+USER_BITS+VALPOINTER_WIDTH +: 16] <= writebackEntry[KEY_WIDTH +VALPOINTER_WIDTH-16 +: 16];
						state <= ST_IDLE;
					
					end			

					HTOP_GETRAW : begin

						output_valid <= 1;
						output_data[0 +: KEY_WIDTH+META_WIDTH+USER_BITS] <= inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS];		

						if (writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH] ==0) begin
							output_data[KEY_WIDTH+META_WIDTH+USER_BITS +: VALPOINTER_WIDTH] <= writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH];
							output_data[KEY_WIDTH+META_WIDTH+USER_BITS+VALPOINTER_WIDTH +: 16] <= writebackEntry[KEY_WIDTH +VALPOINTER_WIDTH-16 +: 16];
						end
						else begin
							output_data[KEY_WIDTH+META_WIDTH+USER_BITS +: VALPOINTER_WIDTH] <= writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH  +: VALPOINTER_WIDTH];
							output_data[KEY_WIDTH+META_WIDTH+USER_BITS+VALPOINTER_WIDTH +: 16] <= writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH  +VALPOINTER_WIDTH-16 +: 16]; 
						end
						state <= ST_IDLE;
					
					end					

					HTOP_SETNEXT,HTOP_SETCUR : begin

						if (feedback_ready==1 && free_ready==1 && kk_cnt<2**FASTFORWARD_BITS-1) begin 

							state <= ST_WRITEDATA;

							if (writebackNeedsKick==1) begin
								// kick out a key

								feedback_valid <= 1;
								feedback_data <= {inputReg[KEY_WIDTH+META_WIDTH +: USER_BITS], {META_WIDTH{1'b0}},writebackEntry[0 +: KEY_WIDTH]};
								feedback_data[KEY_WIDTH+META_WIDTH-8 +: 4] <= HTOP_SETCUR;
								feedback_data[KEY_WIDTH+META_WIDTH-4 +: 4] <= 4'b0100;

								kicked_keys_write_data <= writebackEntry;						
								kicked_keys_write_addr <= kk_head;
								kicked_keys_write_valid <= 1;
								kk_head <= kk_head+1;
								kk_cnt <= kk_cnt+1;
							end

							if (writebackKeyMatch==1) begin
								// this is the same key, look at pointers	

								if (opmode==HTOP_SETCUR && writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH]==0) begin
									//nothing prepared yet, put pointer there

									writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH] <= {inputValueSize,mallocRegData};

								end else if (opmode==HTOP_SETCUR && writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH]!=0) begin
									//pointer location is taken...

									writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH] <= {inputValueSize,mallocRegData};
									free_valid <= 1;
									free_wipe <= 0;
									free_pointer <= writebackEntry[KEY_WIDTH +: 32];
									free_size <= {writebackEntry[KEY_WIDTH+32 +: 13],3'b000};

								end else if (opmode==HTOP_SETNEXT && writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH]==0) begin
									//nothing prepared yet, put pointer there

									writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH] <= {inputValueSize,mallocRegData};

								end else if (opmode==HTOP_SETNEXT && writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH]!=0) begin
									//pointer location is taken...

									writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH] <= {inputValueSize,mallocRegData};
									free_valid <= 1;
									free_wipe <= 0;
									free_pointer <= writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: 32];
									free_size <= {writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH+32 +: 13],3'b000};
								end

							end else begin
								// this is a brand new insert								
								if (opmode==HTOP_SETCUR) begin

									writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH] <= {inputValueSize,mallocRegData};
									writebackEntry[0 +: KEY_WIDTH] <= inputReg[0 +: KEY_WIDTH];
									writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH] <= 0;

								end else begin

									writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH] <= {inputValueSize,mallocRegData};
									writebackEntry[0 +: KEY_WIDTH] <= inputReg[0 +: KEY_WIDTH];
									writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH] <= 0;

								end
							end
						end

					end

					HTOP_DELCUR : begin
						if (free_ready==1) begin 

							if (writebackKeyMatch==1) begin
								// this is the same key, look at pointers	
																
								writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH] <= 0;
								free_valid <= 1;
								free_wipe <= 0;
								free_pointer <= writebackEntry[KEY_WIDTH +: 32];
								free_size <= {writebackEntry[KEY_WIDTH+32 +: 13], 3'b000};

								state <= ST_WRITEDATA;

							end else begin

								output_data <= { 16'h0, {VALPOINTER_WIDTH{1'b0}}, inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
								output_valid <= 1;

								state <= ST_IDLE;
							end

						end
					end

					HTOP_FLIPPOINT : begin
						if (free_ready==1) begin 

							if (writebackKeyMatch==1 && writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH]!=0) begin
							 
								writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH] <= writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH];
								writebackEntry[KEY_WIDTH+VALPOINTER_WIDTH +: VALPOINTER_WIDTH] <= 0;

								if (writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH]!=0) begin
									free_valid <= 1;
									free_wipe <= 0;
									free_pointer <= writebackEntry[KEY_WIDTH +: 32];
									free_size <= writebackEntry[KEY_WIDTH+32 +: 16];									
								end

								state <= ST_WRITEDATA;

							end else begin

								if (silent_resp==1) begin								
									output_data <= { 16'hFFFF, {VALPOINTER_WIDTH{1'b0}}, inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
									output_valid <= 1;
								end else 								
								begin
									output_data <= { 16'h0, {VALPOINTER_WIDTH{1'b0}}, inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
									output_valid <= 1;
								end
								
								state <= ST_IDLE;
							end
						end					

					end

					HTOP_FLUSH : begin
						if (output_ready==1) begin
							output_data <= { 16'h0, {VALPOINTER_WIDTH{1'b0}}, inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
							output_valid <= 1;
							
							state <= ST_IDLE;
						end
					end

				endcase


			end

			ST_SENDOUT : begin
				if (output_ready==1) begin
					output_data <= {16'h0, {VALPOINTER_WIDTH{1'b0}}, inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
					if (opmode==HTOP_IGNOREPROP) begin
						output_data[KEY_WIDTH+META_WIDTH+USER_BITS+VALPOINTER_WIDTH +: 16] <= inputValueSize;
						output_data[KEY_WIDTH+META_WIDTH-8 +: 4] <= HTOP_IGNORE;
					end
					output_valid <= 1;
					state <= ST_IDLE;
				end
			end


			ST_WRITEDATA : begin
				if (writebackToKK==0) begin
					if (wr_ready==1 && wrcmd_ready==1 && ff_cnt<2**FASTFORWARD_BITS-1 && output_ready==1) begin

						wr_data <= writebackLine;
						wr_data[writebackIdx*(KEY_WIDTH+HEADER_WIDTH) +: (KEY_WIDTH+HEADER_WIDTH)] <= writebackEntry;
						wr_valid <= 1;

						wrcmd_data[MEMADDR_WIDTH-1:0] <= {curr_user,writebackAddr[MEMADDR_WIDTH-USER_BITS-1:0]};
						wrcmd_data[31:MEMADDR_WIDTH] <= 0;
						wrcmd_valid <= 1;

						if (inputReg[KEY_WIDTH+META_WIDTH-4 +: 4]==0) begin
							// not a kicked reinsert

							output_valid <= 1;

							if (opmode==HTOP_SETNEXT) begin
								output_data <= {16'h0, writebackEntry[KEY_WIDTH +VALPOINTER_WIDTH +: VALPOINTER_WIDTH], inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
							end else begin
								if (silent_resp==1 && opmode==HTOP_FLIPPOINT) begin
									output_data <= {16'hFFFF, writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH], inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
								end
								else begin
									output_data <= {16'h0, writebackEntry[KEY_WIDTH +: VALPOINTER_WIDTH], inputReg[0 +: KEY_WIDTH+META_WIDTH+USER_BITS]};
								end
							end						
						end

						fastforward_write_data <= writebackLine;
						fastforward_write_data[writebackIdx*(KEY_WIDTH+HEADER_WIDTH) +: (KEY_WIDTH+HEADER_WIDTH)] <= writebackEntry;
						fastforward_write_addr <= ff_head;
						fastforward_write_valid <= 1;
						fastforward_addr[ff_head] <= writebackAddr;
						ff_head <= ff_head+1;

						delayer[0] <= 1;

						if (delayer[MEM_WRITE_WAIT-1]==1 && ff_cnt>0) begin
							ff_cnt <= ff_cnt; 
						end else begin
							ff_cnt <= ff_cnt+1;						
						end

						state <= ST_IDLE;				

				    end
				end else begin
					kicked_keys_write_data <= writebackEntry;						
					kicked_keys_write_addr <= writebackAddr;
					kicked_keys_write_valid <= 1;

					state <= ST_IDLE;
				end
			end



		endcase
		
	end
end

        
   endmodule



`default_nettype wire