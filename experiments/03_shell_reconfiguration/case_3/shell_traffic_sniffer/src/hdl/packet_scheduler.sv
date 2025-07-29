/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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

/**
 *  Packet Sniifer RX/TX Scheduler & Merger
 */ 
import lynxTypes::*;

module packet_sniffer_sched (
  input  logic                        aclk,
  input  logic                        aresetn,

  AXI4S.s                             sink_rx,
  AXI4S.s                             sink_tx,
  AXI4S.m                             src
);

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) sink_rx_r ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) sink_tx_r ();

logic sink_rx_first, sink_tx_first;
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        sink_rx_first <= 1;
        sink_tx_first <= 1;
    end else begin
        if (sink_rx.tvalid & sink_rx.tready) begin
            sink_rx_first <= 0;
            if (sink_rx.tlast) begin
                sink_rx_first <= 1;
            end
        end
        if (sink_tx.tvalid & sink_tx.tready) begin
            sink_tx_first <= 0;
            if (sink_tx.tlast) begin
                sink_tx_first <= 1;
            end
        end
    end
end

axis_data_fifo_rx_sniffer_vfpga axis_data_fifo_rx_sniffer_vfpga_inst (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(sink_rx.tvalid),
  .s_axis_tready(sink_rx.tready),
  .s_axis_tdata(sink_rx.tdata),
  .s_axis_tkeep(sink_rx.tkeep),
  .s_axis_tlast(sink_rx.tlast),
  //.m_axis_aclk(aclk),
  .m_axis_tvalid(sink_rx_r.tvalid),
  .m_axis_tready(sink_rx_r.tready),
  .m_axis_tdata(sink_rx_r.tdata),
  .m_axis_tkeep(sink_rx_r.tkeep),
  .m_axis_tlast(sink_rx_r.tlast)
);

axis_data_fifo_tx_sniffer_vfpga axis_data_fifo_tx_sniffer_vfpga_inst (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(sink_tx.tvalid),
  .s_axis_tready(sink_tx.tready),
  .s_axis_tdata(sink_tx.tdata),
  .s_axis_tkeep(sink_tx.tkeep),
  .s_axis_tlast(sink_tx.tlast),
  //.m_axis_aclk(aclk),
  .m_axis_tvalid(sink_tx_r.tvalid),
  .m_axis_tready(sink_tx_r.tready),
  .m_axis_tdata(sink_tx_r.tdata),
  .m_axis_tkeep(sink_tx_r.tkeep),
  .m_axis_tlast(sink_tx_r.tlast)
);

logic [63:0] packets_order; // save order of arriving packets (0 for rx and 1 for tx)
logic [6:0]  packets_cnt;   // the number valid bits in packets_order
logic [63:0] packets_order_next;
logic [6:0]  packets_cnt_next;
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        packets_order <= 0;
        packets_cnt   <= 0;
    end else begin
        packets_order <= packets_order_next;
        packets_cnt   <= packets_cnt_next;
    end
end

always_comb begin
    src.tvalid = 0;
    src.tdata  = 0;
    src.tkeep  = 0;
    src.tlast  = 0;
    sink_rx_r.tready = 0;
    sink_tx_r.tready = 0;

    if (packets_cnt > 0) begin
        if (packets_order[0] == 1'b0) begin
            // rx -> src
            src.tvalid       = sink_rx_r.tvalid;
            src.tdata        = sink_rx_r.tdata;
            src.tkeep        = sink_rx_r.tkeep;
            src.tlast        = sink_rx_r.tlast;
            sink_rx_r.tready = src.tready;
        end else begin
            // tx -> src
            src.tvalid       = sink_tx_r.tvalid;
            src.tdata        = sink_tx_r.tdata;
            src.tkeep        = sink_tx_r.tkeep;
            src.tlast        = sink_tx_r.tlast;
            sink_tx_r.tready = src.tready;
        end
    end
end

logic         packets_dec_flg; // 1: src finished sending a packet
logic [1:0]   packets_inc_cnt; // 0, 1 or 2
logic [63:0]  packets_inc_content;
always_comb begin
    packets_dec_flg     = 0;
    packets_inc_cnt     = 0;
    packets_inc_content = 64'b00;
    if (src.tlast & src.tvalid & src.tready) begin
        packets_dec_flg = 1;
    end
    if (sink_rx.tvalid & sink_rx.tready & sink_rx_first & sink_tx.tvalid & sink_tx.tready & sink_tx_first) begin
        packets_inc_cnt     = 2;
        packets_inc_content = 64'b10;
    end else if (sink_rx.tvalid & sink_rx.tready & sink_rx_first) begin
        packets_inc_cnt     = 1;
        packets_inc_content = 64'b00;
    end else if (sink_tx.tvalid & sink_tx.tready & sink_tx_first) begin
        packets_inc_cnt     = 1;
        packets_inc_content = 64'b01;
    end

    packets_cnt_next   = packets_cnt + packets_inc_cnt - packets_dec_flg;
    packets_order_next = (packets_order | (packets_inc_content << packets_cnt)) >> packets_dec_flg;
end

endmodule