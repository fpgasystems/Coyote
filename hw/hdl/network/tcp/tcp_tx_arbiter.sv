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

`timescale 1ns/1ps

import lynxTypes::*;

/**
 * @brief   TCP TX multiplexer
 *
 */

module tcp_tx_arbiter (
    input  logic                                  aclk,
    input  logic                                  aresetn,

    metaIntf.s                                    s_tx_meta [N_REGIONS],
    metaIntf.m                                    m_tx_meta,

    metaIntf.s                                    s_tx_stat,
    metaIntf.m                                    m_tx_stat [N_REGIONS],

    AXI4S.s                                       s_axis_tx [N_REGIONS],
    AXI4S.m                                       m_axis_tx
);


  logic [N_REGIONS-1 : 0] m_tx_stat_ready;
  logic [N_REGIONS-1 : 0] m_tx_stat_valid;
  logic [$bits(tcp_tx_stat_t)-1 : 0] m_tx_stat_data[N_REGIONS];

  logic [N_REGIONS-1 : 0] s_axis_tx_ready;
  logic [N_REGIONS-1 : 0] s_axis_tx_valid;
  logic [AXI_DATA_BITS/8-1 : 0] s_axis_tx_keep [N_REGIONS];
  logic [N_REGIONS-1 : 0] s_axis_tx_last;
  logic [AXI_DATA_BITS-1 : 0] s_axis_tx_data [N_REGIONS];
 
  for(genvar i = 0; i < N_REGIONS; i++) begin
    assign m_tx_stat_ready[i] = m_tx_stat[i].ready;
    assign m_tx_stat[i].valid = m_tx_stat_valid[i];
    assign m_tx_stat[i].data = m_tx_stat_data[i];

    assign s_axis_tx[i].tready = s_axis_tx_ready[i];
    assign s_axis_tx_valid[i] = s_axis_tx[i].tvalid;
    assign s_axis_tx_keep[i] = s_axis_tx[i].tkeep ;
    assign s_axis_tx_last[i] = s_axis_tx[i].tlast ;
    assign s_axis_tx_data[i] = s_axis_tx[i].tdata ;
  end


  // ---------------------------------------------------------------------------
  // Safe VF bitwidth (avoid zero-width when N_REGIONS == 1)
  // ---------------------------------------------------------------------------
  localparam int VF_BITS = (N_REGIONS <= 1) ? 1 : $clog2(N_REGIONS);

  // ---------------------------------------------------------------------------
  // Meta arbitration
  // ---------------------------------------------------------------------------
  logic [VF_BITS-1:0] vfid_pick;
  metaIntf #(.STYPE(tcp_tx_meta_t)) tx_meta ();

  meta_arbiter #(.DATA_BITS($bits(tcp_tx_meta_t))) i_meta_arbiter (
    .aclk    (aclk),
    .aresetn (aresetn),
    .s_meta  (s_tx_meta),
    .m_meta  (tx_meta),
    .id_out  (vfid_pick)
  );

  // ---------------------------------------------------------------------------
  // Two VF-only queues: seq_q (data), cmp_q (status)
  // ---------------------------------------------------------------------------
  metaIntf #(.STYPE(logic[VF_BITS-1:0])) seq_snk (), seq_src ();
  metaIntf #(.STYPE(logic[VF_BITS-1:0])) cmp_snk (), cmp_src ();
  logic forward_ok;

  always_comb begin
    // defaults
    m_tx_meta.valid = 1'b0;
    m_tx_meta.data  = tx_meta.data;
    tx_meta.ready   = 1'b0;

    seq_snk.valid   = 1'b0;
    seq_snk.data    = vfid_pick;

    cmp_snk.valid   = 1'b0;
    cmp_snk.data    = vfid_pick;

    if (tx_meta.valid && m_tx_meta.ready && seq_snk.ready && cmp_snk.ready) begin
        m_tx_meta.valid = 1;
        tx_meta.ready   = 1;
        seq_snk.valid   = 1;
        cmp_snk.valid   = 1;
    end
  end

  queue #(
    .QTYPE (logic [VF_BITS-1:0]),
    .QDEPTH(32)
  ) i_seq_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (seq_snk.valid),
    .rdy_snk  (seq_snk.ready),
    .data_snk (seq_snk.data),
    .val_src  (seq_src.valid),
    .rdy_src  (seq_src.ready),
    .data_src (seq_src.data)
  );

  queue #(
    .QTYPE (logic [VF_BITS-1:0]),
    .QDEPTH(32)
  ) i_cmp_q (
    .aclk     (aclk),
    .aresetn  (aresetn),
    .val_snk  (cmp_snk.valid),
    .rdy_snk  (cmp_snk.ready),
    .data_snk (cmp_snk.data),
    .val_src  (cmp_src.valid),
    .rdy_src  (cmp_src.ready),
    .data_src (cmp_src.data)
  );

  // ---------------------------------------------------------------------------
  // Data path FSM: drain selected VF until TLAST handshake
  // ---------------------------------------------------------------------------
  typedef enum logic { ST_IDLE, ST_SEND} n_state_data_t;
  logic                              state_data_C, state_data_N;
  logic [VF_BITS-1:0]                data_vfid_C,  data_vfid_N;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      state_data_C <= ST_IDLE;
      data_vfid_C  <= '0;
    end else begin
      state_data_C <= state_data_N;
      data_vfid_C  <= data_vfid_N;
    end
  end

  always_comb begin : NSL_DATA
    state_data_N = state_data_C;
    case (state_data_C)
      ST_IDLE: begin
        if (seq_src.valid) state_data_N = ST_SEND;
      end
      ST_SEND: begin
        if ( s_axis_tx_valid[data_vfid_C]
          && m_axis_tx.tready
          && s_axis_tx_last[data_vfid_C] ) begin
          state_data_N = ST_IDLE;
        end
      end
    endcase
  end



  always_comb begin : DP_DATA
      seq_src.ready   = 1'b0;
      m_axis_tx.tvalid = 1'b0;
      m_axis_tx.tdata  = '0;
      m_axis_tx.tkeep  = '0;
      m_axis_tx.tlast  = '0;
      for (int i = 0; i < N_REGIONS; i++) begin
        s_axis_tx_ready[i] = 1'b0;
      end
      data_vfid_N = data_vfid_C;

      case (state_data_C)
          ST_IDLE: begin
            seq_src.ready = 1'b1;
            if (seq_src.valid) data_vfid_N = seq_src.data;
          end
          ST_SEND: begin
            s_axis_tx_ready[data_vfid_C] = m_axis_tx.tready;

            m_axis_tx.tvalid = s_axis_tx_valid[data_vfid_C];
            m_axis_tx.tdata  = s_axis_tx_data[data_vfid_C];
            m_axis_tx.tkeep  = s_axis_tx_keep[data_vfid_C];
            m_axis_tx.tlast  = s_axis_tx_last[data_vfid_C];
          end
      endcase
  end

  
  // ---------------------------------------------------------------------------
  // Status routing: route only to cmp_q head; pop on handshake
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] { ST_M_IDLE, ST_M_SEND, ST_M_RSP_WAIT } n_state_sts_t;

  logic [1:0]                        state_sts_C, state_sts_N;
  logic [VF_BITS-1:0]                sts_vfid_C,  sts_vfid_N;
  logic [$bits(s_tx_stat.data)-1:0]  stat_payload_C, stat_payload_N;

  // REG
  always_ff @(posedge aclk) begin : PROC_REG_STS
    if (!aresetn) begin
      state_sts_C     <= ST_M_IDLE;
      sts_vfid_C      <= '0;
      stat_payload_C  <= '0;
    end else begin
      state_sts_C     <= state_sts_N;
      sts_vfid_C      <= sts_vfid_N;
      stat_payload_C  <= stat_payload_N;
    end
  end

  always_comb begin : NSL_STS
      state_sts_N = state_sts_C;
      case (state_sts_C)
          ST_M_IDLE:     state_sts_N = cmp_src.valid ? ST_M_SEND : ST_M_IDLE;
          ST_M_SEND: 
            if (s_tx_stat.valid) begin
              state_sts_N =  (m_tx_stat_ready[sts_vfid_C])? ST_M_IDLE : ST_M_RSP_WAIT;
            end
            else begin
              state_sts_N = ST_M_SEND;
            end
          ST_M_RSP_WAIT: state_sts_N = (m_tx_stat_ready[sts_vfid_C]) ? ST_M_IDLE : ST_M_RSP_WAIT; 
          default:       state_sts_N = ST_M_IDLE;
      endcase
  end

  always_comb begin : DP_STS
    cmp_src.ready   = 1'b0;
    s_tx_stat.ready = 1'b0;
    for (int i = 0; i < N_REGIONS; i++) begin
      m_tx_stat_valid[i] = 1'b0;
      m_tx_stat_data[i] = '0;
    end

    sts_vfid_N     = sts_vfid_C;
    stat_payload_N = stat_payload_C;

    case(state_sts_C)
      ST_M_IDLE: begin
          cmp_src.ready = 1'b1;
          if (cmp_src.valid) sts_vfid_N = cmp_src.data;
      end
      ST_M_SEND: begin
        if (s_tx_stat.valid) begin
          if (m_tx_stat_ready[sts_vfid_C]) begin // passthrough
            m_tx_stat_valid[sts_vfid_C] = 1'b1;
            m_tx_stat_data [sts_vfid_C] = s_tx_stat.data;
            s_tx_stat.ready             = 1'b1;   
          end else begin
            stat_payload_N              = s_tx_stat.data;
            s_tx_stat.ready             = 1'b1;   
          end
        end
      end
      ST_M_RSP_WAIT: begin
        s_tx_stat.ready = 1'b0;
        m_tx_stat_valid[sts_vfid_C] = 1'b1;
        m_tx_stat_data [sts_vfid_C] = stat_payload_C;
      end
    endcase
  end


endmodule
