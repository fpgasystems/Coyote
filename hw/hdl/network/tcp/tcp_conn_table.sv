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

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief TCP connection table
 *
 */

module tcp_conn_table (
    input  logic                                   aclk,
    input  logic                                   aresetn,

    // Open / Close
    metaIntf.s                                     s_open_req [N_REGIONS],
    metaIntf.m                                     m_open_req,

    metaIntf.s                                     s_close_req [N_REGIONS],
    metaIntf.m                                     m_close_req,

    metaIntf.s                                     s_open_rsp,
    metaIntf.m                                     m_open_rsp [N_REGIONS],

    // Notify
    metaIntf.s                                     s_notify,
    metaIntf.m                                     m_notify [N_REGIONS],
    metaIntf.m                                     m_rx_route,

    output logic [TCP_IP_PORT_BITS-1:0]            port_addr,   
    input  logic [TCP_PORT_TABLE_DATA_BITS-1:0]    rsid_in     
);

    // -- Constants --------------------------------------------------------------  
    localparam int SID_ADDR_BITS  = 10;     
    localparam int SID_DATA_BITS  = 1 + N_REGIONS_BITS;         
    localparam int SID_DATA_BYTES = (SID_DATA_BITS+7)/8;       
    localparam int SID_RAM_BITS = SID_DATA_BYTES * 8;       

    // Port table entry is {valid, vfid}
    localparam int PT_VALID_BIT   = N_REGIONS_BITS;

    // Data notifications without an owner cannot be dropped (their packet is in the shared RX FIFO),
    // so they are delivered to this vFPGA
    localparam logic [N_REGIONS_BITS-1:0] UNROUTED_SINK_VFID = '0;

    // RAM ports
    logic [SID_DATA_BYTES -1 : 0] a_we;
    logic [SID_ADDR_BITS - 1 : 0] a_addr;
    logic [SID_RAM_BITS - 1: 0] a_data_in, a_data_out;

    logic [SID_ADDR_BITS-1:0]    b_addr;
    logic [SID_RAM_BITS-1:0]    b_data_out;

    // -- SID table write arbitration (port a, priority: flush > open > notify) --
    // Flush clears the table after reset (one entry per cycle, requests are held off meanwhile)
    logic                      clr_C;
    logic [SID_ADDR_BITS-1:0]  clr_addr_C;

    always_ff @(posedge aclk) begin : REG_CLR
        if (!aresetn) begin
            clr_C      <= 1'b1;
            clr_addr_C <= '0;
        end
        else if (clr_C) begin
            clr_C      <= ~&clr_addr_C;
            clr_addr_C <= clr_addr_C + 1;
        end
    end

    logic                      flush_wr_req;
    logic [SID_ADDR_BITS-1:0]  flush_wr_sid;
    logic                      open_wr_req;
    logic [SID_ADDR_BITS-1:0]  open_wr_sid;
    logic [N_REGIONS_BITS-1:0] open_wr_vfid;
    logic                      ntf_wr_req;
    logic [SID_ADDR_BITS-1:0]  ntf_wr_sid;
    logic                      ntf_wr_valid;
    logic [N_REGIONS_BITS-1:0] ntf_wr_vfid;
    logic                      ntf_wr_gnt;

    assign flush_wr_req = clr_C;
    assign flush_wr_sid = clr_addr_C;

    assign ntf_wr_gnt = ntf_wr_req & ~flush_wr_req & ~open_wr_req;

    // Port a is also read by the close FSM, in cycles without a write
    logic                      cls_rd;
    logic [SID_ADDR_BITS-1:0]  cls_rd_sid;

    always_comb begin : SID_WR_ARB
        a_we      = '0;
        a_addr    = '0;
        a_data_in = '0;

        if (flush_wr_req) begin
            a_addr    = flush_wr_sid;
            a_data_in = '0;
            a_we      = {SID_DATA_BYTES{1'b1}};
        end
        else if (open_wr_req) begin
            a_addr    = open_wr_sid;
            a_data_in = {{(SID_RAM_BITS-SID_DATA_BITS){1'b0}}, {1'b1, open_wr_vfid}};
            a_we      = {SID_DATA_BYTES{1'b1}};
        end
        else if (ntf_wr_req) begin
            a_addr    = ntf_wr_sid;
            a_data_in = {{(SID_RAM_BITS-SID_DATA_BITS){1'b0}}, {ntf_wr_valid, ntf_wr_vfid}};
            a_we      = {SID_DATA_BYTES{1'b1}};
        end
        else if (cls_rd) begin
            a_addr    = cls_rd_sid;
        end
    end


    // Close ------------
    // A close is only forwarded if the session belongs to the requesting vFPGA

    typedef enum logic [2:0] { C_IDLE, C_REQ, C_WAIT, C_WAIT_2, C_SEND } c_state_t;
    c_state_t c_state_C, c_state_N;

    tcp_close_req_t            cls_buf_C, cls_buf_N;
    logic [N_REGIONS_BITS-1:0] vfid_cls_C, vfid_cls_N;

    metaIntf #(.STYPE(tcp_close_req_t)) close_req_arb ();
    logic [N_REGIONS_BITS-1:0] vfid_cls_arb;

    meta_arbiter #(
        .DATA_BITS($bits(tcp_close_req_t))
    ) i_tcp_close_req_arb_in (
        .aclk    (aclk),
        .aresetn (aresetn),
        .s_meta  (s_close_req),
        .m_meta  (close_req_arb),
        .id_out  (vfid_cls_arb)
    );

    logic cls_owner;
    assign cls_owner = a_data_out[SID_DATA_BITS-1] && (a_data_out[N_REGIONS_BITS-1:0] == vfid_cls_C);

    // -- REG (CLOSE) ------------------------------------------------------------
    always_ff @(posedge aclk) begin : REG_CLOSE
        if (!aresetn) begin
            c_state_C  <= C_IDLE;
            cls_buf_C  <= '0;
            vfid_cls_C <= '0;
        end
        else begin
            c_state_C  <= c_state_N;
            cls_buf_C  <= cls_buf_N;
            vfid_cls_C <= vfid_cls_N;
        end
    end

    // -- NSL (CLOSE) ------------------------------------------------------------
    always_comb begin : NSL_CLOSE
        c_state_N = c_state_C;
        case (c_state_C)
            C_IDLE:   c_state_N = (close_req_arb.valid && !clr_C) ? C_REQ : C_IDLE;
            C_REQ:    c_state_N = (|a_we) ? C_REQ : C_WAIT;
            C_WAIT:   c_state_N = C_WAIT_2;
            C_WAIT_2: c_state_N = cls_owner ? C_SEND : C_IDLE;
            C_SEND:   c_state_N = m_close_req.ready ? C_IDLE : C_SEND;
            default:  c_state_N = C_IDLE;
        endcase
    end

    // -- DP (CLOSE) -------------------------------------------------------------
    always_comb begin : DP_CLOSE
        close_req_arb.ready = 1'b0;
        m_close_req.valid   = 1'b0;
        m_close_req.data    = cls_buf_C;

        cls_buf_N  = cls_buf_C;
        vfid_cls_N = vfid_cls_C;

        cls_rd     = (c_state_C == C_REQ);
        cls_rd_sid = cls_buf_C.sid[SID_ADDR_BITS-1:0];

        case (c_state_C)
            C_IDLE: begin
                close_req_arb.ready = !clr_C;
                if (close_req_arb.valid && !clr_C) begin
                    cls_buf_N  = close_req_arb.data;
                    vfid_cls_N = vfid_cls_arb;
                end
            end

            C_SEND: begin
                m_close_req.valid = 1'b1;
            end
            default: ;
        endcase
    end


    // Open ------------

    typedef enum logic [1:0] { ST_IDLE, ST_REQ_SEND, ST_WAIT, ST_RSP_SEND } o_state_t;
    o_state_t o_state_C, o_state_N;

    tcp_open_req_t  req_buf_C,  req_buf_N;     
    logic [N_REGIONS_BITS-1:0] vfid_open_C, vfid_open_N;
    tcp_open_rsp_t  rsp_buf_C,  rsp_buf_N;

    logic [N_REGIONS-1 : 0] m_open_rsp_ready;
    logic [N_REGIONS-1 : 0] m_open_rsp_valid;
    logic [$bits(tcp_open_rsp_t)-1 : 0] m_open_rsp_data [N_REGIONS];

    metaIntf #(.STYPE(tcp_open_req_t)) open_req_arb ();
    logic [N_REGIONS_BITS-1:0] vfid_open_arb;

    meta_arbiter #(
        .DATA_BITS($bits(tcp_open_req_t))
    ) i_tcp_open_req_arb_in (
        .aclk    (aclk),
        .aresetn (aresetn),
        .s_meta  (s_open_req),
        .m_meta  (open_req_arb),
        .id_out  (vfid_open_arb)
    );


    // -- REG (OPEN) -------------------------------------------------------------
    always_ff @(posedge aclk) begin : REG_OPEN
        if (!aresetn) begin
            o_state_C    <= ST_IDLE;
            req_buf_C    <= '0;
            vfid_open_C  <= '0;
            rsp_buf_C    <= '0;
        end
        else begin
            o_state_C    <= o_state_N;
            req_buf_C    <= req_buf_N;
            vfid_open_C  <= vfid_open_N;
            rsp_buf_C    <= rsp_buf_N;
        end
    end

    // -- NSL (OPEN) -------------------------------------------------------------
    always_comb begin : NSL_OPEN
        o_state_N = o_state_C;
        case (o_state_C)
            ST_IDLE:       o_state_N = (open_req_arb.valid && !clr_C) ? ST_REQ_SEND : ST_IDLE;
            ST_REQ_SEND:   o_state_N = m_open_req.ready   ? ST_WAIT     : ST_REQ_SEND;
            ST_WAIT:       o_state_N = s_open_rsp.valid   ? ST_RSP_SEND : ST_WAIT;
            ST_RSP_SEND:   o_state_N = (m_open_rsp_ready[vfid_open_C]) ? ST_IDLE : ST_RSP_SEND;
            default:       o_state_N = ST_IDLE;
        endcase
    end

    for(genvar i = 0; i < N_REGIONS; i++) begin
        assign m_open_rsp_ready[i] = m_open_rsp[i].ready;
        assign m_open_rsp[i].valid = m_open_rsp_valid[i];
        assign m_open_rsp[i].data  = m_open_rsp_data[i];
    end

    // -- DP (OPEN) --------------------------------------------------------------
    always_comb begin : DP_OPEN
        open_req_arb.ready   = 1'b0;
        m_open_req.valid     = 1'b0;
        m_open_req.data      = req_buf_C;
        s_open_rsp.ready     = 1'b0;

        for (int i = 0; i < N_REGIONS; i++) begin
            m_open_rsp_valid[i] = 1'b0;
            m_open_rsp_data[i]  = '0;
        end

        req_buf_N    = req_buf_C;
        vfid_open_N  = vfid_open_C;
        rsp_buf_N    = rsp_buf_C;

        open_wr_req  = 1'b0;
        open_wr_sid  = '0;
        open_wr_vfid = '0;

        case (o_state_C)
            ST_IDLE: begin
                if (open_req_arb.valid && !clr_C) begin
                    open_req_arb.ready   = 1'b1;
                    req_buf_N            = open_req_arb.data;
                    vfid_open_N          = vfid_open_arb;
                end
            end

            ST_REQ_SEND: begin
                m_open_req.valid = 1'b1;
                m_open_req.data  = req_buf_C;
            end

            ST_WAIT: begin
                s_open_rsp.ready = 1'b1;
                if (s_open_rsp.valid) begin
                    rsp_buf_N = s_open_rsp.data;
                end
            end

            ST_RSP_SEND: begin
                // Only a successful open owns its session
                open_wr_req  = |rsp_buf_C.success;
                open_wr_sid  = rsp_buf_C.sid[SID_ADDR_BITS - 1 : 0];
                open_wr_vfid = vfid_open_C;
                m_open_rsp_valid[vfid_open_C] = 1'b1;
                m_open_rsp_data[vfid_open_C]  = rsp_buf_C;
            end
            default: ;
        endcase
    end

    // Notify ------------
    typedef enum logic [2:0] { N_IDLE, N_REQ, N_WAIT, N_WAIT_2, N_LEARN, N_CLEAR, N_RSP_SEND } n_state_t;
    n_state_t n_state_C, n_state_N;

    tcp_notify_t not_C, not_N;

    logic [N_REGIONS_BITS-1:0] dst_vfid_C, dst_vfid_N;

    logic sid_hit;
    assign sid_hit        = b_data_out[SID_DATA_BITS-1];

    logic [N_REGIONS_BITS-1:0] vfid_sid;
    assign vfid_sid  = b_data_out[N_REGIONS_BITS-1:0];

    // Port 0 carries no port information (e.g. timeout close)
    logic [N_REGIONS_BITS-1:0] vfid_port;
    assign vfid_port = rsid_in[N_REGIONS_BITS-1:0];

    logic port_ok;
    assign port_ok = rsid_in[PT_VALID_BIT] && (not_C.dst_port != '0);

    // Routing decision (valid in N_WAIT_2)
    logic                      rt_drop;
    logic                      rt_learn;
    logic [N_REGIONS_BITS-1:0] rt_vfid;
    always_comb begin : ROUTE
        rt_drop  = 1'b0;
        rt_learn = 1'b0;
        rt_vfid  = vfid_port;

        if (not_C.opened) begin
            // Passive open: learn the owner of the listening port
            if (port_ok) begin
                rt_vfid  = vfid_port;
                rt_learn = !(sid_hit && (vfid_sid == vfid_port));
            end
            else begin
                rt_drop = 1'b1;
            end
        end
        else if (sid_hit) begin
            rt_vfid = vfid_sid;
        end
        else if (port_ok) begin
            rt_vfid = vfid_port;
        end
        else if (not_C.len != '0) begin
            rt_vfid = UNROUTED_SINK_VFID;
        end
        else begin
            rt_drop = 1'b1;
        end
    end

    logic [N_REGIONS-1:0]             m_notify_valid;
    logic [$bits(tcp_notify_t)-1:0]   m_notify_data [N_REGIONS];
    logic [N_REGIONS-1:0]             m_notify_ready;

    for (genvar i = 0; i < N_REGIONS; i++) begin : GEN_NOTIFY_IF_GLUE
        assign m_notify[i].valid = m_notify_valid[i];
        assign m_notify[i].data  = m_notify_data[i];
        assign m_notify_ready[i] = m_notify[i].ready;
    end

    // Data notifications are also announced to tcp_rx_arbiter
    logic rx_route_en;
    assign rx_route_en = (not_C.len != 0);

    // -- REG (NOTIFY) -----------------------------------------------------------
    always_ff @(posedge aclk) begin : REG_NOTIFY
        if (!aresetn) begin
            n_state_C   <= N_IDLE;
            not_C       <= '0;
            dst_vfid_C  <= '0;
        end else begin
            n_state_C   <= n_state_N;
            not_C       <= not_N;
            dst_vfid_C  <= dst_vfid_N;
        end
    end


    // -- NSL (NOTIFY) -----------------------------------------------------------
    always_comb begin : NSL_NOTIFY
        n_state_N = n_state_C;
        case (n_state_C)
            N_IDLE:     n_state_N = (s_notify.valid && !clr_C) ? N_REQ : N_IDLE;
            N_REQ:      n_state_N = N_WAIT;
            N_WAIT:     n_state_N = N_WAIT_2;
            N_WAIT_2:   n_state_N = rt_drop ? N_IDLE : (rt_learn ? N_LEARN : (not_C.closed ? N_CLEAR : N_RSP_SEND));
            N_LEARN:    n_state_N = ntf_wr_gnt ? N_RSP_SEND : N_LEARN;
            N_CLEAR:    n_state_N = ntf_wr_gnt ? N_RSP_SEND : N_CLEAR;
            N_RSP_SEND: n_state_N = (m_notify_ready[dst_vfid_C] && (!rx_route_en || m_rx_route.ready)) ? N_IDLE : N_RSP_SEND;
            default:    n_state_N = N_IDLE;
        endcase
    end

    // -- DP (NOTIFY) ------------------------------------------------------------
    always_comb begin : DP_NOTIFY
        not_N = not_C;
        s_notify.ready = 1'b0;

        b_addr         = not_C.sid[SID_ADDR_BITS-1:0];
        port_addr      = not_C.dst_port;
        dst_vfid_N     = dst_vfid_C;

        ntf_wr_req     = 1'b0;
        ntf_wr_sid     = not_C.sid[SID_ADDR_BITS-1:0];
        ntf_wr_valid   = 1'b0;
        ntf_wr_vfid    = dst_vfid_C;

        for (int i = 0; i < N_REGIONS; i++) begin
            m_notify_valid[i] = 1'b0;
            m_notify_data[i]  = not_C;
        end

        m_rx_route.valid     = 1'b0;
        m_rx_route.data      = '0;

        case (n_state_C)
            N_IDLE: begin
                s_notify.ready = !clr_C;
                if (s_notify.valid && !clr_C) begin
                    not_N = s_notify.data;
                end
            end

            N_REQ: begin
            end

            N_WAIT: begin
            end

            N_WAIT_2: begin
                dst_vfid_N = rt_vfid;
            end

            N_LEARN: begin
                ntf_wr_req   = 1'b1;
                ntf_wr_valid = 1'b1;
            end

            N_CLEAR: begin
                // Closed session has no owner anymore, the notification still goes to the last one
                ntf_wr_req   = 1'b1;
                ntf_wr_valid = 1'b0;
            end

            N_RSP_SEND: begin
                // Notify and route handshakes complete in the same cycle
                m_notify_valid[dst_vfid_C] = !rx_route_en || m_rx_route.ready;
                m_notify_data[dst_vfid_C] = not_C;

                m_rx_route.valid     = rx_route_en && m_notify_ready[dst_vfid_C];
                m_rx_route.data.vfid = dst_vfid_C;
                m_rx_route.data.len  = not_C.len;
                m_rx_route.data.sid  = not_C.sid;
            end
            default: ;
        endcase
    end

    // -- SID MAP RAM ------------------------------------------------------------
    ram_tp_c #(
        .ADDR_BITS (SID_ADDR_BITS),   
        .DATA_BITS (SID_RAM_BITS)
    ) port_table_inst (
        .clk        (aclk),

        .a_en       (1'b1),
        .a_we       (a_we),
        .a_addr     (a_addr),                     
        .a_data_in  (a_data_in),
        .a_data_out (a_data_out),

        .b_en       (1'b1),
        .b_addr     (b_addr),
        .b_data_out (b_data_out)
    );

endmodule
