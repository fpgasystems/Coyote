#ifndef ZERO_IN_COYOTE_ACCEL_H_
#define ZERO_IN_COYOTE_ACCEL_H_

#include "ap_fixed.h"
#include "ap_int.h"
#include "hls_stream.h"

#include "defines.h"


// Prototype of top level function for C-synthesis
void zero_in_coyote_accel(
    hls::stream<input_t> &bitstream_input,
    hls::stream<result_t> &layer29_out
);

// hls-fpga-machine-learning insert emulator-defines


#endif
