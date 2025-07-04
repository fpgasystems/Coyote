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

module buffer_fifo(
    // Incoming clock and reset 
    input logic clock, 
    input logic reset, 

    // Incoming data, keep and last 
    input logic [511:0] input_data, 
    input logic [63:0] input_keep, 
    input logic input_last, 

    // Incoming read- and write-signals 
    input logic write_enable,  
    input logic read_enable,

    // Outgoing data, keep and last 
    output logic [511:0] output_data, 
    output logic [63:0] output_keep, 
    output logic output_last, 

    // Outgoing full, empty and halffull signals
    output logic full, 
    output logic empty, 
    output logic halffull
);

    // Depth of the FIFO has to be 12 to keep at least two pipelines worth of data (6 pipeline stages in the current design)

    ////////////////////////////////////////////////////////////////////////////
    //
    // Definition of data types required for the FIFO 
    //
    ////////////////////////////////////////////////////////////////////////////

    // Data Type for pointers to the FIFO 
    typedef logic [$clog2(12)-1:0] FIFOPointer; 

    // 512 Bit Data Type to store incoming data words 
    typedef logic [511:0] DataWord; 

    // 64 Bit Data Type to store incoming keep-signals 
    typedef logic [63:0] KeepWord; 

    // 32 bit integer for storing occupancy of the buffer 
    logic [4:0] occupancy;

    
    ////////////////////////////////////////////////////////////////////////////
    //
    // Definition of registers required for the FIFO 
    //
    ///////////////////////////////////////////////////////////////////////////

    // Pointers for read and write 
    FIFOPointer write_pointer; 
    FIFOPointer read_pointer; 

    // Actual FIFO storage 
    DataWord fifo_data[16]; 
    KeepWord fifo_keep[16]; 
    logic fifo_last[16]; 

    // Signals to check for valid read- and write-access
    logic valid_write_access; 
    logic valid_read_access; 

    assign valid_write_access = write_enable && !full;
    assign valid_read_access = read_enable && !empty;

    always_ff @(posedge clock) begin 
        if(reset) begin
            write_pointer <= 0; 
            read_pointer <= 0; 
            for(int i = 0; i < 16; i++) begin 
                fifo_data[i] <= 512'b0; 
                fifo_keep[i] <= 64'b0; 
                fifo_last[i] <= 1'b0; 
            end 
        end else begin 
            // Write-process
            if(valid_write_access) begin 
                fifo_data[write_pointer] <= input_data; 
                fifo_keep[write_pointer] <= input_keep; 
                fifo_last[write_pointer] <= input_last; 
                write_pointer <= write_pointer + 1; 
            end 

            // Read-process 
            if(valid_read_access) begin
                read_pointer <= read_pointer + 1; 
            end 

        end 
    end 

    // Generate the full, empty and halffull-signals. Edge-case: Wrap around is not detected by this additions
    assign full = ((write_pointer + 1) == read_pointer) || (read_pointer == 0 && write_pointer == 15); 
    assign empty = (write_pointer == read_pointer);

    assign occupancy = (write_pointer >= read_pointer) ? 
                   (write_pointer - read_pointer) : 
                   (16 - (read_pointer - write_pointer));
    assign halffull = (occupancy >= 8);

    assign output_data = fifo_data[read_pointer];
    assign output_keep = fifo_keep[read_pointer];   
    assign output_last = fifo_last[read_pointer];

endmodule