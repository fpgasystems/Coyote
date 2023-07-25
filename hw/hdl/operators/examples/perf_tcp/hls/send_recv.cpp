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
#include "send_recv_config.hpp"
#include "send_recv.hpp"
#include <iostream>
#if defined( __VITIS_HLS__)
#include "ap_axi_sdata.h"
#endif

//Buffers responses coming from the TCP stack
void status_handler(hls::stream<appTxRsp>&				txStatus,
							hls::stream<appTxRsp>&	txStatusBuffer)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	if (!txStatus.empty())
	{
		appTxRsp resp = txStatus.read();
		txStatusBuffer.write(resp);
	}
}


void txMetaData_handler(hls::stream<appTxMeta>&	txMetaDataBuffer, 
							hls::stream<appTxMeta>& txMetaData)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	if (!txMetaDataBuffer.empty())
	{
		appTxMeta metaDataReq = txMetaDataBuffer.read();
		txMetaData.write(metaDataReq);
	}
}

template <int WIDTH>
void txDataBuffer_handler(hls::stream<net_axis<WIDTH> >& txDataBuffer,
							hls::stream<net_axis<WIDTH> >& txData)
{
	#pragma HLS PIPELINE II=1
	#pragma HLS INLINE off

	if (!txDataBuffer.empty())
	{
		net_axis<WIDTH> word = txDataBuffer.read();
		txData.write(word);
	}
}

template <int WIDTH>
void client(
				hls::stream<appTxMeta>&	txMetaDataBuffer,
				hls::stream<net_axis<WIDTH> >& 	txDataBuffer,
				hls::stream<appTxRsp>&	txStatus,
               	ap_uint<32> pkgWordCount,
				ap_uint<32> sessionID,
				ap_uint<32> transferSize,
				ap_uint<1> runTx
                )
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	enum txHandlerStateType {WAIT_CMD, CHECK_REQ, WRITE_PKG};
	static txHandlerStateType txHandlerState = WAIT_CMD;

	// static ap_uint<32> sessionID;
	// static ap_uint<32> transferSize;
	// static ap_uint<32> pkgWordCount;

	static ap_uint<16> length;
	static ap_uint<16> remaining_space;
	static ap_uint<8> error;
	static ap_uint<32> currentPkgWord = 0;
	static ap_uint<32> wordCnt = 0;

	static ap_uint<32> sentByteCnt = 0;


	static appTxMeta tx_meta_pkt;

	switch(txHandlerState)
	{
		case WAIT_CMD:
			if (runTx)
			{
				tx_meta_pkt.sessionID = sessionID;

				if (pkgWordCount*(512/8) > transferSize)
					tx_meta_pkt.length = transferSize;
				else
					tx_meta_pkt.length = pkgWordCount*(512/8);

				txMetaDataBuffer.write(tx_meta_pkt);

				txHandlerState = CHECK_REQ;
			}
		break;
		case CHECK_REQ:
			if (!txStatus.empty())
               {
                    appTxRsp txStatus_pkt = txStatus.read();
                    sessionID = txStatus_pkt.sessionID;
                    length = txStatus_pkt.length;
                    remaining_space = txStatus_pkt.remaining_space;
                    error = txStatus_pkt.error;
                    currentPkgWord = (length + (512/8) -1 ) >> 6; //current packet word length

                    //if no error, perpare the tx meta of the next packet
                    if (error == 0)
                    {
                         sentByteCnt = sentByteCnt + length;

                         if (sentByteCnt < transferSize)
                         {
                              tx_meta_pkt.sessionID = sessionID;

                              if (sentByteCnt + pkgWordCount*64 < transferSize )
                              {
                            	  tx_meta_pkt.length = pkgWordCount*(512/8);
                            	  // currentPkgWord = pkgWordCount;
                              }
                              else
                              {
                                  tx_meta_pkt.length = transferSize - sentByteCnt;
                                  // currentPkgWord = (transferSize - sentByteCnt)>>6;
                              }
                              
                              txMetaDataBuffer.write(tx_meta_pkt);
                        }
  						txHandlerState = WRITE_PKG;
                    }
                    //if error, resend the tx meta of current packet 
                    else
                    {
                         //Check if connection  was torn down
                         if (error == 1)
                         {
                              // std::cout << "Connection was torn down. " << sessionID << std::endl;
                         }
                         else
                         {
                              tx_meta_pkt.sessionID = sessionID;
                              tx_meta_pkt.length = length;
                              txMetaDataBuffer.write(tx_meta_pkt);
                         }
                    }
               }
		break;
		case WRITE_PKG:
			wordCnt ++;
			net_axis<WIDTH> currPkt;
			currPkt.data = 0xDEADBEEF;
			currPkt.keep = 0xFFFFFFFFFFFFFFFF;
			currPkt.last = (wordCnt == currentPkgWord);
			txDataBuffer.write(currPkt);
			if (wordCnt == currentPkgWord)
			{
				wordCnt = 0;
				if (sentByteCnt >= transferSize)
				{
					sentByteCnt = 0;
					currentPkgWord = 0;
					txHandlerState = WAIT_CMD;
				}
				else
				{
					txHandlerState = CHECK_REQ;
				}
            }	
		break;
	}

}


