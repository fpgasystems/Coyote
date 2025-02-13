#include "hls_stream.h"
#include "ap_axi_sdata.h"

// Constants and typedefs
#define AXI_DATA_BITS 512
typedef ap_axiu<AXI_DATA_BITS, 0, 0, 0> axi_s;

#define FLOAT_BITS 32
#define NUM_FLOATS AXI_DATA_BITS / FLOAT_BITS

/**
 * hls_vadd example
 * @brief Reads floats from the two incoming streams and addes them, storing the result to axi_out
 * 
 * @param[in] axi_in1 Incoming AXI stream, corresponding to vector a
 * @param[in] axi_in2 Incoming AXI stream, corresponding to vector b
 * @param[out] axi_out Outgoing AXI stream; resulting vector
 *
 * The inputs/outputs are actually buffered in a hls::stream, which corresponds to a FIFO
 * Each element in the FIFO is a AXI stream with data, valid etc. signals
 */
void hls_vadd (
    hls::stream<axi_s> &axi_in1,
    hls::stream<axi_s> &axi_in2,
    hls::stream<axi_s> &axi_out
);