`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   Host networking clock crossing
 *
 * The clock crossing from nclk -> aclk
 */
module host_networking_ccross_ul (
    // Network 
    AXI4S.m m_axis_host_tx_nclk, 
    AXI4S.s s_axis_host_rx_nclk, 

    // User 
    AXI4S.s s_axis_host_tx_aclk, 
    AXI4S.m m_axis_host_rx_aclk, 

    // Clock and Reset 
    input  wire             nclk,
    input  wire             nresetn,
    input  wire             aclk,
    input  wire             aresetn
); 

    // ---------------------------------------------------------------------------------------------------
    // Crossings
    // ---------------------------------------------------------------------------------------------------

    // TX-traffic clock crossing
    axis_data_fifo_host_networking_ccross_data_512 inst_host_tx_traffic (
        .m_axis_aclk(nclk), 
        .s_axis_aclk(aclk), 
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid(s_axis_host_tx_aclk.tvalid),
        .s_axis_tready(s_axis_host_tx_aclk.tready),
        .s_axis_tdata (s_axis_host_tx_aclk.tdata),
        .s_axis_tkeep (s_axis_host_tx_aclk.tkeep),
        .s_axis_tlast (s_axis_host_tx_aclk.tlast),
        .m_axis_tvalid(m_axis_host_tx_nclk.tvalid),
        .m_axis_tready(m_axis_host_tx_nclk.tready),
        .m_axis_tdata (m_axis_host_tx_nclk.tdata),
        .m_axis_tkeep (m_axis_host_tx_nclk.tkeep),
        .m_axis_tlast (m_axis_host_tx_nclk.tlast)
    ); 

    // RX-traffic clock crossing
    axis_data_fifo_host_networking_ccross_data_512 inst_host_rx_traffic (
        .m_axis_aclk(aclk), 
        .s_axis_aclk(nclk), 
        .s_axis_aresetn(nresetn),
        .s_axis_tvalid(s_axis_host_rx_nclk.tvalid),
        .s_axis_tready(s_axis_host_rx_nclk.tready),
        .s_axis_tdata (s_axis_host_rx_nclk.tdata),
        .s_axis_tkeep (s_axis_host_rx_nclk.tkeep),
        .s_axis_tlast (s_axis_host_rx_nclk.tlast),
        .m_axis_tvalid(m_axis_host_rx_aclk.tvalid),
        .m_axis_tready(m_axis_host_rx_aclk.tready),
        .m_axis_tdata (m_axis_host_rx_aclk.tdata),
        .m_axis_tkeep (m_axis_host_rx_aclk.tkeep),
        .m_axis_tlast (m_axis_host_rx_aclk.tlast)
    );

endmodule