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

module muu_HT_Read #(
	parameter KEY_WIDTH = 128,
	parameter META_WIDTH = 96,
	parameter HASHADDR_WIDTH = 64,
    parameter MEMADDR_WIDTH = 21,
    parameter USER_BITS = 3
	)
    (
	// Clock
	input wire         clk,
	input wire         rst,

	input  wire [KEY_WIDTH+META_WIDTH+HASHADDR_WIDTH+USER_BITS-1:0] input_data,
	input  wire         input_valid,
	output wire         input_ready,

	input  wire [KEY_WIDTH+META_WIDTH+HASHADDR_WIDTH+USER_BITS-1:0] feedback_data,
	input  wire         feedback_valid,
	output wire         feedback_ready,

	output reg [KEY_WIDTH+META_WIDTH+HASHADDR_WIDTH+USER_BITS-1:0] output_data,
	output reg         output_valid,
	input  wire         output_ready,

	output reg [31:0] rdcmd_data,
	output reg         rdcmd_valid,
	input  wire         rdcmd_ready
);
`include "muu_ops.vh"

    reg selectInputNext;
    reg selectInput; //1 == input, 0==feedback

	localparam [2:0]
		ST_IDLE   = 0,
        ST_ISSUE_READ_ONE = 1,
		ST_ISSUE_READ_TWO = 2,
		ST_OUTPUT_KEY  = 3;
	reg [2:0] state;    

    wire[HASHADDR_WIDTH+KEY_WIDTH+META_WIDTH+USER_BITS-1:0] in_data;
    wire in_valid;
    reg in_ready;
    wire[HASHADDR_WIDTH-1:0] hash_data;

    wire [USER_BITS-1:0] curr_user;


    assign in_data = (selectInput==1) ? input_data : feedback_data;
    assign in_valid = (selectInput==1) ? input_valid : feedback_valid;
    assign input_ready = (selectInput==1) ? in_ready : 0;
    assign feedback_ready = (selectInput==1) ? 0 : in_ready;

    assign curr_user = (selectInput==1) ? input_data[KEY_WIDTH+META_WIDTH+USER_BITS-1:KEY_WIDTH+META_WIDTH] : feedback_data[KEY_WIDTH+META_WIDTH+USER_BITS-1:KEY_WIDTH+META_WIDTH]; 

    assign hash_data = (selectInput==1) ? input_data[KEY_WIDTH+META_WIDTH+USER_BITS+HASHADDR_WIDTH-1:KEY_WIDTH+META_WIDTH+USER_BITS] : feedback_data[KEY_WIDTH+META_WIDTH+USER_BITS+HASHADDR_WIDTH-1:KEY_WIDTH+META_WIDTH+USER_BITS];    

    wire[MEMADDR_WIDTH-1:0] addr1;    
    wire[MEMADDR_WIDTH-1:0] addr2;    

    assign addr1 = hash_data[0 +: HASHADDR_WIDTH/2];
    assign addr2 = hash_data[HASHADDR_WIDTH/2 +: HASHADDR_WIDTH/2];

    always @(posedge clk) begin
    	if (rst) begin
    		selectInput <= 1;
    		selectInputNext <= 0;    		
    		state <= ST_IDLE;
    		in_ready <= 0;
    		rdcmd_valid <= 0;
    		output_valid <= 0;    		
    	end
    	else begin

    		if (rdcmd_ready==1 && rdcmd_valid==1) begin
    			rdcmd_valid <= 0;
    		end

    		if (output_ready==1 && output_valid==1) begin
    			output_valid <= 0;
    		end

            in_ready <= 0;


    		case (state)    		
    			ST_IDLE : begin
    				if (output_ready==1 && rdcmd_ready==1) begin
    					selectInput <= selectInputNext;
    					selectInputNext <= ~selectInputNext;

    					if (selectInputNext==1 && feedback_valid==1) begin
    						selectInput <= 0;
    						selectInputNext <= 1;    						
                            state <= ST_ISSUE_READ_ONE;     

    					end else if (selectInputNext==1 && input_valid==1) begin
                            state <= ST_ISSUE_READ_ONE;                         

                        end

    					if (selectInputNext==0 && input_valid==1 && feedback_valid==0) begin
    						selectInput <= 1;
    						selectInputNext <= 0;    		                            				
                            state <= ST_ISSUE_READ_ONE;                         

    					end else if (selectInputNext==0 && feedback_valid==1) begin
    						state <= ST_ISSUE_READ_ONE;    						

    					end    					

    				end
    			end

    			ST_ISSUE_READ_ONE: begin    			

                    state <= ST_ISSUE_READ_TWO;                      
                    output_data <= in_data;                  

                    if (in_data[KEY_WIDTH+META_WIDTH-8 +: 4]==HTOP_IGNORE || in_data[KEY_WIDTH+META_WIDTH-8 +: 4]==HTOP_IGNOREPROP) begin
                        // ignore this and don't send read!
                        in_ready <= 1; 
                        state <= ST_OUTPUT_KEY;       

                    end else begin			                        
        				   rdcmd_data[MEMADDR_WIDTH-1:0] <= {curr_user, addr1[MEMADDR_WIDTH-USER_BITS-1:0]};
    					   rdcmd_valid <= 1;
                           rdcmd_data[31:MEMADDR_WIDTH] <= 0;    				    
                    end

    								

    			end


                ST_ISSUE_READ_TWO: begin       

                    if (rdcmd_ready==1) begin         

                        state <= ST_OUTPUT_KEY;                      

                        in_ready <= 1;  
                            
                        rdcmd_data[MEMADDR_WIDTH-1:0] <= {curr_user, addr2[MEMADDR_WIDTH-USER_BITS-1:0]};
                        rdcmd_valid <= 1;
                        rdcmd_data[31:MEMADDR_WIDTH] <= 0;                                                                           
                    end

                end


    			ST_OUTPUT_KEY: begin
    				if (output_ready==1) begin
    					
                        output_valid <= 1;

                        state <= ST_IDLE;
    				end
    			end


    		endcase
    	end
    end
        
    endmodule
