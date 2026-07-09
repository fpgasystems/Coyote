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

#include "tcp_perf_client.hpp"

void tx_status_buffer(hls::stream<txRsp>& s_tx_status, hls::stream<txRsp>& m_tx_status) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	// Buffers TX responses coming from the TCP stack
	if (!s_tx_status.empty()) {
		txRsp resp = s_tx_status.read();
		m_tx_status.write(resp);
	}
}

void session_id_buffer(hls::stream<ap_uint<16>>& s_session_id, hls::stream<ap_uint<16>>& m_session_id) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	if (!s_session_id.empty()) {
		m_session_id.write(s_session_id.read());
	}
}

void tx_meta_buffer(hls::stream<txMeta>& s_tx_meta, hls::stream<txMeta>& m_tx_meta) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	// Forward meta data from the s_tx_meta buffer to the TCP stack
	if (!s_tx_meta.empty()) {
		txMeta meta_req = s_tx_meta.read();
		m_tx_meta.write(meta_req);
	}
}

template <int WIDTH>
void tx_data_buffer(hls::stream<txData<WIDTH>>& s_tx_data, hls::stream<ap_axiu<WIDTH, 0, 0, 0>>& m_tx_data) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	// Forward TX data from the s_tx_data_buffer to the TCP buffer
	if (!s_tx_data.empty()) {
		txData<WIDTH> in = s_tx_data.read();
		ap_axiu<WIDTH,0,0,0> out;
		out.data = in.data;
		out.keep = in.keep;
		out.last = in.last;
		m_tx_data.write(out);
	}
}

void perf_timer(
    hls::stream<bool>& start_signal,
    hls::stream<bool>& stop_signal,
	ap_uint<32>	clk_freq,
    ap_uint<32> duration
){
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

    enum timer_state_t { ST_WAIT_START, ST_RUN };
    static timer_state_t state = ST_WAIT_START;

    static ap_uint<64> cycles = 0;
    static ap_uint<64> target = 0;

    switch (state) {
		case ST_WAIT_START:
			if (!start_signal.empty()) {
				bool start = start_signal.read();
				if (start) {
					cycles = 0;
					target = (ap_uint<64>) clk_freq * (ap_uint<64>) duration;
					state = ST_RUN;
				}
			}
			break;

		case ST_RUN:
			if (cycles >= target) {
				if (!stop_signal.full()) {
					stop_signal.write(true);
					state = ST_WAIT_START;
				}
			} else {
				cycles++;
			}
			break;
	}
}

