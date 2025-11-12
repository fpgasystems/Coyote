#include "tcp_perf_client.hpp"


void status_handler(hls::stream<appTxRsp>& txStatus,
	hls::stream<appTxRsp>&	txStatusBuffer)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	if (!txStatus.empty()){
		appTxRsp resp = txStatus.read();
		txStatusBuffer.write(resp);
	}
}

//Buffers open status coming from the TCP stack
void openStatus_handler(hls::stream<openStatus>& openConStatus,
	hls::stream<openStatus>&	openConStatusBuffer)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	if (!openConStatus.empty())
	{
		openStatus resp = openConStatus.read();
		openConStatusBuffer.write(resp);
	}
}

void txMetaData_handler(hls::stream<appTxMeta>&	txMetaDataBuffer, 
	hls::stream<appTxMeta>& txMetaData)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	if (!txMetaDataBuffer.empty()){
		appTxMeta metaDataReq = txMetaDataBuffer.read();
		txMetaData.write(metaDataReq);
	}
}

template <int WIDTH>
void txDataBuffer_handler(hls::stream<net_axis<WIDTH>>& txDataBuffer,
	hls::stream<ap_axiu<WIDTH, 0, 0, 0>>& txData)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	if (!txDataBuffer.empty()){
		net_axis<WIDTH> in = txDataBuffer.read();
		ap_axiu<WIDTH,0,0,0> out;
		out.data = in.data;
		out.keep = in.keep;
		out.last = in.last;
		txData.write(out);
	}
}

void perf_timer(
    hls::stream<bool>& startSignal,
    hls::stream<bool>& stopSignal,
	ap_uint<32>	userFrequency,
    ap_uint<32> timeInSeconds
){
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

    enum tstate_t { WAIT_START, RUN };
    static tstate_t st = WAIT_START;
    static ap_uint<64> cycles = 0;
    static ap_uint<64> target = 0;

    switch (st) {
    case WAIT_START:
        if (!startSignal.empty()) {
            startSignal.read();
            cycles = 0;
			target = (ap_uint<64>)userFrequency * (ap_uint<64>)timeInSeconds;
            st = RUN;
        }
        break;

    case RUN:
        if (cycles >= target) {
			if(!stopSignal.full()){
				stopSignal.write(true);
				st = WAIT_START;
			}
        }
		else{
			cycles++;
		}
        break;
    }
}

