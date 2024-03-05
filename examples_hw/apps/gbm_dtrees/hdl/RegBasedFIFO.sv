
/*
 * Copyright 2019 - 2020 Systems Group, ETH Zurich
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

module RegBasedFIFO #(parameter FIFO_WIDTH      = 32,
	                  parameter FIFO_DEPTH_BITS = 2
	                 )(
	                 	input   wire  							clk,
					 	input   wire 							rst_n,

					 	input   wire  [FIFO_WIDTH-1:0]          data_in,
					 	input   wire 							data_in_valid,
					 	output  wire 							data_in_ready, 

					 	output  wire  [FIFO_WIDTH-1:0] 			data_out, 
					 	output  wire 							data_out_valid,
					 	input   wire 							data_out_ready
					);



localparam  FIFO_NUM_REGS = 2**FIFO_DEPTH_BITS; 


reg  [FIFO_WIDTH-1:0] 	 fifo_reg_data[FIFO_NUM_REGS-1:0];
reg  					 fifo_reg_valid[FIFO_NUM_REGS-1:0];

// Last Reg in the FIFO
// valid 
always@(posedge clk) begin 
	// data
	if(data_out_ready || ~fifo_reg_valid[FIFO_NUM_REGS-1]) begin
		fifo_reg_data[FIFO_NUM_REGS-1] <= data_in;
	end
	// valid
	if(~rst_n) begin
		fifo_reg_valid[FIFO_NUM_REGS-1] <= 1'b0;
	end
	else begin 
		if(data_out_ready) begin
			fifo_reg_valid[FIFO_NUM_REGS-1] <= 1'b0;
		end
		else if(!fifo_reg_valid[FIFO_NUM_REGS-1] && fifo_reg_valid[FIFO_NUM_REGS-2]) begin
			fifo_reg_valid[FIFO_NUM_REGS-1] <= data_in_valid;
		end
	end
end

// Rest of Regs
genvar i;

generate for (i = 0; i < FIFO_NUM_REGS-1; i=i+1) begin: fifo_regs
	// valid 
	always@(posedge clk) begin 
		// Data
		if(~fifo_reg_valid[i]) begin
			fifo_reg_data[i] <= data_in;
		end
		else if(data_out_ready) begin
			if(fifo_reg_valid[i+1]) begin
				fifo_reg_data[i] <= fifo_reg_data[i+1];
			end
			else begin 
				fifo_reg_data[i] <= data_in;
			end
		end
		// valid
		if(~rst_n) begin
			fifo_reg_valid[i] <= 1'b0;
		end
		else if(~fifo_reg_valid[i]) begin
			if(i == 0) begin
				fifo_reg_valid[i] <= data_in_valid; 
			end
			else begin 
				if(!data_out_ready && fifo_reg_valid[i-1]) begin
					fifo_reg_valid[i] <= data_in_valid; 
				end
			end
		end
		else if(data_out_ready) begin
			if(fifo_reg_valid[i+1]) begin
				fifo_reg_valid[i] <= 1'b1;
			end
			else begin 
				fifo_reg_valid[i] <= data_in_valid; 
			end
		end
	end
end
endgenerate


//
assign data_in_ready  = ~fifo_reg_valid[FIFO_NUM_REGS-2];
assign data_out       = fifo_reg_data[0];
assign data_out_valid = fifo_reg_valid[0];





endmodule