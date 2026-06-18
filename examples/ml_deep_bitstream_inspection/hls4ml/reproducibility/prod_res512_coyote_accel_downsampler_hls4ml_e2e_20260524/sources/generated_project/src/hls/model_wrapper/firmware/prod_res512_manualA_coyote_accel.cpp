#include <iostream>

#include "prod_res512_manualA_coyote_accel.h"
#include "parameters.h"


void prod_res512_manualA_coyote_accel(
    hls::stream<input_t> &bitstream_input,
    hls::stream<result_t> &layer39_out
) {

    // hls-fpga-machine-learning insert IO
    #pragma HLS INLINE OFF
    #pragma HLS DATAFLOW

    // hls-fpga-machine-learning insert load weights
#ifndef __SYNTHESIS__
    static bool loaded_weights = false;
    if (!loaded_weights) {
        nnet::load_weights_from_txt<weight3_t, 200>(w3, "w3.txt");
        nnet::load_weights_from_txt<bias3_t, 8>(b3, "b3.txt");
        nnet::load_weights_from_txt<weight8_t, 1152>(w8, "w8.txt");
        nnet::load_weights_from_txt<bias8_t, 16>(b8, "b8.txt");
        nnet::load_weights_from_txt<weight13_t, 3456>(w13, "w13.txt");
        nnet::load_weights_from_txt<bias13_t, 24>(b13, "b13.txt");
        nnet::load_weights_from_txt<weight18_t, 5184>(w18, "w18.txt");
        nnet::load_weights_from_txt<bias18_t, 24>(b18, "b18.txt");
        nnet::load_weights_from_txt<weight23_t, 6912>(w23, "w23.txt");
        nnet::load_weights_from_txt<bias23_t, 32>(b23, "b23.txt");
        nnet::load_weights_from_txt<weight28_t, 9216>(w28, "w28.txt");
        nnet::load_weights_from_txt<bias28_t, 32>(b28, "b28.txt");
        nnet::load_weights_from_txt<weight33_t, 9216>(w33, "w33.txt");
        nnet::load_weights_from_txt<bias33_t, 32>(b33, "b33.txt");
        nnet::load_weights_from_txt<weight39_t, 32>(w39, "w39.txt");
        nnet::load_weights_from_txt<bias39_t, 1>(b39, "b39.txt");
        loaded_weights = true;    }
#endif
    // ****************************************
    // NETWORK INSTANTIATION
    // ****************************************

    // hls-fpga-machine-learning insert layers

    hls::stream<layer2_t> layer2_out("layer2_out");
    #pragma HLS STREAM variable=layer2_out depth=266256

    hls::stream<conv0_result_t> layer3_out("layer3_out");
    #pragma HLS STREAM variable=layer3_out depth=65536

    hls::stream<layer5_t> layer5_out("layer5_out");
    #pragma HLS STREAM variable=layer5_out depth=65536

    hls::stream<layer6_t> layer6_out("layer6_out");
    #pragma HLS STREAM variable=layer6_out depth=16384

    hls::stream<layer7_t> layer7_out("layer7_out");
    #pragma HLS STREAM variable=layer7_out depth=16900

    hls::stream<conv1_result_t> layer8_out("layer8_out");
    #pragma HLS STREAM variable=layer8_out depth=16384

    hls::stream<layer10_t> layer10_out("layer10_out");
    #pragma HLS STREAM variable=layer10_out depth=16384

    hls::stream<layer11_t> layer11_out("layer11_out");
    #pragma HLS STREAM variable=layer11_out depth=4096

    hls::stream<layer12_t> layer12_out("layer12_out");
    #pragma HLS STREAM variable=layer12_out depth=4356

    hls::stream<conv2_result_t> layer13_out("layer13_out");
    #pragma HLS STREAM variable=layer13_out depth=4096

    hls::stream<layer15_t> layer15_out("layer15_out");
    #pragma HLS STREAM variable=layer15_out depth=4096

    hls::stream<layer16_t> layer16_out("layer16_out");
    #pragma HLS STREAM variable=layer16_out depth=1024

    hls::stream<layer17_t> layer17_out("layer17_out");
    #pragma HLS STREAM variable=layer17_out depth=1156

    hls::stream<conv3_result_t> layer18_out("layer18_out");
    #pragma HLS STREAM variable=layer18_out depth=1024

    hls::stream<layer20_t> layer20_out("layer20_out");
    #pragma HLS STREAM variable=layer20_out depth=1024

    hls::stream<layer21_t> layer21_out("layer21_out");
    #pragma HLS STREAM variable=layer21_out depth=256

    hls::stream<layer22_t> layer22_out("layer22_out");
    #pragma HLS STREAM variable=layer22_out depth=324

    hls::stream<conv4_result_t> layer23_out("layer23_out");
    #pragma HLS STREAM variable=layer23_out depth=256

    hls::stream<layer25_t> layer25_out("layer25_out");
    #pragma HLS STREAM variable=layer25_out depth=256

    hls::stream<layer26_t> layer26_out("layer26_out");
    #pragma HLS STREAM variable=layer26_out depth=64

    hls::stream<layer27_t> layer27_out("layer27_out");
    #pragma HLS STREAM variable=layer27_out depth=100

    hls::stream<conv5_result_t> layer28_out("layer28_out");
    #pragma HLS STREAM variable=layer28_out depth=64

    hls::stream<layer30_t> layer30_out("layer30_out");
    #pragma HLS STREAM variable=layer30_out depth=64

    hls::stream<layer31_t> layer31_out("layer31_out");
    #pragma HLS STREAM variable=layer31_out depth=16

    hls::stream<layer32_t> layer32_out("layer32_out");
    #pragma HLS STREAM variable=layer32_out depth=36

    hls::stream<conv6_result_t> layer33_out("layer33_out");
    #pragma HLS STREAM variable=layer33_out depth=16

    hls::stream<layer35_t> layer35_out("layer35_out");
    #pragma HLS STREAM variable=layer35_out depth=16

    hls::stream<layer36_t> layer36_out("layer36_out");
    #pragma HLS STREAM variable=layer36_out depth=4

    hls::stream<layer37_t> layer37_out("layer37_out");
    #pragma HLS STREAM variable=layer37_out depth=1

    auto& layer38_out = layer37_out;
    nnet::zeropad2d_cl<input_t, layer2_t, config2>(bitstream_input, layer2_out); // pad_conv0

    nnet::conv_2d_cl<layer2_t, conv0_result_t, config3>(layer2_out, layer3_out, w3, b3); // conv0

    nnet::relu<conv0_result_t, layer5_t, relu_config5>(layer3_out, layer5_out); // act0

    nnet::pooling2d_cl<layer5_t, layer6_t, config6>(layer5_out, layer6_out); // pool0

    nnet::zeropad2d_cl<layer6_t, layer7_t, config7>(layer6_out, layer7_out); // pad_conv1

    nnet::conv_2d_cl<layer7_t, conv1_result_t, config8>(layer7_out, layer8_out, w8, b8); // conv1

    nnet::relu<conv1_result_t, layer10_t, relu_config10>(layer8_out, layer10_out); // act1

    nnet::pooling2d_cl<layer10_t, layer11_t, config11>(layer10_out, layer11_out); // pool1

    nnet::zeropad2d_cl<layer11_t, layer12_t, config12>(layer11_out, layer12_out); // pad_conv2

    nnet::conv_2d_cl<layer12_t, conv2_result_t, config13>(layer12_out, layer13_out, w13, b13); // conv2

    nnet::relu<conv2_result_t, layer15_t, relu_config15>(layer13_out, layer15_out); // act2

    nnet::pooling2d_cl<layer15_t, layer16_t, config16>(layer15_out, layer16_out); // pool2

    nnet::zeropad2d_cl<layer16_t, layer17_t, config17>(layer16_out, layer17_out); // pad_conv3

    nnet::conv_2d_cl<layer17_t, conv3_result_t, config18>(layer17_out, layer18_out, w18, b18); // conv3

    nnet::relu<conv3_result_t, layer20_t, relu_config20>(layer18_out, layer20_out); // act3

    nnet::pooling2d_cl<layer20_t, layer21_t, config21>(layer20_out, layer21_out); // pool3

    nnet::zeropad2d_cl<layer21_t, layer22_t, config22>(layer21_out, layer22_out); // pad_conv4

    nnet::conv_2d_cl<layer22_t, conv4_result_t, config23>(layer22_out, layer23_out, w23, b23); // conv4

    nnet::relu<conv4_result_t, layer25_t, relu_config25>(layer23_out, layer25_out); // act4

    nnet::pooling2d_cl<layer25_t, layer26_t, config26>(layer25_out, layer26_out); // pool4

    nnet::zeropad2d_cl<layer26_t, layer27_t, config27>(layer26_out, layer27_out); // pad_conv5

    nnet::conv_2d_cl<layer27_t, conv5_result_t, config28>(layer27_out, layer28_out, w28, b28); // conv5

    nnet::relu<conv5_result_t, layer30_t, relu_config30>(layer28_out, layer30_out); // act5

    nnet::pooling2d_cl<layer30_t, layer31_t, config31>(layer30_out, layer31_out); // pool5

    nnet::zeropad2d_cl<layer31_t, layer32_t, config32>(layer31_out, layer32_out); // pad_conv6

    nnet::conv_2d_cl<layer32_t, conv6_result_t, config33>(layer32_out, layer33_out, w33, b33); // conv6

    nnet::relu<conv6_result_t, layer35_t, relu_config35>(layer33_out, layer35_out); // act6

    nnet::pooling2d_cl<layer35_t, layer36_t, config36>(layer35_out, layer36_out); // pool6

    nnet::pooling2d_cl<layer36_t, layer37_t, config37>(layer36_out, layer37_out); // gap

    nnet::dense<layer37_t, result_t, config39>(layer38_out, layer39_out, w39, b39); // output_dense

}

