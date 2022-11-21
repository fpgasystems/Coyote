
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


module smart_shifter #(parameter ELEMENTS_PER_CL      = 16,
                       parameter ELEMENTS_PER_CL_BITS = 4)
    (
    input  wire                                clk,
    input  wire                                rst_n,

    input  wire 			                   inValid,
    input  wire                                inLast,
    input  wire  [3:0]                         inOffs,    
    input  wire  [1023:0]                      inData,

    output wire                                outValid,  
    output wire                                outLast, 
    output reg   [511:0]                       outData
    );    
    
    reg   [1023:0]                           shData [14:0];
    reg   [3:0]                              shOffs [14:0];
	 
	integer i;

    always @(posedge clk) begin
        // Level 0
        if ( |inOffs ) begin
            shData[0] <= {32'b0, inData[1023:32]};
            shOffs[0]  <= inOffs - 4'd1;
        end 
        else begin
            shData[0]  <= inData;
            shOffs[0]  <= inOffs;
        end
        // Rest of levels: Data, shOffs
        for ( i = 0; i <14; i = i+1) begin
            if ( |shOffs[i] ) begin
                shData[i+1]  <= {32'b0, shData[i][1023:32]};
                shOffs[i+1]  <= shOffs[i] - 4'd1;
            end 
            else begin
                shData[i+1]  <= shData[i];
                shOffs[i+1]  <= shOffs[i];
            end
        end

        outData  <= shData[14][511:0];
    end
    //

    delay #(.DATA_WIDTH(1),
            .DELAY_CYCLES(16) 
    ) validDelay(
        .clk              (clk),
        .rst_n            (rst_n),
        .data_in          ( inLast ),   // 
        .data_in_valid    ( inValid ),
        .data_out         ( outLast ),
        .data_out_valid   ( outValid )
     );

endmodule
