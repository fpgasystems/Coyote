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
#pragma once

#include "ap_int.h"
#include "hls_stream.h"
#include "ap_axi_sdata.h"
#include <stdint.h>

#define DATA_WIDTH 512
#define DEST_WIDTH 8

typedef ap_axiu<DATA_WIDTH, 0, 0, DEST_WIDTH> stream_word;

#define STREAM hls::stream
#define STREAM_READ(s)       s.read()
#define STREAM_WRITE(s, val) s.write(val)

void reduce_ops(
    STREAM<stream_word> &in0,
    STREAM<stream_word> &in1,
    STREAM<stream_word> &out
);
