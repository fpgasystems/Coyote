#include <iostream>
#include "hls_stream.h"
#include "reduce_ops.h"
#include "ap_axi_sdata.h"

// Sample testbench for reduce_ops
int main() {
    hls::stream<stream_word> in0("in0_stream");
    hls::stream<stream_word> in1("in1_stream");
    hls::stream<stream_word> out("out_stream");

    stream_word val0, val1, result;

    // Single beat, single element int32 addition tests
    val0.data = 50;
    val0.dest = 2; 
    val0.last = 1;
    val0.keep = 0xF;

    val1.data = 25;
    val1.last = 1;
    val0.dest = 2; 
    val1.keep = 0xF;

    in0.write(val0);
    in1.write(val1);

    reduce_ops(in0, in1, out);

    // Run test and check output
    if (!out.empty()) {
        result = out.read();
        std::cout << "SUCCESS: Processed single beat." << std::endl;
        std::cout << "Output Data: " << result.data << " | TLAST: " << (int) result.last << std::endl;
    } else {
        std::cout << "FAILURE: No data produced." << std::endl;
    }

    return 0;
}
