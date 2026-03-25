/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
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

`timescale 1ns / 1ps

import lynxTypes::*;

module network_module_dcmac (
    input  wire         aclk,
    input  wire         aresetn,

    input  wire         gt_refclk_p,
    input  wire         gt_refclk_n,
    
    input  wire [3:0]   gt_rxp_in,
    input  wire [3:0]   gt_rxn_in,
    output wire [3:0]   gt_txp_out,
    output wire [3:0]   gt_txn_out,
	
    AXI4S.m             m_axis_net_rx,
    AXI4S.s             s_axis_net_tx
);

// TX
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) tx_axis_int (.aclk(aclk), .aresetn(aresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) tx_axis_dcmac (.aclk(aclk), .aresetn(aresetn));

ethernet_frame_padding_512_ip ethernet_frame_padding_inst (
    .ap_clk(aclk),
    .ap_rst_n(aresetn),
    .m_axis_TVALID(tx_axis_int.tvalid),
    .m_axis_TREADY(tx_axis_int.tready),
    .m_axis_TDATA(tx_axis_int.tdata),
    .m_axis_TKEEP(tx_axis_int.tkeep),
    .m_axis_TLAST(tx_axis_int.tlast),
    .s_axis_TVALID(s_axis_net_tx.tvalid),
    .s_axis_TREADY(s_axis_net_tx.tready),
    .s_axis_TDATA(s_axis_net_tx.tdata),
    .s_axis_TKEEP(s_axis_net_tx.tkeep),
    .s_axis_TLAST(s_axis_net_tx.tlast)
);

axis_reg_array #(.N_STAGES(2)) inst_reg_tx (.aclk(aclk), .aresetn(aresetn), .s_axis(tx_axis_int), .m_axis(tx_axis_dcmac));

// RX
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rx_axis_dcmac (.aclk(aclk), .aresetn(aresetn));
axis_reg_array #(.N_STAGES(2)) inst_reg_rx (.aclk(aclk), .aresetn(aresetn), .s_axis(rx_axis_dcmac), .m_axis(m_axis_net_rx));

// DCMAC Wrapper
dcmac_versal_axis_wrapper dcmac_wrapper_inst (
    // Clock, reset
    .aclk(aclk),
    .aresetn(aresetn),
    
    // TX data
    .s_axis_tx_tdata(tx_axis_dcmac.tdata),
    .s_axis_tx_tkeep(tx_axis_dcmac.tkeep),
    .s_axis_tx_tlast(tx_axis_dcmac.tlast),
    .s_axis_tx_tready(tx_axis_dcmac.tready),
    .s_axis_tx_tvalid(tx_axis_dcmac.tvalid),
    
    // RX data
    .m_axis_rx_tdata(rx_axis_dcmac.tdata),
    .m_axis_rx_tkeep(rx_axis_dcmac.tkeep),
    .m_axis_rx_tlast(rx_axis_dcmac.tlast),
    .m_axis_rx_tready(rx_axis_dcmac.tready),
    .m_axis_rx_tvalid(rx_axis_dcmac.tvalid),
     
    // GT clock
    .gt_clk_clk_n(gt_refclk_n),
    .gt_clk_clk_p(gt_refclk_p),
    
    // GT signals
    .gt_grx_n(gt_rxn_in),
    .gt_grx_p(gt_rxp_in),
    .gt_gtx_n(gt_txn_out),
    .gt_gtx_p(gt_txp_out)
); 

endmodule
