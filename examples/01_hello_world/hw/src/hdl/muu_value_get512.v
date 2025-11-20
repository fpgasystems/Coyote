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


module muu_Value_Get512 #(
	parameter KEY_WIDTH = 128,
	parameter HEADER_WIDTH = 42, //vallen + val addr
	parameter META_WIDTH = 96,
	parameter MEMORY_WIDTH = 512,
	parameter SUPPORT_SCANS = 0, 
	parameter USER_BITS = 3,
	parameter MAX_WORDS_IN_PACKET = 1152/64 //MTU-headers / 64
	)
    (
	// Clock
	input wire         clk,
	input wire         rst,

	input  wire [KEY_WIDTH+HEADER_WIDTH+META_WIDTH-1:0] input_data,
	input  wire         input_valid,
	output reg         input_ready,

	input  wire        cond_drop,
	input  wire        cond_valid,
	output reg         cond_ready,

	input  wire [MEMORY_WIDTH-1:0] value_data,
	input  wire         value_valid,
	output wire         value_ready,

	input  wire [MEMORY_WIDTH-1:0] repl_in_data,
	input  wire         repl_in_valid,
	output wire         repl_in_ready,

	output wire [META_WIDTH+512-1:0] output_data,
	output wire [7:0] 		output_user,
	output reg         output_valid,
	output reg 			output_last,
	input  wire         output_ready,

	input wire 			scan_mode,

	input wire[31:0] malloc_stat_data

);

