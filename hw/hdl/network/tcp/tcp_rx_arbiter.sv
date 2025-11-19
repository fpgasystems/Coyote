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
 * @brief   RX arbitration (tlast-based)
 *
 * Arbitrates incoming RX stream:
 */
module tcp_rx_arbiter (
    input  logic                                   aclk,
    input  logic                                   aresetn,

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


  logic [N_REGIONS-1 : 0] m_rx_meta_ready;
  logic [N_REGIONS-1 : 0] m_rx_meta_valid;
  logic [$bits(tcp_rx_meta_t)-1 : 0] m_rx_meta_data[N_REGIONS];

  logic [N_REGIONS-1 : 0] m_axis_rx_ready;
  logic [N_REGIONS-1 : 0] m_axis_rx_valid;
  logic [AXI_DATA_BITS/8-1 : 0] m_axis_rx_keep [N_REGIONS];
  logic [N_REGIONS-1 : 0] m_axis_rx_last;
  logic [AXI_DATA_BITS-1 : 0] m_axis_rx_data [N_REGIONS];
 
  for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_rx_meta_ready[i] = m_rx_meta[i].ready;
    assign m_rx_meta[i].valid = m_rx_meta_valid[i];
    assign m_rx_meta[i].data = m_rx_meta_data[i];
    assign m_axis_rx_ready[i] = m_axis_rx[i].tready;
    assign m_axis_rx[i].tvalid = m_axis_rx_valid[i];
    assign m_axis_rx[i].tkeep = m_axis_rx_keep[i];
    assign m_axis_rx[i].tlast = m_axis_rx_last[i];
    assign m_axis_rx[i].tdata = m_axis_rx_data[i];
  end


  // ---------------------------------------------------------------------------
  // Safe VF bitwidth (avoid zero-width when N_REGIONS == 1)
  // ---------------------------------------------------------------------------
  localparam int VF_BITS = (N_REGIONS <= 1) ? 1 : $clog2(N_REGIONS);

  // ---------------------------------------------------------------------------
  // Meta arbitration
  // ---------------------------------------------------------------------------

  always_comb begin
    m_rd_pkg.valid  = 1'b0;
    m_rd_pkg.data   = rd_pkg.data;
    rd_pkg.ready    = 1'b0;

    rx_seq_snk.valid  = 1'b0;
    rx_seq_snk.data   = rx_vfid_pick;

    rx_meta_snk.valid = 1'b0;
    rx_meta_snk.data  = rx_vfid_pick;

    if (rd_pkg.valid && m_rd_pkg.ready && rx_seq_snk.ready && rx_meta_snk.ready) begin
      m_rd_pkg.valid   = 1'b1;
      rd_pkg.ready     = 1'b1;
      rx_seq_snk.valid = 1'b1;
      rx_meta_snk.valid= 1'b1;
    end
  end


  // Arbiter
  logic [VF_BITS-1:0] rx_vfid_pick;
  metaIntf #(.STYPE(tcp_rd_pkg_t)) rd_pkg ();

  meta_arbiter #(.DATA_BITS($bits(tcp_rd_pkg_t))) i_rd_pkg_arbiter (
    .aclk    (aclk),
    .aresetn (aresetn),
    .s_meta  (s_rd_pkg),
    .m_meta  (rd_pkg),
    .id_out  (rx_vfid_pick)
  );

  metaIntf #(.STYPE(logic[VF_BITS-1:0])) rx_seq_snk (), rx_seq_src ();
  metaIntf #(.STYPE(logic[VF_BITS-1:0])) rx_meta_snk(), rx_meta_src();
  
  queue #(
    .QTYPE (logic [VF_BITS-1:0]),
    .QDEPTH(32)
  ) i_rx_seq_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (rx_seq_snk.valid),
    .rdy_snk  (rx_seq_snk.ready),
    .data_snk (rx_seq_snk.data),
    .val_src  (rx_seq_src.valid),
    .rdy_src  (rx_seq_src.ready),
    .data_src (rx_seq_src.data)
  );

  queue #(
    .QTYPE (logic [VF_BITS-1:0]),
    .QDEPTH(32)
  ) i_rx_meta_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (rx_meta_snk.valid),
    .rdy_snk  (rx_meta_snk.ready),
    .data_snk (rx_meta_snk.data),
    .val_src  (rx_meta_src.valid),
    .rdy_src  (rx_meta_src.ready),
    .data_src (rx_meta_src.data)
  );

  // ---------------------------------------------------------------------------
  // Meta routing
  // ---------------------------------------------------------------------------

  typedef enum logic [1:0] { RM_IDLE, RM_ROUTE } n_state_rxmeta_t;

  logic [1:0]         state_rm_C, state_rm_N;
  logic [VF_BITS-1:0] rxm_vfid_C, rxm_vfid_N;

  // FF
  always_ff @(posedge aclk) begin : FF_RX_META
    if (!aresetn) begin
      state_rm_C <= RM_IDLE;
      rxm_vfid_C <= '0;
    end else begin
      state_rm_C <= state_rm_N;
      rxm_vfid_C <= rxm_vfid_N;
    end
  end

  // NSL
  always_comb begin : NSL_RX_META
    state_rm_N = state_rm_C;
    case (state_rm_C)
      RM_IDLE: begin
        if (rx_meta_src.valid) state_rm_N = RM_ROUTE;
      end
      RM_ROUTE: begin
        if (s_rx_meta.valid && m_rx_meta_ready[rxm_vfid_C])
          state_rm_N = RM_IDLE;
      end
    endcase
  end

  // DP
  always_comb begin : DP_RX_META
    rx_meta_src.ready = 1'b0;
    s_rx_meta.ready   = 1'b0;
    for (int i = 0; i < N_REGIONS; i++) begin
      m_rx_meta_valid[i] = 1'b0;
      m_rx_meta_data[i]  = '0;
    end

    rxm_vfid_N = rxm_vfid_C;

    case (state_rm_C)
      RM_IDLE: begin
        rx_meta_src.ready = 1'b1;
        if (rx_meta_src.valid) rxm_vfid_N = rx_meta_src.data;
      end

      RM_ROUTE: begin
        m_rx_meta_valid[rxm_vfid_C]= s_rx_meta.valid;
        m_rx_meta_data[rxm_vfid_C]  = s_rx_meta.data;
        s_rx_meta.ready             = m_rx_meta_ready[rxm_vfid_C];
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // 3) Data demux 
  // ---------------------------------------------------------------------------
  typedef enum logic { RD_IDLE, RD_FWD } n_state_rxdata_t;

  logic              state_rd_C, state_rd_N;
  logic [VF_BITS-1:0] rxd_vfid_C, rxd_vfid_N;

  // FF
  always_ff @(posedge aclk) begin : PROC_RX_DATA
    if (!aresetn) begin
      state_rd_C  <= RD_IDLE;
      rxd_vfid_C  <= '0;
    end else begin
      state_rd_C  <= state_rd_N;
      rxd_vfid_C  <= rxd_vfid_N;
    end
  end

  // NSL
  always_comb begin : NSL_RX_DATA
    state_rd_N = state_rd_C;
    case (state_rd_C)
      RD_IDLE: begin
        if (rx_seq_src.valid) state_rd_N = RD_FWD;
      end
      RD_FWD: begin
        if ( s_axis_rx.tvalid
          && m_axis_rx_ready[rxd_vfid_C]
          && s_axis_rx.tlast )
          state_rd_N = RD_IDLE;
      end
    endcase
  end

  // DP
  always_comb begin : DP_RX_DATA
    rx_seq_src.ready = 1'b0;

    s_axis_rx.tready  = 1'b0;
    for (int i = 0; i < N_REGIONS; i++) begin
      m_axis_rx_valid[i] = 1'b0;
      m_axis_rx_data [i] = '0;
      m_axis_rx_keep [i] = '0;
      m_axis_rx_last [i] = 1'b0;
    end

    rxd_vfid_N = rxd_vfid_C;

    case (state_rd_C)
      RD_IDLE: begin
        rx_seq_src.ready = 1'b1;
        if (rx_seq_src.valid) rxd_vfid_N = rx_seq_src.data;
      end

      RD_FWD: begin
        m_axis_rx_valid[rxd_vfid_C] = s_axis_rx.tvalid;
        m_axis_rx_data[rxd_vfid_C] = s_axis_rx.tdata;
        m_axis_rx_keep[rxd_vfid_C] = s_axis_rx.tkeep;
        m_axis_rx_last[rxd_vfid_C] = s_axis_rx.tlast;
        
        s_axis_rx.tready             = m_axis_rx_ready[rxd_vfid_C];
      end
    endcase
  end

endmodule