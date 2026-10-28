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

/**
 * Simulation model of the Xilinx Floating-Point Operator v7.1 (floating_point_v7_1_19) for Verilator.
 *
 * The RTL of the IP is encrypted; xsim loads it from its precompiled library. Verilator cannot, so
 * sim/vl/build.sh passes this folder with -y and Verilator takes this file when the module is missing.
 *
 * Covered: the configuration that Vitis HLS generates for single-precision add, subtract, multiply
 * and divide. Non-blocking AXI-Stream (C_THROTTLE_SCHEME 3: tready always high, result valid after
 * C_LATENCY cycles), aclken, aresetn. Rounding is round to nearest even and denormals are flushed to
 * zero, as in the core. Any other configuration stops the simulation at time 0 with $fatal.
 */

`timescale 1ns/1ps

module floating_point_v7_1_19 #(
    parameter C_XDEVICEFAMILY = "virtexuplusHBM",
    parameter C_PART = "",
    parameter integer C_HAS_ADD = 0,
    parameter integer C_HAS_SUBTRACT = 0,
    parameter integer C_HAS_MULTIPLY = 0,
    parameter integer C_HAS_DIVIDE = 0,
    parameter integer C_HAS_SQRT = 0,
    parameter integer C_HAS_COMPARE = 0,
    parameter integer C_HAS_FIX_TO_FLT = 0,
    parameter integer C_HAS_FLT_TO_FIX = 0,
    parameter integer C_HAS_FLT_TO_FLT = 0,
    parameter integer C_HAS_RECIP = 0,
    parameter integer C_HAS_RECIP_SQRT = 0,
    parameter integer C_HAS_ABSOLUTE = 0,
    parameter integer C_HAS_LOGARITHM = 0,
    parameter integer C_HAS_EXPONENTIAL = 0,
    parameter integer C_HAS_FMA = 0,
    parameter integer C_HAS_FMS = 0,
    parameter integer C_HAS_UNFUSED_MULTIPLY_ADD = 0,
    parameter integer C_HAS_UNFUSED_MULTIPLY_SUB = 0,
    parameter integer C_HAS_UNFUSED_MULTIPLY_ACCUMULATOR_A = 0,
    parameter integer C_HAS_UNFUSED_MULTIPLY_ACCUMULATOR_S = 0,
    parameter integer C_HAS_ACCUMULATOR_A = 0,
    parameter integer C_HAS_ACCUMULATOR_S = 0,
    parameter integer C_HAS_ACCUMULATOR_PRIMITIVE_A = 0,
    parameter integer C_HAS_ACCUMULATOR_PRIMITIVE_S = 0,
    parameter integer C_A_WIDTH = 32,
    parameter integer C_A_FRACTION_WIDTH = 24,
    parameter integer C_B_WIDTH = 32,
    parameter integer C_B_FRACTION_WIDTH = 24,
    parameter integer C_C_WIDTH = 32,
    parameter integer C_C_FRACTION_WIDTH = 24,
    parameter integer C_RESULT_WIDTH = 32,
    parameter integer C_RESULT_FRACTION_WIDTH = 24,
    parameter integer C_COMPARE_OPERATION = 8,
    parameter integer C_LATENCY = 0,
    parameter integer C_OPTIMIZATION = 1,
    parameter integer C_MULT_USAGE = 2,
    parameter integer C_BRAM_USAGE = 0,
    parameter integer C_RATE = 1,
    parameter integer C_ACCUM_INPUT_MSB = 32,
    parameter integer C_ACCUM_MSB = 32,
    parameter integer C_ACCUM_LSB = -31,
    parameter integer C_HAS_UNDERFLOW = 0,
    parameter integer C_HAS_OVERFLOW = 0,
    parameter integer C_HAS_INVALID_OP = 0,
    parameter integer C_HAS_DIVIDE_BY_ZERO = 0,
    parameter integer C_HAS_ACCUM_OVERFLOW = 0,
    parameter integer C_HAS_ACCUM_INPUT_OVERFLOW = 0,
    parameter integer C_HAS_ACLKEN = 0,
    parameter integer C_HAS_ARESETN = 0,
    parameter integer C_THROTTLE_SCHEME = 3,
    parameter integer C_HAS_A_TUSER = 0,
    parameter integer C_HAS_A_TLAST = 0,
    parameter integer C_HAS_B = 1,
    parameter integer C_HAS_B_TUSER = 0,
    parameter integer C_HAS_B_TLAST = 0,
    parameter integer C_HAS_C = 0,
    parameter integer C_HAS_C_TUSER = 0,
    parameter integer C_HAS_C_TLAST = 0,
    parameter integer C_HAS_OPERATION = 0,
    parameter integer C_HAS_OPERATION_TUSER = 0,
    parameter integer C_HAS_OPERATION_TLAST = 0,
    parameter integer C_HAS_RESULT_TUSER = 0,
    parameter integer C_HAS_RESULT_TLAST = 0,
    parameter integer C_TLAST_RESOLUTION = 0,
    parameter integer C_A_TDATA_WIDTH = 32,
    parameter integer C_A_TUSER_WIDTH = 1,
    parameter integer C_B_TDATA_WIDTH = 32,
    parameter integer C_B_TUSER_WIDTH = 1,
    parameter integer C_C_TDATA_WIDTH = 32,
    parameter integer C_C_TUSER_WIDTH = 1,
    parameter integer C_OPERATION_TDATA_WIDTH = 8,
    parameter integer C_OPERATION_TUSER_WIDTH = 1,
    parameter integer C_RESULT_TDATA_WIDTH = 32,
    parameter integer C_RESULT_TUSER_WIDTH = 1,
    parameter integer C_FIXED_DATA_UNSIGNED = 0
) (
    input  wire                                 aclk,
    input  wire                                 aclken,
    input  wire                                 aresetn,
    input  wire                                 s_axis_a_tvalid,
    output wire                                 s_axis_a_tready,
    input  wire [C_A_TDATA_WIDTH-1:0]           s_axis_a_tdata,
    input  wire [C_A_TUSER_WIDTH-1:0]           s_axis_a_tuser,
    input  wire                                 s_axis_a_tlast,
    input  wire                                 s_axis_b_tvalid,
    output wire                                 s_axis_b_tready,
    input  wire [C_B_TDATA_WIDTH-1:0]           s_axis_b_tdata,
    input  wire [C_B_TUSER_WIDTH-1:0]           s_axis_b_tuser,
    input  wire                                 s_axis_b_tlast,
    input  wire                                 s_axis_c_tvalid,
    output wire                                 s_axis_c_tready,
    input  wire [C_C_TDATA_WIDTH-1:0]           s_axis_c_tdata,
    input  wire [C_C_TUSER_WIDTH-1:0]           s_axis_c_tuser,
    input  wire                                 s_axis_c_tlast,
    input  wire                                 s_axis_operation_tvalid,
    output wire                                 s_axis_operation_tready,
    input  wire [C_OPERATION_TDATA_WIDTH-1:0]   s_axis_operation_tdata,
    input  wire [C_OPERATION_TUSER_WIDTH-1:0]   s_axis_operation_tuser,
    input  wire                                 s_axis_operation_tlast,
    output wire                                 m_axis_result_tvalid,
    input  wire                                 m_axis_result_tready,
    output wire [C_RESULT_TDATA_WIDTH-1:0]      m_axis_result_tdata,
    output wire [C_RESULT_TUSER_WIDTH-1:0]      m_axis_result_tuser,
    output wire                                 m_axis_result_tlast
);

    localparam integer N_OPS = C_HAS_ADD + C_HAS_SUBTRACT + C_HAS_MULTIPLY + C_HAS_DIVIDE;

    initial begin
        if (N_OPS != 1 || C_A_WIDTH != 32 || C_B_WIDTH != 32 || C_RESULT_WIDTH != 32 ||
            C_A_TDATA_WIDTH != 32 || C_B_TDATA_WIDTH != 32 || C_RESULT_TDATA_WIDTH != 32 ||
            C_HAS_B != 1 || C_HAS_OPERATION != 0 || C_RATE != 1 || C_THROTTLE_SCHEME != 3)
            $fatal(1, "floating_point_v7_1_19 model: only one of add, subtract, multiply, divide on two single-precision operands, non-blocking, is supported");
    end

    // float32 to double, exact. Denormals are read as zero, as in the core.
    function automatic real fp32_to_real(input [31:0] x);
        logic [63:0] d;
        if (x[30:23] == 8'd0)
            d = {x[31], 63'd0};
        else if (x[30:23] == 8'hff)
            d = {x[31], 11'h7ff, x[22:0], 29'd0};
        else
            d = {x[31], 11'd896 + {3'd0, x[30:23]}, x[22:0], 29'd0}; // bias 1023 - 127 = 896
        return $bitstoreal(d);
    endfunction

    // double to float32, round to nearest even. Overflow gives infinity, denormal results give zero.
    // NaN gives the quiet NaN of the core.
    function automatic [31:0] real_to_fp32(input real r);
        logic [63:0] d;
        logic [24:0] m;  // carry, hidden one, 23 fraction bits
        integer e;
        d = $realtobits(r);
        if (d[62:52] == 11'h7ff)
            return d[51:0] != 52'd0 ? 32'h7fc00000 : {d[63], 8'hff, 23'd0};
        if (d[62:52] == 11'd0)
            return {d[63], 31'd0};
        e = int'(d[62:52]) - 1023;
        m = {2'b01, d[51:29]};
        if (d[28] && (d[29] || d[27:0] != 28'd0))  // guard set and (odd or sticky): round up
            m = m + 25'd1;
        if (m[24]) begin
            m = m >> 1;
            e = e + 1;
        end
        if (e > 127)
            return {d[63], 8'hff, 23'd0};
        if (e < -126)
            return {d[63], 31'd0};
        return {d[63], 8'(e + 127), m[22:0]};
    endfunction

    function automatic [31:0] compute(input [31:0] a, input [31:0] b);
        real ra, rb, rr;
        ra = fp32_to_real(a);
        rb = fp32_to_real(b);
        if (C_HAS_ADD)           rr = ra + rb;
        else if (C_HAS_SUBTRACT) rr = ra - rb;
        else if (C_HAS_MULTIPLY) rr = ra * rb;
        else                     rr = ra / rb;
        return real_to_fp32(rr);
    endfunction

    wire        ce       = C_HAS_ACLKEN ? aclken : 1'b1;
    wire        rst      = C_HAS_ARESETN ? ~aresetn : 1'b0;
    wire        in_valid = s_axis_a_tvalid & s_axis_b_tvalid;
    wire [31:0] result   = compute(s_axis_a_tdata, s_axis_b_tdata);

    generate
        if (C_LATENCY == 0) begin : g_comb
            assign m_axis_result_tvalid = in_valid;
            assign m_axis_result_tdata  = result;
        end else begin : g_pipe
            reg [C_LATENCY-1:0] valid_q;
            reg [31:0]          data_q [C_LATENCY];

            always @(posedge aclk) begin
                if (rst) begin
                    valid_q <= '0;
                end else if (ce) begin
                    valid_q   <= {valid_q, in_valid};
                    data_q[0] <= result;
                    for (int i = 1; i < C_LATENCY; i++)
                        data_q[i] <= data_q[i-1];
                end
            end

            assign m_axis_result_tvalid = valid_q[C_LATENCY-1];
            assign m_axis_result_tdata  = data_q[C_LATENCY-1];
        end
    endgenerate

    assign s_axis_a_tready         = 1'b1;
    assign s_axis_b_tready         = 1'b1;
    assign s_axis_c_tready         = 1'b1;
    assign s_axis_operation_tready = 1'b1;
    assign m_axis_result_tuser     = '0;
    assign m_axis_result_tlast     = 1'b0;

endmodule
