#include "hls_vadd.hpp"

void hls_vadd (
    hls::stream<axi_s> &axi_in1,
    hls::stream<axi_s> &axi_in2,
    hls::stream<axi_s> &axi_out
) {
    // A free-runing kernel; no control interfaces needed to start the operation
    #pragma HLS INTERFACE ap_ctrl_none port=return

    // Specify that the input/output signals are AXI streams (axis)
    #pragma HLS INTERFACE axis register port=axi_in1 name=s_axi_in1
    #pragma HLS INTERFACE axis register port=axi_in2 name=s_axi_in2
    #pragma HLS INTERFACE axis register port=axi_out name=m_axi_out

    // If both inputs are valid, proceed
    if (!axi_in1.empty() && !axi_in2.empty()) {
        axi_s data_out;
        axi_s data_in1 = axi_in1.read();
        axi_s data_in2 = axi_in2.read();

        // Read 16 32-bit floats from the incoming 512-bit streams and add them
        // Performed fully in parallel, due to the pragma
        // TODO: We're doing some weird magic with pointer casting to convert the incoming bits to floats
        // In the future we should us hls::vector<float, 16> and avoid reinterpret_cast
        for (int i = 0; i < NUM_FLOATS; i++) {
            #pragma HLS UNROLL

            // Convert 32-bits to a floating-point value
            ap_uint<FLOAT_BITS> input1_bits = data_in1.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS);
            float a = *reinterpret_cast<float*>(&input1_bits);

            ap_uint<FLOAT_BITS> input2_bits = data_in2.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS);
            float b = *reinterpret_cast<float*>(&input2_bits);

            // Add
            float output = a + b;

            // Convert result and store
            ap_uint<FLOAT_BITS> output_bits = *reinterpret_cast<ap_uint<FLOAT_BITS>*>(&output);
            data_out.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS) = output_bits;
        }

        // tlast is asserted if either of the incoming signals is marked as last
        // tkeep is set to true if both incoming signals are marked as tkeep for a specifc byte
        data_out.last = data_in1.last | data_in2.last;
        data_out.keep = data_in1.keep & data_in2.keep;
        axi_out.write(data_out);
    }
}