template <int WIDTH>
void server(	hls::stream<appNotification>&	notifications,
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


#if defined( __VITIS_HLS__)
void send_recv(		hls::stream<appNotification>& notifications,
					hls::stream<appReadRequest>& readRequest,
					hls::stream<ap_uint<16> >& rxMetaData,
					hls::stream<ap_axiu<DATA_WIDTH, 0, 0, 0> >& rxData,
					hls::stream<appTxMeta>& txMetaData,
					hls::stream<ap_axiu<DATA_WIDTH, 0, 0, 0> >& txData,
					hls::stream<appTxRsp>& txStatus,
					ap_uint<32>	pkgWordCount,
					ap_uint<32> sessionID,
					ap_uint<32> transferSize,
					ap_uint<1> runTx
					)

{
	#pragma HLS DATAFLOW disable_start_propagation
	#pragma HLS INTERFACE ap_ctrl_none port=return

	#pragma HLS INTERFACE axis register port=notifications name=s_axis_notifications
	#pragma HLS INTERFACE axis register port=readRequest name=m_axis_read_package
	#pragma HLS aggregate compact=bit variable=notifications
	#pragma HLS aggregate compact=bit variable=readRequest

	#pragma HLS INTERFACE axis register port=rxMetaData name=s_axis_rx_metadata
	#pragma HLS INTERFACE axis register port=rxData name=s_axis_rx_data

	#pragma HLS INTERFACE axis register port=txMetaData name=m_axis_tx_metadata
	#pragma HLS INTERFACE axis register port=txData name=m_axis_tx_data
	#pragma HLS INTERFACE axis register port=txStatus name=s_axis_tx_status
	#pragma HLS aggregate compact=bit variable=txMetaData
	#pragma HLS aggregate compact=bit variable=txStatus

	#pragma HLS INTERFACE ap_none register port=pkgWordCount
	#pragma HLS INTERFACE ap_none register port=sessionID
	#pragma HLS INTERFACE ap_none register port=transferSize
	#pragma HLS INTERFACE ap_none register port=runTx


	//This is required to buffer up to 1024 reponses => supporting up to 1024 connections
	static hls::stream<appTxRsp>	txStatusBuffer("txStatusBuffer");
	#pragma HLS STREAM variable=txStatusBuffer depth=512

	//This is required to buffer up to 512 tx_meta_data => supporting up to 512 connections
	static hls::stream<appTxMeta>	txMetaDataBuffer("txMetaDataBuffer");
	#pragma HLS STREAM variable=txMetaDataBuffer depth=512

	//This is required to buffer up to MAX_SESSIONS txData 
	static hls::stream<net_axis<DATA_WIDTH> >	txDataBuffer("txDataBuffer");
	#pragma HLS STREAM variable=txDataBuffer depth=512

	static hls::stream<net_axis<DATA_WIDTH> > rxData_internal;
	#pragma HLS STREAM depth=2 variable=rxData_internal

	static hls::stream<net_axis<DATA_WIDTH> > txData_internal;
	#pragma HLS STREAM depth=2 variable=txData_internal

	/*
	 * Client
	 */
	status_handler(txStatus, txStatusBuffer);
	txMetaData_handler(txMetaDataBuffer, txMetaData);
	txDataBuffer_handler(txDataBuffer, txData_internal);

	convert_axis_to_net_axis<DATA_WIDTH>(rxData, 
							rxData_internal);

	convert_net_axis_to_axis<DATA_WIDTH>(txData_internal, 
							txData);

	client<DATA_WIDTH>(
				txMetaDataBuffer,
				txDataBuffer,
				txStatusBuffer,
               	pkgWordCount,
				sessionID,
				transferSize,
				runTx
                );

	/*
	 * Server
	 */
	server<DATA_WIDTH>(	
			notifications,
			readRequest,
			rxMetaData,
			rxData_internal);

}
#else
void send_recv(		hls::stream<appNotification>& notifications,
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
					)

{
	#pragma HLS DATAFLOW disable_start_propagation
	#pragma HLS INTERFACE ap_ctrl_none port=return

	#pragma HLS INTERFACE axis register port=notifications name=s_axis_notifications
	#pragma HLS INTERFACE axis register port=readRequest name=m_axis_read_package
	#pragma HLS DATA_PACK variable=notifications
	#pragma HLS DATA_PACK variable=readRequest

	#pragma HLS INTERFACE axis register port=rxMetaData name=s_axis_rx_metadata
	#pragma HLS INTERFACE axis register port=rxData name=s_axis_rx_data

	#pragma HLS INTERFACE axis register port=txMetaData name=m_axis_tx_metadata
	#pragma HLS INTERFACE axis register port=txData name=m_axis_tx_data
	#pragma HLS INTERFACE axis register port=txStatus name=s_axis_tx_status
	#pragma HLS DATA_PACK variable=txMetaData
	#pragma HLS DATA_PACK variable=txStatus

	#pragma HLS INTERFACE ap_none register port=pkgWordCount
	#pragma HLS INTERFACE ap_none register port=sessionID
	#pragma HLS INTERFACE ap_none register port=transferSize
	#pragma HLS INTERFACE ap_none register port=runTx


	//This is required to buffer up to 1024 reponses => supporting up to 1024 connections
	static hls::stream<appTxRsp>	txStatusBuffer("txStatusBuffer");
	#pragma HLS STREAM variable=txStatusBuffer depth=512

	//This is required to buffer up to 512 tx_meta_data => supporting up to 512 connections
	static hls::stream<appTxMeta>	txMetaDataBuffer("txMetaDataBuffer");
	#pragma HLS STREAM variable=txMetaDataBuffer depth=512

	//This is required to buffer up to MAX_SESSIONS txData 
	static hls::stream<net_axis<DATA_WIDTH> >	txDataBuffer("txDataBuffer");
	#pragma HLS STREAM variable=txDataBuffer depth=512

	/*
	 * Client
	 */
	status_handler(txStatus, txStatusBuffer);
	txMetaData_handler(txMetaDataBuffer, txMetaData);
	txDataBuffer_handler(txDataBuffer, txData);

	client<DATA_WIDTH>(
				txMetaDataBuffer,
				txDataBuffer,
				txStatusBuffer,
               	pkgWordCount,
				sessionID,
				transferSize,
				runTx
                );

	/*
	 * Server
	 */
	server<DATA_WIDTH>(	
			notifications,
			readRequest,
			rxMetaData,
			rxData);

}
#endif