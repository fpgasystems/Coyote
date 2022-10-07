/*
 * Copyright (c) 2022, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#include "rocev2.hpp"
#include <fstream>
#include <vector>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h> /* Added for the nonblocking socket */

#include "../axi_utils.hpp" //TODO why is this needed here
#include "../ib_transport_protocol/ib_transport_protocol.hpp"
#include "rocev2_config.hpp"

// #include "simulation.h" // multi-PE sim with pthread

using namespace hls;
#include "newFakeDram.hpp"
#include "simSwitch.hpp"


#define IBTPORT(ninst)                                            \
    static stream<txMeta> s_axis_sq_meta_n##ninst;                       \
    static stream<ackMeta> m_axis_rx_ack_meta_n##ninst;                  \
    static stream<qpContext> s_axis_qp_interface_n##ninst;               \
    static stream<ifConnReq> s_axis_qp_conn_interface_n##ninst;          \
    static stream<memCmd> m_axis_mem_write_cmd_n##ninst;                 \
    static stream<memCmd> m_axis_mem_read_cmd_n##ninst;                  \
    static stream<net_axis<DATA_WIDTH> > m_axis_mem_write_data_n##ninst; \
    static stream<net_axis<DATA_WIDTH> > s_axis_mem_read_data_n##ninst;  \
    ap_uint<32> regInvalidPsnDropCount_n##ninst;                  \
    ap_uint<32> regValidIbvCountRx_n##ninst;


#define IBTRUN(ninst)                               \
    ib_transport_protocol<DATA_WIDTH, ninst>(       \
        s_axis_rx_meta_n##ninst,                    \
        s_axis_rx_data_n##ninst,                    \
        m_axis_tx_meta_n##ninst,                    \
        m_axis_tx_data_n##ninst,                    \
        s_axis_sq_meta_n##ninst,                    \
        m_axis_rx_ack_meta_n##ninst,                \
        m_axis_mem_write_cmd_n##ninst,              \
        m_axis_mem_read_cmd_n##ninst,               \
        m_axis_mem_write_data_n##ninst,             \
        s_axis_mem_read_data_n##ninst,              \
        s_axis_qp_interface_n##ninst,               \
        s_axis_qp_conn_interface_n##ninst,          \
        regInvalidPsnDropCount_n##ninst,            \
        regValidIbvCountRx_n##ninst                 \
    );

#define SWITCHPORT(port)                                    \
    stream<ipUdpMeta> s_axis_rx_meta_n##port;               \
    stream<net_axis<DATA_WIDTH> > s_axis_rx_data_n##port;   \
    stream<ipUdpMeta> m_axis_tx_meta_n##port;               \
    stream<net_axis<DATA_WIDTH> > m_axis_tx_data_n##port;

#define SWITCHRUN()         \
    simSwitch<DATA_WIDTH>(  \
        s_axis_rx_meta_n0,  \
        s_axis_rx_data_n0,  \
        s_axis_rx_meta_n1,  \
        s_axis_rx_data_n1,  \
        m_axis_tx_meta_n0,  \
        m_axis_tx_data_n0,  \
        m_axis_tx_meta_n1,  \
        m_axis_tx_data_n1,  \
        ipAddrN0,           \
        ipAddrN1,           \
        0                   \
    );

#define DRAMRUN(ninst)                                                                                  \
if (!m_axis_mem_write_cmd_n##ninst.empty() && !writeCmdReady[ninst]){                                   \
    m_axis_mem_write_cmd_n##ninst.read(writeCmd[ninst]);                                                \
    writeCmdReady[ninst] = true;                                                                        \
}                                                                                                       \
if (writeCmdReady[ninst] && m_axis_mem_write_data_n##ninst.size() >= (writeCmd[ninst].len/8)){          \
    memoryN##ninst.processWrite(writeCmd[ninst], m_axis_mem_write_data_n##ninst);                       \
    writeCmdReady[ninst] = false;                                                                       \
}                                                                                                       \
if (!m_axis_mem_read_cmd_n##ninst.empty()){                                                             \
    m_axis_mem_read_cmd_n##ninst.read(readCmd[ninst]);                                                  \
    memoryN##ninst.processRead(readCmd[ninst], s_axis_mem_read_data_n##ninst);                          \
}

