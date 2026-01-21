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

/**
 * @brief QDMA interrupt wrapper
 *
 * Maps the one-hot encoded interrupt signal from the shell to the correct format for the QDMA interrupt interface.
 * Each bit corresponds to the region (vFPGA) issuing the interrupt and is simply converted to a decimal number
 *
 * Additionally, this module ensures that only one interrupt is sent to the QDMA at a time, waiting for the driver to acknowledge
 * the interrupt and clear the corresponding bit before sending the next one. Other DMA engines (e.g., XDMA) could support
 * multiple interrupts being sent at the same time, but QDMA only supports one at a time.
 */
module qdma_interrupt_wrapper #(
    parameter integer N_IRQ = 16 
) (
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [N_IRQ-1:0]    usr_irq, 
    
    input  logic                usr_irq_ack,
    input  logic                usr_irq_fail,
    output logic                usr_irq_valid,
    output logic [4:0]          usr_irq_vec, 
    output logic [12:0]         usr_irq_fnc    
);

    // FSM:
    // 1. IDLE: Wait for next interrupt
    // 2. SEND: Interrupt sent to the QDMA, valid bit must remain high until ack is received
    // 3. WAIT: Interrupt acked by QDMA, wait for driver to process and clear the corresponding bit
    // 4. DONE: Driver cleared the interrupt bit, go back to IDLE
    typedef enum logic[1:0]  {ST_IDLE, ST_SEND, ST_WAIT, ST_DONE} state_t;
    logic [1:0] state_C, state_N;

    logic [4:0] idx_C, idx_N;

    // REG
    always_ff @(posedge aclk) begin
        if (aresetn == 1'b0) begin
            state_C <= ST_IDLE;
            idx_C <= 0;
        end else begin
            state_C <= state_N;
            idx_C <= idx_N;
        end
    end

    // NSL
    always_comb begin
        state_N = state_C;
        idx_N = idx_C;
        
        unique case(state_C)
            ST_IDLE: begin
                for (int i = 0; i < N_IRQ; i++) begin
                    // Found next interrupt -> send to QDMA
                    if (usr_irq[i]) begin
                        idx_N = i;
                        state_N = ST_SEND;
                        break;
                    end
                end
            end

            ST_SEND: begin
                // Interrupt acked by QDMA -> wait for driver to process 
                if (usr_irq_ack) begin
                    state_N = ST_WAIT;
                end

                // QDMA failed to accept interrupt -> go back to IDLE and (eventually) try again (driver can't clear bit if IRQ was never received)
                if (usr_irq_fail) begin
                    state_N = ST_IDLE;
                end
            end

            ST_WAIT: begin
                // Driver processed interrupt & cleared the active bit for the current vFPGA
                // The bit is cleared by writing to a memory-mapped register in cnfg_slave_avx
                if (usr_irq[idx_C] == 1'b0) begin
                    state_N = ST_DONE;
                end
            end

            ST_DONE: begin
                // Extra timing state, nothing special; could be removed
                state_N = ST_IDLE;
            end
        endcase
    end

    // DP
    assign usr_irq_valid = (state_C == ST_SEND);
    assign usr_irq_fnc = 0;
    assign usr_irq_vec = idx_C;

endmodule
