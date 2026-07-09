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

#ifndef _TCP_PERF_CLIENT_HPP_
#define _TCP_PERF_CLIENT_HPP_

#include "ap_int.h"
#include "hls_stream.h"
#if defined( __VITIS_HLS__)
#include "ap_axi_sdata.h"
#endif

#define AXIS_DATA_WIDTH 512

/// TX Metadata structure; session_id and length of the data to be sent (set before sending the data)
struct txMeta {
	ap_uint<16> session_id;
	ap_uint<16> length;

	txMeta() {}

	txMeta(ap_uint<16> id, ap_uint<16> len)
		:session_id(id), length(len) {}
};

/// TX Response structure; response from the TCP stack after sending data
struct txRsp {
	ap_uint<16>	session_id;
	ap_uint<16> length;
	ap_uint<30> remaining_space;
	ap_uint<2>	error;

	txRsp() {}

	txRsp(ap_uint<16> id, ap_uint<16> len, ap_uint<30> rem_space, ap_uint<2> err)
		:session_id(id), length(len), remaining_space(rem_space), error(err) {}
};

/// TX Data structure; data to be sent to the TCP stack (standard AXI4 Stream)
template <int D>
struct txData {
	ap_uint<D>		data;
	ap_uint<D/8>	keep;
	ap_uint<1>		last;

	txData() {}

	txData(ap_uint<D> data, ap_uint<D/8> keep, ap_uint<1> last)
		:data(data), keep(keep), last(last) {}
};


/// Buffers the TX status responses in a FIFO
void tx_status_buffer(hls::stream<txRsp>& s_tx_status, hls::stream<txRsp>& m_tx_status);

/// Buffers SW-injected session IDs in a FIFO
void session_id_buffer(hls::stream<ap_uint<16>>& s_session_id, hls::stream<ap_uint<16>>& m_session_id);

/// Buffers TX metadata in a FIFO
void tx_meta_buffer(hls::stream<txMeta>& s_tx_meta, hls::stream<txMeta>& m_tx_meta);

/// Buffers TX data in a FIFO
template <int WIDTH>
void tx_data_buffer(hls::stream<txData<WIDTH>>& s_tx_data, hls::stream<ap_axiu<WIDTH, 0, 0, 0>>& m_tx_data);

/**
 * @brief Performance timer to control the duration of the TCP performance test.
 * When the start signal is received, counts clock cycles until clk_freq * duration
 * cycles have elapsed, then fires a stop signal.
 */
void perf_timer(hls::stream<bool>& start_signal, hls::stream<bool>& stop_signal, ap_uint<32> clk_freq, ap_uint<32> duration);

/// Main client logic — consumes SW-injected session IDs and sends benchmark traffic
template <int WIDTH>
void inst_client(
	hls::stream<ap_uint<16>>& 		session_ids,
	hls::stream<txMeta>& 			tx_meta,
	hls::stream<txData<WIDTH> >& 	tx_data,
	hls::stream<txRsp>&				tx_status,
	hls::stream<bool>& 				start_signal,
	hls::stream<bool>& 				stop_signal,
	ap_uint<1> 						start_client,
	ap_uint<16>						n_sessions,
	ap_uint<32>						pkg_word_count,
	ap_uint<4>&						client_state
);

/// Top-level function for TCP performance client
void tcp_perf_client(
	hls::stream<ap_uint<16>>& 		session_ids,
	hls::stream<txMeta>& 			tx_meta,
	hls::stream<ap_axiu<AXIS_DATA_WIDTH, 0, 0, 0> >& tx_data,
	hls::stream<txRsp>& 			tx_status,
	ap_uint<1>						start_client,
	ap_uint<16>						n_sessions,
	ap_uint<32> 					pkg_word_count,
	ap_uint<32>						clk_freq,
	ap_uint<32>						duration,
	ap_uint<4>&						client_state
);

#endif // _TCP_PERF_CLIENT_HPP_
