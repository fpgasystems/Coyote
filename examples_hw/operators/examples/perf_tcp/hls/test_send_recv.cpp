/************************************************
Copyright (c) 2018, Systems Group, ETH Zurich.
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
#include "send_recv_config.hpp"
#include "send_recv.hpp"
#include <iostream>

using namespace hls;


int main()
{
	hls::stream<ap_uint<16> > listenPort("listenPort");
	hls::stream<bool> listenPortStatus("listenPortStatus");
	hls::stream<appNotification> notifications("notifications");
	hls::stream<appReadRequest> readRequest("readRequest");
	hls::stream<ap_uint<16> > rxMetaData("rxMetaData");
	hls::stream<net_axis<DATA_WIDTH> > rxData("rxData");
	hls::stream<ipTuple> openConnection("openConnection");
	hls::stream<openStatus> openConStatus("openConStatus");
	hls::stream<ap_uint<16> > closeConnection("closeConnection");
	hls::stream<appTxMeta> txMetaData("txMetaData");
	hls::stream<net_axis<DATA_WIDTH> > txData("txData");
	hls::stream<appTxRsp> txStatus("txStatus");
	ap_uint<1> runExperiment;
	ap_uint<1> dualModeEn;
	ap_uint<13> useConn;
	ap_uint<8> pkgWordCount;
	ap_uint<8> pkgGap;
	ap_uint<32> timeInSeconds;
	ap_uint<64> timeInCycles;
	ap_uint<16>	useIpAddr = 2;
	ap_uint<16>	regBasePort = 5001;
	ap_uint<32> sessionID = 1;
	ap_uint<32> transferSize = 2*1024;

	dualModeEn = 0;
	pkgWordCount = 16;
	pkgGap = 0;
	timeInSeconds = 100;
	timeInCycles = 1000;

	int count = 0;
	while (count < 10000)
	{
		useConn = 2;
		runExperiment = 0;
		if (count == 20)
		{
			runExperiment = 1;
		}
		send_recv(	listenPort,
					listenPortStatus,
					notifications,
					readRequest,
					rxMetaData,
					rxData,
					txMetaData,
					txData,
					txStatus,
					pkgWordCount,
					sessionID,
					transferSize,
					runExperiment
					);


		if (!listenPort.empty())
		{
			ap_uint<16> port = listenPort.read();
			std::cout << "Port " << port << " openend." << std::endl;
			listenPortStatus.write(true);
		}

	
		if (!txMetaData.empty())
		{
			appTxMeta meta = txMetaData.read();
			std::cout << "New Pkg: " << std::dec << meta.sessionID << ", length[B]: " << meta.length << std::endl;
			// int toss = rand() % 2;
			// toss = (toss == 0 || meta.length == IPERF_TCP_HEADER_SIZE/8) ? 0 : -1;
			int toss = 0;
			std::cout << "toss: " << toss << std::endl;
			txStatus.write(appTxRsp(meta.sessionID, meta.length, 0xFFFF, toss));
		}
		while (!txData.empty())
		{
			net_axis<DATA_WIDTH> currWord = txData.read();
			printLE(std::cout, currWord);
			std::cout << std::endl;

		}

		count++;
	}
	return 0;
}
