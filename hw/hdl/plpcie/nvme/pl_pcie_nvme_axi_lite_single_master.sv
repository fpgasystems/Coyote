/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
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

// -----------------------------------------------------------------------------
// pl_pcie_nvme_axi_lite_single_master
// -----------------------------------------------------------------------------
// Minimal AXI4-Lite transaction generator.
//
// The module accepts one abstract read/write command, converts it to AXI4-Lite,
// and returns exactly one response.
//
// A local timeout prevents an absent/misconfigured PCIe target from holding the
// enumeration state machine forever.
// -----------------------------------------------------------------------------
module pl_pcie_nvme_axi_lite_single_master #(
    parameter integer ADDR_WIDTH     = 32,
    parameter integer TIMEOUT_CYCLES = 1_000_000
) (
    input  wire                       aclk,
    input  wire                       aresetn,

    // One-command-at-a-time interface.
    input  wire                       cmd_valid,
    output wire                       cmd_ready,
    input  wire                       cmd_write,
    input  wire [ADDR_WIDTH-1:0]      cmd_addr,
    input  wire [31:0]                cmd_wdata,
    input  wire [3:0]                 cmd_wstrb,

    output logic                      rsp_valid,
    input  wire                       rsp_ready,
    output logic [31:0]               rsp_rdata,
    output logic [1:0]                rsp_resp,
    output logic                      rsp_timeout,

    // AXI4-Lite master interface.
    output wire [ADDR_WIDTH-1:0]      m_axi_awaddr,
    output wire [2:0]                 m_axi_awprot,
    output wire                       m_axi_awvalid,
    input  wire                       m_axi_awready,

    output wire [31:0]                m_axi_wdata,
    output wire [3:0]                 m_axi_wstrb,
    output wire                       m_axi_wvalid,
    input  wire                       m_axi_wready,

    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output wire                       m_axi_bready,

    output wire [ADDR_WIDTH-1:0]      m_axi_araddr,
    output wire [2:0]                 m_axi_arprot,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,

    input  wire [31:0]                m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready
);

    localparam integer TIMEOUT_COUNT_MAX =
        (TIMEOUT_CYCLES < 2) ? 2 : TIMEOUT_CYCLES;
    localparam integer TIMEOUT_WIDTH = $clog2(TIMEOUT_COUNT_MAX);
    localparam integer TIMEOUT_LIMIT =
        (TIMEOUT_CYCLES < 1) ? 1 : TIMEOUT_CYCLES;
    localparam logic [TIMEOUT_WIDTH-1:0] TIMEOUT_LAST_COUNT =
        TIMEOUT_LIMIT - 1;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WRITE_SEND,
        ST_WRITE_RESPONSE,
        ST_READ_ADDRESS,
        ST_READ_DATA,
        ST_RESPONSE
    } state_t;

    state_t state;

    logic [ADDR_WIDTH-1:0] addr_reg;
    logic [31:0]           wdata_reg;
    logic [3:0]            wstrb_reg;
    logic                  aw_pending;
    logic                  w_pending;
    logic [TIMEOUT_WIDTH-1:0] timeout_count;

    wire timeout_enabled = (TIMEOUT_CYCLES != 0);
    wire timeout_hit =
        timeout_enabled && (timeout_count == TIMEOUT_LAST_COUNT);

    assign cmd_ready = aresetn && (state == ST_IDLE) && !rsp_valid;

    assign m_axi_awaddr  = addr_reg;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awvalid = (state == ST_WRITE_SEND) && aw_pending;

    assign m_axi_wdata   = wdata_reg;
    assign m_axi_wstrb   = wstrb_reg;
    assign m_axi_wvalid  = (state == ST_WRITE_SEND) && w_pending;

    assign m_axi_bready  = (state == ST_WRITE_RESPONSE);

    assign m_axi_araddr  = addr_reg;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arvalid = (state == ST_READ_ADDRESS);

    assign m_axi_rready  = (state == ST_READ_DATA);

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state         <= ST_IDLE;
            addr_reg      <= '0;
            wdata_reg     <= '0;
            wstrb_reg     <= '0;
            aw_pending    <= 1'b0;
            w_pending     <= 1'b0;
            timeout_count <= '0;
            rsp_valid     <= 1'b0;
            rsp_rdata     <= '0;
            rsp_resp      <= 2'b00;
            rsp_timeout   <= 1'b0;
        end else begin
            // A response remains asserted until its consumer accepts it.
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    timeout_count <= '0;

                    if (cmd_valid && cmd_ready) begin
                        addr_reg    <= cmd_addr;
                        wdata_reg   <= cmd_wdata;
                        wstrb_reg   <= cmd_wstrb;
                        rsp_timeout <= 1'b0;

                        if (cmd_write) begin
                            // AXI permits AW and W to handshake independently.
                            aw_pending <= 1'b1;
                            w_pending  <= 1'b1;
                            state      <= ST_WRITE_SEND;
                        end else begin
                            state <= ST_READ_ADDRESS;
                        end
                    end
                end

                ST_WRITE_SEND: begin
                    if (m_axi_awvalid && m_axi_awready)
                        aw_pending <= 1'b0;

                    if (m_axi_wvalid && m_axi_wready)
                        w_pending <= 1'b0;

                    // The expressions account for a channel that completed in
                    // an earlier cycle as well as one completing now.
                    if ((!aw_pending || m_axi_awready) &&
                        (!w_pending  || m_axi_wready)) begin
                        state <= ST_WRITE_RESPONSE;
                    end

                    if (timeout_hit) begin
                        aw_pending  <= 1'b0;
                        w_pending   <= 1'b0;
                        rsp_rdata   <= '0;
                        rsp_resp    <= 2'b11; // DECERR-like local indication.
                        rsp_timeout <= 1'b1;
                        rsp_valid   <= 1'b1;
                        state       <= ST_RESPONSE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_WRITE_RESPONSE: begin
                    if (m_axi_bvalid) begin
                        rsp_rdata   <= '0;
                        rsp_resp    <= m_axi_bresp;
                        rsp_timeout <= 1'b0;
                        rsp_valid   <= 1'b1;
                        state       <= ST_RESPONSE;
                    end else if (timeout_hit) begin
                        rsp_rdata   <= '0;
                        rsp_resp    <= 2'b11;
                        rsp_timeout <= 1'b1;
                        rsp_valid   <= 1'b1;
                        state       <= ST_RESPONSE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_READ_ADDRESS: begin
                    if (m_axi_arvalid && m_axi_arready)
                        state <= ST_READ_DATA;

                    if (timeout_hit) begin
                        rsp_rdata   <= '0;
                        rsp_resp    <= 2'b11;
                        rsp_timeout <= 1'b1;
                        rsp_valid   <= 1'b1;
                        state       <= ST_RESPONSE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_READ_DATA: begin
                    if (m_axi_rvalid) begin
                        rsp_rdata   <= m_axi_rdata;
                        rsp_resp    <= m_axi_rresp;
                        rsp_timeout <= 1'b0;
                        rsp_valid   <= 1'b1;
                        state       <= ST_RESPONSE;
                    end else if (timeout_hit) begin
                        rsp_rdata   <= '0;
                        rsp_resp    <= 2'b11;
                        rsp_timeout <= 1'b1;
                        rsp_valid   <= 1'b1;
                        state       <= ST_RESPONSE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_RESPONSE: begin
                    if (rsp_valid && rsp_ready)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
