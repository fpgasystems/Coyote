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
 * irq_valid is set to true as long as one of the regions is requesting an interrupt.
 *
 * TODO (Versal): Can the QDMA handle more than 8 interrupts per PF in the QDMA? PR IRQ is 15 in Coyote by default...
 * TODO (Versal): How to handle concurrent interrupts? Would the shell ever encounter such a scenario?
 */
module qdma_interrupt_wrapper (
    input  logic [15:0] usr_irq, 
    output logic        usr_irq_valid,
    output logic [10:0] usr_irq_vec, 
    output logic [12:0] usr_irq_fnc    
);

    assign usr_irq_valid = |usr_irq;
    assign usr_irq_fnc = 0;

    always @(usr_irq)
    case(usr_irq)
        16'b0000000000000001 : usr_irq_vec = {6'b0, 5'd0};
        16'b0000000000000010 : usr_irq_vec = {6'b0, 5'd1};
        16'b0000000000000100 : usr_irq_vec = {6'b0, 5'd2};
        16'b0000000000001000 : usr_irq_vec = {6'b0, 5'd3};
        16'b0000000000010000 : usr_irq_vec = {6'b0, 5'd4};
        16'b0000000000100000 : usr_irq_vec = {6'b0, 5'd5};
        16'b0000000001000000 : usr_irq_vec = {6'b0, 5'd6};
        16'b0000000010000000 : usr_irq_vec = {6'b0, 5'd7};
        16'b0000000100000000 : usr_irq_vec = {6'b0, 5'd8};
        16'b0000001000000000 : usr_irq_vec = {6'b0, 5'd9};
        16'b0000010000000000 : usr_irq_vec = {6'b0, 5'd10};
        16'b0000100000000000 : usr_irq_vec = {6'b0, 5'd11};
        16'b0001000000000000 : usr_irq_vec = {6'b0, 5'd12};
        16'b0010000000000000 : usr_irq_vec = {6'b0, 5'd13};
        16'b0100000000000000 : usr_irq_vec = {6'b0, 5'd14};
        16'b1000000000000000 : usr_irq_vec = {6'b0, 5'd15};
        default              : usr_irq_vec = 11'b0; 
    endcase

endmodule
