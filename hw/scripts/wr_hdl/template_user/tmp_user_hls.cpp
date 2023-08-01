#include <hls_stream.h>
#include <stdint.h>
#include <fstream>
#include <iomanip>
#if defined( __VITIS_HLS__)
#include "ap_axi_sdata.h"
#endif

#include "ap_int.h"
#include "lynx_hls_c0_0.hpp" // TODO: Adjust the vFPGA ids

/**
 * User logic
 *
 */
#if defined( __VITIS_HLS__) // FIX: These interfaces are a mess, should just drop the support for vivado hls

void design_user_hls_c0_0_top ( // TODO: Adjust the vFPGA ids
#ifdef EN_BPSS
    // Bypass descriptors
    hls::stream<reqIntf>& bpss_rd_req,
    hls::stream<reqIntf>& bpss_wr_req,
    hls::stream<doneIntf>& bpss_rd_done,
    hls::stream<doneIntf>& bpss_wr_done,

#endif
#ifdef EN_STRM
    // Host streams
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_host_0_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_host_0_src,

#endif
#ifdef EN_MEM
    // Card streams
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_card_0_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_card_0_src,

#endif
#ifdef EN_RDMA_0
    // RDMA descriptors
    hls::stream<reqIntf>& rdma_0_rd_req,
    hls::stream<reqIntf>& rdma_0_wr_req,

    // RDMA rq and sq
    hls::stream<rdmaIntf>& rdma_0_rq,
    hls::stream<rdmaIntf>& rdma_0_sq,

    // RDMA streams
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_rdma_0_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_rdma_0_src,
    
#endif
#ifdef EN_RDMA_1
    // RDMA descriptors
    hls::stream<reqIntf>& rdma_1_rd_req,
    hls::stream<reqIntf>& rdma_1_wr_req,

    // RDMA rq and sq
    hls::stream<rdmaIntf>& rdma_1_rq,
    hls::stream<rdmaIntf>& rdma_1_sq,

    // RDMA streams
    hhls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_rdma_1_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_rdma_1_src,

#endif
#ifdef EN_TCP_0
    // TCP/IP descriptors
    hls::stream<tcpNotifyIntf>& tcp_0_notify,
    hls::stream<tcpRdPkgIntf>& tcp_0_rd_package,
    hls::stream<tcpRxMetaIntf>& tcp_0_rx_meta,
    hls::stream<tcpTxMetaIntf>& tcp_0_tx_meta,
    hls::stream<tcpTxStatIntf>& tcp_0_tx_stat,

    // TCP/IP streams
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_tcp_0_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_tcp_0_src,

#endif
#ifdef EN_TCP_1
    // TCP/IP descriptors
    hls::stream<tcpNotifyIntf>& tcp_1_notify,
    hls::stream<tcpRdPkgIntf>& tcp_1_rd_package,
    hls::stream<tcpRxMetaIntf>& tcp_1_rx_meta,
    hls::stream<tcpTxMetaIntf>& tcp_1_tx_meta,
    hls::stream<tcpTxStatIntf>& tcp_1_tx_stat,

    // TCP/IP streams
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_tcp_1_sink,
    hls::stream<ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> >& axis_tcp_1_src,

#endif
    ap_uint<64> axi_ctrl
) {
    #pragma HLS DATAFLOW disable_start_propagation
    #pragma HLS INTERFACE ap_ctrl_none port=return  

#ifdef EN_BPSS
    #pragma HLS INTERFACE axis register port=bpss_rd_req name=m_bpss_rd_req
    #pragma HLS INTERFACE axis register port=bpss_wr_req name=m_bpss_wr_req
    #pragma HLS aggregate variable=bpss_rd_req compact=bit
    #pragma HLS aggregate variable=bpss_wr_req compact=bit
    #pragma HLS INTERFACE axis register port=bpss_rd_done name=s_bpss_rd_done
    #pragma HLS INTERFACE axis register port=bpss_wr_done name=s_bpss_wr_done
    #pragma HLS aggregate variable=bpss_rd_done compact=bit
    #pragma HLS aggregate variable=bpss_wr_done compact=bit

#endif
#ifdef EN_STRN
    #pragma HLS INTERFACE axis register port=axis_host_0_sink name=s_axis_host_0_sink
    #pragma HLS INTERFACE axis register port=axis_host_0_src name=m_axis_host_0_src

#endif
#ifdef EN_MEM
    #pragma HLS INTERFACE axis register port=axis_card_0_sink name=s_axis_card_0_sink
    #pragma HLS INTERFACE axis register port=axis_card_0_src name=m_axis_card_0_src

#endif
#ifdef EN_RDMA_0
    #pragma HLS INTERFACE axis register port=rdma_0_rd_req name=s_rdma_0_rd_req
    #pragma HLS INTERFACE axis register port=rdma_0_wr_req name=s_rdma_0_wr_req
    #pragma HLS aggregate variable=rdma_0_rd_req compact=bit
    #pragma HLS aggregate variable=rdma_0_wr_req compact=bit
    #pragma HLS INTERFACE axis register port=rdma_0_rq name=rdma_0_rq
    #pragma HLS INTERFACE axis register port=rdma_0_sq name=rdma_0_sq
    #pragma HLS aggregate variable=rdma_0_rq compact=bit
    #pragma HLS aggregate variable=rdma_0_sq compact=bit
    #pragma HLS INTERFACE axis register port=axis_rdma_0_sink name=s_axis_rdma_0_sink
    #pragma HLS INTERFACE axis register port=axis_rdma_0_src name=m_axis_rdma_0_src

#endif
#ifdef EN_RDMA_1
    #pragma HLS INTERFACE axis register port=rdma_1_rd_req name=s_rdma_1_rd_req
    #pragma HLS INTERFACE axis register port=rdma_1_wr_req name=s_rdma_1_wr_req
    #pragma HLS aggregate variable=rdma_1_rd_req compact=bit
    #pragma HLS aggregate variable=rdma_1_wr_req compact=bit
    #pragma HLS INTERFACE axis register port=rdma_1_rq name=rdma_1_rq
    #pragma HLS INTERFACE axis register port=rdma_1_sq name=rdma_1_sq
    #pragma HLS aggregate variable=rdma_1_rq compact=bit
    #pragma HLS aggregate variable=rdma_1_sq compact=bit
    #pragma HLS INTERFACE axis register port=axis_rdma_1_sink name=s_axis_rdma_1_sink
    #pragma HLS INTERFACE axis register port=axis_rdma_1_src name=m_axis_rdma_1_src

#endif
#ifdef EN_TCP_0
    #pragma HLS INTERFACE axis register port=tcp_0_notify name=s_tcp_0_notify
    #pragma HLS INTERFACE axis register port=tcp_0_rd_pkg name=m_tcp_0_rd_pkg
    #pragma HLS INTERFACE axis register port=tcp_0_rx_meta name=m_tcp_0_rx_meta
    #pragma HLS INTERFACE axis register port=tcp_0_tx_meta name=m_tcp_0_tx_meta
    #pragma HLS INTERFACE axis register port=tcp_0_tx_stat name=s_tcp_0_tx_stat
    #pragma HLS INTERFACE axis register port=axis_tcp_0_src name=m_axis_tcp_0_src
    #pragma HLS INTERFACE axis register port=axis_tcp_0_sink name=s_axis_tcp_0_sink
    #pragma HLS aggregate variable=tcp_0_notify compact=bit
    #pragma HLS aggregate variable=tcp_0_rd_pkg compact=bit
    #pragma HLS aggregate variable=tcp_0_rx_meta compact=bit
    #pragma HLS aggregate variable=tcp_0_tx_meta compact=bit
    #pragma HLS aggregate variable=tcp_0_tx_stat compact=bit

#endif
#ifdef EN_TCP_1
    #pragma HLS INTERFACE axis register port=tcp_1_notify name=s_tcp_1_notify
    #pragma HLS INTERFACE axis register port=tcp_1_rd_pkg name=m_tcp_1_rd_pkg
    #pragma HLS INTERFACE axis register port=tcp_1_rx_meta name=m_tcp_1_rx_meta
    #pragma HLS INTERFACE axis register port=tcp_1_tx_meta name=m_tcp_1_tx_meta
    #pragma HLS INTERFACE axis register port=tcp_1_tx_stat name=s_tcp_1_tx_stat
    #pragma HLS INTERFACE axis register port=axis_tcp_1_src name=m_axis_tcp_1_src
    #pragma HLS INTERFACE axis register port=axis_tcp_1_sink name=s_axis_tcp_1_sink
    #pragma HLS aggregate variable=tcp_1_notify compact=bit
    #pragma HLS aggregate variable=tcp_1_rd_pkg compact=bit
    #pragma HLS aggregate variable=tcp_1_rx_meta compact=bit
    #pragma HLS aggregate variable=tcp_1_tx_meta compact=bit
    #pragma HLS aggregate variable=tcp_1_tx_stat compact=bit

#endif
    
    #pragma HLS INTERFACE s_axilite port=return     bundle=control
    //#pragma HLS INTERFACE s_axilite port=axi_ctrl_a bundle=control
    //#pragma HLS INTERFACE s_axilite port=axi_ctrl_b bundle=control
    //#pragma HLS INTERFACE s_axilite port=axi_ctrl_c bundle=control

    //
    // User logic 
    //

    // Default tie-off
#ifdef EN_BPSS
    bpss_rd_req.write(reqIntf());
    bpss_wr_req.write(reqIntf());
    doneIntf tmp_bpss_rd_done = bpss_rd_done.read();
    doneIntf tmp_bpss_wr_done = bpss_wr_done.read();

#endif
#ifdef EN_STRM
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> tmp_axis_host_0_sink = axis_host_0_sink.read();
    axis_host_0_src.write(ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0>());

#endif
#ifdef EN_MEM
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> tmp_axis_card_0_sink = axis_card_0_sink.read();
    axis_card_0_src.write(ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0>());

#endif
#ifdef EN_RDMA_0
    reqIntf tmp_rdma_0_rd_req = rdma_0_rd_req.read();
    reqIntf tmp_rdma_0_wr_req = rdma_0_wr_req.read();
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> tmp_axis_rdma_0_sink = axis_rdma_0_sink.read();
    axis_rdma_0_src.write(ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0>());
    rdmaIntf tmp_rdma_0_rq = rdma_0_rq.read();
    rdma_0_sq.write(rdmaIntf());

#endif   
#ifdef EN_RDMA_1
    reqIntf tmp_rdma_1_rd_req = rdma_1_rd_req.read();
    reqIntf tmp_rdma_1_wr_req = rdma_1_wr_req.read();
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> tmp_axis_rdma_1_sink = axis_rdma_1_sink.read();
    axis_rdma_1_src.write(ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0>());
    rdmaIntf tmp_rdma_1_rq = rdma_1_rq.read();
    rdma_1_sq.write(rdmaIntf());

#endif   
#ifdef EN_TCP_0
    tcpNotifyIntf tmp_tcp_0_notify = tcp_0_notify.read();
    tcp_0_rd_pkg.write(tcpRdPkgIntf());
    tcp_0_rx_meta.write(tcpRxMetaIntf());
    tcp_0_tx_meta.write(tcpTxMetaIntf());
    tcpTxStatIntf tmp_tcp_0_tx_stat = tcp_0_tx_stat.read();
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> tmp_axis_tcp_0_sink = axis_tcp_0_sink.read();
    axis_tcp_0_src.write(ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0>());

#endif
#ifdef EN_TCP_1
    tcpNotifyIntf tmp_tcp_1_notify = tcp_1_notify.read();
    tcp_1_rd_pkg.write(tcpRdPkgIntf());
    tcp_1_rx_meta.write(tcpRxMetaIntf());
    tcp_1_tx_meta.write(tcpTxMetaIntf());
    tcpTxStatIntf tmp_tcp_1_tx_stat = tcp_1_tx_stat.read();
    ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0> tmp_axis_tcp_0_sink = axis_tcp_1_sink.read();
    axis_tcp_1_src.write(ap_axiu<AXI_DATA_BITS, 0, PID_BITS, 0>());

#endif

}