// TCP connections are opened by host software via cThread::openConnTcp().
// The returned session IDs are injected directly by the AXI ctrl parser.
// This kernel only handles the TX data path; it never opens or closes connections.
template <int WIDTH>
void inst_client(
	hls::stream<ap_uint<16>>& 		session_ids,
	hls::stream<txMeta>&			tx_meta,
	hls::stream<txData<WIDTH> >& 	tx_data,
	hls::stream<txRsp>&				tx_status,
	hls::stream<bool>& 				start_signal,
	hls::stream<bool>& 				stop_signal,
	ap_uint<1>						start_client,
	ap_uint<16>						n_sessions,
	ap_uint<32>						pkg_word_count,
	ap_uint<4>&						client_state
) {
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	enum client_state_t { ST_IDLE, ST_WAIT_CONN, ST_WAIT_INIT_TX_RSP, ST_INIT_PROBE_SEND, ST_CHECK_REQ, ST_START_PKG, ST_WRITE_PKG };
	static client_state_t state = ST_IDLE;

	// The session for which packets are currently being sent
	static ap_uint<16> curr_session_id;

	// Number of currently opened connections; used to track when all connections are opened
	static ap_uint<16> n_conns;

	// Number of SW-injected session IDs received so far
	static ap_uint<16> sessions_received;

	// A counter which increments between 0 and n_conns and constructs headers and the TX data for each session
	static ap_uint<16> session_cntr;

	// A counter to track how many words have been sent for the current packet
	static ap_uint<32> word_cntr;

	// Benchmark stop signal, because the target duration has been reached
	static bool        stop_send;

	// Boolean to indicate traffic sending should stop
	static bool        end_tx;

	if (!stop_signal.empty()) {
        end_tx = stop_signal.read();
    }

	switch (state) {
		// Reset all variables and wait for SW to inject session IDs
		case ST_IDLE:
			if (start_client) {
				curr_session_id = 0;
				n_conns = 0;
				sessions_received = 0;
				session_cntr = 0;
				word_cntr = 0;
				end_tx = false;
				stop_send = false;
				state = ST_WAIT_CONN;
			}
			break;

		// Consume SW-injected session IDs.
		// SW calls openConnTcp() for each session and writes the returned
		// session ID to the SESSION_ID CSR; each write produces one entry here.
		case ST_WAIT_CONN:
			if (sessions_received == n_sessions) {
				start_signal.write(true);
				session_cntr = 0;
				state = ST_WAIT_INIT_TX_RSP;
			} else if (!session_ids.empty()) {
				ap_uint<16> sid = session_ids.read();
				tx_meta.write(txMeta(sid, WIDTH/8));
				n_conns++;
				sessions_received++;
			}
			break;

		// For each connection, wait for the TX status response after sending the meta data for each initial probe packet
		case ST_WAIT_INIT_TX_RSP:
			// All initial probe packets have been sent, move to checking state of FSM and conns, before sending real packets
			if (session_cntr == n_conns) {
				session_cntr = 0;
				state = ST_CHECK_REQ;

			// Receive TX status response for the previously issued meta
			} else if (!tx_status.empty()) {
				txRsp resp = tx_status.read();
				if (resp.error == 0) { 			// error = 0: OK -> send probe packet
					curr_session_id = resp.session_id;
					state = ST_INIT_PROBE_SEND;
				} else if (resp.error == 1) {	//  error = 1: session not found; drop connection
					n_conns--;
				} else {						// error = 2: TX buffer full, retry
					tx_meta.write(txMeta(resp.session_id, WIDTH/8));
				}
			}
			break;

		case ST_INIT_PROBE_SEND:
			// Before the benchmark starts, a single word is sent per connection to verify the TCP stack can accept data.
			if(!tx_data.full() && !tx_meta.full()){
				txData<WIDTH> probe_packet;
				probe_packet.data = 0;
				probe_packet.last = 1;
				for (int i = 0; i < (WIDTH/64); i++) {
					#pragma HLS UNROLL
					probe_packet.keep(i*8+7, i*8) = 0xff;
				}
				tx_data.write(probe_packet);

				// Issue meta request for the actual benchmark payloads
				// Checking their response happens in ST_CHECK_REQ
				tx_meta.write(txMeta(curr_session_id, pkg_word_count*(WIDTH/8)));

				// Increment session_cntr, which eventually causes the transition: ST_WAIT_INIT_TX_RSP -> ST_CHECK_REQ
				session_cntr++;
				state = ST_WAIT_INIT_TX_RSP;
			}
			break;

		case ST_CHECK_REQ:
			if (n_conns == 0) {
				state = ST_IDLE;
			} else if (!tx_status.empty()) {
				txRsp resp = tx_status.read();
				if (stop_send) {
					// If benchmark finished, flush the status FIFO
					n_conns--;
				} else if (resp.error == 0) {
					// error = 0; meta accepted, fire payload
					curr_session_id = resp.session_id;
					state = ST_START_PKG;
				} else if (resp.error == 1) {
					// error = 1: invalid session, drop connection
					n_conns--;
				} else if (resp.error == 2 && !end_tx) {
					// error = 2: TX buffer full, retry
					tx_meta.write(txMeta(resp.session_id, pkg_word_count*(WIDTH/8)));
				} else {
					n_conns--;
				}
			}
			break;

		// Start data transfer
		case ST_START_PKG: {
			// If stop signal received, mark benchmark as done; otherwise issue another
			// meta request for this session (payload = pkg_word_count * (WIDTH/8) B)
			if (!end_tx) {
				tx_meta.write(txMeta(curr_session_id, pkg_word_count*(WIDTH/8)));
			} else {
				stop_send = true;
				n_conns--;
			}

			// Write TX data and keep track of the number of words sent
			txData<WIDTH> curr_word;
			for (int i = 0; i < (WIDTH/64); i++) {
				#pragma HLS UNROLL
				curr_word.data(i*64+63, i*64) = 0x3736353433323130ULL;
				curr_word.keep(i*8+7, i*8) = 0xff;
			}
			word_cntr = 1;
			curr_word.last = (pkg_word_count == 1);
			tx_data.write(curr_word);

			if (curr_word.last) {
				word_cntr = 0;
				state = ST_CHECK_REQ;
			} else {
				state = ST_WRITE_PKG;
			}
		}
			break;

		// Continue write process until pkg_word_count AXI beats (words) have been sent
		case ST_WRITE_PKG: {
			word_cntr++;
			txData<WIDTH> curr_word;
			for (int i = 0; i < (WIDTH/64); i++) {
				#pragma HLS UNROLL
				curr_word.data(i*64+63, i*64) = 0x3736353433323130ULL;
				curr_word.keep(i*8+7, i*8) = 0xff;
			}
			curr_word.last = (word_cntr == pkg_word_count);
			tx_data.write(curr_word);

			if (curr_word.last) {
				word_cntr = 0;
				state = ST_CHECK_REQ;
			}
		}
			break;

	}

	client_state = (ap_uint<4>) state;
}


