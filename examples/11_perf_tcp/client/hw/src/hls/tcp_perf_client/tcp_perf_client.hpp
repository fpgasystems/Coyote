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

#include "hls_stream.h"
#if defined( __VITIS_HLS__)
#include "ap_axi_sdata.h"
#endif
#include "ap_int.h"                 
#include <iostream>

#define DATA_WIDTH 512

struct ipTuple
{
	ap_uint<32>	ip_address;
	ap_uint<16>	ip_port;
};


struct openStatus
{
	ap_uint<16>	sessionID;
	ap_uint<8>	success;
	ap_uint<32> ip;
	ap_uint<16> port;
	openStatus() {}
	openStatus(ap_uint<16> id, ap_uint<8> success)
		:sessionID(id), success(success), ip(0), port(0) {}
	openStatus(ap_uint<16> id, ap_uint<8> success, ap_uint<32> ip, ap_uint<16> port)
		:sessionID(id), success(success), ip(ip), port(port) {}
};

struct appNotification
{
	ap_uint<16>			sessionID;
	ap_uint<16>			length;
	ap_uint<32>			ipAddress;
	ap_uint<16>			dstPort;
	bool				closed;
	appNotification() {}
	appNotification(ap_uint<16> id, ap_uint<16> len, ap_uint<32> addr, ap_uint<16> port)
				:sessionID(id), length(len), ipAddress(addr), dstPort(port), closed(false) {}
	appNotification(ap_uint<16> id, bool closed)
				:sessionID(id), length(0), ipAddress(0),  dstPort(0), closed(closed) {}
	appNotification(ap_uint<16> id, ap_uint<32> addr, ap_uint<16> port, bool closed)
				:sessionID(id), length(0), ipAddress(addr),  dstPort(port), closed(closed) {}
	appNotification(ap_uint<16> id, ap_uint<16> len, ap_uint<32> addr, ap_uint<16> port, bool closed)
			:sessionID(id), length(len), ipAddress(addr), dstPort(port), closed(closed) {}
};


struct appReadRequest
{
	ap_uint<16> sessionID;
	//ap_uint<16> address;
	ap_uint<16> length;
	appReadRequest() {}
	appReadRequest(ap_uint<16> id, ap_uint<16> len)
			:sessionID(id), length(len) {}
};

struct appTxMeta
{
	ap_uint<16> sessionID;
	ap_uint<16> length;
	appTxMeta() {}
	appTxMeta(ap_uint<16> id, ap_uint<16> len)
		:sessionID(id), length(len) {}
};

struct appTxRsp
{
	ap_uint<16>	sessionID;
	ap_uint<16> length;
	ap_uint<30> remaining_space;
	ap_uint<2>	error;
	appTxRsp() {}
	appTxRsp(ap_uint<16> id, ap_uint<16> len, ap_uint<30> rem_space, ap_uint<2> err)
		:sessionID(id), length(len), remaining_space(rem_space), error(err) {}
};


template <int D>
struct net_axis
{
	ap_uint<D>		data;
	ap_uint<D/8>	keep;
	ap_uint<1>		last;
	net_axis() {}
	net_axis(ap_uint<D> data, ap_uint<D/8> keep, ap_uint<1> last)
		:data(data), keep(keep), last(last) {}
};

void tcp_perf_client(
	hls::stream<ipTuple>& openConnection,
	hls::stream<openStatus>& openConStatus,
	hls::stream<ap_uint<16> >& closeConnection,
	hls::stream<appTxMeta>& txMetaData,
	hls::stream<ap_axiu<DATA_WIDTH, 0, 0, 0> >& txData,
	hls::stream<appTxRsp>& txStatus,
	ap_uint<1>		runTx,
	ap_uint<16>		numSessions,
	ap_uint<32> 	pkgWordCount,
	ap_uint<32>		serverIpAddress,
	ap_uint<32>		userFrequency,
	ap_uint<32>		timeInSeconds,
	ap_uint<32>& 	totalWord,
	ap_uint<4>&		state_debug);

	
	