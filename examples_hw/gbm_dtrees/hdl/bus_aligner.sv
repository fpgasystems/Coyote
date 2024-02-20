
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

import DTPackage::*;

module bus_aligner 
	(
	input   wire                               clk,
	input   wire                               rst_n,

	input   wire  [511:0]           	       data_in,
	input   wire 							   data_in_last, 
	input   wire 							   data_in_type,
	input   wire                    		   data_in_valid,
	input   wire  [3:0]                        data_in_off,
	input   wire  [2:0]                        data_in_size, 
	input   wire  [4:0]                        data_in_word_count, 
	input   wire 							   stream_last,
    
    output  wire  [511:0]   		           data_out,
    output  wire                               data_out_last, 
    output  wire                               data_out_type, 
    output  wire  [2:0]                        data_out_size,
    output  wire                               data_out_valid
	);


reg  [511:0]       data_in_d1; 
reg  [511:0]       data_in_d2; 

reg                data_in_valid_d1; 
reg                data_in_valid_d2; 

reg                data_in_last_d1;
reg                data_in_last_d2;

reg  [3:0]  	   data_in_off_d1;
reg  [3:0]  	   data_in_off_d2;

reg  [2:0]         data_in_size_d1; 
reg  [2:0]         data_in_size_d2; 

reg  [4:0]         data_in_word_count_d1; 
reg  [4:0]         data_in_word_count_d2; 

reg 			   stream_last_d1;
reg 			   stream_last_d2;

reg 			   data_in_type_d1;
reg 			   data_in_type_d2;

wire 			   shifter_in_last;
///////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////          Prepare lines for Shifter          /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
always@(posedge clk)begin 
	////////////// Signals with reset //////////////////
	// Line 1
	if(~rst_n) begin
		data_in_valid_d1 <= 1'b0;
		data_in_valid_d2 <= 1'b0;
	end
	else begin
		// Line 1
		data_in_valid_d1 <= data_in_valid;

		// Line 2
		if(data_in_valid_d2) begin
			if(data_in_valid_d1) begin
				if(data_in_last_d2) begin
					data_in_valid_d2 <= 1'b1;
				end
				else if(data_in_last_d1) begin
					data_in_valid_d2 <= data_in_word_count_d1 > data_in_off_d2;
				end
				else begin 
					data_in_valid_d2 <= 1'b1;
				end
			end
			else if(stream_last_d2) begin
				data_in_valid_d2 <= 1'b0;
			end
		end
		else begin 
			data_in_valid_d2 <= data_in_valid_d1;
		end
	end
	////////////// Signals with no reset //////////////////
	// Line 1
	data_in_last_d1       <= data_in_last;
	data_in_d1            <= data_in;
	data_in_off_d1        <= data_in_off;
	data_in_word_count_d1 <= data_in_word_count;
	data_in_size_d1       <= data_in_size;
	data_in_type_d1       <= data_in_type;
	stream_last_d1        <= stream_last;

	// Line 2
	if(data_in_valid_d2) begin
		if(data_in_valid_d1) begin
			data_in_last_d2       <= data_in_last_d1;
			data_in_d2            <= data_in_d1;
			data_in_off_d2        <= data_in_off_d1;
			data_in_word_count_d2 <= data_in_word_count_d1;
			data_in_size_d2       <= data_in_size_d1;
			data_in_type_d2       <= data_in_type_d1;
			stream_last_d2        <= stream_last_d1;
		end
	end
	else begin 
		data_in_last_d2       <= data_in_last_d1;
		data_in_d2            <= data_in_d1;
		data_in_off_d2        <= data_in_off_d1;
		data_in_word_count_d2 <= data_in_word_count_d1;
		data_in_type_d2       <= data_in_type_d1;
		data_in_size_d2       <= data_in_size_d1;
		stream_last_d2        <= stream_last_d1;
	end
end


delay #(.DATA_WIDTH( 4 ),
	    .DELAY_CYCLES(16) 
	) smart_shifter_delay(
	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          ( {data_in_type_d2, data_in_size_d2} ),   // 
	    .data_in_valid    ( (data_in_valid_d1 || stream_last_d2) && data_in_valid_d2 ),
	    .data_out         ( {data_out_type, data_out_size} ),
	    .data_out_valid   (  )
     );

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                Smart Shifter                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign shifter_in_last = data_in_last_d2 || (data_in_last_d1 && (data_in_word_count_d1 <= data_in_off_d1));

smart_shifter #(.ELEMENTS_PER_CL(16),
                .ELEMENTS_PER_CL_BITS(4))
    smart_shifter_x(
    .clk               (clk),
    .rst_n             (rst_n),

    .inValid           ((data_in_valid_d1 || stream_last_d2) && data_in_valid_d2),
    .inOffs			   (data_in_off_d2),  
    .inLast            (shifter_in_last), 
    .inData            ({data_in_d1, data_in_d2}),

    .outValid          (data_out_valid),
    .outLast           (data_out_last),
    .outData           (data_out)
    );


endmodule   



