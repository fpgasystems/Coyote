/*
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

import lynxTypes::*;

module qdma_wr_wrapper #(
    parameter integer N_CHAN = 1,
    parameter integer N_QUEUES_PER_CHAN = 1
) (
    input logic         aclk,
    input logic         aresetn,

    dmaIntf.s           s_dma_wr [N_CHAN],
    qdmaC2HIntf.m       m_qdma_c2h_cmd,
    qdmaC2HSts.s        s_qdma_c2h_sts,

    qdmaC2HS.m          qdma_in,
    AXI4S.s             dyn_in [N_CHAN],

    input logic         pfch_tag_valid,
    input logic [11:0]  pfch_tag_qid,
    input logic [6:0]   pfch_tag
);

// Constants
localparam integer N_CHAN_BITS = clog2s(N_CHAN);

localparam integer TKEEP_WIDTH = AXI_DATA_BITS / 8;
localparam integer AXI_DATA_BYTES = AXI_DATA_BITS / 8;
localparam integer AXI_DATA_BYTES_BITS = clog2s(AXI_DATA_BYTES);

localparam integer QDMA_N_WR_QUEUES = QDMA_N_QUEUES - QDMA_WR_QUEUE_START_IDX;
localparam integer QDMA_N_WR_QUEUES_BITS = clog2s(QDMA_N_WR_QUEUES);

localparam integer N_QUEUES_PER_CHAN_BITS = clog2s(N_QUEUES_PER_CHAN);

// Simple data types, holding values from each of the channels but instead of Verilog arrays uses logic
// Needed to pass synthesis; arrays will throw syntax errors if indexed with non-constant values.
logic [N_CHAN-1:0] s_dma_wr_valids;
logic [N_CHAN-1:0] s_dma_wr_readys;
dma_req_t [N_CHAN-1:0] s_dma_wr_reqs;

logic [N_CHAN-1:0] dyn_in_tvalids;
logic [N_CHAN-1:0] dyn_in_treadys;
logic [N_CHAN-1:0][TKEEP_WIDTH-1:0] dyn_in_tkeeps;
logic [N_CHAN-1:0][AXI_DATA_BITS-1:0] dyn_in_tdatas;

// Current state of the wrapper
// IDLE: Waiting for new descriptor
// WRITING: Accepting data from the shell and sending it to the QDMA
// Additionally it blocks other descriptors from being sent before all the data for this descriptor has been sent
typedef enum logic {ST_IDLE, ST_WRITING} state_t;
logic state_C, state_N;

// To ensure maximum throughput, each of the shell channels can use to multiple QDMA queues
// By definition, in Coyote, each shell channel can have N_OUTSTANDING DMA commands;
// hence, to improve throughput, multiple parallel queues are used
logic [N_CHAN-1:0][N_QUEUES_PER_CHAN_BITS-1:0] chan_qid_C;
logic [N_CHAN-1:0][N_QUEUES_PER_CHAN_BITS-1:0] chan_qid_N;

// The next channel to fire QDMA write command
logic [N_CHAN_BITS-1:0] curr_ch_idx_C, curr_ch_idx_N;

// The length of the DMA request; for some reason, the len is not part of the command stream, but the data stream in QDMA C2H
// This means, that, the field needs to be buffered until the data is available and sent with the data
logic [15:0] curr_dma_wr_len_C, curr_dma_wr_len_N;

// Additionally, keep track of the number of data beats required to write, 
// So that, tlast can be correctly asserted and in_flight_cmd can be de-asserted
logic [10:0] curr_dma_wr_beats_req_C, curr_dma_wr_beats_req_N;

// The number of data beats sent to the QDMA
logic [10:0] curr_dma_beat_cnt;

// The QDMA doesn't use the standard TKEEP signal; intead it uses mty (empty) for the number of empty bytes
logic [5:0] data_mty;

// Each C2H queue needs a prefetch tag, which is obtained from the driver by writting to a QDMA memory mapped register (0x140)
// Once obtained, this value is propagated to Coyote's static layer, through the static_slave module
logic [QDMA_N_WR_QUEUES-1:0][6:0] pfch_tags;

///////////////////////////////////////////
//                I/O                   //
//////////////////////////////////////////

for (genvar i = 0; i < N_CHAN; i++) begin
    // Command
    assign s_dma_wr_valids[i]   = s_dma_wr[i].valid;
    assign s_dma_wr_reqs[i]     = s_dma_wr[i].req;
    assign s_dma_wr[i].ready    = s_dma_wr_readys[i];

    // Data
    assign dyn_in_tvalids[i]    = dyn_in[i].tvalid;
    assign dyn_in_tkeeps[i]     = dyn_in[i].tkeep;
    assign dyn_in_tdatas[i]     = dyn_in[i].tdata;
    assign dyn_in[i].tready     = dyn_in_treadys[i];

    // Completion status
    // Read (C2H) completed, per Table 62 in QDMA specification
    // Don't check against cmp since we set has_cmp to zero in the C2H data stream (no completions issued to software / driver)
    assign s_dma_wr[i].rsp.done = 
        s_qdma_c2h_sts.valid && 
        ((QDMA_WR_QUEUE_START_IDX + (i * N_QUEUES_PER_CHAN)) <= s_qdma_c2h_sts.qid) &&
        ((QDMA_WR_QUEUE_START_IDX + ((i + 1) * N_QUEUES_PER_CHAN)) > s_qdma_c2h_sts.qid) &&              
        !s_qdma_c2h_sts.drop &&                                       
        !s_qdma_c2h_sts.error;                                         
end

///////////////////////////////////////////
//                REG                   //
//////////////////////////////////////////
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        // Command registers
        state_C <= ST_IDLE;
        chan_qid_C <= '0;
        curr_ch_idx_C <= 0;
        curr_dma_wr_len_C <= 'X;
        curr_dma_wr_beats_req_C <= 'X;

        // Data beat counter
        curr_dma_beat_cnt <= 0;

        // Pre-fetch tag
        pfch_tags <= 'X;
    end else begin
        // Command registers
        state_C <= state_N;
        chan_qid_C <= chan_qid_N;
        curr_ch_idx_C <= curr_ch_idx_N;
        curr_dma_wr_len_C <= curr_dma_wr_len_N;
        curr_dma_wr_beats_req_C <= curr_dma_wr_beats_req_N;

        // Data beat counter
        if (qdma_in.tvalid && qdma_in.tready) begin
            if (curr_dma_beat_cnt == (curr_dma_wr_beats_req_N - 1)) begin
                curr_dma_beat_cnt <= 0;
            end else begin
                curr_dma_beat_cnt <= curr_dma_beat_cnt + 1;
            end
        end

        // Pre-fetch tag assignment
        if (pfch_tag_valid) begin
            pfch_tags[pfch_tag_qid[QDMA_N_WR_QUEUES_BITS-1:0]] <= pfch_tag;
        end
    end
end

///////////////////////////////////////////
//                  DP                   //
//////////////////////////////////////////
always_comb begin
    // Default values of state variables
    chan_qid_N = chan_qid_C;
    curr_ch_idx_N = curr_ch_idx_C;
    curr_dma_wr_len_N = curr_dma_wr_len_C;
    curr_dma_wr_beats_req_N = curr_dma_wr_beats_req_C;

    // Always constant
    m_qdma_c2h_cmd.req.func      = 0;    // Coyote only supports one PF (for now...)
    m_qdma_c2h_cmd.req.error     = 0;    // Assume data and command (coming from the shell) are well-formed, so no error
    m_qdma_c2h_cmd.req.port_id   = 0;    // port_id offers even finer granularity than qid --- UNUSED
    qdma_in.payload.tcrc         = 0;    // Error checking is disabled, so no CRC is needed
    qdma_in.payload.ecc          = 0;    // Error checking is disabled, so no ECC is needed
    qdma_in.payload.has_cmpt     = 0;    // No completion is sent to the driver/software
    qdma_in.payload.marker       = 0;    // Used for flushing the queues, not needed here
    qdma_in.payload.port_id      = 0;    // port_id offers even finer granularity than qid --- UNUSED
    
    unique case (state_C)
        // If there is no outstanding data, assign next DMA command to the QDMA interface
        ST_IDLE: begin
            // Find the next channel active channel to issue DMA command
            s_dma_wr_readys = 0;
            for (int i = 0; i < N_CHAN; i++) begin
                if (s_dma_wr_valids[i]) begin
                    curr_ch_idx_N = i;
                    break;
                end
            end

            // Address, length 
            m_qdma_c2h_cmd.req.addr         = s_dma_wr_reqs[curr_ch_idx_N].paddr;
            curr_dma_wr_len_N               = s_dma_wr_reqs[curr_ch_idx_N].len;
            curr_dma_wr_beats_req_N         = (s_dma_wr_reqs[curr_ch_idx_N].len + AXI_DATA_BYTES - 1) >> AXI_DATA_BYTES_BITS;

            // Queue, prefetch tag
            m_qdma_c2h_cmd.req.qid          = QDMA_WR_QUEUE_START_IDX + curr_ch_idx_N * N_QUEUES_PER_CHAN + chan_qid_C[curr_ch_idx_N];
            m_qdma_c2h_cmd.req.pfch_tag     = pfch_tags[curr_ch_idx_N * N_QUEUES_PER_CHAN + chan_qid_C[curr_ch_idx_N]];

            // Handshake signals
            m_qdma_c2h_cmd.valid            = s_dma_wr_valids[curr_ch_idx_N];
            s_dma_wr_readys[curr_ch_idx_N]  = m_qdma_c2h_cmd.ready;

            // For easier timing closure, don't send data and command in the same clock cycle
            // Data will always be sent at least one clock cycle after the command
            qdma_in.tvalid                  = 0;
            dyn_in_treadys                  = 0;
    
            // Set the payload to 0, to avoid Vivado inferring a latch in hardware
            data_mty                        = 0;
            qdma_in.tlast                   = 0;
            qdma_in.payload.mty             = 0;
            qdma_in.payload.tdata           = 0;
            qdma_in.payload.len             = 0;
            qdma_in.payload.qid             = 0;

            // If valid, set in_flight_cmd and update queue ID for this channel; otherwise, leave old value 
            if (m_qdma_c2h_cmd.valid && m_qdma_c2h_cmd.ready) begin
                state_N = ST_WRITING;
            end else begin
                state_N = ST_IDLE;
            end
        end

        // If there is no outstanding data, assign next DMA command to the QDMA interface
        ST_WRITING: begin
            // Command and data are not issued in the same clock cycle
            m_qdma_c2h_cmd.valid            = 0;
            s_dma_wr_readys                 = 0;   

            // Set the request contents to 0, to avoid Vivado inferring a latch in hardware
            m_qdma_c2h_cmd.req.addr         = 0;
            m_qdma_c2h_cmd.req.pfch_tag     = 0;
            m_qdma_c2h_cmd.req.qid          = 0;

            // Data
            qdma_in.payload.tdata           = dyn_in_tdatas[curr_ch_idx_C];
            qdma_in.payload.len             = curr_dma_wr_len_C;
            qdma_in.payload.qid             = QDMA_WR_QUEUE_START_IDX + curr_ch_idx_C * N_QUEUES_PER_CHAN + chan_qid_C[curr_ch_idx_C];  

            /*
            * TLAST
            * 
            * IMPORTANT: For QDMA C2H transfers, the tlast must be asserted for every descriptor, on the last data beat
            * If it's not asserted, it can cause data from future transfers to "spill over" to the current transfer
            * (even if the correct amount of data is provided), writing to the current descriptor's address.
            * This was not the case for the XDMA core (the shell only sets tlast on the last data beat of the last descriptor).
            * Additionally, the tlast signal must be set before the tvalid signal; if not, every now and then,
            * the QDMA will drop the packet (length mismatch error), likely indicating some race condition
            */
            qdma_in.tlast                   = dyn_in_tvalids[curr_ch_idx_C] && qdma_in.tready && (curr_dma_beat_cnt == (curr_dma_wr_beats_req_C - 1));

            // Calculate the number of empty bytes from the TKEEP signal
            data_mty = 0;
            for (int i = 0; i < TKEEP_WIDTH; i++) begin
                if (dyn_in_tkeeps[curr_ch_idx_C][i] == 1'b0) begin
                    data_mty++;
                end
            end

            // Empty only needs to be set for the last data beat
            qdma_in.payload.mty             = qdma_in.tlast ? data_mty : 0;

            // Handshake
            qdma_in.tvalid                  = dyn_in_tvalids[curr_ch_idx_C];
            dyn_in_treadys                  = 0;
            dyn_in_treadys[curr_ch_idx_C]   = qdma_in.tready;

            // If data packet is last, reset in_flight_cmd and update the queue ID for the next transfer
            if (qdma_in.tlast) begin
                state_N = ST_IDLE;
        
                if (chan_qid_C[curr_ch_idx_C] == N_QUEUES_PER_CHAN - 1) begin
                    chan_qid_N[curr_ch_idx_C] = 0;
                end else begin
                    chan_qid_N[curr_ch_idx_C]++; 
                end
            end else begin
                state_N = ST_WRITING;
            end                
        end
    endcase
end

endmodule