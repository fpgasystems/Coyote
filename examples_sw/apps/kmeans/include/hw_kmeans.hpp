/*
 * Copyright (c) 2019, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
/**/
// #include <iostream>
// #include "../../hwoperators.h"


// class HWKmeans {

// public:
//         HWKmeans(uint32_t* points, uint32_t* initial_center ,uint64_t size, uint32_t dimensions, uint32_t cluster, uint32_t num_cl_tuple, uint32_t num_cl_centroid, uint32_t number_of_iteration);
//         ~HWKmeans();

//         void run(uint16_t iter, uint8_t precision, uint32_t num_cl_centroid,uint32_t num_cl_tuple);

//         uint64_t getSSE( uint32_t num_cl_centroid, uint32_t precision);

//         void printCentroids(uint32_t number_of_iteration, uint32_t num_cl_centroid);
        
//         // void debug_counters(bool state_counters);

//         void print_debug_counters_expected_value(uint16_t number_of_iteration, uint8_t precision, uint32_t num_cl_tuple, uint32_t num_cl_centroid);


//         uint32_t*       mResults;


// private:

//     void initCentroids();
//     FPGA* my_fpga;
//     uint32_t*       mPoints;
//     uint32_t*       mCentroids;
//     uint64_t mSize;
//     uint32_t mClusters;
//     uint32_t mDimensions;


// };