void tcp_perf_client(
	hls::stream<ap_uint<16>>& session_ids,
	hls::stream<txMeta>& tx_meta,
	hls::stream<ap_axiu<AXIS_DATA_WIDTH, 0, 0, 0> >& tx_data,
	hls::stream<txRsp>& tx_status,
	ap_uint<1>	start_client,
	ap_uint<16>	n_sessions,
	ap_uint<32> pkg_word_count,
	ap_uint<32>	clk_freq,
	ap_uint<32>	duration,
	ap_uint<4>&	client_state
) {
	// Enable dataflow for pipelining; no AP_CTRL interface
	#pragma HLS DATAFLOW disable_start_propagation
	#pragma HLS INTERFACE ap_ctrl_none port=return

	// Define streaming interfaces as AXI4 Stream
	#pragma HLS INTERFACE axis register port=session_ids name=s_axis_session_ids
	#pragma HLS INTERFACE axis register port=tx_meta name=m_axis_tx_meta
	#pragma HLS INTERFACE axis register port=tx_data name=m_axis_tx_data
	#pragma HLS INTERFACE axis register port=tx_status name=s_axis_tx_status

	// No dedicated interface for scalar ports (just a wire)
	#pragma HLS INTERFACE ap_none register port=start_client
	#pragma HLS INTERFACE ap_none register port=n_sessions
	#pragma HLS INTERFACE ap_none register port=pkg_word_count
	#pragma HLS INTERFACE ap_none register port=clk_freq
	#pragma HLS INTERFACE ap_none register port=duration
	#pragma HLS INTERFACE ap_none register port=client_state

	// Make streams with structs compact -> no padding bits in the structs
	#pragma HLS aggregate compact=bit variable=tx_meta
	#pragma HLS aggregate compact=bit variable=tx_status

	// Required to buffer up to 512 TX responses
	static hls::stream<txRsp> tx_status_fifo("tx_status_fifo");
	#pragma HLS STREAM variable=tx_status_fifo depth=512
	tx_status_buffer(tx_status, tx_status_fifo);

	// Buffer incoming session IDs injected by SW
	static hls::stream<ap_uint<16>> session_ids_fifo("session_ids_fifo");
	#pragma HLS STREAM variable=session_ids_fifo depth=128
	session_id_buffer(session_ids, session_ids_fifo);

	// Required to buffer up to 512 TX meta data to support many sessions
	static hls::stream<txMeta> tx_meta_fifo("tx_meta_fifo");
	#pragma HLS STREAM variable=tx_meta_fifo depth=512
	tx_meta_buffer(tx_meta_fifo, tx_meta);

	// Required to buffer up to 512 TX data words to support many sessions
	static hls::stream<txData<AXIS_DATA_WIDTH>> tx_data_fifo("tx_data_fifo");
	#pragma HLS STREAM variable=tx_data_fifo depth=512
	tx_data_buffer<AXIS_DATA_WIDTH>(tx_data_fifo, tx_data);

	// Benchmark timer module
	static hls::stream<bool> start_signal("start_signal");
	#pragma HLS STREAM variable=start_signal depth=2

	static hls::stream<bool> stop_signal("stop_signal");
	#pragma HLS STREAM variable=stop_signal depth=2

	perf_timer(
		start_signal,
		stop_signal,
		clk_freq,
		duration
	);

	// Main client logic
	inst_client<AXIS_DATA_WIDTH>(
		session_ids_fifo,
		tx_meta_fifo,
		tx_data_fifo,
		tx_status_fifo,
		start_signal,
		stop_signal,
		start_client,
		n_sessions,
		pkg_word_count,
		client_state
	);
}
