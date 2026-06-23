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

import lynxTypes::*;

`include "axi_macros.svh"

/**
 * @brief   NVMe PRP-list controller
 *
 * Stores PRP-list entries in BRAM and serves them to the SSD over the AXI port.
 */
module nvme_prp_ctrl #(
    parameter integer NVME_QUEUE_BITS = lynxTypes::NVME_QUEUE_BITS,  // Default: 6 (64 entries)
    parameter integer PRP_ADDR_BITS   = lynxTypes::PRP_ADDR_BITS,    // Default: 5 (32 entries, 128KB max)
    parameter integer N_NVME_BITS     = lynxTypes::N_NVME_BITS,      // Default: 2 (4 devices)
    parameter integer PRP_AXI_OFFSET  = 0                             // BD residual offset (0 when base is EXT_ADDR_WIDTH-aligned)
)(
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_prp,          // nvme_prp_write_t {addr, data}

    AXI4.s              s_axi_nvme_prp      // AXI slave for host read access
);

    // Derived Parameters
    // Internal BRAM address: {dev_id, queue_idx, prp_entry}
    localparam integer unsigned ADDR_BITS = N_NVME_BITS + NVME_QUEUE_BITS + PRP_ADDR_BITS;

    // AXI BRAM Controller (DATA_WIDTH=64) outputs byte addresses
    // Each AXI word = 8 bytes → byte offset bits = log2(8) = 3
    localparam integer unsigned PRP_DATA_BYTES  = 8;                              // 64-bit PRP entry
    localparam integer unsigned BRAM_BYTE_BITS  = $clog2(PRP_DATA_BYTES);         // = 3

    // External: NVMe spec requires PRP list to be 4KB page-aligned
    // Each queue occupies 4KB in BAR space, but only PRP_ADDR_BITS entries used internally
    localparam integer unsigned EXT_PAGE_BITS   = 12;                             // 4KB page
    localparam integer unsigned EXT_ADDR_WIDTH  = N_NVME_BITS + NVME_QUEUE_BITS + EXT_PAGE_BITS;

    // Internal Signals

    // Write port A (from s_prp pipeline)
    logic                      a_en;
    logic [PRP_DATA_BYTES-1:0] a_we;
    logic [ADDR_BITS-1:0]      a_addr;
    logic [63:0]               a_data_in;

    // Read port B (from AXI BRAM controller)
    logic                      bram_en_a;
    logic [EXT_ADDR_WIDTH-1:0] bram_addr_a;      // Full external byte address from AXI BRAM ctrl
    logic [ADDR_BITS-1:0]      b_addr;           // Entry index into RAM
    logic [63:0]               b_data_out;

    // 64-bit read data back to AXI BRAM Controller
    logic [63:0]               bram_rddata_wire;

    // AXI BRAM Controller (DATA_WIDTH=64)
    logic [63:0]                  prp_bram_awaddr;
    logic [1:0]                   prp_bram_awburst;
    logic [3:0]                   prp_bram_awcache;
    logic [AXI_ID_BITS-1:0]       prp_bram_awid;
    logic [7:0]                   prp_bram_awlen;
    logic [0:0]                   prp_bram_awlock;
    logic [2:0]                   prp_bram_awprot;
    logic [3:0]                   prp_bram_awqos;
    logic [3:0]                   prp_bram_awregion;
    logic [2:0]                   prp_bram_awsize;
    logic                         prp_bram_awvalid;
    logic                         prp_bram_awready;

    logic [AXI_DATA_BITS-1:0]     prp_bram_wdata;
    logic [AXI_DATA_BITS/8-1:0]   prp_bram_wstrb;
    logic                         prp_bram_wlast;
    logic                         prp_bram_wvalid;
    logic                         prp_bram_wready;

    logic [1:0]                   prp_bram_bresp;
    logic                         prp_bram_bvalid;
    logic                         prp_bram_bready;
    logic [AXI_ID_BITS-1:0]       prp_bram_bid;

    logic [63:0]                  prp_bram_araddr;
    logic [1:0]                   prp_bram_arburst;
    logic [3:0]                   prp_bram_arcache;
    logic [AXI_ID_BITS-1:0]       prp_bram_arid;
    logic [7:0]                   prp_bram_arlen;
    logic [0:0]                   prp_bram_arlock;
    logic [2:0]                   prp_bram_arprot;
    logic [3:0]                   prp_bram_arqos;
    logic [3:0]                   prp_bram_arregion;
    logic [2:0]                   prp_bram_arsize;
    logic                         prp_bram_arvalid;
    logic                         prp_bram_arready;

    logic [AXI_DATA_BITS-1:0]     prp_bram_rdata;
    logic [1:0]                   prp_bram_rresp;
    logic                         prp_bram_rlast;
    logic                         prp_bram_rvalid;
    logic                         prp_bram_rready;
    logic [AXI_ID_BITS-1:0]       prp_bram_rid;

    `AXI_ASSIGN_I2S(s_axi_nvme_prp, prp_bram)

    nvme_prp_axi_bram_ctrl inst_nvme_prp_bram_ctrl (
        .s_axi_aclk       (aclk),
        .s_axi_aresetn    (aresetn),

        .s_axi_awaddr     (prp_bram_awaddr[EXT_ADDR_WIDTH-1:0]),
        .s_axi_awlen      (prp_bram_awlen),
        .s_axi_awsize     (prp_bram_awsize),
        .s_axi_awburst    (prp_bram_awburst),
        .s_axi_awlock     (prp_bram_awlock),
        .s_axi_awcache    (prp_bram_awcache),
        .s_axi_awprot     (prp_bram_awprot),
        .s_axi_awvalid    (prp_bram_awvalid),
        .s_axi_awready    (prp_bram_awready),

        .s_axi_wdata      (prp_bram_wdata[63:0]),
        .s_axi_wstrb      (prp_bram_wstrb[PRP_DATA_BYTES-1:0]),
        .s_axi_wlast      (prp_bram_wlast),
        .s_axi_wvalid     (prp_bram_wvalid),
        .s_axi_wready     (prp_bram_wready),

        .s_axi_bresp      (prp_bram_bresp),
        .s_axi_bvalid     (prp_bram_bvalid),
        .s_axi_bready     (prp_bram_bready),

        .s_axi_araddr     (prp_bram_araddr[EXT_ADDR_WIDTH-1:0]),
        .s_axi_arlen      (prp_bram_arlen),
        .s_axi_arsize     (prp_bram_arsize),
        .s_axi_arburst    (prp_bram_arburst),
        .s_axi_arlock     (prp_bram_arlock),
        .s_axi_arcache    (prp_bram_arcache),
        .s_axi_arprot     (prp_bram_arprot),
        .s_axi_arvalid    (prp_bram_arvalid),
        .s_axi_arready    (prp_bram_arready),

        .s_axi_rdata      (prp_bram_rdata[63:0]),
        .s_axi_rresp      (prp_bram_rresp),
        .s_axi_rlast      (prp_bram_rlast),
        .s_axi_rvalid     (prp_bram_rvalid),
        .s_axi_rready     (prp_bram_rready),

        .bram_addr_a      (bram_addr_a),
        .bram_clk_a       (),
        .bram_wrdata_a    (),
        .bram_rddata_a    (bram_rddata_wire),
        .bram_en_a        (bram_en_a),
        .bram_rst_a       (),
        .bram_we_a        ()
    );

    // Address remapping: external 4KB page → internal PRP_ADDR_BITS entries
    //
    // BD interconnect does not translate addresses, so the full offset appears.
    // leaving a residual offset (PRP_AXI_OFFSET) in the slave address.
    // Subtract it before extracting {dev_id, sq_tail, entry_idx}.
    //
    // Clean byte addr: [EXT-1 : PAGE] = dev_id + sq_tail
    //                  [PAGE-1 : PRP+BYTE] = unused (always 0)
    //                  [PRP+BYTE-1 : BYTE] = entry_idx
    //                  [BYTE-1 : 0] = byte offset
    // Internal BRAM addr: {dev_id, sq_tail, entry_idx}
    logic [EXT_ADDR_WIDTH-1:0] bram_addr_clean;
    assign bram_addr_clean = bram_addr_a - PRP_AXI_OFFSET[EXT_ADDR_WIDTH-1:0];

    assign b_addr = {bram_addr_clean[EXT_ADDR_WIDTH-1 : EXT_PAGE_BITS],
                     bram_addr_clean[PRP_ADDR_BITS+BRAM_BYTE_BITS-1 : BRAM_BYTE_BITS]};

    // Read data: direct connection (64-bit AXI ↔ 64-bit BRAM)
    assign bram_rddata_wire = b_data_out;

    // Write path: s_prp -> BRAM
    assign a_en      = s_prp.valid;
    assign a_we      = {PRP_DATA_BYTES{s_prp.valid}};
    assign a_addr    = s_prp.data.addr[ADDR_BITS-1:0];
    assign a_data_in = s_prp.data.data;
    assign s_prp.ready = 1'b1;

    // Dual-port BRAM (1-cycle read latency)
    ram_sdp_nc #(
        .ADDR_BITS (ADDR_BITS),
        .DATA_BITS (64)
    ) inst_nvme_prp_bram (
        .clk        (aclk),
        .a_en       (a_en),
        .a_we       (a_we),
        .a_addr     (a_addr),
        .a_data_in  (a_data_in),
        .b_en       (bram_en_a),
        .b_addr     (b_addr),
        .b_data_out (b_data_out)
    );

    // ILA Debug