#else 


void design_user_hls_c0_0_top ( // TODO: Adjust the vFPGA ids
#ifdef EN_BPSS
    // Bypass descriptors
    hls::stream<reqIntf>& bpss_rd_req,
    hls::stream<reqIntf>& bpss_wr_req,
    hls::stream<doneIntf>& bpss_rd_done,
    hls::stream<doneIntf>& bpss_wr_done,

#endif
#ifdef EN_STRM
    // Host streams
    hls::stream<axisIntf>& axis_host_0_sink,
    hls::stream<axisIntf>& axis_host_0_src,

#endif
#ifdef EN_MEM
    // Card streams
    hls::stream<axisIntf>& axis_card_0_sink,
    hls::stream<axisIntf>& axis_card_0_src,

#endif
#ifdef EN_RDMA_0
    // RDMA descriptors
    hls::stream<reqIntf>& rdma_0_rd_req,
    hls::stream<reqIntf>& rdma_0_wr_req,

    // RDMA rq and sq
    hls::stream<rdmaIntf>& rdma_0_rq,
    hls::stream<rdmaIntf>& rdma_0_sq,

    // RDMA streams
    hls::stream<axisIntf>& axis_rdma_0_sink,
    hls::stream<axisIntf>& axis_rdma_0_src,
    
#endif
#ifdef EN_RDMA_1
    // RDMA descriptors
    hls::stream<reqIntf>& rdma_1_rd_req,
    hls::stream<reqIntf>& rdma_1_wr_req,

    // RDMA rq and sq
    hls::stream<rdmaIntf>& rdma_1_rq,
    hls::stream<rdmaIntf>& rdma_1_sq,

    // RDMA streams
    hls::stream<axisIntf>& axis_rdma_1_sink,
    hls::stream<axisIntf>& axis_rdma_1_src,

#endif
#ifdef EN_TCP_0
    // TCP/IP descriptors
    hls::stream<tcpNotifyIntf>& tcp_0_notify,
    hls::stream<tcpRdPkgIntf>& tcp_0_rd_package,
    hls::stream<tcpRxMetaIntf>& tcp_0_rx_meta,
    hls::stream<tcpTxMetaIntf>& tcp_0_tx_meta,
    hls::stream<tcpTxStatIntf>& tcp_0_tx_stat,

    // TCP/IP streams
    hls::stream<axisIntf>& axis_tcp_0_sink,
    hls::stream<axisIntf>& axis_tcp_0_src,

#endif
#ifdef EN_TCP_1
    // TCP/IP descriptors
    hls::stream<tcpNotifyIntf>& tcp_1_notify,
    hls::stream<tcpRdPkgIntf>& tcp_1_rd_package,
    hls::stream<tcpRxMetaIntf>& tcp_1_rx_meta,
    hls::stream<tcpTxMetaIntf>& tcp_1_tx_meta,
    hls::stream<tcpTxStatIntf>& tcp_1_tx_stat,

    // TCP/IP streams
    hls::stream<axisIntf>& axis_tcp_1_sink,
    hls::stream<axisIntf>& axis_tcp_1_src,

#endif
    ap_uint<64> axi_ctrl
) {
    #pragma HLS DATAFLOW disable_start_propagation
    #pragma HLS INTERFACE ap_ctrl_none port=return  

#ifdef EN_BPSS
    #pragma HLS INTERFACE axis register port=bpss_rd_req name=m_bpss_rd_req
    #pragma HLS INTERFACE axis register port=bpss_wr_req name=m_bpss_wr_req
    #pragma HLS DATA_PACK variable=bpss_rd_req
    #pragma HLS DATA_PACK variable=bpss_wr_req
    #pragma HLS INTERFACE axis register port=bpss_rd_done name=s_bpss_rd_done
    #pragma HLS INTERFACE axis register port=bpss_wr_done name=s_bpss_wr_done
    #pragma HLS DATA_PACK variable=bpss_rd_done
    #pragma HLS DATA_PACK variable=bpss_wr_done

#endif
#ifdef EN_STRN
    #pragma HLS INTERFACE axis register port=axis_host_0_sink name=s_axis_host_0_sink
    #pragma HLS INTERFACE axis register port=axis_host_0_src name=m_axis_host_0_src

#endif
#ifdef EN_MEM
    #pragma HLS INTERFACE axis register port=axis_card_0_sink name=s_axis_card_0_sink
    #pragma HLS INTERFACE axis register port=axis_card_0_src name=m_axis_card_0_src

#endif
#ifdef EN_RDMA_0
    #pragma HLS INTERFACE axis register port=rdma_0_rd_req name=s_rdma_0_rd_req
    #pragma HLS INTERFACE axis register port=rdma_0_wr_req name=s_rdma_0_wr_req
    #pragma HLS DATA_PACK variable=rdma_0_rd_req
    #pragma HLS DATA_PACK variable=rdma_0_wr_req
    #pragma HLS INTERFACE axis register port=rdma_0_rq name=rdma_0_rq
    #pragma HLS INTERFACE axis register port=rdma_0_sq name=rdma_0_sq
    #pragma HLS DATA_PACK variable=rdma_0_rq
    #pragma HLS DATA_PACK variable=rdma_0_sq
    #pragma HLS INTERFACE axis register port=axis_rdma_0_sink name=s_axis_rdma_0_sink
    #pragma HLS INTERFACE axis register port=axis_rdma_0_src name=m_axis_rdma_0_src

#endif
#ifdef EN_RDMA_1
    #pragma HLS INTERFACE axis register port=rdma_1_rd_req name=s_rdma_1_rd_req
    #pragma HLS INTERFACE axis register port=rdma_1_wr_req name=s_rdma_1_wr_req
    #pragma HLS DATA_PACK variable=rdma_1_rd_req
    #pragma HLS DATA_PACK variable=rdma_1_wr_req
    #pragma HLS INTERFACE axis register port=rdma_1_rq name=rdma_1_rq
    #pragma HLS INTERFACE axis register port=rdma_1_sq name=rdma_1_sq
    #pragma HLS DATA_PACK variable=rdma_1_rq
    #pragma HLS DATA_PACK variable=rdma_1_sq
    #pragma HLS INTERFACE axis register port=axis_rdma_1_sink name=s_axis_rdma_1_sink
    #pragma HLS INTERFACE axis register port=axis_rdma_1_src name=m_axis_rdma_1_src

#endif
#ifdef EN_TCP_0
    #pragma HLS INTERFACE axis register port=tcp_0_notify name=s_tcp_0_notify
    #pragma HLS INTERFACE axis register port=tcp_0_rd_pkg name=m_tcp_0_rd_pkg
    #pragma HLS INTERFACE axis register port=tcp_0_rx_meta name=m_tcp_0_rx_meta
    #pragma HLS INTERFACE axis register port=tcp_0_tx_meta name=m_tcp_0_tx_meta
    #pragma HLS INTERFACE axis register port=tcp_0_tx_stat name=s_tcp_0_tx_stat
    #pragma HLS INTERFACE axis register port=axis_tcp_0_src name=m_axis_tcp_0_src
    #pragma HLS INTERFACE axis register port=axis_tcp_0_sink name=s_axis_tcp_0_sink
    #pragma HLS DATA_PACK variable=tcp_0_notify
    #pragma HLS DATA_PACK variable=tcp_0_rd_pkg
    #pragma HLS DATA_PACK variable=tcp_0_rx_meta
    #pragma HLS DATA_PACK variable=tcp_0_tx_meta
    #pragma HLS DATA_PACK variable=tcp_0_tx_stat

#endif
#ifdef EN_TCP_1
    #pragma HLS INTERFACE axis register port=tcp_1_notify name=s_tcp_1_notify
    #pragma HLS INTERFACE axis register port=tcp_1_rd_pkg name=m_tcp_1_rd_pkg
    #pragma HLS INTERFACE axis register port=tcp_1_rx_meta name=m_tcp_1_rx_meta
    #pragma HLS INTERFACE axis register port=tcp_1_tx_meta name=m_tcp_1_tx_meta
    #pragma HLS INTERFACE axis register port=tcp_1_tx_stat name=s_tcp_1_tx_stat
    #pragma HLS INTERFACE axis register port=axis_tcp_1_src name=m_axis_tcp_1_src
    #pragma HLS INTERFACE axis register port=axis_tcp_1_sink name=s_axis_tcp_1_sink
    #pragma HLS DATA_PACK variable=tcp_1_notify
    #pragma HLS DATA_PACK variable=tcp_1_rd_pkg
    #pragma HLS DATA_PACK variable=tcp_1_rx_meta
    #pragma HLS DATA_PACK variable=tcp_1_tx_meta
    #pragma HLS DATA_PACK variable=tcp_1_tx_stat

#endif
    
    #pragma HLS INTERFACE s_axilite port=return     bundle=control
    #pragma HLS INTERFACE s_axilite port=axi_ctrl_a bundle=control
    #pragma HLS INTERFACE s_axilite port=axi_ctrl_b bundle=control
    #pragma HLS INTERFACE s_axilite port=axi_ctrl_c bundle=control

    //
    // User logic 
    //

    // Default tie-off
#ifdef EN_BPSS
    bpss_rd_req.write(reqIntf());
    bpss_wr_req.write(reqIntf());
    doneIntf tmp_bpss_rd_done = bpss_rd_done.read();
    doneIntf tmp_bpss_wr_done = bpss_wr_done.read();

#endif
#ifdef EN_STRM
    axisIntf tmp_axis_host_0_sink = axis_host_0_sink.read();
    axis_host_0_src.write(axisIntf());

#endif
#ifdef EN_MEM
    axisIntf tmp_axis_card_0_sink = axis_card_0_sink.read();
    axis_card_0_src.write(axisIntf());

#endif
#ifdef EN_RDMA_0
    reqIntf tmp_rdma_0_rd_req = rdma_0_rd_req.read();
    reqIntf tmp_rdma_0_wr_req = rdma_0_wr_req.read();
    axisIntf tmp_axis_rdma_0_sink = axis_rdma_0_sink.read();
    axis_rdma_0_src.write(axisIntf());
    rdmaIntf tmp_rdma_0_rq = rdma_0_rq.read();
    rdma_0_sq.write(rdmaIntf());

#endif   
#ifdef EN_RDMA_1
    reqIntf tmp_rdma_1_rd_req = rdma_1_rd_req.read();
    reqIntf tmp_rdma_1_wr_req = rdma_1_wr_req.read();
    axisIntf tmp_axis_rdma_1_sink = axis_rdma_1_sink.read();
    axis_rdma_1_src.write(axisIntf());
    rdmaIntf tmp_rdma_1_rq = rdma_1_rq.read();
    rdma_1_sq.write(rdmaIntf());

#endif   
#ifdef EN_TCP_0
    tcpNotifyIntf tmp_tcp_0_notify = tcp_0_notify.read();
    tcp_0_rd_pkg.write(tcpRdPkgIntf());
    tcp_0_rx_meta.write(tcpRxMetaIntf());
    tcp_0_tx_meta.write(tcpTxMetaIntf());
    tcpTxStatIntf tmp_tcp_0_tx_stat = tcp_0_tx_stat.read();
    axisIntf tmp_axis_tcp_0_sink = axis_tcp_0_sink.read();
    axis_tcp_0_src.write(axisIntf());

#endif
#ifdef EN_TCP_1
    tcpNotifyIntf tmp_tcp_1_notify = tcp_1_notify.read();
    tcp_1_rd_pkg.write(tcpRdPkgIntf());
    tcp_1_rx_meta.write(tcpRxMetaIntf());
    tcp_1_tx_meta.write(tcpTxMetaIntf());
    tcpTxStatIntf tmp_tcp_1_tx_stat = tcp_1_tx_stat.read();
    axisIntf tmp_axis_tcp_1_sink = axis_tcp_1_sink.read();
    axis_tcp_1_src.write(axisIntf());

#endif

}

#endif 