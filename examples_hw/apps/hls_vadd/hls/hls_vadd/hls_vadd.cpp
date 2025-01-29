#include "hls_vadd.hpp"

void hls_vadd (
    hls::stream<axi_s> &axi_in1,
    hls::stream<axi_s> &axi_in2,
    hls::stream<axi_s> &axi_out
) {
    #pragma HLS INTERFACE ap_ctrl_none port=return

    #pragma HLS INTERFACE axis register port=axi_in1 name=s_axi_in1
    #pragma HLS INTERFACE axis register port=axi_in2 name=s_axi_in2
    #pragma HLS INTERFACE axis register port=axi_out name=m_axi_out

    if (!axi_in1.empty() && !axi_in2.empty()) {
        axi_s data_out;
        axi_s data_in1 = axi_in1.read();
        axi_s data_in2 = axi_in2.read();

        for (int i = 0; i < NUM_FLOATS; i++) {
            #pragma HLS UNROLL
            ap_uint<FLOAT_BITS> input1_bits = data_in1.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS);
            float a = *reinterpret_cast<float*>(&input1_bits);

            ap_uint<FLOAT_BITS> input2_bits = data_in2.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS);
            float b = *reinterpret_cast<float*>(&input2_bits);

            float output = a + b;

            ap_uint<FLOAT_BITS> output_bits = *reinterpret_cast<ap_uint<FLOAT_BITS>*>(&output);
            data_out.data.range((i + 1) * FLOAT_BITS - 1, i * FLOAT_BITS) = output_bits;
        }

        data_out.last = data_in1.last | data_in2.last;
        data_out.keep = data_in1.keep & data_in2.keep;
        axi_out.write(data_out);
    }
}
