#include "tcp_perf_server.hpp"


template <int WIDTH>
void rxData_handler(hls::stream<ap_axiu<WIDTH, 0, 0, 0> >& input,
					hls::stream<net_axis<WIDTH> >& output)
{
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	ap_axiu<WIDTH, 0, 0, 0> inputWord;
	net_axis<WIDTH> outputWord;

	if (!input.empty())
	{
		inputWord = input.read();
		outputWord.data = inputWord.data;
		outputWord.keep = inputWord.keep;
		outputWord.last = inputWord.last;
		output.write(outputWord);
	}
}

template <int WIDTH>
void inst_server(
				hls::stream<appNotification>&	notifications,
				hls::stream<appReadRequest>&	readRequest,
				hls::stream<ap_uint<16> >&		rxMetaData,
				hls::stream<net_axis<WIDTH> >&	rxData)
{
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off


	enum consumeFsmStateType {WAIT_PKG, CONSUME};
	static consumeFsmStateType  serverFsmState = WAIT_PKG;


	if (!notifications.empty())
	{
		appNotification notification = notifications.read();

		if (notification.length != 0)
		{
			readRequest.write(appReadRequest(notification.sessionID, notification.length));
		}
	}

	switch (serverFsmState)
	{
	case WAIT_PKG:
		if (!rxMetaData.empty() && !rxData.empty())
		{
			rxMetaData.read();
			net_axis<WIDTH> receiveWord = rxData.read();
			if (!receiveWord.last)
			{
				serverFsmState = CONSUME;
			}
		}
		break;
	case CONSUME:
		if (!rxData.empty())
		{
			net_axis<WIDTH> receiveWord = rxData.read();
			if (receiveWord.last)
			{
				serverFsmState = WAIT_PKG;
			}
		}
		break;
	}
}


void tcp_perf_server(
					hls::stream<appNotification>& notifications,
					hls::stream<appReadRequest>& readRequest,
					hls::stream<ap_uint<16> >& rxMetaData,
					hls::stream<ap_axiu<DATA_WIDTH, 0, 0, 0> >& rxData){
						
	#pragma HLS DATAFLOW disable_start_propagation
	#pragma HLS INTERFACE ap_ctrl_none port=return

	#pragma HLS INTERFACE axis register port=notifications name=s_axis_notifications
	#pragma HLS INTERFACE axis register port=readRequest name=m_axis_read_package
	#pragma HLS aggregate compact=bit variable=notifications
	#pragma HLS aggregate compact=bit variable=readRequest

	#pragma HLS INTERFACE axis register port=rxMetaData name=s_axis_rx_metadata
	#pragma HLS INTERFACE axis register port=rxData name=s_axis_rx_data

	static hls::stream<net_axis<DATA_WIDTH> > rxData_internal;
	#pragma HLS STREAM depth=2 variable=rxData_internal

	rxData_handler<DATA_WIDTH>(rxData, rxData_internal);

	/*
	 * Server
	 */
	inst_server<DATA_WIDTH>(
			notifications,
			readRequest,
			rxMetaData,
			rxData_internal);

}
