#ifndef DEFINES_H_
#define DEFINES_H_

#include "ap_fixed.h"
#include "ap_int.h"
#include "nnet_utils/nnet_types.h"
#include <array>
#include <cstddef>
#include <cstdio>
#include <tuple>
#include <tuple>


// hls-fpga-machine-learning insert numbers

// hls-fpga-machine-learning insert layer-precision
typedef nnet::array<ap_fixed<16,6>, 1*1> input_t;
typedef nnet::array<ap_fixed<16,6>, 1*1> layer2_t;
typedef ap_fixed<30,13> conv0_accum_t;
typedef nnet::array<ap_fixed<30,13>, 8*1> conv0_result_t;
typedef ap_fixed<8,1> weight3_t;
typedef ap_fixed<8,1> bias3_t;
typedef nnet::array<ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0>, 8*1> layer5_t;
typedef ap_fixed<18,8> act0_table_t;
typedef ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0> pool0_accum_t;
typedef nnet::array<ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0>, 8*1> layer6_t;
typedef nnet::array<ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0>, 8*1> layer7_t;
typedef ap_fixed<24,11> conv1_accum_t;
typedef nnet::array<ap_fixed<24,11>, 16*1> conv1_result_t;
typedef ap_fixed<8,1> weight8_t;
typedef ap_fixed<8,1> bias8_t;
typedef nnet::array<ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0>, 16*1> layer10_t;
typedef ap_fixed<18,8> act1_table_t;
typedef ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0> pool1_accum_t;
typedef nnet::array<ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0>, 16*1> layer11_t;
typedef nnet::array<ap_ufixed<8,2,AP_RND_CONV,AP_SAT,0>, 16*1> layer12_t;
typedef ap_fixed<25,12> conv2_accum_t;
typedef nnet::array<ap_fixed<25,12>, 24*1> conv2_result_t;
typedef ap_fixed<8,1> weight13_t;
typedef ap_fixed<8,1> bias13_t;
typedef nnet::array<ap_ufixed<8,3,AP_RND_CONV,AP_SAT,0>, 24*1> layer15_t;
typedef ap_fixed<18,8> act2_table_t;
typedef ap_ufixed<8,3,AP_RND_CONV,AP_SAT,0> pool2_accum_t;
typedef nnet::array<ap_ufixed<8,3,AP_RND_CONV,AP_SAT,0>, 24*1> layer16_t;
typedef nnet::array<ap_ufixed<8,3,AP_RND_CONV,AP_SAT,0>, 24*1> layer17_t;
typedef ap_fixed<25,13> conv3_accum_t;
typedef nnet::array<ap_fixed<25,13>, 24*1> conv3_result_t;
typedef ap_fixed<8,1> weight18_t;
typedef ap_fixed<8,1> bias18_t;
typedef nnet::array<ap_ufixed<8,4,AP_RND_CONV,AP_SAT,0>, 24*1> layer20_t;
typedef ap_fixed<18,8> act3_table_t;
typedef ap_ufixed<8,4,AP_RND_CONV,AP_SAT,0> pool3_accum_t;
typedef nnet::array<ap_ufixed<8,4,AP_RND_CONV,AP_SAT,0>, 24*1> layer21_t;
typedef nnet::array<ap_ufixed<8,4,AP_RND_CONV,AP_SAT,0>, 24*1> layer22_t;
typedef ap_fixed<25,14> conv4_accum_t;
typedef nnet::array<ap_fixed<25,14>, 32*1> conv4_result_t;
typedef ap_fixed<8,1> weight23_t;
typedef ap_fixed<8,1> bias23_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer25_t;
typedef ap_fixed<18,8> act4_table_t;
typedef ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0> pool4_accum_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer26_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer27_t;
typedef ap_fixed<26,16> conv5_accum_t;
typedef nnet::array<ap_fixed<26,16>, 32*1> conv5_result_t;
typedef ap_fixed<8,1> weight28_t;
typedef ap_fixed<8,1> bias28_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer30_t;
typedef ap_fixed<18,8> act5_table_t;
typedef ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0> pool5_accum_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer31_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer32_t;
typedef ap_fixed<26,16> conv6_accum_t;
typedef nnet::array<ap_fixed<26,16>, 32*1> conv6_result_t;
typedef ap_fixed<8,1> weight33_t;
typedef ap_fixed<8,1> bias33_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer35_t;
typedef ap_fixed<18,8> act6_table_t;
typedef ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0> pool6_accum_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer36_t;
typedef ap_ufixed<8,5> gap_accum_t;
typedef nnet::array<ap_ufixed<8,5,AP_RND_CONV,AP_SAT,0>, 32*1> layer37_t;
typedef ap_fixed<22,12> output_dense_accum_t;
typedef nnet::array<ap_fixed<22,12>, 1*1> result_t;
typedef ap_fixed<8,1> weight39_t;
typedef ap_fixed<8,1> bias39_t;
typedef ap_uint<1> layer39_index;

// hls-fpga-machine-learning insert emulator-defines


#endif
