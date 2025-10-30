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
 * @brief TCP port table
 *
 */

module tcp_port_table (
    input  logic                                   aclk,
    input  logic                                   aresetn,

    metaIntf.s                                     s_listen_req [N_REGIONS],
    metaIntf.m                                     m_listen_req,

    metaIntf.s                                     s_listen_rsp,
    metaIntf.m                                     m_listen_rsp [N_REGIONS],

    input  logic [TCP_IP_PORT_BITS-1:0]            port_addr,   
    output logic [TCP_PORT_TABLE_DATA_BITS-1:0]    rsid_out     
);

    localparam int PT_ADDR_BITS   = 10;                
    localparam int PT_DATA_BITS   = 1 + N_REGIONS_BITS;
    localparam int PT_VALID_BIT   = PT_DATA_BITS-1;
    localparam int PT_DATA_BYTES  = (PT_DATA_BITS+7)/8;
    localparam int PT_RAM_BITS    = PT_DATA_BYTES*8;

    // -- Arbitration ------------------------------------------------------------
    metaIntf #(.STYPE(tcp_listen_req_t)) listen_req_arb ();
    logic [N_REGIONS_BITS-1:0] vfid_arb;

    meta_arbiter #(
        .DATA_BITS($bits(tcp_listen_req_t))
    ) i_tcp_port_arb_in (
        .aclk   (aclk),
        .aresetn(aresetn),
        .s_meta (s_listen_req),
        .m_meta (listen_req_arb),
        .id_out (vfid_arb)
    );

    logic [PT_DATA_BYTES-1:0] a_we;
    logic [PT_ADDR_BITS-1:0]  a_addr;
    logic [PT_RAM_BITS-1:0]   a_din, a_dout;

    logic [PT_ADDR_BITS-1:0]  b_addr;
    logic [PT_RAM_BITS-1:0]   b_dout;

    assign b_addr   = port_addr[PT_ADDR_BITS-1:0];
    assign rsid_out = b_dout[PT_DATA_BITS-1:0];

    typedef enum logic [2:0] {
        ST_IDLE,       
        ST_LKUP_REQ,   
        ST_LKUP_W1,    
        ST_LKUP_W2,    
        ST_HIT_RSP,    
        ST_MISS_SEND,  
        ST_WAIT_RSP,
        ST_SEND_DOWN  
    } state_t;
    
    state_t state_C, state_N;

    tcp_listen_req_t           req_buf_C, req_buf_N;
    tcp_listen_rsp_t           rsp_buf_C, rsp_buf_N;
    logic [N_REGIONS_BITS-1:0] vfid_C,    vfid_N;

    logic                      hit;
    logic [N_REGIONS_BITS-1:0] vfid_hit;

    assign hit      = a_dout[PT_VALID_BIT];                  
    assign vfid_hit = a_dout[N_REGIONS_BITS-1:0];            

    logic [N_REGIONS-1:0]             m_listen_rsp_ready;
    logic [N_REGIONS-1:0]             m_listen_rsp_valid;
    logic [$bits(tcp_listen_rsp_t)-1:0] m_listen_rsp_data [N_REGIONS];

    for (genvar i = 0; i < N_REGIONS; i++) begin : GEN_RSP_GLUE
        assign m_listen_rsp_ready[i] = m_listen_rsp[i].ready;
        assign m_listen_rsp[i].valid = m_listen_rsp_valid[i];
        assign m_listen_rsp[i].data  = m_listen_rsp_data[i];
    end



    // -- REG --------------------------------------------------------------------
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C   <= ST_IDLE;
            req_buf_C <= '0;
            rsp_buf_C <= '0;
            vfid_C    <= '0;
        end else begin
            state_C   <= state_N;
            req_buf_C <= req_buf_N;
            rsp_buf_C <= rsp_buf_N;
            vfid_C    <= vfid_N;
        end
    end

    // -- NSL --------------------------------------------------------------------
    always_comb begin
        state_N = state_C;
        case (state_C)
            ST_IDLE:      state_N = listen_req_arb.valid ? ST_LKUP_REQ : ST_IDLE;
            ST_LKUP_REQ:  state_N = ST_LKUP_W1;
            ST_LKUP_W1:   state_N = ST_LKUP_W2;
            ST_LKUP_W2:   state_N = hit ? ST_HIT_RSP : ST_MISS_SEND;
            ST_HIT_RSP:   state_N = m_listen_rsp_ready[vfid_C] ? ST_IDLE : ST_HIT_RSP;
            ST_MISS_SEND: state_N = m_listen_req.ready? ST_WAIT_RSP : ST_MISS_SEND;
            ST_WAIT_RSP:  state_N = (s_listen_rsp.valid)? ST_SEND_DOWN : ST_WAIT_RSP;
            ST_SEND_DOWN: state_N = m_listen_rsp_ready[vfid_C]? ST_IDLE : ST_SEND_DOWN;
            default:      state_N = ST_IDLE;
        endcase
    end

    // -- DP ---------------------------------------------------------------------
    always_comb begin : DP_LISTEN
        listen_req_arb.ready = 1'b0;
        m_listen_req.valid   = 1'b0;
        m_listen_req.data    = req_buf_C;
        s_listen_rsp.ready   = 1'b0;

        for (int i = 0; i < N_REGIONS; i++) begin
            m_listen_rsp_valid[i] = 1'b0;
            m_listen_rsp_data[i]  = '0;
        end

        a_we   = '0;
        a_addr = req_buf_C.ip_port[PT_ADDR_BITS-1:0];
        a_din  = '0;

        req_buf_N = req_buf_C;
        rsp_buf_N = rsp_buf_C;
        vfid_N    = vfid_C;

        case (state_C)
            ST_IDLE: begin
                if (listen_req_arb.valid) begin
                    listen_req_arb.ready = 1'b1;
                    req_buf_N = listen_req_arb.data;
                    vfid_N = vfid_arb;
                end
            end

            ST_LKUP_REQ: begin
            end

            ST_LKUP_W1: begin
            end

            ST_LKUP_W2: begin
            end

            ST_HIT_RSP: begin
                m_listen_rsp_valid[vfid_C] = 1'b1;
                m_listen_rsp_data[vfid_C]  = '0;
            end

            ST_MISS_SEND: begin
                m_listen_req.valid = 1'b1;
                m_listen_req.data  = req_buf_C;

                if (m_listen_req.ready) begin
                    a_we  = {PT_DATA_BYTES{1'b1}};
                    a_din = {{(PT_RAM_BITS-PT_DATA_BITS){1'b0}}, {1'b1, vfid_C}};
                end
            end

            ST_WAIT_RSP: begin
                s_listen_rsp.ready = 1'b1;                
                if (s_listen_rsp.valid) begin
                    rsp_buf_N = s_listen_rsp.data;
                end
            end

            ST_SEND_DOWN: begin
                m_listen_rsp_valid[vfid_C] = 1'b1;
                m_listen_rsp_data[vfid_C]  = rsp_buf_C;
            end


            default: ;
        endcase
    end

    // -- RAM -------------------------------------------------------
    ram_tp_c #(
        .ADDR_BITS (PT_ADDR_BITS),
        .DATA_BITS (PT_RAM_BITS)
    ) inst_port_table (
        .clk        (aclk),

        .a_en       (1'b1),
        .a_we       (a_we),
        .a_addr     (a_addr),
        .a_data_in  (a_din),
        .a_data_out (a_dout),

        .b_en       (1'b1),
        .b_addr     (b_addr),
        .b_data_out (b_dout)
    );

endmodule
