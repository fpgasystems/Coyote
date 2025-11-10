/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

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

/**
 * @brief   Stripe adjusted CDMA
 *
 * Adjustment layer for 64-byte aligned striping. Both CDMA variations can be used. 
 * 
 *  @param DATA_BITS    Size of the data bus (both AXI and stream)
 *  @param ADDR_BITS    Size of the address bits
 */
module cdma_adj #(
    parameter integer                   DATA_BITS = AXI_DATA_BITS,
    parameter integer                   ADDR_BITS = AXI_ADDR_BITS
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    dmaIntf.s                           rd_CDMA,
    dmaIntf.s                           wr_CDMA,

    AXI4S.s                             s_axis_user,
    AXI4S.m                            m_axis_user,

    AXI4.m                             m_axi_card [N_MEM_CHAN]
);

`ifdef MULT_DDR_CHAN

    AXI4S #(.AXI4S_DATA_BITS(DATA_BITS)) axis_mux_cdma [N_MEM_CHAN] ();
    AXI4S #(.AXI4S_DATA_BITS(DATA_BITS)) axis_cdma_mux [N_MEM_CHAN] ();
    dmaIntf rd_CDMA_adj [N_MEM_CHAN] ();
    dmaIntf wr_CDMA_adj [N_MEM_CHAN] ();
    muxIntf #(.N_ID_BITS(N_MEM_CHAN_BITS), .ARB_DATA_BITS(DATA_BITS)) rd_mux_card ();
    muxIntf #(.N_ID_BITS(N_MEM_CHAN_BITS), .ARB_DATA_BITS(DATA_BITS)) wr_mux_card ();

    // Adjustments
    cdma_adj_cmd #(
        .DATA_BITS(DATA_BITS)
    ) inst_rd_cdma_adj_cmd (
        .aclk(aclk),
        .aresetn(aresetn),
        .CDMA(rd_CDMA),
        .CDMA_adj(rd_CDMA_adj),
        .s_mux_card(rd_mux_card)
    );

    cdma_adj_cmd #(
        .DATA_BITS(DATA_BITS)
    ) inst_wr_cdma_adj_cmd (
        .aclk(aclk),
        .aresetn(aresetn),
        .CDMA(wr_CDMA),
        .CDMA_adj(wr_CDMA_adj),
        .s_mux_card(wr_mux_card)
    );

    // Adjust to interface sink+src
    axis_mux_cdma_a_user_sink #(
        .DATA_BITS(DATA_BITS)
    ) inst_sink_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .m_mux_card(rd_mux_card), 
        .s_axis_user(s_axis_user),
        .m_axis_card(axis_mux_cdma)
    );

    axis_mux_cdma_a_user_src #(
        .DATA_BITS(DATA_BITS)
    ) inst_src_user (
        .aclk(aclk),
        .aresetn(aresetn),
        .m_mux_card(wr_mux_card), 
        .s_axis_card(axis_cdma_mux),
        .m_axis_user(m_axis_user)
    );

    // CDMA
    for(genvar i = 0; i < N_MEM_CHAN; i++) begin
        cdma #(
            .DATA_BITS(DATA_BITS),
            .ADDR_BITS(ADDR_BITS)
        ) inst_cdma (
            .aclk(aclk),
            .aresetn(aresetn),
            .rd_CDMA(rd_CDMA_adj[i]),
            .wr_CDMA(wr_CDMA_adj[i]),
            .m_axi_ddr(m_axi_card[i]),
            .s_axis_ddr(axis_mux_cdma[i]),
            .m_axis_ddr(axis_cdma_mux[i])
        );
    end

`else 

    // CDMA
    cdma #(
        .DATA_BITS(DATA_BITS),
        .ADDR_BITS(ADDR_BITS)
    ) inst_cdma (
        .aclk(aclk),
        .aresetn(aresetn),
        .rd_CDMA(rd_CDMA),
        .wr_CDMA(wr_CDMA),
        .m_axi_ddr(m_axi_card[0]),
        .s_axis_ddr(s_axis_user),
        .m_axis_ddr(m_axis_user)
    );

`endif

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_CDMA_ADJ

`endif

endmodule