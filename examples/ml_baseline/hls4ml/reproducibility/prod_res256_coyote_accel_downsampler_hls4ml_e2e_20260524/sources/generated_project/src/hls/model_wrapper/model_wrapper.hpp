#ifndef MODEL_WRAPPER_HPP_
#define MODEL_WRAPPER_HPP_

#include "hls_stream.h"
#include "ap_axi_sdata.h"

#define COYOTE_AXI_STREAM_BITS 512
typedef ap_axiu<COYOTE_AXI_STREAM_BITS, 0, 0, 0> axi_s;

#include "firmware/prod_res256_manualA_coyote_accel.h"
#include "firmware/nnet_utils/nnet_axi_utils.h"
#include "firmware/nnet_utils/nnet_axi_utils_stream.h"
#include "firmware/zero_in_raw_downsample.hpp"

void model_wrapper (
    hls::stream<axi_s> &data_in,
    hls::stream<axi_s> &data_out
);

#endif
