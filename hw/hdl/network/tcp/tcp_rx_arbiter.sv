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
 * @brief   TCP RX multiplexer
 *
 * With RX_DDR_BYPASS the TOE keeps the payload of all sessions in one shared FIFO, and each
 * rd_pkg pops the next packet from it, whatever sid it names. The rd_pkgs must therefore be
 * issued in notification order.
 *
 * tcp_conn_table pushes one route entry {vfid, len, sid} per data notification (s_rx_route).
 * The head entry is issued to the TOE once its vFPGA presents a rd_pkg; requests of other
 * vFPGAs wait until their entry is at the head. rx_meta and payload are routed to the owner
 * of the issued entry. rd_pkgs with len == 0 are dropped (the TOE ignores them).
 */

module tcp_rx_arbiter #(
    parameter integer ROUTE_QDEPTH = 64,
    parameter integer META_QDEPTH  = 32,
    parameter integer DATA_QDEPTH  = 32
) (
    input  logic                                   aclk,
    input  logic                                   aresetn,

    // Route entries, in notification order
    metaIntf.s                                     s_rx_route,

    // Read package meta (N inputs -> 1 output)
    metaIntf.s                                     s_rd_pkg   [N_REGIONS],
    metaIntf.m                                     m_rd_pkg,

    // RX meta (1 input -> N outputs)
    metaIntf.s                                     s_rx_meta,
    metaIntf.m                                     m_rx_meta  [N_REGIONS],

    // AXI4-Stream data (1 input -> N outputs), no TID
    AXI4S.s                                        s_axis_rx,
    AXI4S.m                                        m_axis_rx  [N_REGIONS]
);

  // ---------------------------------------------------------------------------
  // Interface glue
  // ---------------------------------------------------------------------------
  logic [N_REGIONS-1:0]            s_rd_pkg_valid;
  tcp_rd_pkg_t [N_REGIONS-1:0]     s_rd_pkg_data;
  logic [N_REGIONS-1:0]            s_rd_pkg_ready;

  logic [N_REGIONS-1:0]            m_rx_meta_ready;
  logic [N_REGIONS-1:0]            m_rx_meta_valid;

  logic [N_REGIONS-1:0]            m_axis_rx_ready;
  logic [N_REGIONS-1:0]            m_axis_rx_valid;

  for(genvar i = 0; i < N_REGIONS; i++) begin
    assign s_rd_pkg_valid[i]  = s_rd_pkg[i].valid;
    assign s_rd_pkg_data[i]   = s_rd_pkg[i].data;
    assign s_rd_pkg[i].ready  = s_rd_pkg_ready[i];

    assign m_rx_meta_ready[i] = m_rx_meta[i].ready;
    assign m_rx_meta[i].valid = m_rx_meta_valid[i];
    assign m_rx_meta[i].data  = s_rx_meta.data;

    assign m_axis_rx_ready[i] = m_axis_rx[i].tready;
    assign m_axis_rx[i].tvalid = m_axis_rx_valid[i];
    assign m_axis_rx[i].tdata  = s_axis_rx.tdata;
    assign m_axis_rx[i].tkeep  = s_axis_rx.tkeep;
    assign m_axis_rx[i].tlast  = s_axis_rx.tlast;
  end

  // ---------------------------------------------------------------------------
  // Route queue
  // ---------------------------------------------------------------------------
  tcp_rx_route_t route_head;
  logic          route_vld;
  logic          fire;

  queue #(
    .QTYPE (tcp_rx_route_t),
    .QDEPTH(ROUTE_QDEPTH)
  ) i_route_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (s_rx_route.valid),
    .rdy_snk  (s_rx_route.ready),
    .data_snk (s_rx_route.data),
    .val_src  (fire),
    .rdy_src  (route_vld),
    .data_src (route_head)
  );

  // ---------------------------------------------------------------------------
  // Issue: head entry, once its owner presents a rd_pkg
  // ---------------------------------------------------------------------------
  logic [N_REGIONS-1:0] head_sel;
  logic [N_REGIONS-1:0] usr_zero;
  logic                 meta_q_rdy, data_q_rdy;
  logic                 issue_rdy;

  for(genvar i = 0; i < N_REGIONS; i++) begin
    assign head_sel[i] = route_vld && (route_head.vfid == i);
    assign usr_zero[i] = s_rd_pkg_valid[i] && (s_rd_pkg_data[i].len == 0);
  end

  assign issue_rdy = meta_q_rdy && data_q_rdy;

  assign m_rd_pkg.valid    = |(head_sel & s_rd_pkg_valid & ~usr_zero) && issue_rdy;
  assign m_rd_pkg.data.sid = route_head.sid;
  assign m_rd_pkg.data.len = route_head.len;

  assign fire = m_rd_pkg.valid && m_rd_pkg.ready;

  assign s_rd_pkg_ready = usr_zero | (head_sel & {N_REGIONS{issue_rdy && m_rd_pkg.ready}});

  // ---------------------------------------------------------------------------
  // Meta routing
  // ---------------------------------------------------------------------------
  logic [N_REGIONS_BITS-1:0] meta_head;
  logic                      meta_vld;
  logic                      meta_pop;
  logic [N_REGIONS-1:0]      meta_sel;

  queue #(
    .QTYPE (logic [N_REGIONS_BITS-1:0]),
    .QDEPTH(META_QDEPTH)
  ) i_meta_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (fire),
    .rdy_snk  (meta_q_rdy),
    .data_snk (route_head.vfid),
    .val_src  (meta_pop),
    .rdy_src  (meta_vld),
    .data_src (meta_head)
  );

  for(genvar i = 0; i < N_REGIONS; i++) begin
    assign meta_sel[i]        = meta_vld && (meta_head == i);
    assign m_rx_meta_valid[i] = meta_sel[i] && s_rx_meta.valid;
  end

  assign s_rx_meta.ready = |(meta_sel & m_rx_meta_ready);
  assign meta_pop        = s_rx_meta.valid && s_rx_meta.ready;

  // ---------------------------------------------------------------------------
  // Data routing, one queue entry per packet
  // ---------------------------------------------------------------------------
  logic [N_REGIONS_BITS-1:0] data_head;
  logic                      data_vld;
  logic                      data_pop;
  logic [N_REGIONS-1:0]      data_sel;

  queue #(
    .QTYPE (logic [N_REGIONS_BITS-1:0]),
    .QDEPTH(DATA_QDEPTH)
  ) i_data_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (fire),
    .rdy_snk  (data_q_rdy),
    .data_snk (route_head.vfid),
    .val_src  (data_pop),
    .rdy_src  (data_vld),
    .data_src (data_head)
  );

  for(genvar i = 0; i < N_REGIONS; i++) begin
    assign data_sel[i]        = data_vld && (data_head == i);
    assign m_axis_rx_valid[i] = data_sel[i] && s_axis_rx.tvalid;
  end

  assign s_axis_rx.tready = |(data_sel & m_axis_rx_ready);
  assign data_pop         = s_axis_rx.tvalid && s_axis_rx.tready && s_axis_rx.tlast;

endmodule
