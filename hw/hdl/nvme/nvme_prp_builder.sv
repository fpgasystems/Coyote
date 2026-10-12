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

/**
 * @brief   NVMe PRP builder
 *
 * Translates a PRP request via the MMU and emits the PRP response and PRP-list
 * writes, handling 4 KB, 8 KB, and multi-page transfers.
 */
module nvme_prp_builder #(
    parameter integer PRP_ADDR_BITS = lynxTypes::PRP_ADDR_BITS
)(
    input  logic        aclk,
    input  logic        aresetn,

    metaIntf.s          s_nvme_prp_req,       // nvme_prp_req_t
    metaIntf.m          m_nvme_prp_rsp,       // nvme_prp_rsp_t
    output logic       m_prp_fault,          // accompanies PRP response handshake

    metaIntf.m          m_nvme_mmu_req,       // req_t (strm=STRM_NVME)
    metaIntf.s          s_nvme_mmu_rsp,       // nvme_mmu_rsp_t

    metaIntf.m          m_nvme_prp_write_req, // nvme_prp_write_t

    input  logic [63:0] FPGA_BAR_BASE,
    input  logic [63:0] FPGA_PRP_BAR_BASE
);

    // PRP-list window: one 4-KiB page per CID and a fixed 1-MiB stride per
    // device (256 pages), whatever the configured queue depth.
    localparam int unsigned PRP_DEV_STRIDE_BITS = 20;

