/************************************************
Copyright (c) 2019, Systems Group, ETH Zurich.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
************************************************/
#pragma once

#include "send_recv_config.hpp"
#include "axi_utils.hpp"
#include "packet.hpp"
#include "toe.hpp"

#ifndef __SYNTHESIS__
static const ap_uint<32> END_TIME		= 1000; //1000000;
static const ap_uint<40> END_TIME_120	= 1000;

#else
static const ap_uint<32> END_TIME		= 1546546546;//1501501501;
static const ap_uint<40> END_TIME_120	= 18750000000;
#endif

const uint32_t IPERF_TCP_HEADER_SIZE = 512;

/**
 * iperf TCP Header
 */
template <int W>
class iperfTcpHeader : public packetHeader<W, IPERF_TCP_HEADER_SIZE> {
   using packetHeader<W, IPERF_TCP_HEADER_SIZE>::header;

public:
   iperfTcpHeader()
   {
      header(63, 32) = 0x01000000;
      header(79, 64) = 0x0000;
      header(127, 96) = 0x00000000;
      header(159, 128) = 0;
   }

   void setDualMode(bool en)
   {
      if (en)
      {
         header(31, 0) = 0x01000080;
      }
      else
      {
         header(31, 0) = 0x00000000;
      }
   }
   //This is used for dual tes
   void setListenPort(ap_uint<16> port)
   {
      header(95, 80) = reverse(port);
   }
   void setSeconds(ap_uint<32> seconds)
   {
      header(191, 160) = reverse(seconds);
   }
};


void send_recv(
					hls::stream<appNotification>& notifications,
					hls::stream<appReadRequest>& readRequest,
					hls::stream<ap_uint<16> >& rxMetaData,
					hls::stream<net_axis<DATA_WIDTH> >& rxData,
					hls::stream<appTxMeta>& txMetaData,
					hls::stream<net_axis<DATA_WIDTH> >& txData,
					hls::stream<appTxRsp>& txStatus,
					ap_uint<32>	pkgWordCount,
					ap_uint<32> sessionID,
					ap_uint<32> transferSize,
					ap_uint<1> runTx
					);