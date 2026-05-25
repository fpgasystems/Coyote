#ifndef PROD_RES512_MANUALA_COYOTE_ACCEL_H_
#define PROD_RES512_MANUALA_COYOTE_ACCEL_H_

#include "ap_fixed.h"
#include "ap_int.h"
#include "hls_stream.h"

#include "defines.h"


// Prototype of top level function for C-synthesis
void prod_res512_manualA_coyote_accel(
    hls::stream<input_t> &bitstream_input,
    hls::stream<result_t> &layer39_out
);

// hls-fpga-machine-learning insert emulator-defines


#endif
