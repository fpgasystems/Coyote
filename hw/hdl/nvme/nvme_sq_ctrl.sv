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
 * @brief   NVMe SQ controller
 *
 * Stores SQEs in BRAM (single AXI port for all devices) for SSD fetch.
 */
module nvme_sq_ctrl #(
    parameter int unsigned SQ_ADDR_BITS = 6,  // 64 entries per device
    parameter int unsigned N_NVME_BITS  = 4   // number of NVMe devices bits
)(
    input  logic        aclk,
    input  logic        aresetn,

    // From cmd_sqe stage
    metaIntf.s          s_sqe,       // nvme_sqe_t

    // AXI access to observe/debug SQE contents (512-bit view)
    AXI4.s              s_axi_nvme_sq
);

    localparam int unsigned ADDR_BITS = SQ_ADDR_BITS + N_NVME_BITS;

    localparam int unsigned BRAM_BYTE_BITS  = 6;  // log2(512/8)
    localparam int unsigned BRAM_ADDR_WIDTH = ADDR_BITS + BRAM_BYTE_BITS;  // 16

    // Write port A (from s_sqe)
    logic                      a_en;
    logic [24:0]               a_we;
    logic [ADDR_BITS-1:0]      a_addr;
    logic [199:0]              a_data_in;

    // Read port B (from AXI BRAM controller)
    logic                      bram_en_a;
    logic [BRAM_ADDR_WIDTH-1:0] bram_addr_a;    // full byte address
    logic [ADDR_BITS-1:0]      b_addr;           // entry index into RAM
    logic [ADDR_BITS-1:0]      b_addr_q;         // 1-cycle delayed for CID alignment
    logic [199:0]              b_data_out;

    // 512-bit SQE view presented to AXI bram controller
    logic [511:0]              sq_entry_wire;

    // BRAM controller instance (AXI read address in, read data back).
    logic [63:0]                  sq_bram_awaddr;
    logic [1:0]                   sq_bram_awburst;
    logic [3:0]                   sq_bram_awcache;
    logic [AXI_ID_BITS-1:0]       sq_bram_awid;
    logic [7:0]                   sq_bram_awlen;
    logic [0:0]                   sq_bram_awlock;
    logic [2:0]                   sq_bram_awprot;
    logic [3:0]                   sq_bram_awqos;
    logic [3:0]                   sq_bram_awregion;
    logic [2:0]                   sq_bram_awsize;
    logic                         sq_bram_awvalid;
    logic                         sq_bram_awready;

    logic [AXI_DATA_BITS-1:0]     sq_bram_wdata;
    logic [AXI_DATA_BITS/8-1:0]   sq_bram_wstrb;
    logic                         sq_bram_wlast;
    logic                         sq_bram_wvalid;
    logic                         sq_bram_wready;

    logic [1:0]                   sq_bram_bresp;
    logic                         sq_bram_bvalid;
    logic                         sq_bram_bready;
    logic [AXI_ID_BITS-1:0]       sq_bram_bid;

    logic [63:0]                  sq_bram_araddr;
    logic [1:0]                   sq_bram_arburst;
    logic [3:0]                   sq_bram_arcache;
    logic [AXI_ID_BITS-1:0]       sq_bram_arid;
    logic [7:0]                   sq_bram_arlen;
    logic [0:0]                   sq_bram_arlock;
    logic [2:0]                   sq_bram_arprot;
    logic [3:0]                   sq_bram_arqos;
    logic [3:0]                   sq_bram_arregion;
    logic [2:0]                   sq_bram_arsize;
    logic                         sq_bram_arvalid;
    logic                         sq_bram_arready;

    logic [AXI_DATA_BITS-1:0]     sq_bram_rdata;
    logic [1:0]                   sq_bram_rresp;
    logic                         sq_bram_rlast;
    logic                         sq_bram_rvalid;
    logic                         sq_bram_rready;
    logic [AXI_ID_BITS-1:0]       sq_bram_rid;

    `AXI_ASSIGN_I2S(s_axi_nvme_sq, sq_bram)

    nvme_sq_axi_bram_ctrl inst_nvme_sq_bram_ctrl (
        .s_axi_aclk       (aclk),
        .s_axi_aresetn     (aresetn),

        .s_axi_awaddr     (sq_bram_awaddr[BRAM_ADDR_WIDTH-1:0]),
        .s_axi_awlen      (sq_bram_awlen),
        .s_axi_awsize     (sq_bram_awsize),
        .s_axi_awburst    (sq_bram_awburst),
        .s_axi_awlock     (sq_bram_awlock),
        .s_axi_awcache    (sq_bram_awcache),
        .s_axi_awprot     (sq_bram_awprot),
        .s_axi_awvalid    (sq_bram_awvalid),
        .s_axi_awready    (sq_bram_awready),

        .s_axi_wdata      (sq_bram_wdata),
        .s_axi_wstrb      (sq_bram_wstrb),
        .s_axi_wlast      (sq_bram_wlast),
        .s_axi_wvalid     (sq_bram_wvalid),
        .s_axi_wready     (sq_bram_wready),

        .s_axi_bresp      (sq_bram_bresp),
        .s_axi_bvalid     (sq_bram_bvalid),
        .s_axi_bready     (sq_bram_bready),

        .s_axi_araddr     (sq_bram_araddr[BRAM_ADDR_WIDTH-1:0]),
        .s_axi_arlen      (sq_bram_arlen),
        .s_axi_arsize     (sq_bram_arsize),
        .s_axi_arburst    (sq_bram_arburst),
        .s_axi_arlock     (sq_bram_arlock),
        .s_axi_arcache    (sq_bram_arcache),
        .s_axi_arprot     (sq_bram_arprot),
        .s_axi_arvalid    (sq_bram_arvalid),
        .s_axi_arready    (sq_bram_arready),

        .s_axi_rdata      (sq_bram_rdata),
        .s_axi_rresp      (sq_bram_rresp),
        .s_axi_rlast      (sq_bram_rlast),
        .s_axi_rvalid     (sq_bram_rvalid),
        .s_axi_rready     (sq_bram_rready),

        .bram_addr_a      (bram_addr_a),
        .bram_clk_a       (),                 // tied
        .bram_wrdata_a    (),                 // tied (read-only view from AXI)
        .bram_rddata_a    (sq_entry_wire),    // 512-bit SQE view
        .bram_en_a        (bram_en_a),
        .bram_rst_a       (),                 // tied
        .bram_we_a        ()                  // tied
    );

    // byte address → entry index conversion
    //   bram_addr_a = byte address from IP
    //   b_addr      = entry index = bram_addr_a >> 6
    assign b_addr = bram_addr_a[BRAM_ADDR_WIDTH-1 : BRAM_BYTE_BITS];

    // Register b_addr (2 stages) to align CID with b_data_out
    logic [ADDR_BITS-1:0] b_addr_q1;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            b_addr_q1 <= '0;
            b_addr_q  <= '0;
        end else begin
            b_addr_q1 <= b_addr;
            b_addr_q  <= b_addr_q1;
        end
    end

    // SQ BRAM (1-cycle read latency + external reg = 2 total)
    logic [199:0] b_data_out_raw;

    ram_sdp_nc #(
        .ADDR_BITS (ADDR_BITS),
        .DATA_BITS (200)
    ) inst_nvme_sq_bram (
        .clk        (aclk),
        .a_en       (a_en),
        .a_we       (a_we),
        .a_addr     (a_addr),
        .a_data_in  (a_data_in),
        .b_en       (bram_en_a),
        .b_addr     (b_addr),
        .b_data_out (b_data_out_raw)
    );

    always_ff @(posedge aclk) begin
        if (!aresetn)
            b_data_out <= '0;
        else
            b_data_out <= b_data_out_raw;
    end

    // Ingress: cmd_sqe -> BRAM write
    // Store layout (200b):
    // [  3:  0] cmd4
    // [  7:  4] nsid4
    // [ 71:  8] prp1  (64)
    // [135: 72] prp2  (64)
    // [183:136] slba48
    // [199:184] nlba16
    always_comb begin
        logic [3:0] cmd4;
        logic [3:0] nsid4;

        cmd4  = s_sqe.data.writeRead ? 4'd1 : 4'd2; // WRITE=1, READ=2
        nsid4 = s_sqe.data.nsid[3:0];

        a_en      = s_sqe.valid;
        a_we      = {25{s_sqe.valid}};
        a_addr    = s_sqe.data.entry;

        a_data_in = '0;
        a_data_in[3:0]     = cmd4;
        a_data_in[7:4]     = nsid4;
        a_data_in[71:8]    = s_sqe.data.prp1;
        a_data_in[135:72]  = s_sqe.data.prp2;
        a_data_in[183:136] = s_sqe.data.slba[47:0];
        a_data_in[199:184] = s_sqe.data.nlba[15:0];

        s_sqe.ready = 1'b1;
    end

    // Egress: BRAM (200b) -> 512b NVMe SQE view for AXI reads
    // CID from registered b_addr_q
    always_comb begin
        logic [15:0] cid16;
        logic [7:0]  opcode8;
        logic [31:0] nsid32;
        logic [63:0] prp1_64;
        logic [63:0] prp2_64;
        logic [63:0] slba64;
        logic [15:0] nlba16;

        cid16   = {{(16-ADDR_BITS){1'b0}}, b_addr_q};   // registered addr
        opcode8 = {4'b0, b_data_out[3:0]};
        nsid32  = {28'b0, b_data_out[7:4]};
        prp1_64 = b_data_out[71:8];
        prp2_64 = b_data_out[135:72];
        slba64  = {16'b0, b_data_out[183:136]};
        nlba16  = b_data_out[199:184];

        sq_entry_wire = '0;

        // DW0: OPC + FUSE/RSVD + CID
        sq_entry_wire[7:0]   = opcode8;
        sq_entry_wire[15:8]  = 8'h00;
        sq_entry_wire[31:16] = cid16;

        // DW1: NSID
        sq_entry_wire[63:32] = nsid32;

        // DW2..DW5 reserved
        sq_entry_wire[32*2+31:32*2+0] = 32'h0;
        sq_entry_wire[32*3+31:32*3+0] = 32'h0;
        sq_entry_wire[32*4+31:32*4+0] = 32'h0;
        sq_entry_wire[32*5+31:32*5+0] = 32'h0;

        // DW6..DW9 PRP1/PRP2
        sq_entry_wire[32*6+31:32*6+0] = prp1_64[31:0];
        sq_entry_wire[32*7+31:32*7+0] = prp1_64[63:32];
        sq_entry_wire[32*8+31:32*8+0] = prp2_64[31:0];
        sq_entry_wire[32*9+31:32*9+0] = prp2_64[63:32];

        // DW10..DW11 SLBA
        sq_entry_wire[32*10+31:32*10+0] = slba64[31:0];
        sq_entry_wire[32*11+31:32*11+0] = slba64[63:32];

        // DW12 NLB
        sq_entry_wire[32*12+15:32*12+0]  = nlba16;
        sq_entry_wire[32*12+31:32*12+16] = 16'h0;

        // DW13..DW15 reserved
        sq_entry_wire[32*13+31:32*13+0] = 32'h0;
        sq_entry_wire[32*14+31:32*14+0] = 32'h0;
        sq_entry_wire[32*15+31:32*15+0] = 32'h0;
    end

    // ILA Debug
// `define EN_ILA_NVME_SQ_CTRL
`ifdef EN_ILA_NVME_SQ_CTRL
    ila_nvme_sq_ctrl inst_ila_nvme_sq_ctrl (
        .clk    (aclk),
        // -- Ingress (FPGA writes SQE to BRAM) --
        .probe0 (s_sqe.valid),                          // 1
        .probe1 (s_sqe.ready),                          // 1
        .probe2 (s_sqe.data.dev_id),                    // N_NVME_BITS (4)
        .probe3 (s_sqe.data.entry),                     // N_NVME_BITS+NVME_QUEUE_BITS (10)
        .probe4 (bram_en_a),                            // 1
        .probe5 (a_addr),                               // ADDR_BITS (10)
        .probe6 (a_en),                                 // 1
        .probe7 (b_addr),                               // ADDR_BITS (10)
        .probe8 (b_addr_q),                             // ADDR_BITS (10)
        // -- Egress: SQE fields SSD reads --
        .probe9 (sq_entry_wire[31:0]),                  // 32  DW0: {CID[31:16], 8'h0, opcode[7:0]}
        .probe10(sq_entry_wire[63:32]),                 // 32  DW1: NSID
        .probe11(sq_entry_wire[32*6+31:32*6]),          // 32  DW6: PRP1[31:0]
        .probe12(sq_entry_wire[32*7+31:32*7]),          // 32  DW7: PRP1[63:32]
        .probe13(sq_entry_wire[32*10+31:32*10]),        // 32  DW10: SLBA[31:0]
        .probe14(sq_entry_wire[32*11+31:32*11]),        // 32  DW11: SLBA[63:32]
        .probe15(sq_entry_wire[32*12+31:32*12])         // 32  DW12: {16'h0, NLBA[15:0]}
    );
`endif

endmodule
