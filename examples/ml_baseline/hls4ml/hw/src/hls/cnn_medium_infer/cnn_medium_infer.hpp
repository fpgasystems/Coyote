/**
 * Placeholder Coyote HLS wrapper for the eventual hls4ml-generated cnn_medium core.
 *
 * The wrapper currently drains one fixed-size sample blob and emits one result
 * word. Once the external hls4ml toolchain is available, the generated network
 * sources should be dropped into this directory and called from
 * cnn_medium_infer.cpp.
 */

#pragma once

#include "ap_axi_sdata.h"
#include "ap_int.h"
#include "hls_stream.h"

constexpr int AXI_DATA_BITS = 512;
constexpr int INPUT_BYTES = 1024 * 1024;
constexpr int AXI_BYTES = AXI_DATA_BITS / 8;
constexpr int INPUT_BEATS = INPUT_BYTES / AXI_BYTES;

typedef ap_axiu<AXI_DATA_BITS, 0, 0, 0> axi_s;

void cnn_medium_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out);