// // top module contains two ibt
// template <int DATA_WIDTH>
// void ib_transport_protocol_2nodes( 
//     stream<ipUdpMeta>& s_axis_rx_meta_n0,
//     stream<net_axis<DATA_WIDTH> >& s_axis_rx_data_n0,
//     stream<ipUdpMeta>& m_axis_tx_meta_n0,
//     stream<net_axis<DATA_WIDTH> >& m_axis_tx_data_n0,
//     stream<txMeta>& s_axis_sq_meta_n0,
//     stream<ackMeta>& m_axis_rx_ack_meta_n0,
//     stream<memCmd>& m_axis_mem_write_cmd_n0,
//     stream<memCmd>& m_axis_mem_read_cmd_n0,
//     stream<net_axis<DATA_WIDTH> >& m_axis_mem_write_data_n0,
//     stream<net_axis<DATA_WIDTH> >& s_axis_mem_read_data_n0,
//     stream<qpContext>& s_axis_qp_interface_n0,
//     stream<ifConnReq>& s_axis_qp_conn_interface_n0,
//     ap_uint<32>& regInvalidPsnDropCount_n0,
//     ap_uint<32>& regValidIbvCountRx_n0,
//     stream<ipUdpMeta>& s_axis_rx_meta_n1,
//     stream<net_axis<DATA_WIDTH> >& s_axis_rx_data_n1,
//     stream<ipUdpMeta>& m_axis_tx_meta_n1,
//     stream<net_axis<DATA_WIDTH> >& m_axis_tx_data_n1,
//     stream<txMeta>& s_axis_sq_meta_n1,
//     stream<ackMeta>& m_axis_rx_ack_meta_n1,
//     stream<memCmd>& m_axis_mem_write_cmd_n1,
//     stream<memCmd>& m_axis_mem_read_cmd_n1,
//     stream<net_axis<DATA_WIDTH> >& m_axis_mem_write_data_n1,
//     stream<net_axis<DATA_WIDTH> >& s_axis_mem_read_data_n1,
//     stream<qpContext>& s_axis_qp_interface_n1,
//     stream<ifConnReq>& s_axis_qp_conn_interface_n1,
//     ap_uint<32>& regInvalidPsnDropCount_n1,
//     ap_uint<32>& regValidIbvCountRx_n1
// ) {
//     #pragma HLS DATAFLOW

//         // Dataflow functions running in parallel
//         HLSLIB_DATAFLOW_INIT();
//         HLSLIB_DATAFLOW_FUNCTION(ib_transport_protocol<0, DATA_WIDTH>,
//             s_axis_rx_meta_n0,
//             s_axis_rx_data_n0,
//             m_axis_tx_meta_n0,
//             m_axis_tx_data_n0,
//             s_axis_sq_meta_n0,
//             m_axis_rx_ack_meta_n0,
//             m_axis_mem_write_cmd_n0,
//             m_axis_mem_read_cmd_n0,
//             m_axis_mem_write_data_n0,
//             s_axis_mem_read_data_n0,
//             s_axis_qp_interface_n0,
//             s_axis_qp_conn_interface_n0,
//             regInvalidPsnDropCount_n0,
//             regValidIbvCountRx_n0
//         );
//         HLSLIB_DATAFLOW_FUNCTION(ib_transport_protocol<1, DATA_WIDTH>, 
//             s_axis_rx_meta_n1,
//             s_axis_rx_data_n1,
//             m_axis_tx_meta_n1,
//             m_axis_tx_data_n1,
//             s_axis_sq_meta_n1,
//             m_axis_rx_ack_meta_n1,
//             m_axis_mem_write_cmd_n1,
//             m_axis_mem_read_cmd_n1,
//             m_axis_mem_write_data_n1,
//             s_axis_mem_read_data_n1,
//             s_axis_qp_interface_n1,
//             s_axis_qp_conn_interface_n1,
//             regInvalidPsnDropCount_n1,
//             regValidIbvCountRx_n1
//         );
//         HLSLIB_DATAFLOW_FINALIZE();

