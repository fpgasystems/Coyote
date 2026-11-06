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


`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   NVMe doorbell DMA arbiter
 *
 * Merges the SQ and CQ doorbell DMA streams onto a single DMA write channel.
 */
module nvme_doorbell_arb (
    input  logic        aclk,
    input  logic        aresetn,
    
    // Port 0: Host DMA (higher priority in tie)
    dmaIntf.s           s_dma_req_0,
    AXI4S.s             s_axis_0,
    
    // Port 1: NVMe Doorbell DMA
    dmaIntf.s           s_dma_req_1,
    AXI4S.s             s_axis_1,
    
    // Output: Merged
    dmaIntf.m           m_dma_req,
    AXI4S.m             m_axis
);

    // State machine
    
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_GRANT_0_REQ,
        ST_GRANT_0_DATA,
        ST_GRANT_1_REQ,
        ST_GRANT_1_DATA
    } state_t;
    
    state_t state_C, state_N;
    
    // Last grant for round-robin (0 = port 0 was last, 1 = port 1 was last)
    logic last_grant_C, last_grant_N;

    // State machine transitions
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C <= ST_IDLE;
            last_grant_C <= 1'b0;
        end else begin
            state_C <= state_N;
            last_grant_C <= last_grant_N;
        end
    end
    
    // Next state logic
    
    always_comb begin
        state_N = state_C;
        last_grant_N = last_grant_C;
        
        case (state_C)
            ST_IDLE: begin
                // Round-robin arbitration
                if (last_grant_C == 1'b1) begin
                    // Last was port 1, check port 0 first
                    if (s_dma_req_0.valid) begin
                        state_N = ST_GRANT_0_REQ;
                    end else if (s_dma_req_1.valid) begin
                        state_N = ST_GRANT_1_REQ;
                    end
                end else begin
                    // Last was port 0, check port 1 first
                    if (s_dma_req_1.valid) begin
                        state_N = ST_GRANT_1_REQ;
                    end else if (s_dma_req_0.valid) begin
                        state_N = ST_GRANT_0_REQ;
                    end
                end
            end
            
            ST_GRANT_0_REQ: begin
                if (m_dma_req.valid && m_dma_req.ready) begin
                    state_N = ST_GRANT_0_DATA;
                end
            end
            
            ST_GRANT_1_REQ: begin
                if (m_dma_req.valid && m_dma_req.ready) begin
                    state_N = ST_GRANT_1_DATA;
                end
            end
            
            ST_GRANT_0_DATA: begin
                if (m_axis.tvalid && m_axis.tready && m_axis.tlast) begin
                    last_grant_N = 1'b0;
                    state_N = ST_IDLE;
                end
            end
            
            ST_GRANT_1_DATA: begin
                if (m_axis.tvalid && m_axis.tready && m_axis.tlast) begin
                    last_grant_N = 1'b1;
                    state_N = ST_IDLE;
                end
            end
            
            default: begin
                state_N = ST_IDLE;
            end
        endcase
    end
    
    // Output muxing - DMA Request
    
    always_comb begin
        // Default: tie-off
        m_dma_req.valid = 1'b0;
        m_dma_req.req = '0;
        s_dma_req_0.ready = 1'b0;
        s_dma_req_1.ready = 1'b0;
        
        case (state_C)
            ST_GRANT_0_REQ: begin
                m_dma_req.valid = s_dma_req_0.valid;
                m_dma_req.req = s_dma_req_0.req;
                s_dma_req_0.ready = m_dma_req.ready;
            end
            
            ST_GRANT_1_REQ: begin
                m_dma_req.valid = s_dma_req_1.valid;
                m_dma_req.req = s_dma_req_1.req;
                s_dma_req_1.ready = m_dma_req.ready;
            end
            
            default: begin
                // Keep defaults
            end
        endcase
    end
    
    // DMA response routing
    always_comb begin
        s_dma_req_0.rsp = '0;
        s_dma_req_1.rsp = '0;
        
        case (state_C)
            ST_GRANT_0_REQ, ST_GRANT_0_DATA: begin
                s_dma_req_0.rsp = m_dma_req.rsp;
            end
            
            ST_GRANT_1_REQ, ST_GRANT_1_DATA: begin
                s_dma_req_1.rsp = m_dma_req.rsp;
            end
            
            default: begin
                // Keep defaults
            end
        endcase
    end
    
    // Output muxing - AXI4S Data
    
    always_comb begin
        // Default: tie-off
        m_axis.tvalid = 1'b0;
        m_axis.tdata = '0;
        m_axis.tkeep = '0;
        m_axis.tlast = 1'b0;
        s_axis_0.tready = 1'b0;
        s_axis_1.tready = 1'b0;
        
        case (state_C)
            ST_GRANT_0_DATA: begin
                m_axis.tvalid = s_axis_0.tvalid;
                m_axis.tdata = s_axis_0.tdata;
                m_axis.tkeep = s_axis_0.tkeep;
                m_axis.tlast = s_axis_0.tlast;
                s_axis_0.tready = m_axis.tready;
            end
            
            ST_GRANT_1_DATA: begin
                m_axis.tvalid = s_axis_1.tvalid;
                m_axis.tdata = s_axis_1.tdata;
                m_axis.tkeep = s_axis_1.tkeep;
                m_axis.tlast = s_axis_1.tlast;
                s_axis_1.tready = m_axis.tready;
            end
            
            default: begin
                // Keep defaults
            end
        endcase
    end

`ifdef EN_ILA_DMA_ARBITER_2TO1

    // Grant Counters
    logic [31:0] port0_grant_count;     // SQ doorbell grants
    logic [31:0] port1_grant_count;     // CQ doorbell grants
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            port0_grant_count <= '0;
            port1_grant_count <= '0;
        end else begin
            // Port 0 grant complete
            if (state_C == ST_GRANT_0_DATA && m_axis.tvalid && m_axis.tready && m_axis.tlast)
                port0_grant_count <= port0_grant_count + 1;
            
            // Port 1 grant complete
            if (state_C == ST_GRANT_1_DATA && m_axis.tvalid && m_axis.tready && m_axis.tlast)
                port1_grant_count <= port1_grant_count + 1;
        end
    end

    // Wait Cycle Counters
    logic [31:0] port0_wait_cycles;     // Port 0 waiting for grant
    logic [31:0] port1_wait_cycles;     // Port 1 waiting for grant
    logic [15:0] port0_current_wait;    // Current wait duration
    logic [15:0] port1_current_wait;
    logic [15:0] port0_max_wait;        // Max wait ever seen
    logic [15:0] port1_max_wait;
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            port0_wait_cycles <= '0;
            port1_wait_cycles <= '0;
            port0_current_wait <= '0;
            port1_current_wait <= '0;
            port0_max_wait <= '0;
            port1_max_wait <= '0;
        end else begin
            // Port 0 waiting (valid but not being served)
            if (s_dma_req_0.valid && state_C != ST_GRANT_0_REQ && state_C != ST_GRANT_0_DATA) begin
                port0_wait_cycles <= port0_wait_cycles + 1;
                port0_current_wait <= port0_current_wait + 1;
                if (port0_current_wait > port0_max_wait)
                    port0_max_wait <= port0_current_wait;
            end else begin
                port0_current_wait <= '0;
            end
            
            // Port 1 waiting (valid but not being served)
            if (s_dma_req_1.valid && state_C != ST_GRANT_1_REQ && state_C != ST_GRANT_1_DATA) begin
                port1_wait_cycles <= port1_wait_cycles + 1;
                port1_current_wait <= port1_current_wait + 1;
                if (port1_current_wait > port1_max_wait)
                    port1_max_wait <= port1_current_wait;
            end else begin
                port1_current_wait <= '0;
            end
        end
    end

    // Contention Detection
    logic both_requesting;
    logic [31:0] contention_count;
    logic [31:0] port0_won_contention;
    logic [31:0] port1_won_contention;
    
    assign both_requesting = s_dma_req_0.valid && s_dma_req_1.valid;
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            contention_count <= '0;
            port0_won_contention <= '0;
            port1_won_contention <= '0;
        end else begin
            // Both requesting at IDLE
            if (both_requesting && state_C == ST_IDLE) begin
                contention_count <= contention_count + 1;
                // Who won?
                if (state_N == ST_GRANT_0_REQ)
                    port0_won_contention <= port0_won_contention + 1;
                else if (state_N == ST_GRANT_1_REQ)
                    port1_won_contention <= port1_won_contention + 1;
            end
        end
    end

    // Output Blocked Detection
    logic output_req_blocked;
    logic output_data_blocked;
    logic [15:0] output_block_counter;
    logic [15:0] max_output_block;
    
    assign output_req_blocked = (state_C == ST_GRANT_0_REQ || state_C == ST_GRANT_1_REQ) && 
                                 m_dma_req.valid && !m_dma_req.ready;
    assign output_data_blocked = (state_C == ST_GRANT_0_DATA || state_C == ST_GRANT_1_DATA) && 
                                  m_axis.tvalid && !m_axis.tready;
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            output_block_counter <= '0;
            max_output_block <= '0;
        end else begin
            if (output_req_blocked || output_data_blocked) begin
                output_block_counter <= output_block_counter + 1;
                if (output_block_counter > max_output_block)
                    max_output_block <= output_block_counter;
            end else if (state_C == ST_IDLE)
                output_block_counter <= '0;
        end
    end

    // Transaction Duration
    logic [15:0] transaction_duration;
    logic [15:0] max_transaction_duration;
    
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            transaction_duration <= '0;
            max_transaction_duration <= '0;
        end else begin
            if (state_C != ST_IDLE) begin
                transaction_duration <= transaction_duration + 1;
                if (transaction_duration > max_transaction_duration)
                    max_transaction_duration <= transaction_duration;
            end else begin
                transaction_duration <= '0;
            end
        end
    end

    // ILA Instance
    ila_dma_arbiter inst_ila_dma_arbiter (
        .clk     (aclk),
        
        // GRANT STATISTICS (probe 0-5)
        .probe0  (port0_grant_count[15:0]),     // 16-bit - SQ doorbell grants
        .probe1  (port1_grant_count[15:0]),     // 16-bit - CQ doorbell grants
        .probe2  (contention_count[15:0]),      // 16-bit - both requested simultaneously
        .probe3  (port0_won_contention[15:0]),  // 16-bit - port0 won when both valid
        .probe4  (port1_won_contention[15:0]),  // 16-bit - port1 won when both valid
        .probe5  (both_requesting),             // 1-bit
        
        // WAIT STATISTICS (probe 6-13)
        .probe6  (port0_wait_cycles[15:0]),     // 16-bit - total port0 wait
        .probe7  (port1_wait_cycles[15:0]),     // 16-bit - total port1 wait
        .probe8  (port0_current_wait),          // 16-bit - current port0 wait
        .probe9  (port1_current_wait),          // 16-bit - current port1 wait
        .probe10 (port0_max_wait),              // 16-bit - worst port0 wait
        .probe11 (port1_max_wait),              // 16-bit - worst port1 wait
        
        // OUTPUT BLOCKED (probe 12-15)
        .probe12 (output_req_blocked),          // 1-bit
        .probe13 (output_data_blocked),         // 1-bit
        .probe14 (output_block_counter),        // 16-bit
        .probe15 (max_output_block),            // 16-bit
        
        // FSM STATE (probe 16-19)
        .probe16 (state_C),                     // 3-bit
        .probe17 (state_N),                     // 3-bit
        .probe18 (last_grant_C),                // 1-bit (0=port0, 1=port1)
        .probe19 (transaction_duration),        // 16-bit
        
        // PORT 0 - SQ DOORBELL (probe 20-27)
        .probe20 (s_dma_req_0.valid),           // 1-bit
        .probe21 (s_dma_req_0.ready),           // 1-bit
        .probe22 (s_dma_req_0.req.paddr),       // PADDR_BITS (44-bit)
        .probe23 (s_dma_req_0.req.len),         // LEN_BITS (28-bit)
        .probe24 (s_axis_0.tvalid),             // 1-bit
        .probe25 (s_axis_0.tready),             // 1-bit
        .probe26 (s_axis_0.tdata[31:0]),        // 32-bit - SQ tail value
        .probe27 (s_axis_0.tlast),              // 1-bit
        
        // PORT 1 - CQ DOORBELL (probe 28-35)
        .probe28 (s_dma_req_1.valid),           // 1-bit
        .probe29 (s_dma_req_1.ready),           // 1-bit
        .probe30 (s_dma_req_1.req.paddr),       // PADDR_BITS (44-bit)
        .probe31 (s_dma_req_1.req.len),         // LEN_BITS (28-bit)
        .probe32 (s_axis_1.tvalid),             // 1-bit
        .probe33 (s_axis_1.tready),             // 1-bit
        .probe34 (s_axis_1.tdata[31:0]),        // 32-bit - CQ head value
        .probe35 (s_axis_1.tlast),              // 1-bit
        
        // OUTPUT (probe 36-43)
        .probe36 (m_dma_req.valid),             // 1-bit
        .probe37 (m_dma_req.ready),             // 1-bit - XDMA ready
        .probe38 (m_dma_req.req.paddr),         // PADDR_BITS (44-bit)
        .probe39 (m_dma_req.req.len),           // LEN_BITS (28-bit)
        .probe40 (m_axis.tvalid),               // 1-bit
        .probe41 (m_axis.tready),               // 1-bit
        .probe42 (m_axis.tdata[31:0]),          // 32-bit
        .probe43 (m_axis.tlast),                // 1-bit
        
        // TIMING (probe 44-45)
        .probe44 (max_transaction_duration),    // 16-bit
        .probe45 (max_output_block)             // 16-bit (duplicate for easy trigger)
    );

`endif // EN_ILA_DMA_ARBITER_2TO1

endmodule
