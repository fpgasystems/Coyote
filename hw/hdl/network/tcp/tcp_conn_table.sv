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

    output logic [TCP_IP_PORT_BITS-1:0]            port_addr,   
    input  logic [TCP_PORT_TABLE_DATA_BITS-1:0]    rsid_in     
);

    // -- Constants --------------------------------------------------------------  
    localparam int SID_ADDR_BITS  = 10;     
    localparam int SID_DATA_BITS  = 1 + N_REGIONS_BITS;         
    localparam int SID_DATA_BYTES = (SID_DATA_BITS+7)/8;       
    localparam int SID_RAM_BITS = SID_DATA_BYTES * 8;       

    // Close
    // -- Arbitration ------------------------------------------------------------
    meta_arbiter #(
        .DATA_BITS($bits(tcp_close_req_t))
    ) i_tcp_close_req_arb_in (
        .aclk    (aclk),
        .aresetn (aresetn),
        .s_meta  (s_close_req),
        .m_meta  (m_close_req),
        .id_out  (/*unused*/)
    );


    // RAM ports
    logic [SID_DATA_BYTES -1 : 0] a_we;
    logic [SID_ADDR_BITS - 1 : 0] a_addr;
    logic [SID_RAM_BITS - 1: 0] a_data_in, a_data_out;

    logic [SID_ADDR_BITS-1:0]    b_addr;
    logic [SID_RAM_BITS-1:0]    b_data_out;


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
            ST_IDLE:       o_state_N = open_req_arb.valid ? ST_REQ_SEND : ST_IDLE;
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

        a_we      = '0;
        a_addr    = '0;
        a_data_in = '0;
        
        case (o_state_C)
            ST_IDLE: begin
                if (open_req_arb.valid) begin
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
                a_addr = rsp_buf_C.sid[SID_ADDR_BITS - 1 : 0];
                a_data_in = {{(SID_RAM_BITS-SID_DATA_BITS){1'b0}}, {1'b1, vfid_open_C}};
                a_we = {SID_DATA_BYTES{1'b1}};
                m_open_rsp_valid[vfid_open_C] = 1'b1;
                m_open_rsp_data[vfid_open_C]  = rsp_buf_C;
            end
            default: ;
        endcase
    end

    // Notify FSM
    typedef enum logic [2:0] { N_IDLE, N_REQ, N_WAIT, N_WAIT_2, N_RSP_SEND } n_state_t;
    n_state_t n_state_C, n_state_N;

    tcp_notify_t not_C, not_N;

    logic [N_REGIONS_BITS-1:0] dst_vfid_C, dst_vfid_N;

    logic sid_hit;
    assign sid_hit        = b_data_out[SID_DATA_BITS-1];                // MSB = VALID

    logic [N_REGIONS_BITS-1:0] vfid_sid;
    assign vfid_sid  = b_data_out[N_REGIONS_BITS-1:0];            

    logic [N_REGIONS_BITS-1:0] vfid_port;
    assign vfid_port = rsid_in[N_REGIONS_BITS-1:0];

    logic [N_REGIONS-1:0]             m_notify_valid;
    logic [$bits(tcp_notify_t)-1:0]   m_notify_data [N_REGIONS];
    logic [N_REGIONS-1:0]             m_notify_ready;

    for (genvar i = 0; i < N_REGIONS; i++) begin : GEN_NOTIFY_IF_GLUE
        assign m_notify[i].valid = m_notify_valid[i];
        assign m_notify[i].data  = m_notify_data[i];
        assign m_notify_ready[i] = m_notify[i].ready;
    end

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
            N_IDLE:     n_state_N = s_notify.valid ? N_REQ : N_IDLE;
            N_REQ:      n_state_N = N_WAIT;              
            N_WAIT:     n_state_N = N_WAIT_2;
            N_WAIT_2:   n_state_N = N_RSP_SEND;
            N_RSP_SEND: n_state_N = m_notify_ready[dst_vfid_C]? N_IDLE : N_RSP_SEND;
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

        for (int i = 0; i < N_REGIONS; i++) begin
            m_notify_valid[i] = 1'b0;
            m_notify_data[i]  = not_C;
        end

        case (n_state_C)
            N_IDLE: begin
                s_notify.ready = 1;
                if (s_notify.valid) begin
                    not_N = s_notify.data;
                end
            end

            N_REQ: begin
            end

            N_WAIT: begin
            end
            
            N_WAIT_2: begin
                if (sid_hit) begin
                    dst_vfid_N = vfid_sid;
                end else begin
                    dst_vfid_N = vfid_port;
                end
            end

            N_RSP_SEND: begin
                m_notify_valid[dst_vfid_C] = 1;
                m_notify_data[dst_vfid_C] = not_C;         
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
