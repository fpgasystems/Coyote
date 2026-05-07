/*******************************************************************************
#  Copyright (C) 2021 Xilinx, Inc
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
# *******************************************************************************/

#include "ap_int.h"
#include <stdint.h>
#include "reduce_ops.h"

// Problematic kernel, from ACCL: https://github.com/Xilinx/ACCL
// Works as expected in Vivado 2022.2, but fails to produce any outputs in Vivado 2024.1

using namespace std;

template<unsigned int data_width, unsigned int dest_width, typename T>
ap_uint<data_width> stream_add(ap_uint<data_width> op1, ap_uint<data_width> op2) {
#pragma HLS inline

	unsigned const dwb = 8*sizeof(T);
	unsigned const simd = data_width / dwb;
	ap_uint<data_width> res;
	
	for (unsigned int j = 0; j < simd; j++) {
#pragma HLS UNROLL
		ap_uint<dwb> op1_word = op1((j+1)*dwb-1,j*dwb);
		ap_uint<dwb> op2_word = op2((j+1)*dwb-1,j*dwb);
		T op1_word_t = *reinterpret_cast<T*>(&op1_word);
		T op2_word_t = *reinterpret_cast<T*>(&op2_word);
		T sum = op1_word_t + op2_word_t;
		ap_uint<dwb> res_word = *reinterpret_cast<ap_uint<dwb>*>(&sum);
		res((j+1)*dwb-1,j*dwb) = res_word;
	}

	return res;
}

template<unsigned int data_width, unsigned int dest_width, typename T>
ap_uint<data_width> stream_max(ap_uint<data_width> op1, ap_uint<data_width> op2) {
#pragma HLS inline

	unsigned const dwb = 8*sizeof(T);
	unsigned const simd = data_width / dwb;
	ap_uint<data_width> res;

	for (unsigned int j = 0; j < simd; j++) {
#pragma HLS UNROLL
		ap_uint<dwb> op1_word = op1((j+1)*dwb-1,j*dwb);
		ap_uint<dwb> op2_word = op2((j+1)*dwb-1,j*dwb);
		T op1_word_t = *reinterpret_cast<T*>(&op1_word);
		T op2_word_t = *reinterpret_cast<T*>(&op2_word);
		T max = (op1_word_t > op2_word_t) ? op1_word_t : op2_word_t;
		ap_uint<dwb> res_word = *reinterpret_cast<ap_uint<dwb>*>(&max);
		res((j+1)*dwb-1,j*dwb) = res_word;
	}

	return res;
}

void reduce_ops(STREAM<stream_word> & in0, STREAM<stream_word> & in1, STREAM<stream_word> & out) {
#pragma HLS INTERFACE axis register both port=in0 name=in0
#pragma HLS INTERFACE axis register both port=in1 name=in1
#pragma HLS INTERFACE axis register both port=out name=out
#pragma HLS INTERFACE ap_ctrl_none port=return
	stream_word op0, op1, wword;
	ap_uint<DATA_WIDTH> res;

	do {
#pragma HLS PIPELINE II=1 style=frp
		op0 = STREAM_READ(in0);
		op1 = STREAM_READ(in1);

		if(op0.dest == 0)      res = stream_add<DATA_WIDTH, DEST_WIDTH, float>(op0.data, op1.data);
		else if(op0.dest == 1) res = stream_add<DATA_WIDTH, DEST_WIDTH, double>(op0.data, op1.data);
		else if(op0.dest == 2) res = stream_add<DATA_WIDTH, DEST_WIDTH, int32_t>(op0.data, op1.data);
		else if(op0.dest == 3) res = stream_add<DATA_WIDTH, DEST_WIDTH, int64_t>(op0.data, op1.data);
		else if(op0.dest == 5) res = stream_max<DATA_WIDTH, DEST_WIDTH, float>(op0.data, op1.data);
		else if(op0.dest == 6) res = stream_max<DATA_WIDTH, DEST_WIDTH, double>(op0.data, op1.data);
		else if(op0.dest == 7) res = stream_max<DATA_WIDTH, DEST_WIDTH, int32_t>(op0.data, op1.data);
		else if(op0.dest == 8) res = stream_max<DATA_WIDTH, DEST_WIDTH, int64_t>(op0.data, op1.data);
		else res = stream_add<DATA_WIDTH, DEST_WIDTH, float>(op0.data, op1.data);

		wword.data = res;
		wword.last = op0.last;
		wword.keep = op0.keep;
		wword.dest = 0;
		STREAM_WRITE(out, wword);

	} while(op0.last != 1);
}