template <int WIDTH>
void inst_client(
				hls::stream<ipTuple>&				openConnection,
            	hls::stream<openStatus>& 			openConStatusBuffer,
				hls::stream<ap_uint<16> >&			closeConnection,
				hls::stream<appTxMeta>&				txMetaDataBuffer,
				hls::stream<net_axis<WIDTH> >& 		txDataBuffer,
				hls::stream<appTxRsp>&				txStatus,
				hls::stream<bool>& 					startSignal,
				hls::stream<bool>& 					stopSignal,
				ap_uint<1>							runTx,
				ap_uint<16>							numSessions,
				ap_uint<32>							pkgWordCount,
				ap_uint<32>							serverIpAddress,
				ap_uint<32>&						totalWord,
				ap_uint<4>&							state)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	enum perfFsmStateType { IDLE, INIT_CON, WAIT_CON, CONSTRUCT_HEADER, INIT_RUN, CHECK_REQ, START_PKG, WRITE_PKG, CHECK_TIME };
	static perfFsmStateType perfFsmState = IDLE;

	static ap_uint<16> currentSessionID;
	static ap_uint<16> numConnections;
	static ap_uint<16> openTrial;
	static ap_uint<16> openReply;
	static ap_uint<16> sessionIt;
	static ap_uint<16> closeIt;
	static ap_uint<32> wordCount;
	static bool        stopSend;
	static ap_uint<32> totalWord_int;
	totalWord = totalWord_int;
	static bool			endTx;

	if (!stopSignal.empty()) {
        endTx = stopSignal.read();
    }

	switch (perfFsmState){
		case IDLE:
			if(runTx){
				openTrial = 0;
				openReply = 0;

				currentSessionID = 0;
				numConnections = 0;
				openTrial = 0;
				openReply = 0;
				sessionIt = 0;
				closeIt = 0;
				wordCount = 0;
				totalWord = 0;
				totalWord_int = 0;
				endTx = false;
				stopSend      	= false;
				perfFsmState 	= INIT_CON;
			}
		break;
		
		case INIT_CON:{
			ipTuple openTuple;
			openTuple.ip_address = serverIpAddress;
			openTuple.ip_port = 5001;
			openTrial++;
			openConnection.write(openTuple);
			if(openTrial == numSessions){
				perfFsmState = WAIT_CON;
			}
		}
		break;

		case WAIT_CON:
			if(openReply == numSessions){
				startSignal.write(true);
				sessionIt = 0;
				perfFsmState   = CONSTRUCT_HEADER;
			}
			else if(!openConStatusBuffer.empty()){
				openStatus status = openConStatusBuffer.read();
				if(status.success){
					txMetaDataBuffer.write(appTxMeta(status.sessionID, WIDTH/8));
					numConnections++;
				}
				openReply++;
			}
		break;

		case CONSTRUCT_HEADER:
			if (sessionIt == numConnections)
			{
				sessionIt = 0;
				perfFsmState = CHECK_REQ;
			}
			else if (!txStatus.empty())
			{
				appTxRsp resp = txStatus.read();
				if (resp.error == 0){ // OK
					currentSessionID = resp.sessionID;
					perfFsmState = INIT_RUN;
				}
				else if (resp.error == 1) { // failed
					numConnections--;
				}
			}			
		break;
		case INIT_RUN:
			if(!txDataBuffer.full() && !txMetaDataBuffer.full()){
				net_axis<WIDTH> headerWord;
				headerWord.data = 0;
				headerWord.last = 1;
				for (int i = 0; i < (WIDTH/64); i++)
				{
					#pragma HLS UNROLL
					headerWord.keep(i*8+7, i*8) = 0xff;
				}
				txDataBuffer.write(headerWord);
				txMetaDataBuffer.write(appTxMeta(currentSessionID, pkgWordCount*(WIDTH/8)));
				sessionIt++;
				perfFsmState = CONSTRUCT_HEADER;
			}
		break;
		case CHECK_REQ:
			if(closeIt == numConnections){
				perfFsmState = IDLE;
			}
			else if (!txStatus.empty())
			{
				appTxRsp resp = txStatus.read();
				if (resp.error == 0){
					currentSessionID = resp.sessionID;
					perfFsmState = START_PKG;
				}
				else{	
					if (resp.error == 1){
						numConnections--;
					}
					else if(endTx){ // Stop Sending Packets : 
						closeConnection.write(resp.sessionID);
						closeIt++;

					}
					else{
						txMetaDataBuffer.write(appTxMeta(resp.sessionID, pkgWordCount*(WIDTH/8)));
					}
				}
			}
		break;
		case START_PKG:{
			if (!endTx){
				txMetaDataBuffer.write(appTxMeta(currentSessionID, pkgWordCount*(WIDTH/8)));
			}
			else{
				stopSend = true;
			}
			net_axis<WIDTH> currWord;
			for (int i = 0; i < (WIDTH/64); i++)
			{
				#pragma HLS UNROLL
				currWord.data(i*64+63, i*64) = 0x3736353433323130ULL;
				currWord.keep(i*8+7, i*8) = 0xff;
			}
			wordCount = 1;
			currWord.last = (pkgWordCount == 1);
			txDataBuffer.write(currWord);
			if (currWord.last)
			{
				totalWord_int += pkgWordCount;
				wordCount = 0;
				perfFsmState = CHECK_TIME;
			}
			else perfFsmState = WRITE_PKG;
		}
		break;
		case WRITE_PKG:
		{
			wordCount++;
			net_axis<WIDTH> currWord;
			for (int i = 0; i < (WIDTH/64); i++) 
			{
				#pragma HLS UNROLL
				currWord.data(i*64+63, i*64) = 0x3736353433323130ULL;
				currWord.keep(i*8+7, i*8) = 0xff;
			}
			currWord.last = (wordCount == pkgWordCount);
			txDataBuffer.write(currWord);
			if (currWord.last)
			{
				totalWord_int += pkgWordCount;
				wordCount = 0;
				perfFsmState = CHECK_TIME;
			}
		}
		break;
		case CHECK_TIME:
		{
			if (stopSend)
			{
				if(closeIt == numConnections){
					perfFsmState = IDLE;
				}
				else{
					closeConnection.write(currentSessionID);
					closeIt++;
					perfFsmState = CHECK_REQ;
				}
			}
			else{
				perfFsmState = CHECK_REQ;
			}
		}
		break;
	}
	state = (ap_uint<4>)perfFsmState;
}


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
					ap_uint<4>&		state_debug)

