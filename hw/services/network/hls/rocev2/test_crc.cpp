/*
 * Copyright (c) 2022, Systems Group, ETH Zurich
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
#include "rocev2.hpp"
#include <fstream>
#include <vector>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h> /* Added for the nonblocking socket */
#include <cstdint>

#include "../axi_utils.hpp" //TODO why is this needed here
#include "../crc/crc.hpp"
#include "rocev2_config.hpp"

using namespace hls;

int main(int argc, char* argv[]){
    // interfaces
    static stream<net_axis<DATA_WIDTH> > s_axis_data_n0;
    static stream<net_axis<DATA_WIDTH> > m_axis_data_n0;
    static stream<net_axis<DATA_WIDTH> > s_axis_data_0_1_n0;
    static stream<net_axis<DATA_WIDTH> > axis_data_0_1;
    static stream<net_axis<DATA_WIDTH> > m_axis_data_0_1_n1;
    static stream<net_axis<DATA_WIDTH> > s_axis_data_n1;
    static stream<net_axis<DATA_WIDTH> > m_axis_data_n1;
    ap_uint<32> regCrcDropPkgCount_n0;
    ap_uint<32> regCrcDropPkgCount_n1;

    int count = 0;
    //Make sure it is initialized
    while (count < 10)
    {
        crc<DATA_WIDTH, 0>(
            s_axis_data_n0,             
            m_axis_data_n0,             
            s_axis_data_0_1_n0,             
            axis_data_0_1,             
            regCrcDropPkgCount_n0      
        );

        crc<DATA_WIDTH, 1>(
            axis_data_0_1,             
            m_axis_data_0_1_n1,             
            s_axis_data_n1,             
            m_axis_data_n1,             
            regCrcDropPkgCount_n1      
        );
        count++;
    }

    // issue packetse
    int N_PACKETS = 1;
    ap_uint<512> currWord;
    

    for (int i = 0; i < N_PACKETS; i++) {
        for(int j = 0; j < 64; j++) {
            currWord(j*8+7, j*8) = rand();
        }
        s_axis_data_0_1_n0.write(net_axis<DATA_WIDTH>(currWord, ~0, i == N_PACKETS-1));
    }

    while (count < 20000)
    {
        crc<DATA_WIDTH, 0>(
            s_axis_data_n0,             
            m_axis_data_n0,             
            s_axis_data_0_1_n0,             
            axis_data_0_1,             
            regCrcDropPkgCount_n0      
        );

        crc<DATA_WIDTH, 1>(
            axis_data_0_1,             
            m_axis_data_0_1_n1,             
            s_axis_data_n1,             
            m_axis_data_n1,             
            regCrcDropPkgCount_n1      
        );
        if(!m_axis_data_0_1_n1.empty()) m_axis_data_0_1_n1.read();
        count++;
    }

    return 0;
}
