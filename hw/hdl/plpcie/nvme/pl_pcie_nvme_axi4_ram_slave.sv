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
// pl_pcie_nvme_axi4_ram_slave
// -----------------------------------------------------------------------------
// Small, deterministic AXI4-to-native-RAM bridge for NVMe queue/data memory.
//
// The intended connection is:
//
//   PG344 M_AXIB -> optional SmartConnect/width converter -> this slave
//
// SmartConnect should convert the PG344 data width to DATA_WIDTH (64 bits by
// default).  This module accepts INCR bursts, byte strobes, narrow transfers,
// and one transaction at a time.  Serializing reads and writes is intentional:
// it provides predictable ownership of one TDP-RAM port and is sufficient for
// first NVMe bring-up.  AXI IDs are returned unchanged.
//
// Address behavior is intentionally modulo the RAM size: high address bits
// are discarded.  Queue/PRP parameters therefore only need page alignment.
// -----------------------------------------------------------------------------
module pl_pcie_nvme_axi4_ram_slave #(
    parameter integer ADDR_WIDTH     = 64,
    parameter integer DATA_WIDTH     = 64,
    parameter integer ID_WIDTH       = 4,
    parameter integer RAM_ADDR_WIDTH = 11
) (
    input  wire                       aclk,
    input  wire                       aresetn,

    input  wire [ID_WIDTH-1:0]        s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire [7:0]                 s_axi_awlen,
    input  wire [2:0]                 s_axi_awsize,
    input  wire [1:0]                 s_axi_awburst,
    input  wire                       s_axi_awlock,
    input  wire [3:0]                 s_axi_awcache,
    input  wire [2:0]                 s_axi_awprot,
    input  wire [3:0]                 s_axi_awqos,
    input  wire [3:0]                 s_axi_awregion,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,

    input  wire [DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0]  s_axi_wstrb,
    input  wire                       s_axi_wlast,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,

    output wire [ID_WIDTH-1:0]        s_axi_bid,
    output wire [1:0]                 s_axi_bresp,
    output wire                       s_axi_bvalid,
    input  wire                       s_axi_bready,

    input  wire [ID_WIDTH-1:0]        s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire [7:0]                 s_axi_arlen,
    input  wire [2:0]                 s_axi_arsize,
    input  wire [1:0]                 s_axi_arburst,
    input  wire                       s_axi_arlock,
    input  wire [3:0]                 s_axi_arcache,
    input  wire [2:0]                 s_axi_arprot,
    input  wire [3:0]                 s_axi_arqos,
    input  wire [3:0]                 s_axi_arregion,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,

    output wire [ID_WIDTH-1:0]        s_axi_rid,
    output wire [DATA_WIDTH-1:0]      s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                       s_axi_rlast,
    output wire                       s_axi_rvalid,
    input  wire                       s_axi_rready,

    // Native RAM port.  Read data is valid one cycle after ram_en.
    output logic                      ram_en,
    output logic [(DATA_WIDTH/8)-1:0] ram_we,
    output logic [RAM_ADDR_WIDTH-1:0] ram_addr,
    output logic [DATA_WIDTH-1:0]     ram_wdata,
    input  wire [DATA_WIDTH-1:0]      ram_rdata,

    // Compact ILA probes.
    output wire [3:0]                 state_dbg,
    output logic [ADDR_WIDTH-1:0]     last_axi_addr,
    output logic [1:0]                last_axi_resp,
    output logic                      protocol_error
);

    localparam integer BYTE_LANES = DATA_WIDTH / 8;
    localparam integer BYTE_SHIFT = $clog2(BYTE_LANES);
    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;

    typedef enum logic [3:0] {
        ST_IDLE        = 4'h0,
        ST_WRITE_DATA  = 4'h1,
        ST_WRITE_RESP  = 4'h2,
        ST_READ_ISSUE  = 4'h4,
        ST_READ_WAIT   = 4'h5,
        ST_READ_SEND   = 4'h6
    } state_t;

    state_t state;

    logic [ID_WIDTH-1:0]   transaction_id;
    logic [ADDR_WIDTH-1:0] current_addr;
    logic [7:0]            burst_len;
    logic [7:0]            beat_index;
    logic [2:0]            transfer_size;
    logic [1:0]            burst_type;
    logic [1:0]            transaction_resp;
    logic [1:0]            read_beat_resp;
    logic                  read_beat_valid;
    logic [DATA_WIDTH-1:0] read_data_reg;

    wire [ADDR_WIDTH-1:0] bytes_this_beat =
        {{(ADDR_WIDTH-1){1'b0}}, 1'b1} << transfer_size;

    wire transfer_supported =
        (transfer_size <= BYTE_SHIFT) &&
        ((burst_type == 2'b01) ||
         ((burst_type == 2'b00) && (burst_len == 8'd0)));

    wire expected_last = (beat_index == burst_len);

    assign state_dbg = state;

    // Give writes priority if AWVALID and ARVALID arrive together.  The read
    // address remains unaccepted and may be retried once the write completes.
    assign s_axi_awready = aresetn && (state == ST_IDLE);
    assign s_axi_arready =
        aresetn && (state == ST_IDLE) && !s_axi_awvalid;
    assign s_axi_wready  = aresetn && (state == ST_WRITE_DATA);

    assign s_axi_bid    = transaction_id;
    assign s_axi_bresp  = transaction_resp;
    assign s_axi_bvalid = (state == ST_WRITE_RESP);

    assign s_axi_rid    = transaction_id;
    assign s_axi_rdata  = read_data_reg;
    assign s_axi_rresp  = read_beat_resp;
    assign s_axi_rlast  = expected_last;
    assign s_axi_rvalid = (state == ST_READ_SEND);

    // One native RAM operation is issued for each accepted write beat or each
    // read beat entering ST_READ_ISSUE.
    always_comb begin
        ram_en    = 1'b0;
        ram_we    = '0;
        ram_addr  = current_addr[BYTE_SHIFT +: RAM_ADDR_WIDTH];
        ram_wdata = s_axi_wdata;

        if ((state == ST_WRITE_DATA) && s_axi_wvalid && s_axi_wready &&
            transfer_supported) begin
            ram_en = 1'b1;
            ram_we = s_axi_wstrb;
        end else if ((state == ST_READ_ISSUE) &&
                     transfer_supported) begin
            ram_en = 1'b1;
            ram_we = '0;
        end
    end

    // Return the most severe response observed over a burst.
    function automatic logic [1:0] merge_response(
        input logic [1:0] old_response,
        input logic [1:0] new_response
    );
        begin
            if ((old_response != AXI_OKAY) ||
                     (new_response != AXI_OKAY))
                merge_response = AXI_SLVERR;
            else
                merge_response = AXI_OKAY;
        end
    endfunction

    // Sideband fields do not alter the local RAM behavior, but retaining them
    // on the port makes direct SmartConnect wiring straightforward.
    wire _unused_sidebands = ^{
        s_axi_awlock, s_axi_awcache, s_axi_awprot, s_axi_awqos,
        s_axi_awregion, s_axi_arlock, s_axi_arcache, s_axi_arprot,
        s_axi_arqos, s_axi_arregion
    };

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state            <= ST_IDLE;
            transaction_id   <= '0;
            current_addr     <= '0;
            burst_len        <= '0;
            beat_index       <= '0;
            transfer_size    <= BYTE_SHIFT;
            burst_type       <= 2'b01;
            transaction_resp <= AXI_OKAY;
            read_beat_resp   <= AXI_OKAY;
            read_beat_valid  <= 1'b0;
            read_data_reg    <= '0;
            last_axi_addr    <= '0;
            last_axi_resp    <= AXI_OKAY;
            protocol_error   <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    beat_index <= 8'd0;

                    if (s_axi_awvalid && s_axi_awready) begin
                        transaction_id <= s_axi_awid;
                        current_addr   <= s_axi_awaddr;
                        burst_len      <= s_axi_awlen;
                        transfer_size <= s_axi_awsize;
                        burst_type     <= s_axi_awburst;
                        last_axi_addr  <= s_axi_awaddr;

                        if ((s_axi_awsize > BYTE_SHIFT) ||
                            !((s_axi_awburst == 2'b01) ||
                              ((s_axi_awburst == 2'b00) &&
                               (s_axi_awlen == 8'd0)))) begin
                            transaction_resp <= AXI_SLVERR;
                            protocol_error   <= 1'b1;
                        end else begin
                            transaction_resp <= AXI_OKAY;
                        end
                        state <= ST_WRITE_DATA;
                    end else if (s_axi_arvalid && s_axi_arready) begin
                        transaction_id <= s_axi_arid;
                        current_addr   <= s_axi_araddr;
                        burst_len      <= s_axi_arlen;
                        transfer_size <= s_axi_arsize;
                        burst_type     <= s_axi_arburst;
                        last_axi_addr  <= s_axi_araddr;

                        if ((s_axi_arsize > BYTE_SHIFT) ||
                            !((s_axi_arburst == 2'b01) ||
                              ((s_axi_arburst == 2'b00) &&
                               (s_axi_arlen == 8'd0)))) begin
                            transaction_resp <= AXI_SLVERR;
                            protocol_error   <= 1'b1;
                        end else begin
                            transaction_resp <= AXI_OKAY;
                        end
                        state <= ST_READ_ISSUE;
                    end
                end

                ST_WRITE_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        last_axi_addr <= current_addr;

                        if (s_axi_wlast != expected_last) begin
                            transaction_resp <= merge_response(
                                transaction_resp, AXI_SLVERR
                            );
                        end

                        if (s_axi_wlast != expected_last) begin
                            protocol_error <= 1'b1;
                        end

                        // A conforming master asserts WLAST on the AWLEN beat.
                        // Also terminate on an early WLAST so a malformed test
                        // transaction cannot deadlock this diagnostic bridge.
                        if (expected_last || s_axi_wlast) begin
                            state <= ST_WRITE_RESP;
                        end else begin
                            beat_index <= beat_index + 1'b1;
                            if (burst_type == 2'b01)
                                current_addr <= current_addr + bytes_this_beat;
                        end
                    end
                end

                ST_WRITE_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        last_axi_resp <= transaction_resp;
                        state <= ST_IDLE;
                    end
                end

                ST_READ_ISSUE: begin
                    read_beat_valid <= transfer_supported;
                    read_beat_resp <= transaction_resp;

                    state <= ST_READ_WAIT;
                end

                ST_READ_WAIT: begin
                    read_data_reg <= read_beat_valid ? ram_rdata : '0;
                    state <= ST_READ_SEND;
                end

                ST_READ_SEND: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        last_axi_addr <= current_addr;
                        last_axi_resp <= read_beat_resp;

                        if (expected_last) begin
                            state <= ST_IDLE;
                        end else begin
                            beat_index <= beat_index + 1'b1;
                            if (burst_type == 2'b01)
                                current_addr <= current_addr + bytes_this_beat;
                            state <= ST_READ_ISSUE;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    initial begin
        if ((DATA_WIDTH < 8) || ((DATA_WIDTH % 8) != 0) ||
            ((1 << BYTE_SHIFT) != BYTE_LANES))
            $error("axi4_ram_slave: DATA_WIDTH must be a power-of-two byte width");
        if ((BYTE_SHIFT + RAM_ADDR_WIDTH) > ADDR_WIDTH)
            $error("pl_pcie_nvme_axi4_ram_slave: RAM address exceeds AXI width");
    end

    wire _unused_ok = _unused_sidebands;

endmodule
