/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _TCP_PERF_SERVER_HPP_
#define _TCP_PERF_SERVER_HPP_

#include "ap_int.h"                 
#include "hls_stream.h"
#if defined( __VITIS_HLS__)
#include "ap_axi_sdata.h"
#endif

#define AXIS_DATA_WIDTH 512

/// Notification of received data from the TCP stack
struct rxNotification {
	ap_uint<16>			session_id;
	ap_uint<16>			length;
	ap_uint<32>			ip_address;
	ap_uint<16>			dst_port;
	bool				closed;

	rxNotification() {}

	rxNotification(ap_uint<16> id, ap_uint<16> len, ap_uint<32> addr, ap_uint<16> port, bool closed)
		:session_id(id), length(len), ip_address(addr), dst_port(port), closed(closed) {}
};

/// Request to read RX data from the TCP stack; sent when a notification is received
struct rxReadRequest {
	ap_uint<16> session_id;
	ap_uint<16> length;

	rxReadRequest() {}

	rxReadRequest(ap_uint<16> id, ap_uint<16> len)
		:session_id(id), length(len) {}
};

/// RX Data structure; data received from the TCP stack (standard AXI4 Stream)
template <int D>
struct rxData {
	ap_uint<D>		data;
	ap_uint<D/8>	keep;
	ap_uint<1>		last;

	rxData() {}

	rxData(ap_uint<D> data, ap_uint<D/8> keep, ap_uint<1> last)
		:data(data), keep(keep), last(last) {}
};

/// Simple register stage for RX data
template <int WIDTH>
void rx_data_buffer(hls::stream<ap_axiu<WIDTH, 0, 0, 0>>& s_axi_rx_data, hls::stream<rxData<WIDTH>>& m_axi_rx_data);

/// Main server logic, responsible for receiving data
template <int WIDTH>
void inst_server(
	hls::stream<rxNotification>&	rx_notif,
	hls::stream<rxReadRequest>&		rx_read_request,
	hls::stream<ap_uint<16>>&		rx_meta,
	hls::stream<rxData<WIDTH>>&		rx_data
);

/// Top-level function for TCP performance server
void tcp_perf_server(
	hls::stream<rxNotification>& 			rx_notif,
	hls::stream<rxReadRequest>& 			rx_read_request,
	hls::stream<ap_uint<16>>& 				rx_meta,
	hls::stream<ap_axiu<AXIS_DATA_WIDTH,0,0,0>>&	rx_data
);

#endif //_TCP_PERF_SERVER_HPP_