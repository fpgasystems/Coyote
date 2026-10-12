`timescale 1ns/1ps

/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
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

module pl_pcie_nvme_queue_tdp_ram
  #(
    parameter ADDR_BITS = 10,
    parameter DATA_BITS = 64
  )
  (
    input  logic                          clk,
    input  logic                          a_en,
    input  logic [(DATA_BITS/8)-1:0]      a_we,
    input  logic [ADDR_BITS-1:0]          a_addr,
    input  logic                          b_en,
    input  logic [(DATA_BITS/8)-1:0]      b_we,
    input  logic [ADDR_BITS-1:0]          b_addr,
    input  logic [DATA_BITS-1:0]          a_data_in,
    input  logic [DATA_BITS-1:0]          b_data_in,
    output logic [DATA_BITS-1:0]          a_data_out,
    output logic [DATA_BITS-1:0]          b_data_out
  );

  localparam DEPTH = 2**ADDR_BITS;

  (* ram_style = "block" *) reg [DATA_BITS-1:0] ram[0:DEPTH-1];

  integer i;
  always @(posedge clk) begin
    if(a_en) begin
      for (i = 0; i < (DATA_BITS/8); i = i + 1) begin
        if(a_we[i]) begin
          ram[a_addr][(i*8)+:8] <= a_data_in[(i*8)+:8];
        end
      end
      a_data_out <= ram[a_addr];
    end
  end

  integer j;
  always @(posedge clk) begin
    if(b_en) begin
      for (j = 0; j < (DATA_BITS/8); j = j + 1) begin
        if(b_we[j]) begin
          ram[b_addr][(j*8)+:8] <= b_data_in[(j*8)+:8];
        end
      end
      b_data_out <= ram[b_addr];
    end
  end

endmodule // pl_pcie_nvme_queue_tdp_ram