// `define EN_ILA_NVME_PRP_CTRL
`ifdef EN_ILA_NVME_PRP_CTRL
    ila_nvme_prp_ctrl inst_ila_nvme_prp_ctrl (
        .clk    (aclk),
        // Write port (from manage_prp)
        .probe0 (s_prp.valid),                          // 1
        .probe1 (s_prp.ready),                          // 1
        .probe2 (s_prp.data.addr),                      // ADDR_BITS
        .probe3 (s_prp.data.data[31:0]),                // 32
        .probe4 (a_en),                                 // 1
        .probe5 (a_addr),                               // ADDR_BITS
        .probe6 (a_data_in[31:0]),                      // 32
        // Read port (from AXI BRAM ctrl — NVMe device reads)
        .probe7 (bram_en_a),                            // 1
        .probe8 (bram_addr_a),                          // EXT_ADDR_WIDTH
        .probe9 (b_addr),                               // ADDR_BITS
        .probe10(b_data_out[31:0]),                     // 32
        .probe11(b_data_out[63:32]),                    // 32
        // AXI read channel
        .probe12(s_axi_nvme_prp.arvalid),                   // 1
        .probe13(s_axi_nvme_prp.arready),                   // 1
        .probe14(s_axi_nvme_prp.araddr[19:0]),              // 20
        .probe15(s_axi_nvme_prp.rvalid),                    // 1
        .probe16(s_axi_nvme_prp.rready),                    // 1
        .probe17(s_axi_nvme_prp.rdata[31:0]),               // 32
        .probe18(s_axi_nvme_prp.rdata[63:32])               // 32
    );
`endif

endmodule
