/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`ifndef VC_ECI_PACKETIZER_C_SV
`define VC_ECI_PACKETIZER_C_SV

import eci_cmd_defs::*;

module vc_eci_packetizer_c #(
   parameter VC_MAX_SIZE = 7,
   parameter VC_MAX_SIZE_BITS = 3,
   parameter WORD_WIDTH = ECI_WORD_WIDTH,
   
   // Maximum number of words in output packet 
   // Header + Payload = 17
   
   parameter MAX_PACKET_SIZE = ECI_PACKET_SIZE,
   parameter MAX_PACKET_SIZE_WIDTH = ECI_PACKET_SIZE_WIDTH
) (
    input  logic 						                            clk,
    input  logic 						                            reset,

    // Input data stream from VC
    input  logic [VC_MAX_SIZE-1:0][WORD_WIDTH-1:0]      vc_data_i,
    input  logic [VC_MAX_SIZE_BITS-1:0] 			          vc_size_i,
    input  logic 						                            vc_valid_i,
    output logic 						                            vc_ready_o,

    
    // ECI Packet stream output
    output logic [MAX_PACKET_SIZE-1:0][WORD_WIDTH-1:0]  eci_pkt_o,
    output logic [MAX_PACKET_SIZE_WIDTH-1:0] 		        eci_pkt_size_o,
    output logic 						                            eci_pkt_valid_o,
    input  logic 						                            eci_pkt_ready_i
);

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------

localparam integer N_REG_WORDS = 32;
localparam integer N_REG_WORDS_BITS = $clog2(N_REG_WORDS);
localparam integer ECI_LOG_WORD_BITS = $clog2(ECI_WORD_WIDTH);

// -- Regs
logic [VC_MAX_SIZE-1:0][WORD_WIDTH-1:0] vc_data_C, vc_data_N;
logic [VC_MAX_SIZE_BITS-1:0] vc_size_C, vc_size_N;
logic vc_valid_C, vc_valid_N;

logic [N_REG_WORDS-1:0][WORD_WIDTH-1:0] data_C, data_N;
logic [MAX_PACKET_SIZE_WIDTH-1:0] size_C, size_N;
logic [N_REG_WORDS_BITS-1:0] head_C, head_N;
logic [N_REG_WORDS_BITS-1:0] tail_C, tail_N;

logic [MAX_PACKET_SIZE-1:0][WORD_WIDTH-1:0] eci_data_C, eci_data_N;
logic [MAX_PACKET_SIZE_WIDTH-1:0] eci_size_C, eci_size_N;
logic eci_valid_C, eci_valid_N;

// -- Internal
logic [ECI_PACKET_SIZE_WIDTH-1:0] header_size;
logic stall;
logic full;
logic [N_REG_WORDS_BITS-1:0] diff;

/*
ila_packetizer inst_ila_packetizer (
    .clk(clk),
    .probe0(vc_size_C), // 3 
    .probe1(vc_valid_C), 
    .probe2(size_C), // 5
    .probe3(head_C), // 5
    .probe4(tail_C), // 5
    .probe5(diff), // 5
    .probe6(header_size), // 5
    .probe7(stall), 
    .probe8(full),
    .probe9(eci_size_C), // 5
    .probe10(eci_valid_C),
    .probe11(vc_valid_i),
    .probe12(vc_ready_o),
    .probe13(vc_size_i) // 3
);
*/

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------

// -- REG
always_ff @( posedge clk ) begin : REG
  if(reset) begin
    vc_data_C <= 'X;
    vc_size_C <= 'X;
    vc_valid_C <= 1'b0;
    data_C <= 'X;
    size_C <= 0;
    head_C <= 0;
    tail_C <= 0;
    eci_data_C <= 'X;
    eci_size_C <= 'X;
    eci_valid_C <= 1'b0;
  end
  else begin
    vc_data_C <= vc_data_N;
    vc_size_C <= vc_size_N;
    vc_valid_C <= vc_valid_N;
    data_C <= data_N;
    size_C <= size_N;
    head_C <= head_N;
    tail_C <= tail_N;
    eci_data_C <= eci_data_N;
    eci_size_C <= eci_size_N;
    eci_valid_C <= eci_valid_N;
  end
end

// -- DP
always_comb begin : DP
  // Input regs
  vc_data_N = vc_data_C;
  vc_size_N = vc_size_C;
  vc_valid_N = vc_valid_C;
  // Middle regs
  data_N = data_C;
  size_N = size_C;
  head_N = head_C;
  tail_N = tail_C;
  // Output regs
  eci_data_N = eci_data_C;
  eci_size_N = eci_size_C;
  eci_valid_N = eci_valid_C;

  if(~stall) begin
    // No stall

    // Input
    if(~full) begin
      vc_data_N = vc_data_i;
      vc_size_N = vc_size_i;
      vc_valid_N = vc_valid_i;

      if(vc_valid_C) begin
        head_N = head_C + vc_size_C;
        
        for(logic[N_REG_WORDS_BITS-1:0] i = 0; i < VC_MAX_SIZE; i++) begin
          logic [N_REG_WORDS_BITS-1:0] tmp_idx;
          tmp_idx = head_C + i; 
          data_N[tmp_idx] = vc_data_C[i];
        end
      end
    end

    // Middle
    if(size_C == 0 && diff != 0) begin
      if(diff >= header_size) begin
        // The packet is already good to go (small packets, not gonna happen in ECI DMA)
        size_N = 0;
        tail_N = tail_C + header_size;

        eci_size_N = header_size;
        eci_valid_N = 1'b1;
      end 
      else begin
        // Latch the header size and wait for the accumulation of the complete packet
        size_N = header_size;
        eci_valid_N = 1'b0;
      end
    end
    else if(size_C != 0) begin
      if(diff >= size_C) begin
        // The packet is good to go
        size_N = 0;
        tail_N = tail_C + size_C;

        eci_size_N = size_C;
        eci_valid_N = 1'b1;
      end
      else begin
        // Not ready
        eci_valid_N = 1'b0;
      end
    end
    else begin
      // Not ready
      eci_valid_N = 1'b0;
    end

    // Output
    for(int i = 0; i < MAX_PACKET_SIZE; i++) begin
      logic [N_REG_WORDS_BITS-1:0] tmp_idx;
      tmp_idx = tail_C + i;
      eci_data_N[i] = data_C[tmp_idx];
    end

  end
  else begin
    // Not ready
    eci_valid_N = 1'b0;
  end

end

// Stall
assign stall = ~eci_pkt_ready_i;
assign full = diff + VC_MAX_SIZE >= (N_REG_WORDS);

// Diff
assign diff = (head_C >= tail_C) ? (head_C - tail_C) : (N_REG_WORDS - (tail_C - head_C));

// I/O
assign vc_ready_o = ~stall && ~full;

assign eci_pkt_o = eci_data_C;
assign eci_pkt_size_o = eci_size_C;
assign eci_pkt_valid_o = eci_valid_C;

// Calc the size
eci_get_num_words_in_pkt_c inst_get_pkt	(
  .eci_command(data_C[tail_C]),
  .num_words_in_pkt(header_size)
);

endmodule

`endif
