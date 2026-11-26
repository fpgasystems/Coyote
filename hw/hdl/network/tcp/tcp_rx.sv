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
 * @brief   TCP RX: drains the TOE into per-vFPGA queues
 *
 * Every data notification is read out of the TOE's shared FIFO at once, into its owner's data FIFO and,
 * with the last beat, a {len, sid} entry. The TOE admits segments only against the owner's credit (the queue
 * size in beats), so the queue always has room. Segments of an unknown owner (>= N_REGIONS) are discarded.
 * Credit is returned as beats leave the data FIFOs or are discarded. The rules for sq_rd are in
 * docs/agents/services/network.md.
 */
module tcp_rx #(
    parameter integer ROUTE_QDEPTH = 32
) (
    input  logic            aclk,
    input  logic            aresetn,

    // TOE
    metaIntf.s              s_notify,
    metaIntf.m              m_rd_pkg,
    metaIntf.s              s_rx_meta,
    AXI4S.s                 s_axis_rx,
    metaIntf.m              m_rx_credit,

    // vFPGAs
    metaIntf.m              m_rq_wr [N_REGIONS],
    metaIntf.s              s_sq_rd [N_REGIONS],
    metaIntf.m              m_cq_rd [N_REGIONS],
    AXI4SR.m                m_axis_rx [N_REGIONS]
);

localparam integer N_OWNERS = 2**TCP_OWNER_BITS;

typedef struct packed {
    logic [TCP_OWNER_BITS-1:0] owner;
    tcp_rd_pkg_t               pkg;
} route_t;

typedef enum logic [1:0] {R_IDLE, R_DATA, R_CQ} r_state_t;

// ---------------------------------------------------------------------------------------------------
// Drain
// ---------------------------------------------------------------------------------------------------
logic   route_rdy, route_vld, route_pop;
route_t route_in, route_head;

assign route_in.owner = s_notify.data.owner;
assign route_in.pkg   = {s_notify.data.len, s_notify.data.sid};

assign m_rd_pkg.valid = s_notify.valid && route_rdy;
assign m_rd_pkg.data  = route_in.pkg;
assign s_notify.ready = m_rd_pkg.ready && route_rdy;

queue #(
    .QTYPE(route_t),
    .QDEPTH(ROUTE_QDEPTH)
) inst_route_q (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(s_notify.valid && s_notify.ready),
    .rdy_snk(route_rdy),
    .data_snk(route_in),
    .val_src(route_pop),
    .rdy_src(route_vld),
    .data_src(route_head)
);

assign s_rx_meta.ready = 1'b1;

logic                 known;
logic [N_REGIONS-1:0] wr_sel;
logic [N_REGIONS-1:0] dat_wr_rdy, ent_wr_rdy;
logic [N_REGIONS-1:0] rd_beat;
logic                 disc_beat;

assign known = (route_head.owner < N_REGIONS);

always_comb begin
    s_axis_rx.tready = route_vld && !known;
    for (int i = 0; i < N_REGIONS; i++) begin
        if (wr_sel[i]) s_axis_rx.tready = dat_wr_rdy[i] && (!s_axis_rx.tlast || ent_wr_rdy[i]);
    end
end

assign route_pop = s_axis_rx.tvalid && s_axis_rx.tready && s_axis_rx.tlast;
assign disc_beat = s_axis_rx.tvalid && s_axis_rx.tready && !known;

