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

#include "cosine_similarity.hpp"

void cosine_similarity(
    hls::stream<axi_s> &axi_in1,
    hls::stream<axi_s> &axi_in2,
    hls::stream<axi_s> &axi_out
) {
    // Define inputs/outputs as AXI streams
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=axi_in1 name=s_axi_in1
    #pragma HLS INTERFACE axis register port=axi_in2 name=s_axi_in2
    #pragma HLS INTERFACE axis register port=axi_out name=m_axi_out

    // Accumulator for the sum of squared differences
    static float norm_a = 0;
    static float norm_b = 0;
    static float dot_product = 0;

    // Read vectors, calculate difference
    if (!axi_in1.empty() && !axi_in2.empty()) {

        axi_s data_in1 = axi_in1.read();
        axi_s data_in2 = axi_in2.read();

        for (int i = 0; i < NUM_FLOATS; i++) {
            #pragma HLS UNROLL

            // Only calculate if both floats are valid (TKEEP is high)
            bool keep_valid = data_in1.keep[i * FLOAT_BYTES] && data_in1.keep[i * FLOAT_BYTES + 1] && 
                              data_in1.keep[i * FLOAT_BYTES + 2] && data_in1.keep[i * FLOAT_BYTES + 3] &&
                              data_in2.keep[i * FLOAT_BYTES] && data_in2.keep[i * FLOAT_BYTES + 1] &&
                              data_in2.keep[i * FLOAT_BYTES + 2] && data_in2.keep[i * FLOAT_BYTES + 3];
            if (keep_valid) {
                ap_uint<FLOAT_BITS> input1_bits = data_in1.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS);
                float a = *reinterpret_cast<float*>(&input1_bits);

                ap_uint<FLOAT_BITS> input2_bits = data_in2.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS);
                float b = *reinterpret_cast<float*>(&input2_bits);

                dot_product += a * b;
                norm_a += a * a;
                norm_b += b * b;
            }
        }

        // If last, write result and reset variables    
        if (data_in1.last || data_in2.last) {

            float similarity =  dot_product / (hls::sqrt(norm_a) * hls::sqrt(norm_b));
            ap_uint<FLOAT_BITS> output_bits = *reinterpret_cast<ap_uint<FLOAT_BITS>*>(&similarity);

            axi_s data_out;
            data_out.last = 1;
            data_out.keep = 0xF;
            data_out.data.range(FLOAT_BITS - 1, 0) = output_bits;
            axi_out.write(data_out);

            norm_a = 0;
            norm_b = 0;
            dot_product = 0; 
        }
    }
}
