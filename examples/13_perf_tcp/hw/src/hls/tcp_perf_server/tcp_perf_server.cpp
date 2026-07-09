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

#include "tcp_perf_server.hpp"

template <int WIDTH>
void rx_data_buffer(hls::stream<ap_axiu<WIDTH, 0, 0, 0>>& s_axi_rx_data, hls::stream<rxData<WIDTH>>& m_axi_rx_data) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	ap_axiu<WIDTH, 0, 0, 0> input_word;
	rxData<WIDTH> output_word;

	if (!s_axi_rx_data.empty()) {
		input_word = s_axi_rx_data.read();
		output_word.data = input_word.data;
		output_word.keep = input_word.keep;
		output_word.last = input_word.last;
		m_axi_rx_data.write(output_word);
	}
}

template <int WIDTH>
void inst_server(
	hls::stream<rxNotification>&	rx_notif,
	hls::stream<rxReadRequest>&		rx_read_request,
	hls::stream<ap_uint<16>>&		rx_meta,
	hls::stream<rxData<WIDTH>>&		rx_data
) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	enum server_state_t {ST_WAIT_PKG, ST_CONSUME};
	static server_state_t  state = ST_WAIT_PKG;

	// If a notification is received, request to read the data
	if (!rx_notif.empty()) {
		rxNotification notification = rx_notif.read();

		if (notification.length != 0) {
			rx_read_request.write(rxReadRequest(notification.session_id, notification.length));
		}
	}

	switch (state) {
		case ST_WAIT_PKG:
			// Read the data and the metadata
			// For this benchmark, metadata is discarded (but needs to be consumed/read to avoid stalling the TCP stack)
			if (!rx_meta.empty() && !rx_data.empty()) {
				rx_meta.read();
				rxData<WIDTH> received_word = rx_data.read();
				
				// If not last, continue consuming packages
				if (!received_word.last) {
					state = ST_CONSUME;
				}
			}
			break;
		
		case ST_CONSUME:
			if (!rx_data.empty()) {
				rxData<WIDTH> received_word = rx_data.read();

				// If last, wait for next package
				if (received_word.last) {
					state = ST_WAIT_PKG;
				}
			}
			break;
	}
}

void tcp_perf_server(
	hls::stream<rxNotification>& 			rx_notif,
	hls::stream<rxReadRequest>& 			rx_read_request,
	hls::stream<ap_uint<16>>& 				rx_meta,
	hls::stream<ap_axiu<AXIS_DATA_WIDTH,0,0,0>>& rx_data
) {
	// Enable dataflow for pipelining; no AP_CTRL interface			
	#pragma HLS DATAFLOW disable_start_propagation
	#pragma HLS INTERFACE ap_ctrl_none port=return

	// Define streaming interfaces as AXI4 Stream
	#pragma HLS INTERFACE axis register port=rx_notif name=s_axis_notif
	#pragma HLS INTERFACE axis register port=rx_read_request name=m_axis_read_package
	#pragma HLS INTERFACE axis register port=rx_meta name=s_axis_rx_meta
	#pragma HLS INTERFACE axis register port=rx_data name=s_axis_rx_data

	// Make streams with structs compact -> no padding bits in the structs
	#pragma HLS aggregate compact=bit variable=rx_notif
	#pragma HLS aggregate compact=bit variable=rx_read_request

	// Simple register stage
	static hls::stream<rxData<AXIS_DATA_WIDTH> > rx_data_int;
	#pragma HLS STREAM depth=2 variable=rx_data_int
	rx_data_buffer<AXIS_DATA_WIDTH>(rx_data, rx_data_int);

	// Main server logic
	inst_server<AXIS_DATA_WIDTH>(
		rx_notif,
		rx_read_request,
		rx_meta,
		rx_data_int
	);
}
