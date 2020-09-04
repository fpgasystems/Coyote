
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


module quick_fifo #(
    parameter FIFO_WIDTH = 32,
    parameter FIFO_DEPTH_BITS = 8,
    parameter FIFO_ALMOSTFULL_THRESHOLD = 2**FIFO_DEPTH_BITS - 4
) (
    input  wire                         clk,
    input  wire                         reset_n,
    
    input  wire                         we,              // input   write enable
    input  wire [FIFO_WIDTH - 1:0]      din,            // input   write data with configurable width

    input  wire                         re,              // input   read enable    
    output reg                          valid,           // dout valid
    output reg  [FIFO_WIDTH - 1:0]      dout,           // output  read data with configurable width    

    output reg  [FIFO_DEPTH_BITS - 1:0] count,              // output  FIFOcount
    output reg                          empty,              // output  FIFO empty
    output reg                          full,               // output  FIFO full                
    output reg                          almostfull         // output  configurable programmable full/ almost full    
);
        
    reg  [FIFO_DEPTH_BITS - 1:0]        rp = 0;
    reg  [FIFO_DEPTH_BITS - 1:0]        wp = 0;

    reg  [FIFO_DEPTH_BITS - 1:0]        mem_count = 0;              // output  FIFOcount
    reg                                 mem_empty = 1'b1;

    reg                                 valid_t1 = 0, valid_t2 = 0;
    reg                                 valid0 = 0;

    wire                                remem;
    wire                                wemem;
    wire                                remem_valid;

    wire  [FIFO_WIDTH-1:0]              dout_mem;
    
    assign remem     = (re & valid_t1 & valid_t2) | ~(valid_t1 & valid_t2);
    assign wemem     = we & ~full;

    assign remem_valid = remem & ~mem_empty;
    
        
    bram #(.DATA_WIDTH(FIFO_WIDTH),
           .ADDR_WIDTH(FIFO_DEPTH_BITS)) fifo_mem( 
        .clk        (clk),
        .we         (wemem),
		.re 		(remem),
        .raddr      (rp),
        .waddr      (wp),
        .din        (din),
        .dout       (dout_mem)
    );
    
    // data
    always @(posedge clk) begin
        dout     <= (valid_t2)? ((re)? dout_mem : dout) : dout_mem;
    end

    // valids, flags        
    always @(posedge clk) begin
        if (~reset_n) begin
            empty      <= 1'b1;
            full       <= 1'b0;
            almostfull <= 1'b0;
            count      <= 0;	//32'b0;            
            rp         <= 0;
            wp         <= 0;
            valid_t2   <= 1'b0;
            valid_t1   <= 1'b0;
            mem_empty  <= 1'b1;
            mem_count  <= 'b0;

            //dout       <= 0;
            valid      <= 0;
            valid0     <= 0;
        end
        
        else begin
            
            valid  <= (valid)? ((re)? valid0 : 1'b1) : valid0;
            valid0 <= (remem)? ~mem_empty : valid0;

            valid_t2 <= (valid_t2)? ((re)? valid_t1 : 1'b1) : valid_t1;

            valid_t1 <= (remem)? ~mem_empty : valid_t1;
            rp       <= (remem & ~mem_empty)?  (rp + 1'b1) : rp;
            wp       <= (wemem)?  (wp + 1'b1) : wp;

            // mem_empty
            if (we)                                mem_empty <= 1'b0;
            else if(remem & (mem_count == 1'b1))   mem_empty <= 1'b1;

            // mem_count 
            if( wemem & ~remem_valid)        mem_count <= mem_count + 1'b1;
            else if (~wemem & remem_valid)   mem_count <= mem_count - 1'b1;  

  
            // empty
            if (we)                                                     empty <= 1'b0;
            else if((re & valid_t2 & ~valid_t1) & (count == 1'b1))      empty <= 1'b1;

            // count 
            if( wemem & (~(re & valid_t2) | ~re) )  count <= count + 1'b1;
            else if (~wemem & (re & valid_t2))      count <= count - 1'b1;             

            // 
            if (we & ~re) begin  

                if (count == (2**FIFO_DEPTH_BITS-1))
                    full <= 1'b1;

                if (count == (FIFO_ALMOSTFULL_THRESHOLD-1))
                    almostfull <= 1'b1;
            end
            // 
            if ((~we | full) & re) begin //                
                full <= 1'b0;
                
                if (count == FIFO_ALMOSTFULL_THRESHOLD)
                    almostfull <= 1'b0;
            end                        
        end
    end

endmodule