`ifdef EN_NVME_PL
    // PG344 programs a 16-TiB inbound Root-Port aperture at this PCIe base and
    // removes the base again: PCIe address = PL_RP_DMA_PCIE_BASE + BD-local
    // address. The aperture cannot grow; qdma_0 translates at most 2^44 bytes.
    localparam logic [63:0] PL_RP_DMA_PCIE_BASE =
        64'h0000_1000_0000_0000;

    // BD-local [0, 8 TiB) is the host window, an identity map: host physical
    // address P is BD-local P. SmartConnect selects axi_nvme_host for it and
    // nvme_axi_host_bridge passes the address through.
    localparam logic [63:0] PL_HOST_ROUTE_BASE =
        64'h0000_0000_0000_0000;
    localparam logic [63:0] PL_HOST_ROUTE_SIZE =
        64'h0000_0800_0000_0000;

    // BD-local [8 TiB, 12 TiB) is the card window. shell_top subtracts this
    // base before axi_nvme_card_mem, so card memory sees zero-based addresses.
    localparam logic [63:0] PL_CARD_ROUTE_BASE =
        64'h0000_0800_0000_0000;

    // SSD-visible address of the 16-MiB PRP-list window. PG344 translates it
    // to the BD-local axi_nvme_prp segment at 0x0FFF_F500_0000.
    localparam logic [63:0] PL_PRP_PCIE_BASE =
        64'h0000_1FFF_F500_0000;

    function automatic logic [63:0] pl_extend_paddr(
        input logic [PADDR_BITS-1:0] paddr
    );
        pl_extend_paddr = {{(64-PADDR_BITS){1'b0}}, paddr};
    endfunction

    function automatic logic pl_host_paddr_valid(
        input logic [PADDR_BITS-1:0] paddr
    );
        // Host addresses must fit in the 8 TiB host window. The window size is
        // a power of two, so this tests that no bit at or above it is set.
        pl_host_paddr_valid =
            ((pl_extend_paddr(paddr) & ~(PL_HOST_ROUTE_SIZE - 64'd1)) == 64'd0);
    endfunction

    function automatic logic [63:0] pl_encode_paddr(
        input logic [PADDR_BITS-1:0] paddr,
        input logic                  is_host
    );
        // The terms occupy disjoint bits, so OR equals the sum: the aperture
        // base is bit 44 and the card window base bit 43; a host paddr is
        // below 8 TiB (pl_host_paddr_valid faults otherwise) and a card
        // address is far below 8 TiB (card memory is tens of GiB).
        pl_encode_paddr = pl_extend_paddr(paddr) | PL_RP_DMA_PCIE_BASE |
                          (is_host ? PL_HOST_ROUTE_BASE : PL_CARD_ROUTE_BASE);
    endfunction

`ifndef SYNTHESIS
    initial assert (PL_HOST_ROUTE_BASE == 64'd0 &&
                    (PL_HOST_ROUTE_SIZE & (PL_HOST_ROUTE_SIZE - 64'd1)) == 64'd0 &&
                    (PL_CARD_ROUTE_BASE & (PL_CARD_ROUTE_BASE - 64'd1)) == 64'd0 &&
                    (PL_RP_DMA_PCIE_BASE & (PL_RP_DMA_PCIE_BASE - 64'd1)) == 64'd0 &&
                    PL_CARD_ROUTE_BASE >= PL_HOST_ROUTE_SIZE &&
                    PL_RP_DMA_PCIE_BASE > PL_CARD_ROUTE_BASE)
        else $fatal(1, "nvme_prp_builder: PL route bases must be disjoint single bits above the host window");
    initial assert (PL_PRP_PCIE_BASE[N_NVME_BITS+PRP_DEV_STRIDE_BITS-1:0] == '0 &&
                    NVME_QUEUE_BITS + 12 <= PRP_DEV_STRIDE_BITS)
        else $fatal(1, "nvme_prp_builder: PRP-list base must clear the device and CID fields");
`endif
`endif

    // State machine
    typedef enum logic [3:0] {
        ST_IDLE              = 4'd0,
        ST_SEND_MMU_PRP1     = 4'd1,
        ST_WAIT_MMU_PRP1     = 4'd2,
        ST_CHECK_SIZE        = 4'd3,
        ST_SEND_PRP_4KB      = 4'd4,
        ST_SEND_MMU_PRP2     = 4'd5,
        ST_WAIT_MMU_PRP2     = 4'd6,
        ST_SEND_PRP_8KB      = 4'd7,
        ST_SEND_PRP_MULT     = 4'd8,
        ST_SEND_WRITE_MULT   = 4'd9,
        ST_WAIT_MMU_MULT     = 4'd10,
        ST_SEND_WRITE_LOOP   = 4'd11,
        ST_FAULT             = 4'd12
    } state_t;

    state_t          state_C, state_N;

    // Registered data
    nvme_prp_req_t   prp_req_C, prp_req_N;
    nvme_prp_rsp_t   prp_rsp_C, prp_rsp_N;
    nvme_prp_write_t prp_write_C, prp_write_N;
    nvme_mmu_rsp_t   mmu_rsp_C, mmu_rsp_N;

    // Temporaries (module scope)
    req_t            mmu_req;

    // Combinational logic
    always_comb begin
        // Defaults
        state_N     = state_C;
        prp_req_N   = prp_req_C;
        prp_rsp_N   = prp_rsp_C;
        prp_write_N = prp_write_C;
        mmu_rsp_N   = mmu_rsp_C;

        s_nvme_prp_req.ready       = 1'b0;
        m_nvme_mmu_req.valid       = 1'b0;
        m_nvme_mmu_req.data        = '0;

        s_nvme_mmu_rsp.ready       = 1'b0;

        m_nvme_prp_rsp.valid       = 1'b0;
        m_nvme_prp_rsp.data        = '0;
        m_prp_fault               = 1'b0;

        m_nvme_prp_write_req.valid = 1'b0;
        m_nvme_prp_write_req.data  = '0;

        mmu_req = '0;

        case (state_C)
            // ST_IDLE: Accept PRP request
            ST_IDLE: begin
                s_nvme_prp_req.ready = 1'b1;
                if (s_nvme_prp_req.valid) begin
                    prp_req_N = s_nvme_prp_req.data;
                    prp_rsp_N = '0;
                    state_N   = ST_SEND_MMU_PRP1;
                end
            end

            // ST_SEND_MMU_PRP1: Send MMU request for PRP1
            ST_SEND_MMU_PRP1: begin
                mmu_req       = '0;
                mmu_req.strm  = STRM_NVME;
                mmu_req.vfid  = prp_req_C.vfid;
                mmu_req.vaddr = prp_req_C.vaddr;
                mmu_req.len   = prp_req_C.len;
                mmu_req.last  = 1'b1;

                m_nvme_mmu_req.valid = 1'b1;
                m_nvme_mmu_req.data  = mmu_req;

                if (m_nvme_mmu_req.ready) begin
                    state_N = ST_WAIT_MMU_PRP1;
                end
            end

            // ST_WAIT_MMU_PRP1: Receive MMU response for PRP1
            ST_WAIT_MMU_PRP1: begin
                s_nvme_mmu_rsp.ready = 1'b1;
                if (s_nvme_mmu_rsp.valid) begin
                    mmu_rsp_N = s_nvme_mmu_rsp.data;
                    // Translation fault → abort
                    if (s_nvme_mmu_rsp.data.fault)
                        state_N = ST_FAULT;
                    else
                        state_N = ST_CHECK_SIZE;
                end
            end

            // ST_CHECK_SIZE: Decide path based on transfer size
            ST_CHECK_SIZE: begin
                // Set PRP1
                prp_rsp_N = prp_rsp_C;
`ifdef EN_NVME_PL
                if (mmu_rsp_C.is_host &&
                    !pl_host_paddr_valid(mmu_rsp_C.paddr)) begin
                    // Host physical addresses >= 8 TiB lie outside the host
                    // window and cannot be represented by the aperture.
                    state_N = ST_FAULT;
                end else begin
                    prp_rsp_N.prp1 = pl_encode_paddr(
                        mmu_rsp_C.paddr, mmu_rsp_C.is_host);
`else
                if (mmu_rsp_C.is_host == 1'b0)
                    prp_rsp_N.prp1 = mmu_rsp_C.paddr + FPGA_BAR_BASE;
                else
                    prp_rsp_N.prp1 = mmu_rsp_C.paddr;
`endif

                if (prp_req_C.len <= 4096) begin
                    // 4KB: Only PRP1 needed
                    prp_rsp_N.prp2 = 64'd0;
                    state_N = ST_SEND_PRP_4KB;
                end
                else begin
                    // >4KB: Need PRP2, send MMU request
                    state_N = ST_SEND_MMU_PRP2;
                end
`ifdef EN_NVME_PL
                end
`endif
            end

            // ST_SEND_PRP_4KB: Send PRP response (4KB case)
            ST_SEND_PRP_4KB: begin
                m_nvme_prp_rsp.valid = 1'b1;
                m_nvme_prp_rsp.data  = prp_rsp_C;

                if (m_nvme_prp_rsp.ready) begin
                    state_N = ST_IDLE;
                end
            end

            // ST_SEND_MMU_PRP2: Send MMU request for PRP2 (>4KB)
            ST_SEND_MMU_PRP2: begin
                // MMU continues streaming from previous request
                // Just wait for next response
                state_N = ST_WAIT_MMU_PRP2;
            end

            // ST_WAIT_MMU_PRP2: Receive MMU response for PRP2
            ST_WAIT_MMU_PRP2: begin
                s_nvme_mmu_rsp.ready = 1'b1;
                if (s_nvme_mmu_rsp.valid) begin
                    mmu_rsp_N = s_nvme_mmu_rsp.data;

                    if (s_nvme_mmu_rsp.data.fault
`ifdef EN_NVME_PL
                        || (s_nvme_mmu_rsp.data.is_host &&
                            !pl_host_paddr_valid(s_nvme_mmu_rsp.data.paddr))
`endif
                    ) begin
                        // Translation fault → abort
                        state_N = ST_FAULT;
                    end
                    else if (prp_req_C.len <= 8192) begin
                        // 8KB: PRP2 is direct address
                        prp_rsp_N = prp_rsp_C;
`ifdef EN_NVME_PL
                        prp_rsp_N.prp2 = pl_encode_paddr(
                            s_nvme_mmu_rsp.data.paddr,
                            s_nvme_mmu_rsp.data.is_host);
`else
                        if (s_nvme_mmu_rsp.data.is_host == 1'b0)
                            prp_rsp_N.prp2 = s_nvme_mmu_rsp.data.paddr + FPGA_BAR_BASE;
                        else
                            prp_rsp_N.prp2 = s_nvme_mmu_rsp.data.paddr;
`endif
                        state_N = ST_SEND_PRP_8KB;
                    end
                    else begin
                        // >8KB: PRP2 points to PRP list
                        prp_rsp_N = prp_rsp_C;
`ifdef EN_NVME_PL
                        // Disjoint fields: 16-MiB aligned base, device in
                        // [23:20], CID page in [19:12]; OR equals the sum.
                        prp_rsp_N.prp2 = PL_PRP_PCIE_BASE
                                       | ({{(64-N_NVME_BITS){1'b0}},
                                            prp_req_C.dev_id}
                                          << PRP_DEV_STRIDE_BITS)
                                       | ({{(64-NVME_QUEUE_BITS){1'b0}},
                                            prp_req_C.sq_tail} << 12);
`else
                        prp_rsp_N.prp2 = FPGA_PRP_BAR_BASE
                                       + ({{(64-N_NVME_BITS){1'b0}},
                                            prp_req_C.dev_id}
                                          << PRP_DEV_STRIDE_BITS)
                                       + ({{(64-NVME_QUEUE_BITS){1'b0}},
                                            prp_req_C.sq_tail} << 12);
`endif

                        // Prepare first write entry
                        prp_write_N.addr = {prp_req_C.dev_id, prp_req_C.sq_tail, {PRP_ADDR_BITS{1'b0}}};
`ifdef EN_NVME_PL
                        prp_write_N.data = pl_encode_paddr(
                            s_nvme_mmu_rsp.data.paddr,
                            s_nvme_mmu_rsp.data.is_host);
`else
                        if (s_nvme_mmu_rsp.data.is_host == 1'b0)
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr + FPGA_BAR_BASE;
                        else
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr;
`endif

                        // Do not expose PRP2 until its entire list is stored.
                        // prp_req_C.sq_tail carries the allocated CID/PRP slot.
                        state_N = ST_SEND_WRITE_MULT;
                    end
                end
            end

            // ST_SEND_PRP_8KB: Send PRP response (8KB case)
            ST_SEND_PRP_8KB: begin
                m_nvme_prp_rsp.valid = 1'b1;
                m_nvme_prp_rsp.data  = prp_rsp_C;

                if (m_nvme_prp_rsp.ready) begin
                    state_N = ST_IDLE;
                end
            end

            // Publish success only after the final list write reaches PRP RAM.
            ST_SEND_PRP_MULT: begin
                m_nvme_prp_rsp.valid = 1'b1;
                m_nvme_prp_rsp.data  = prp_rsp_C;

                if (m_nvme_prp_rsp.ready) begin
                    state_N = ST_IDLE;
                end
            end

            // ST_SEND_WRITE_MULT: Send first PRP list write
            ST_SEND_WRITE_MULT: begin
                m_nvme_prp_write_req.valid = 1'b1;
                m_nvme_prp_write_req.data  = prp_write_C;

                if (m_nvme_prp_write_req.ready) begin
                    prp_write_N.addr = prp_write_C.addr + 1'b1;
                    state_N = mmu_rsp_C.last ? ST_SEND_PRP_MULT : ST_WAIT_MMU_MULT;
                end
            end

            // ST_WAIT_MMU_MULT: Wait for next MMU response
            ST_WAIT_MMU_MULT: begin
                s_nvme_mmu_rsp.ready = 1'b1;
                if (s_nvme_mmu_rsp.valid) begin
                    mmu_rsp_N = s_nvme_mmu_rsp.data;

                    if (s_nvme_mmu_rsp.data.fault
`ifdef EN_NVME_PL
                        || (s_nvme_mmu_rsp.data.is_host &&
                            !pl_host_paddr_valid(s_nvme_mmu_rsp.data.paddr))
`endif
                    ) begin
                        // Translation fault → abort
                        state_N = ST_FAULT;
                    end
                    else begin
                        // Prepare write data
                        prp_write_N = prp_write_C;
`ifdef EN_NVME_PL
                        prp_write_N.data = pl_encode_paddr(
                            s_nvme_mmu_rsp.data.paddr,
                            s_nvme_mmu_rsp.data.is_host);
`else
                        if (s_nvme_mmu_rsp.data.is_host == 1'b0)
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr + FPGA_BAR_BASE;
                        else
                            prp_write_N.data = s_nvme_mmu_rsp.data.paddr;
`endif

                        state_N = ST_SEND_WRITE_LOOP;
                    end
                end
            end

            // ST_SEND_WRITE_LOOP: Send PRP list write entries
            ST_SEND_WRITE_LOOP: begin
                m_nvme_prp_write_req.valid = 1'b1;
                m_nvme_prp_write_req.data  = prp_write_C;

                if (m_nvme_prp_write_req.ready) begin
                    if (mmu_rsp_C.last) begin
                        // Last entry written
                        state_N = ST_SEND_PRP_MULT;
                    end
                    else if (&prp_write_C.addr[PRP_ADDR_BITS-1:0]) begin
                        // A list must never wrap into another CID's storage.
                        // Drain remaining translations and fail unpublished.
                        state_N = ST_FAULT;
                    end
                    else begin
                        // More entries to come
                        prp_write_N.addr = prp_write_C.addr + 1'b1;
                        state_N = ST_WAIT_MMU_MULT;
                    end
                end
            end

            // MMU faults terminate with last=1. Local address rejection or
            // list overflow can precede further responses: drain through last
            // to preserve pairing with the next command, then return failure.
            ST_FAULT: begin
                if (!mmu_rsp_C.last) begin
                    s_nvme_mmu_rsp.ready = 1'b1;
                    if (s_nvme_mmu_rsp.valid) mmu_rsp_N = s_nvme_mmu_rsp.data;
                end else begin
                    m_nvme_prp_rsp.valid = 1'b1;
                    m_prp_fault = 1'b1;
                    if (m_nvme_prp_rsp.ready) state_N = ST_IDLE;
                end
            end

            default: begin
                state_N = ST_IDLE;
            end
        endcase
    end

    // Sequential logic
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_C     <= ST_IDLE;
            prp_req_C   <= '0;
            prp_rsp_C   <= '0;
            prp_write_C <= '0;
            mmu_rsp_C   <= '0;
        end
        else begin
            state_C     <= state_N;
            prp_req_C   <= prp_req_N;
            prp_rsp_C   <= prp_rsp_N;
            prp_write_C <= prp_write_N;
            mmu_rsp_C   <= mmu_rsp_N;
        end
    end

    // ILA Debug
// `define EN_ILA_NVME_MANAGE_PRP
`ifdef EN_ILA_NVME_MANAGE_PRP
    ila_nvme_manage_prp inst_ila_nvme_manage_prp (
        .clk    (aclk),
        .probe0 (s_nvme_prp_req.valid),                 // 1
        .probe1 (s_nvme_prp_req.ready),                 // 1
        .probe2 (m_nvme_prp_rsp.valid),                 // 1
        .probe3 (m_nvme_prp_rsp.ready),                 // 1
        .probe4 (m_nvme_prp_rsp.data.prp1),             // 64
        .probe5 (m_nvme_prp_rsp.data.prp2),             // 64
        .probe6 (m_nvme_mmu_req.valid),                 // 1
        .probe7 (m_nvme_mmu_req.ready),                 // 1
        .probe8 (s_nvme_mmu_rsp.valid),                 // 1
        .probe9 (s_nvme_mmu_rsp.ready),                 // 1
        .probe10(48'(s_nvme_mmu_rsp.data.paddr)),       // Existing 48-bit ILA address probe
        .probe11(s_nvme_mmu_rsp.data.fault),            // 1
        .probe12(m_nvme_prp_write_req.valid),           // 1
        .probe13(m_nvme_prp_write_req.ready),           // 1
        .probe14(state_C),                              // 4
        .probe15(FPGA_BAR_BASE)                         // 64
    );
`endif

endmodule