// ---------------------------------------------------------------------------------------------------
// Per-vFPGA queues
// ---------------------------------------------------------------------------------------------------
for (genvar i = 0; i < N_REGIONS; i++) begin : GEN_REGION
    assign wr_sel[i] = route_vld && known && (route_head.owner == i);

    // Data FIFO
    logic                       dat_vld, dat_rdy, dat_last;
    logic [AXI_NET_BITS-1:0]    dat_data;
    logic [AXI_NET_BITS/8-1:0]  dat_keep;

    axis_data_fifo_512_tcp_rx inst_data_q (
        .s_axis_aclk   (aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid (s_axis_rx.tvalid && wr_sel[i] && (!s_axis_rx.tlast || ent_wr_rdy[i])),
        .s_axis_tready (dat_wr_rdy[i]),
        .s_axis_tdata  (s_axis_rx.tdata),
        .s_axis_tkeep  (s_axis_rx.tkeep),
        .s_axis_tlast  (s_axis_rx.tlast),
        .m_axis_tvalid (dat_vld),
        .m_axis_tready (dat_rdy),
        .m_axis_tdata  (dat_data),
        .m_axis_tkeep  (dat_keep),
        .m_axis_tlast  (dat_last)
    );

    assign rd_beat[i] = dat_vld && dat_rdy;

    // Entries {len, sid}, written with the segment's last beat: notify queue -> rq_wr -> read queue
    logic        ntf_vld, ntf_rdy, ent_vld, ent_rdy, ent_pop;
    tcp_rd_pkg_t ntf, ent;

    axis_data_fifo_tcp_rx_desc inst_ntf_q (
        .s_axis_aclk   (aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid (s_axis_rx.tvalid && wr_sel[i] && s_axis_rx.tlast && dat_wr_rdy[i]),
        .s_axis_tready (ent_wr_rdy[i]),
        .s_axis_tdata  (route_head.pkg),
        .m_axis_tvalid (ntf_vld),
        .m_axis_tready (m_rq_wr[i].ready && ent_rdy),
        .m_axis_tdata  (ntf)
    );

    always_comb begin
        m_rq_wr[i].valid     = ntf_vld && ent_rdy;
        m_rq_wr[i].data      = '0;
        m_rq_wr[i].data.strm = STRM_TCP;
        m_rq_wr[i].data.vfid = i;
        m_rq_wr[i].data.sid  = ntf.sid;
        m_rq_wr[i].data.len  = ntf.len;
        m_rq_wr[i].data.last = 1'b1;
    end

    axis_data_fifo_tcp_rx_desc inst_ent_q (
        .s_axis_aclk   (aclk),
        .s_axis_aresetn(aresetn),
        .s_axis_tvalid (ntf_vld && m_rq_wr[i].ready),
        .s_axis_tready (ent_rdy),
        .s_axis_tdata  (ntf),
        .m_axis_tvalid (ent_vld),
        .m_axis_tready (ent_pop),
        .m_axis_tdata  (ent)
    );

    // Reads
    r_state_t r_state_C, r_state_N;

    req_t                    rd_C, rd_N;
    logic                    err_C, err_N;
    logic [TCP_LEN_BITS-1:0] offs_C, offs_N; // bytes of the head segment already read
    logic [TCP_LEN_BITS-1:0] cnt_C, cnt_N;   // beats left - 1

    logic [TCP_LEN_BITS-1:0] left;
    logic                    bad, match;

    assign left  = ent.len - offs_C;
    assign bad   = (s_sq_rd[i].data.len == 0) || (s_sq_rd[i].data.dest >= N_TCP_AXI);
    assign match = ent_vld && (s_sq_rd[i].data.sid == ent.sid) && (s_sq_rd[i].data.len <= left) &&
                   ((s_sq_rd[i].data.len == left) || (s_sq_rd[i].data.len[BEAT_LOG_BITS-1:0] == 0));

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            r_state_C <= R_IDLE;
            rd_C      <= '0;
            err_C     <= 1'b0;
            offs_C    <= '0;
            cnt_C     <= '0;
        end else begin
            r_state_C <= r_state_N;
            rd_C      <= rd_N;
            err_C     <= err_N;
            offs_C    <= offs_N;
            cnt_C     <= cnt_N;
        end
    end

    always_comb begin
        r_state_N = r_state_C;
        rd_N      = rd_C;
        err_N     = err_C;
        offs_N    = offs_C;
        cnt_N     = cnt_C;

        s_sq_rd[i].ready = 1'b0;
        dat_rdy          = 1'b0;
        ent_pop          = 1'b0;

        m_axis_rx[i].tvalid = 1'b0;
        m_axis_rx[i].tdata  = dat_data;
        m_axis_rx[i].tkeep  = dat_keep;
        m_axis_rx[i].tlast  = (cnt_C == 0) && rd_C.last;
        m_axis_rx[i].tid    = rd_C.dest;

        m_cq_rd[i].valid       = (r_state_C == R_CQ);
        m_cq_rd[i].data        = '0;
        m_cq_rd[i].data.opcode = rd_C.opcode;
        m_cq_rd[i].data.strm   = rd_C.strm;
        m_cq_rd[i].data.host   = rd_C.host;
        m_cq_rd[i].data.dest   = rd_C.dest;
        m_cq_rd[i].data.pid    = rd_C.pid;
        m_cq_rd[i].data.vfid   = rd_C.vfid;
        m_cq_rd[i].data.rsrvd  = err_C ? TCP_ERR_BAD_REQ : 0;

        case (r_state_C)
            R_IDLE: begin
                if (s_sq_rd[i].valid) begin
                    s_sq_rd[i].ready = 1'b1;
                    rd_N  = s_sq_rd[i].data;
                    err_N = bad || !match;
                    cnt_N = (s_sq_rd[i].data.len - 1) >> BEAT_LOG_BITS;
                    r_state_N = (bad || !match) ? R_CQ : R_DATA;
                end
            end

            R_DATA: begin
                m_axis_rx[i].tvalid = dat_vld;
                dat_rdy             = m_axis_rx[i].tready;
                if (dat_vld && dat_rdy) begin
                    cnt_N = cnt_C - 1;
                    if (cnt_C == 0) begin
                        ent_pop   = (offs_C + rd_C.len == ent.len);
                        offs_N    = ent_pop ? '0 : offs_C + rd_C.len;
                        r_state_N = rd_C.last ? R_CQ : R_IDLE;
                    end
                end
            end

            R_CQ: begin
                if (m_cq_rd[i].ready) r_state_N = R_IDLE;
            end

            default: r_state_N = R_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------------------------------
// Credit return: beats are counted per owner and sent as {beats, owner}, owners in turn
// ---------------------------------------------------------------------------------------------------
logic [N_OWNERS-1:0][TCP_CREDIT_BITS-1:0] crd_C;
logic [TCP_OWNER_BITS-1:0]                crd_ptr_C;
logic                                     crd_vld_C;
logic [TCP_RX_CREDIT_BITS-1:0]            crd_out_C;
logic                                     crd_ld;

assign crd_ld = !crd_vld_C || m_rx_credit.ready;

assign m_rx_credit.valid = crd_vld_C;
assign m_rx_credit.data  = crd_out_C;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        crd_C     <= '0;
        crd_ptr_C <= '0;
        crd_vld_C <= 1'b0;
        crd_out_C <= '0;
    end else begin
        for (int o = 0; o < N_OWNERS; o++) begin
            crd_C[o] <= ((crd_ld && (crd_ptr_C == o)) ? 0 : crd_C[o])
                + ((o < N_REGIONS) ? rd_beat[o % N_REGIONS] : 1'b0)
                + (disc_beat && (route_head.owner == o));
        end
        if (crd_ld) begin
            crd_vld_C <= (crd_C[crd_ptr_C] != 0);
            crd_out_C <= {crd_C[crd_ptr_C], crd_ptr_C};
            crd_ptr_C <= crd_ptr_C + 1;
        end
    end
end

endmodule