`include "muu_ops.vh"

localparam [3:0]
	ST_IDLE   = 0,
	ST_HEADER = 1,	
	ST_KEY = 2,
	ST_VALUE = 3,
	ST_KEY_RRAW = 5,
	ST_KEY_REPL = 6,
	ST_VALUE_REPL = 7,
	ST_DROP = 4,
	ST_NO_HEADER = 8;
reg [3:0] state;
reg [3:0] prev_state;

reg [9:0] toread;
reg hasvalue;
reg [META_WIDTH-1:0] meta_data;
reg [KEY_WIDTH-1:0] key_data;
reg [511:0] output_word;
reg [31:0] output_zxid;
reg [31:0] output_epoch;

reg [7:0] out_userid;

reg flush;

reg dropit;

reg scanning;

reg[9:0] words_since_last;
reg must_last;

reg first_value_word;

wire is_forme;
wire is_write;
wire send_answer;


//assign value_ready = (output_ready==1 && state==ST_VALUE) ? 1 : ((prev_state==ST_VALUE || state==ST_DROP) & flush);
assign value_ready = (state==ST_VALUE) ? output_ready : ( state==ST_DROP ? flush : 0); 

//assign repl_in_ready = (output_ready==1 && state==ST_VALUE_REPL) ? 1 : ((prev_state==ST_VALUE_REPL) & flush);
assign repl_in_ready = (state==ST_VALUE_REPL) ? output_ready : 0;

assign output_data = {meta_data,output_word};

wire[3:0] htopcode;
assign htopcode = input_data[KEY_WIDTH+152 +: 4];

wire[7:0] repopcode;
assign repopcode = input_data[KEY_WIDTH+144 +: 8];

assign is_write = (htopcode==HTOP_SETCUR || htopcode==HTOP_SETNEXT || htopcode==HTOP_FLIPPOINT) ? 1:0;
assign is_forme = (htopcode==HTOP_IGNORE || htopcode==HTOP_FLUSH || htopcode==HTOP_GETRAW ) ? 0:1;
assign send_answer = ((htopcode==HTOP_SETNEXT && repopcode==OPCODE_PROPOSAL) || (htopcode==HTOP_FLIPPOINT && repopcode==8'h80)) ? 0:1;

reg [KEY_WIDTH+HEADER_WIDTH+META_WIDTH-1:0] lastInputForSet [2**USER_BITS-1:0] ;

reg sendAnswerReg;


wire[USER_BITS-1:0] current_userid;
assign current_userid = input_data[KEY_WIDTH+META_WIDTH-1 : KEY_WIDTH+META_WIDTH-USER_BITS];

assign output_user = out_userid;

always @(posedge clk) begin
	if (rst) begin
		// reset
		output_valid <= 0;				
		output_last <= 0;
		input_ready <= 0;
		flush <= 0;
		dropit <= 0;

		cond_ready <= 0;

		scanning <= 0;

		state <= ST_IDLE;

		words_since_last <= 0;
		must_last <= 0;

		prev_state <= 0;

		sendAnswerReg <= 0;
	end
	else begin

		prev_state <= state;

		cond_ready <= 0;

		if (output_valid==1 && output_ready==1) begin
			output_valid <= 0;
			output_last <= 0;
		end		

		
        if (output_last==1 && output_valid==1 && output_ready==1) begin
            words_since_last <= 1;
            must_last <= 0;
        end else if (output_valid==1 && output_ready==1) begin
            words_since_last <= words_since_last+1;		
            if (words_since_last>=MAX_WORDS_IN_PACKET) begin
            	must_last <= 1;
        	end else begin
            	must_last <= 0;
        	end
        end
        
       
        
        if (SUPPORT_SCANS==1) begin
			
			if  (scanning==1 && scan_mode==0 && (output_valid!=1 || output_last!=1)) begin
				output_valid <= 1;
				output_last <= 1;
				must_last <= 1;
				words_since_last <= 128;
				output_word <= 512'h00000000FEEBDAED;
			end
		end		


		input_ready <= 0;

		case (state)

			ST_IDLE: begin

				flush <= 0;

				dropit <= 0;

				scanning <= scan_mode;

				if (flush==0 && input_valid==1) begin

					sendAnswerReg <= send_answer;

					out_userid <= {{8-USER_BITS{1'b0}},current_userid};

					if (is_write==1 && is_forme==1) begin
						
						output_valid <= send_answer;	
					    
						hasvalue <= 0;
						state <= send_answer ? ST_HEADER : ST_NO_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						if (input_data[KEY_WIDTH+META_WIDTH +: 30]==0) begin
							// this should actually signal error!
							output_word[63:0] <= {32'h0, input_data[KEY_WIDTH+144 +:8],input_data[KEY_WIDTH+88 +:8], 16'hffff};
							output_word[511:64] <= 0; 
						end else begin
							output_word[63:0] <= {32'h0, input_data[KEY_WIDTH+144 +:8],input_data[KEY_WIDTH+88 +:8], 16'hffff};
							output_word[511:64] <= 0;
						end							

						if (input_data[KEY_WIDTH+88 +: 8]!=0) begin 
							lastInputForSet[current_userid] <= input_data;							
						end else begin
							lastInputForSet[current_userid] <= 0;
						end
				
					end 
					else if (htopcode==HTOP_FLUSH) begin
						output_valid <= 1;		
						hasvalue <= 0;
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						output_word[63:0] <= {32'h0, 32'h0, 16'h1, 16'hffff};
						output_word[511:64] <= 0;
					end 
					else if (htopcode==HTOP_GET) begin
						output_valid <= 1;		
						hasvalue <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0 ? 0 : 1;
						toread <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10];
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						output_word[63:0] <= {22'h0, (input_data[KEY_WIDTH+META_WIDTH+32 +: 10]/8), input_data[KEY_WIDTH+144 +: 8] , input_data[KEY_WIDTH+88 +: 8], 16'hffff};							
						output_word[511:64] <= 0;
					end
					else if (htopcode==HTOP_GETRAW && (repopcode==OPCODE_PROPOSAL || repopcode==OPCODE_SYNCRESP)) begin
						output_valid <= 1;		
						hasvalue <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0 ? 0 : 1;
						toread <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10];
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						output_word[63:0] <= {22'h0, ((input_data[KEY_WIDTH+META_WIDTH+32 +: 10]/8)+1), input_data[KEY_WIDTH+144 +: 8] , input_data[KEY_WIDTH+88 +: 8], 16'hffff};							
						output_word[511:64] <= 0;
					end
					else if (htopcode==HTOP_IGNORE && repopcode==OPCODE_PROPOSAL) begin
						output_valid <= 1;		
						hasvalue <= lastInputForSet[current_userid][KEY_WIDTH+META_WIDTH+32 +: 10]==0 ? 0 : 1;
						toread <= lastInputForSet[current_userid][KEY_WIDTH+META_WIDTH+32 +: 10];
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						output_word[63:0] <= {22'h0, ((lastInputForSet[current_userid][KEY_WIDTH+META_WIDTH+32 +: 10]/8)+1), input_data[KEY_WIDTH+144 +: 8] , input_data[KEY_WIDTH+88 +: 8], 16'hffff};							
						output_word[511:64] <= 0;
					end
					else if (htopcode==HTOP_IGNORE && repopcode==OPCODE_COMMIT) begin
						output_valid <= 1;		
						hasvalue <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0 ? 0 : 1;
						toread <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10];
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						output_word[63:0] <= {22'h0, (input_data[KEY_WIDTH+META_WIDTH+32 +: 10]/8), input_data[KEY_WIDTH+144 +: 8] , input_data[KEY_WIDTH+88 +: 8], 16'hffff};
						output_word[511:64] <= 0;
					end
					else if (htopcode==HTOP_GETCOND) begin
						if (cond_valid==1 || input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0) begin
						
							output_valid <= 1;		
							hasvalue <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0 ? 0 : 1;
							toread <= input_data[KEY_WIDTH+META_WIDTH+32 +: 10];
							state <= ST_HEADER;
							meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
							key_data <= input_data[KEY_WIDTH-1:0];
							input_ready <= 1;
							output_word[63:0] <= {22'h0, (input_data[KEY_WIDTH+META_WIDTH+32 +: 10]/8), input_data[KEY_WIDTH+144 +: 8] , input_data[KEY_WIDTH+88 +: 8], 16'hffff};							
							output_word[511:64] <= 0;
							dropit <= cond_drop;
							
							if (cond_drop==1) begin
								output_word[32 +: 10] <= 0;							
							end
						end
						
					end
					/* 
					else if (input_data[KEY_WIDTH+HEADER_WIDTH+META_WIDTH-8 +: 4] == 4'b1000 || cond_valid==1 || input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0 || (is_write==1 && is_forme==0)) begin							

						hasvalue <= (input_data[KEY_WIDTH+META_WIDTH+32 +: 10]==0) ? 0 : 1;
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];



						if (SUPPORT_SCANS==1 && input_data[KEY_WIDTH+HEADER_WIDTH+META_WIDTH-8 +: 4]==4'b1111 && cond_drop==1) begin
							output_word <= {32'h0, 32'h0, 16'h2, 16'hffff};													
							output_valid <= 0;
							input_ready <= 1;

						end else begin												
							//output_word <= {32'h0, 22'h0, input_data[KEY_WIDTH+META_WIDTH+31 +: 10], input_data[KEY_WIDTH+META_WIDTH+HEADER_WIDTH+88 +: 8] , input_data[KEY_WIDTH+META_WIDTH+HEADER_WIDTH+144 +: 8], 16'hffff};							

							if (input_data[KEY_WIDTH+31 +: 10]!=0) begin
								//if (value_valid==1) begin
									input_ready <= 1;								
									output_valid <= 1;
								//end
							end else begin
								input_ready <= 1;						
								output_valid <= 1;
							end
					
						end

						if (input_data[KEY_WIDTH+HEADER_WIDTH+META_WIDTH-8 +: 4]!=4'b1000 && input_data[KEY_WIDTH+31 +: 10]!=0) begin
							cond_ready <= 1;
							dropit <= cond_valid==1 ? cond_drop : 0;
							if (cond_valid==1) begin
								if (cond_drop==1) begin
									output_word[32 +: 10] <= 0;							
								end
							end
						end

						toread <= input_data[KEY_WIDTH+31 +: 10];			

					end 
					*/
					else if (input_valid==1) begin

						output_valid <= 1;		
						hasvalue <= 0;
						state <= ST_HEADER;
						meta_data <= input_data[KEY_WIDTH +: META_WIDTH];
						key_data <= input_data[KEY_WIDTH-1:0];
						input_ready <= 1;
						output_word[63:0] <= {32'h0, 32'h0, 16'h0, 16'hffff};
						output_word[511:64] <= 0;
					end
				end 
			end

			ST_HEADER: begin
				if (output_ready==1 && (hasvalue==0 || cond_valid==1 || is_forme==0)) begin
					if (htopcode!=HTOP_GETRAW) begin 
						cond_ready <= hasvalue & is_forme;
					end else begin
						cond_ready <= hasvalue;
					end

					output_valid <= 1;
					output_word[63:0] <= {16'h0, meta_data[128 +: 16], meta_data[96 +: 32]}; // prints out the pointer and length
					output_word[511:64] <= 0;
					//output_word <= {32'h0,malloc_stat_data};

					first_value_word <= 1;

					if (hasvalue==1 && toread>0 && dropit==0) begin
						if (is_forme==1) begin
							state <= ST_VALUE;	
						end else begin
							if (htopcode!=HTOP_GETRAW) begin 
								state <= ST_KEY_REPL;					
							end else begin
								state <= ST_KEY_RRAW;					
							end
						end
					end else if (hasvalue==1 && toread>0 && dropit==1) begin							
						state <= ST_DROP;						
						flush <= 1;
						output_last <= (SUPPORT_SCANS==1 && scanning==1) ? must_last : 1;	
						if (must_last==1) begin
							must_last<= 0;
						end;											
					end else begin
						output_last <= (SUPPORT_SCANS==1 && scanning==1) ? must_last : 1;
						state <= ST_IDLE;
						if (must_last==1) begin
							must_last<= 0;
						end;
					end
					
				end
			end

			ST_NO_HEADER: begin
				if (output_ready==1) begin
					output_valid <= sendAnswerReg;
					output_word[63:0] <= {16'h0, meta_data[128 +: 16], meta_data[96 +: 32]}; // prints out the pointer and length
					output_word[511:64] <= 0;
					//output_word <= {32'h0,malloc_stat_data};

					first_value_word <= 1;

					output_last <= sendAnswerReg;
					state <= ST_IDLE;										
				end
			end


			ST_VALUE: begin
				if (output_ready==1 && value_valid==1) begin

					first_value_word <= 0;

					toread <= toread-8;

					output_valid <= 1;
					output_word <= value_data;
					output_last <= must_last;

					
					//if (first_value_word==1 && value_data[15:0]<1500) begin
					//	toread <= (value_data[15:0]+63)/8-1;
					//end else
					if (toread<=8) begin						
						state <= ST_IDLE;	
						output_last <= (SUPPORT_SCANS==1 && scanning==1) ? must_last : 1;

					/*	if (toread<8) begin
							flush <= 1;
						end */
					end

					if (must_last==1) begin
							must_last<= 0;
						end;
				end
			end

			ST_KEY_RRAW: begin
				if (output_ready==1 && value_valid==1) begin

					
					output_valid <= 1;
					output_word[63:0] <= key_data;
					output_word[511:64] <= 0;
										
					state <= ST_VALUE;
				end
			end					

			ST_KEY_REPL: begin
				if (output_ready==1 && repl_in_valid==1) begin

					
					output_valid <= 1;
					output_word[63:0] <= key_data;
					output_word[511:64] <= 0;
										
					state <= ST_VALUE_REPL;
				end
			end					

			ST_VALUE_REPL: begin
				if (output_ready==1 && repl_in_valid==1) begin

					toread <= toread-8;					

					first_value_word <= 0;
					
					output_valid <= 1;
					output_word <= repl_in_data;
					output_last <= must_last;
										
					if (toread<=8) begin						
						state <= ST_IDLE;	
						output_last <= 1;

						if (toread<8) begin
							flush <= 1;
						end
					end

					if (must_last==1) begin
							must_last<= 0;
						end;
				end
			end			

			ST_DROP: begin
				if (value_valid==1 && value_ready==1) begin
					toread <= toread-8;

					first_value_word <= 0;

					//if (first_value_word==1 && value_data[15:0]<1024) begin
					//	toread <= (value_data[15:0]+63)/8-1;
					//	if (((value_data[15:0]+63)/8)==1) begin
					//		flush <= 0;
					//		state <= ST_IDLE;
					//	end
					//end
					//else 
					if (toread<=8) begin
						flush <= 0;
						state <= ST_IDLE;
					end
				end

			end

		endcase

	end
end


endmodule