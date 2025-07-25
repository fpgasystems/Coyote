/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Simple module to enforce time gaps between processed ACKs, has to be used directly after a reasonably large FIFO to buffer incoming but gap-enforced packets

module ack_gap_enforcer(
    // Incoming clock and reset 
    input logic nclk, 
    input logic nresetn, 

    // AXI-Stream interfaces for incoming and outgoing network streams 
    AXI4S.s input_stream,
    AXI4S.m output_stream
);

    // Required variable 
    logic is_ack;
    logic [7:0] gap_counter;

    // Check if the incoming packet is actually an ACK
    assign is_ack = input_stream.tvalid && (input_stream.tdata[15:0] == 16'h0245) && (input_stream.tdata[231:224] == 8'h11) && input_stream.tready;

    // Synchronous block for the gap counter
    always_ff @(posedge nclk) begin
        if(!nresetn) begin
            gap_counter <= 8'h0;
        end else begin
            if(is_ack) begin
                // In case we witness an ACK, set the gap counter to 8'h28 = 40 
                gap_counter <= 8'h55; // 90ns gap
            end else begin
                // As long as the gap is present, decrement the counter 
                if(gap_counter > 8'h0) begin
                    gap_counter <= gap_counter - 8'h1;
                end
            end
        end
    end
    
    // Connect incoming and outgoing AXI-streams, tready and tvalid is where the gap is enforced
    assign output_stream.tvalid = (gap_counter == 8'h0) ? input_stream.tvalid : 1'b0; // If gap is over, connect to input valid 
    assign output_stream.tlast = input_stream.tlast;
    assign output_stream.tdata = input_stream.tdata;
    assign output_stream.tkeep = input_stream.tkeep;
    assign input_stream.tready = (gap_counter == 8'h0) ? output_stream.tready : 1'b0; // If gap is over, connect to output ready 
    
endmodule


// Simple module to enforce time gaps between processed ACKs, has to be used directly after a reasonably large FIFO to buffer incoming but gap-enforced packets

/* module ack_gap_enforcer(
    // Incoming clock and reset 
    input logic nclk, 
    input logic nresetn, 

    // AXI-Stream interfaces for incoming and outgoing network streams 
    AXI4S.s input_stream,
    AXI4S.m output_stream
);

    // Required variable 
    logic is_roce;
    logic was_roce;
    logic [7:0] gap_counter;

    // Check if the incoming packet is actually an ACK
    assign is_roce = input_stream.tvalid && (input_stream.tdata[15:0] == 16'h0245) && input_stream.tready;

    // Synchronous block for the gap counter
    always_ff @(posedge nclk) begin
        if(!nresetn) begin
            gap_counter <= 8'h0;
        end else begin

            if(!was_roce) begin
                if(is_roce && !input_stream.tlast) begin
                    was_roce <= 1'b1; 
                end 
            end else begin
                if(input_stream.tvalid && input_stream.tlast && input_stream.tready) begin
                    was_roce <= 1'b0; 
                end 
            end 

            if((is_roce || was_roce) && input_stream.tvalid && input_stream.tlast && input_stream.tready) begin
                // In case we witness an ACK, set the gap counter to 8'h28 = 40 
                gap_counter <= 8'h55; // 90ns gap
            end else begin
                // As long as the gap is present, decrement the counter 
                if(gap_counter > 8'h0) begin
                    gap_counter <= gap_counter - 8'h1;
                end
            end
        end
    end
    
    // Connect incoming and outgoing AXI-streams, tready and tvalid is where the gap is enforced
    assign output_stream.tvalid = (gap_counter == 8'h0) ? input_stream.tvalid : 1'b0; // If gap is over, connect to input valid 
    assign output_stream.tlast = input_stream.tlast;
    assign output_stream.tdata = input_stream.tdata;
    assign output_stream.tkeep = input_stream.tkeep;
    assign input_stream.tready = (gap_counter == 8'h0) ? output_stream.tready : 1'b0; // If gap is over, connect to output ready 
    
endmodule */ 