// }




int main(int argc, char* argv[]){
    // return testSimSwitch();

    // switch ports
    // SWITCHPORT(0);
    // SWITCHPORT(1);
    static stream<ipUdpMeta> s_axis_rx_meta_n0;
    static stream<net_axis<DATA_WIDTH> > s_axis_rx_data_n0;
    static stream<ipUdpMeta> m_axis_tx_meta_n0;
    static stream<net_axis<DATA_WIDTH> > m_axis_tx_data_n0;
    static stream<ipUdpMeta> s_axis_rx_meta_n1;
    static stream<net_axis<DATA_WIDTH> > s_axis_rx_data_n1;
    static stream<ipUdpMeta> m_axis_tx_meta_n1;
    static stream<net_axis<DATA_WIDTH> > m_axis_tx_data_n1;


    // interfaces
    IBTPORT(0);
    IBTPORT(1);


    // newFakeDRAM
    newFakeDRAM<DATA_WIDTH> memoryN0;
    newFakeDRAM<DATA_WIDTH> memoryN1;
    std::vector<bool> writeCmdReady {false, false};
    std::vector<memCmd> writeCmd(2);
    std::vector<memCmd> readCmd(2);


    ap_uint<128> ipAddrN0, ipAddrN1;
    ipAddrN0(127, 64) = 0xfe80000000000000;
    ipAddrN0(63, 0)   = 0x92e2baff0b01d4d2;
    ipAddrN1(127, 64) = 0xfe80000000000000;
    ipAddrN1(63, 0)   = 0x92e2baff0b01d4d3;

    // Create qp ctx
    // FIXME: confirm only swap the loc/rmt psn?
    qpContext ctxN0 = qpContext(READY_RECV, 0x00, 0xac701e, 0x2a19d6, 0, 0x00);
    qpContext ctxN1 = qpContext(READY_RECV, 0x00, 0x2a19d6, 0xac701e, 0, 0x00);
    ifConnReq connInfoN0 = ifConnReq(0, 0, ipAddrN1, 5000);
    ifConnReq connInfoN1 = ifConnReq(0, 0, ipAddrN0, 5000);

    s_axis_qp_interface_n0.write(ctxN0);
    s_axis_qp_interface_n1.write(ctxN1);
    s_axis_qp_conn_interface_n0.write(connInfoN0);
    s_axis_qp_conn_interface_n1.write(connInfoN1);

    int count = 0;
    //Make sure it is initialized
    while (count < 10)
    {

        // ib_transport_protocol_2nodes<DATA_WIDTH>(
        //     s_axis_rx_meta_n0,            
        //     s_axis_rx_data_n0,            
        //     m_axis_tx_meta_n0,            
        //     m_axis_tx_data_n0,            
        //     s_axis_sq_meta_n0,            
        //     m_axis_rx_ack_meta_n0,        
        //     m_axis_mem_write_cmd_n0,      
        //     m_axis_mem_read_cmd_n0,       
        //     m_axis_mem_write_data_n0,     
        //     s_axis_mem_read_data_n0,      
        //     s_axis_qp_interface_n0,       
        //     s_axis_qp_conn_interface_n0,  
        //     regInvalidPsnDropCount_n0,
        //     regValidIbvCountRx_n0,
        //     s_axis_rx_meta_n1,            
        //     s_axis_rx_data_n1,            
        //     m_axis_tx_meta_n1,            
        //     m_axis_tx_data_n1,            
        //     s_axis_sq_meta_n1,            
        //     m_axis_rx_ack_meta_n1,        
        //     m_axis_mem_write_cmd_n1,      
        //     m_axis_mem_read_cmd_n1,       
        //     m_axis_mem_write_data_n1,     
        //     s_axis_mem_read_data_n1,      
        //     s_axis_qp_interface_n1,       
        //     s_axis_qp_conn_interface_n1,  
        //     regInvalidPsnDropCount_n1,
        //     regValidIbvCountRx_n1
        // );


    ib_transport_protocol<DATA_WIDTH>(
        s_axis_rx_meta_n0,
        s_axis_rx_data_n0,
        m_axis_tx_meta_n0,
        m_axis_tx_data_n0,
        s_axis_sq_meta_n0,
        m_axis_rx_ack_meta_n0,
        m_axis_mem_write_cmd_n0,
        m_axis_mem_read_cmd_n0,
        m_axis_mem_write_data_n0,
        s_axis_mem_read_data_n0,
        s_axis_qp_interface_n0,
        s_axis_qp_conn_interface_n0,
        regInvalidPsnDropCount_n0,
        regValidIbvCountRx_n0
    );

    ib_transport_protocol2<DATA_WIDTH>(
        s_axis_rx_meta_n1,
        s_axis_rx_data_n1,
        m_axis_tx_meta_n1,
        m_axis_tx_data_n1,
        s_axis_sq_meta_n1,
        m_axis_rx_ack_meta_n1,
        m_axis_mem_write_cmd_n1,
        m_axis_mem_read_cmd_n1,
        m_axis_mem_write_data_n1,
        s_axis_mem_read_data_n1,
        s_axis_qp_interface_n1,
        s_axis_qp_conn_interface_n1,
        regInvalidPsnDropCount_n1,
        regValidIbvCountRx_n1
    );



        count++;
    }

    // // issue cmd on n0 sq (RC_RDMA_WRITE_ONLY)
    // // FIXME: bit correct? 
    ap_uint<512> params;
    params(63,0)    = 0x000;    // laddr
    params(127,64)  = 0x100;    // raddr
    params(159,128) = 64;       // length
    s_axis_sq_meta_n0.write(txMeta(RC_RDMA_WRITE_ONLY, 0x00, 0, params));

    while (count < 20000)
    {

        // IBTRUN(0);
        // IBTRUN(1);

    ib_transport_protocol<DATA_WIDTH>(
        s_axis_rx_meta_n0,
        s_axis_rx_data_n0,
        m_axis_tx_meta_n0,
        m_axis_tx_data_n0,
        s_axis_sq_meta_n0,
        m_axis_rx_ack_meta_n0,
        m_axis_mem_write_cmd_n0,
        m_axis_mem_read_cmd_n0,
        m_axis_mem_write_data_n0,
        s_axis_mem_read_data_n0,
        s_axis_qp_interface_n0,
        s_axis_qp_conn_interface_n0,
        regInvalidPsnDropCount_n0,
        regValidIbvCountRx_n0
    );

    ib_transport_protocol2<DATA_WIDTH>(
        s_axis_rx_meta_n1,
        s_axis_rx_data_n1,
        m_axis_tx_meta_n1,
        m_axis_tx_data_n1,
        s_axis_sq_meta_n1,
        m_axis_rx_ack_meta_n1,
        m_axis_mem_write_cmd_n1,
        m_axis_mem_read_cmd_n1,
        m_axis_mem_write_data_n1,
        s_axis_mem_read_data_n1,
        s_axis_qp_interface_n1,
        s_axis_qp_conn_interface_n1,
        regInvalidPsnDropCount_n1,
        regValidIbvCountRx_n1
    );
        // // IBTRUN(1);
        // // SWITCHRUN();
        DRAMRUN(0);
        // DRAMRUN(1);

        // monitor the n1 rx
        PRTMETA(1);
        PRTDATA(1);

        // monitor the n0 rx
        PRTMETA(0);
        PRTDATA(0);

        // monitor the n1 tx
        PRTTXMETA(1);
        PRTTXDATA(1);

        // // monitor the n0 tx
        PRTTXMETA(0);
        PRTTXDATA(0);

        count++;
    }
    return 0;
}


