{
	#pragma HLS DATAFLOW disable_start_propagation
	#pragma HLS INTERFACE ap_ctrl_none port=return

	#pragma HLS INTERFACE axis register port=openConnection name=m_axis_open_connection
	#pragma HLS INTERFACE axis register port=openConStatus name=s_axis_open_status
	#pragma HLS aggregate compact=bit variable=openConnection
	#pragma HLS aggregate compact=bit variable=openConStatus

	#pragma HLS INTERFACE axis register port=closeConnection name=m_axis_close_connection

	#pragma HLS INTERFACE axis register port=txMetaData name=m_axis_tx_meta
	#pragma HLS INTERFACE axis register port=txData name=m_axis_tx_data
	#pragma HLS INTERFACE axis register port=txStatus name=s_axis_tx_status
	#pragma HLS aggregate compact=bit variable=txMetaData
	#pragma HLS aggregate compact=bit variable=txStatus

	#pragma HLS INTERFACE ap_none register port=runTx
	#pragma HLS INTERFACE ap_none register port=numSessions
	#pragma HLS INTERFACE ap_none register port=pkgWordCount
	#pragma HLS INTERFACE ap_none register port=serverIpAddress
	#pragma HLS INTERFACE ap_none register port=userFrequency
	#pragma HLS INTERFACE ap_none register port=timeInSeconds
	#pragma HLS INTERFACE ap_none register port=totalWord
	#pragma HLS INTERFACE ap_none register port=state_debug

	//This is required to buffer up to 512 reponses
	static hls::stream<appTxRsp>	txStatusBuffer("txStatusBuffer");
	#pragma HLS STREAM variable=txStatusBuffer depth=512

	//This is required to buffer up to 512 reponses => supporting up to 128 connections
	static hls::stream<openStatus>	openConStatusBuffer("openConStatusBuffer");
	#pragma HLS STREAM variable=openConStatusBuffer depth=512

	//This is required to buffer up to 512 tx_meta_data => supporting up to 128 connections
	static hls::stream<appTxMeta>	txMetaDataBuffer("txMetaDataBuffer");
	#pragma HLS STREAM variable=txMetaDataBuffer depth=512

	//This is required to buffer up to MAX_SESSIONS txData 
	static hls::stream<net_axis<DATA_WIDTH>>	txDataBuffer("txDataBuffer");
	#pragma HLS STREAM variable=txDataBuffer depth=512
	
	static hls::stream<bool>		startSignal("startSignal");
	static hls::stream<bool>		stopSignal("stopSignal");
	#pragma HLS STREAM variable=startSignal depth=2
	#pragma HLS STREAM variable=stopSignal depth=2

	status_handler(txStatus, txStatusBuffer);
	openStatus_handler(openConStatus, openConStatusBuffer);
	txMetaData_handler(txMetaDataBuffer, txMetaData);
	txDataBuffer_handler<DATA_WIDTH>(txDataBuffer, txData);


	perf_timer(
		startSignal,
		stopSignal,
		userFrequency,
		timeInSeconds
	);

	/*
	 * client
	 */
	inst_client<DATA_WIDTH>(	
		openConnection,
		openConStatusBuffer,
		closeConnection,
		txMetaDataBuffer,
		txDataBuffer,
		txStatusBuffer,
		startSignal,
		stopSignal,
		runTx,
		numSessions,
		pkgWordCount,
		serverIpAddress,
		totalWord,
		state_debug);

}
