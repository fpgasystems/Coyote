/**
 * This file intentionally provides a compileable placeholder top function.
 *
 * TODO:
 * - vendor the generated hls4ml cnn_medium source into this directory
 * - replace the placeholder drain loop with preprocessing + hls4ml invocation
 * - pack the resulting logit/probability into the outgoing AXI word
 */

#include "cnn_medium_infer.hpp"

void cnn_medium_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {
        #pragma HLS PIPELINE II=1
        if (!s_axi_in.empty()) {
            (void) s_axi_in.read();
        }
    }

    axi_s result_word;
    result_word.data = 0;
    result_word.keep = -1;
    result_word.last = 1;
    m_axi_out.write(result_word);
}
