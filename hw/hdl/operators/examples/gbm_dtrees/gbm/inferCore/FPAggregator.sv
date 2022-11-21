
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
 
module FPAggregator #(parameter FP_ADDER_LATENCY = 2) (

		input   wire 						clk,
		input   wire 						rst_n,

		input   wire [31:0]					fp_in,
		input   wire 						fp_in_valid,
		input   wire 						fp_in_last,
		output  wire                        fp_in_ready,

		output  wire [31:0]					aggreg_out,
		output  wire  						aggreg_out_valid,
		input   wire                        aggreg_out_ready
	);




wire 									aggreg_in_fifo_full;
wire 									aggreg_in_fifo_valid;
wire 									aggreg_in_fifo_re;
wire 	[32:0]							aggreg_in_fifo_dout;

wire 	[33:0]							input_A;
reg  	[33:0]							prev_aggreg_value;
wire 	[33:0]							aggreg_value;
reg     [3:0] 							fpadder_latency_count;


wire 									fp_in_valid_delayed;
wire 									fp_in_last_delayed;
wire 									aggregator_ready;

reg     [31:0]					 		aggreg_out_d1;
reg  									aggreg_out_valid_d1;

wire 									aggreg_out_fifo_almfull;
////////////////////////////////////////////////////////////////////////////////
assign fp_in_ready = ~aggreg_in_fifo_full;

quick_fifo  #(.FIFO_WIDTH(32+1),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
             ) aggreg_in_fifo (
        	.clk                (clk),
        	.reset_n            (rst_n),
        	.din                ({fp_in_last, fp_in}),
        	.we                 (fp_in_valid),

        	.re                 (aggreg_in_fifo_re),
        	.dout               (aggreg_in_fifo_dout),
        	.empty              (),
        	.valid              (aggreg_in_fifo_valid),
        	.full               (aggreg_in_fifo_full),
        	.count              (),
        	.almostfull         ()
    	);

assign aggreg_in_fifo_re = aggregator_ready;
////////////////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
	if (~rst_n) begin
		// reset
		prev_aggreg_value      <= 0;
		fpadder_latency_count  <= 0;
		aggreg_out_valid_d1 <= 1'b0;
		aggreg_out_d1       <= 0;
	end
	else begin
		if(aggregator_ready & aggreg_in_fifo_valid) begin
			fpadder_latency_count  <= FP_ADDER_LATENCY;
		end
		else if(!(fpadder_latency_count == 0)) begin
			fpadder_latency_count  <= fpadder_latency_count - 1'b1;
		end
		//--------------------- Do aggregation --------------------------//
		if(fp_in_valid_delayed) begin 
			if(~fp_in_last_delayed) begin
				prev_aggreg_value <= aggreg_value;
			end
			else begin
				prev_aggreg_value <= 0;
			end
		end
                
		//--------------------- Tuple Output ----------------------------//
		aggreg_out_valid_d1 <= 1'b0;

		if(fp_in_valid_delayed & fp_in_last_delayed) begin 
			if(aggreg_value[33:32] == 2'b00) begin
				aggreg_out_d1       <=  0;
			end
			else begin
				aggreg_out_d1       <= aggreg_value[31:0];
			end
			
			aggreg_out_valid_d1 <= 1'b1;
		end
	end
end

assign aggregator_ready = (fpadder_latency_count == 0) & ~aggreg_out_fifo_almfull;

assign input_A = {1'b0, {|(aggreg_in_fifo_dout[31:0])}, aggreg_in_fifo_dout[31:0]};

FPAdder_8_23_uid2_l3 fpadder(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (input_A),
				.Y            (prev_aggreg_value),
				.R            (aggreg_value)
				);

// delay valid, last with FPAdder Latency
delay #(.DATA_WIDTH(1),
	    .DELAY_CYCLES(FP_ADDER_LATENCY) 
	) fpadder_delay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          (aggreg_in_fifo_dout[32]),   // 
	    .data_in_valid    (aggreg_in_fifo_valid & aggregator_ready),
	    .data_out         (fp_in_last_delayed),
	    .data_out_valid   (fp_in_valid_delayed)
	);


quick_fifo  #(.FIFO_WIDTH(32),        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(490)
             ) aggreg_out_fifo (
        	.clk                (clk),
        	.reset_n            (rst_n),
        	.din                (aggreg_out_d1),
        	.we                 (aggreg_out_valid_d1),

        	.re                 (aggreg_out_ready),
        	.dout               (aggreg_out),
        	.empty              (),
        	.valid              (aggreg_out_valid),
        	.full               (),
        	.count              (),
        	.almostfull         (aggreg_out_fifo_almfull)
    	);




endmodule
