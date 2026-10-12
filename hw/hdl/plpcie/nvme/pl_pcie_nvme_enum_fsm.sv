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
// pl_pcie_nvme_enum_fsm
// -----------------------------------------------------------------------------
// Processor-free PCIe enumeration sequencer for one NVMe endpoint connected
// directly below a PG344 AXI Bridge Root Port.
//
// The three abstract transaction interfaces map to three distinct PG344 paths:
//
//   cfg_*  -> normal S_AXIL port (ECAM configuration transactions)
//   csr_*  -> S_AXIL_CSR port (local bridge CSR/BDF-table programming)
//   mmio_* -> S_AXIB port (outbound memory requests to the NVMe BAR)
//
// The PG344 M_AXIB interface is the opposite direction: it carries inbound
// NVMe DMA requests toward DDR/HBM and is not driven by this recognition FSM.
//
// Supported first-bring-up topology:
//
//   Root Port 00:00.0 -> NVMe endpoint 01:00.0
//
// The sequence:
//   1. Waits for PG344 user_lnk_up (and, optionally, phy_ready).
//   2. Programs the Root Port primary/secondary/subordinate bus numbers.
//   3. Optionally probes and assigns the Root Port's 64-bit inbound DMA BAR.
//   4. Identifies the endpoint and verifies the NVMe class code.
//   5. Disables endpoint decoding, probes and assigns endpoint BAR0/BAR1.
//   6. Programs the Root Port Type-1 non-prefetchable memory window.
//   7. Enables Root Port and endpoint Memory Space / Bus Master operation.
//   8. Programs one PG344 AXI-BAR BDF-table entry through S_AXIL_CSR.
//   9. Reads the NVMe CAP and VS registers through S_AXIB.
//
// Deliberate restrictions:
//   * One endpoint/function; no switch traversal or multifunction scan.
//   * Endpoint BAR0 must be a memory BAR.
//   * Endpoint BAR and Type-1 forwarding window remain below 4 GiB.
//   * Endpoint BAR is non-prefetchable by default.
//   * One outbound AXI-BAR window and one BDF-table entry.
//   * The default BDF-table translation value is zero (identity mapping).
//   * MSI/MSI-X and NVMe queues are not configured here.
// -----------------------------------------------------------------------------
module pl_pcie_nvme_enum_fsm #(
    parameter integer CFG_ADDR_WIDTH = 32,
    parameter integer MMIO_ADDR_WIDTH = 64,

    // ECAM system/aperture base.  Use zero for a direct point-to-point
    // connection to PG344 S_AXIL.  A non-zero value is useful only when an AXI
    // interconnect maps the PG344 ECAM aperture into a larger system map.
    parameter logic [CFG_ADDR_WIDTH-1:0] ECAM_BASE = '0,

    // PL-side AXI address issued to PG344 S_AXIB for the endpoint BAR.
    parameter logic [MMIO_ADDR_WIDTH-1:0] NVME_MMIO_AXI_BASE =
        64'h0000_0000_8000_0000,

    // PCIe address assigned to the NVMe endpoint BAR0/BAR1.
    parameter logic [63:0] NVME_PCIE_BAR_BASE =
        64'h0000_0000_8000_0000,

    // Root Port BAR0/BAR1 is the inbound PCIe address aperture used later by
    // NVMe DMA.  A 16 TiB BAR is 2^44 bytes and requires 16 TiB alignment.
    parameter bit          PROGRAM_RP_DMA_BAR = 1'b1,
    parameter logic [63:0] RP_DMA_PCIE_BASE =
        64'h0000_1000_0000_0000,
    parameter logic [63:0] RP_DMA_EXPECTED_SIZE =
        64'h0000_1000_0000_0000,

    // PG344 slave-bridge (AXI-to-PCIe) BDF table.  Entry zero occupies
    // 0x2420..0x2434 on S_AXIL_CSR.  Translation value zero preserves the AXI
    // address, so NVME_MMIO_AXI_BASE must equal NVME_PCIE_BAR_BASE.
    parameter bit          PROGRAM_BDF_TABLE = 1'b1,
    parameter logic [31:0] BDF_TABLE_CSR_BASE = 32'h0000_2420,
    parameter logic [63:0] BDF_ADDR_TRANSLATION = 64'd0,
    parameter logic [11:0] BDF_FUNCTION_NUMBER = 12'd0,
    parameter logic [2:0]  BDF_PROTECTION_ID = 3'b000,

    parameter integer LINK_SETTLE_CYCLES = 1024,
    parameter integer CSR_READY_TIMEOUT_CYCLES = 1_000_000,
    // Highest PCIe Maximum Payload Size encoding that enumeration may select.
    // 0=128 B, 1=256 B, 2=512 B, 3=1024 B, 4=2048 B, 5=4096 B.
    parameter logic [2:0] PCIE_TARGET_MPS = 3'd3,
    parameter bit     REQUIRE_PHY_READY = 1'b1,
    parameter bit     REQUIRE_NVME_CLASS = 1'b1,
    parameter bit     REQUIRE_NON_PREFETCHABLE_BAR = 1'b1
) (
    input  wire                       clk,
    input  wire                       resetn,
    input  wire                       soft_reset,
    input  wire                       start,

    // PG344 global status outputs.
    input  wire                       user_lnk_up,
    input  wire                       phy_ready,
    input  wire                       csr_prog_done,

    // Abstract 32-bit ECAM command interface -> PG344 normal S_AXIL.
    output logic                      cfg_cmd_valid,
    input  wire                       cfg_cmd_ready,
    output logic                      cfg_cmd_write,
    output logic [CFG_ADDR_WIDTH-1:0] cfg_cmd_addr,
    output logic [31:0]               cfg_cmd_wdata,
    output logic [3:0]                cfg_cmd_wstrb,

    input  wire                       cfg_rsp_valid,
    output wire                       cfg_rsp_ready,
    input  wire [31:0]                cfg_rsp_rdata,
    input  wire [1:0]                 cfg_rsp_resp,
    input  wire                       cfg_rsp_timeout,

    // Abstract 32-bit bridge-CSR command interface -> PG344 S_AXIL_CSR.
    output logic                      csr_cmd_valid,
    input  wire                       csr_cmd_ready,
    output logic                      csr_cmd_write,
    output logic [31:0]               csr_cmd_addr,
    output logic [31:0]               csr_cmd_wdata,
    output logic [3:0]                csr_cmd_wstrb,

    input  wire                       csr_rsp_valid,
    output wire                       csr_rsp_ready,
    input  wire [31:0]                csr_rsp_rdata,
    input  wire [1:0]                 csr_rsp_resp,
    input  wire                       csr_rsp_timeout,

    // Abstract 64-bit endpoint-MMIO command interface -> PG344 S_AXIB.
    output logic                      mmio_cmd_valid,
    input  wire                       mmio_cmd_ready,
    output logic                      mmio_cmd_write,
    output logic [MMIO_ADDR_WIDTH-1:0] mmio_cmd_addr,
    output logic [63:0]               mmio_cmd_wdata,
    output logic [7:0]                mmio_cmd_wstrb,
    output logic [2:0]                mmio_cmd_size,

    input  wire                       mmio_rsp_valid,
    output wire                       mmio_rsp_ready,
    input  wire [63:0]                mmio_rsp_rdata,
    input  wire [1:0]                 mmio_rsp_resp,
    input  wire                       mmio_rsp_timeout,

    // Latched recognition results for VIO/ILA or downstream control logic.
    output wire                       busy,
    output wire                       done,
    output wire                       error,
    output wire [7:0]                 state_dbg,
    output logic [7:0]                error_code,
    output logic                      device_present,
    output logic                      nvme_class_match,
    output logic [15:0]               vendor_id,
    output logic [15:0]               device_id,
    output logic [23:0]               class_code,
    output logic                      bar_is_64,
    output logic                      bar_prefetchable,
    output logic [63:0]               bar_size,
    output logic [63:0]               bar_pcie_address,
    output logic [63:0]               rp_dma_bar_size,
    output logic [63:0]               rp_dma_pcie_base,
    output logic [63:0]               rp_dma_pcie_limit,
    output logic                      rp_dma_bar_programmed,
    output logic                      bdf_table_programmed,
    output logic [63:0]               nvme_cap,
    output logic [31:0]               nvme_vs,
    output logic [7:0]                rp_pcie_cap_offset,
    output logic [7:0]                ep_pcie_cap_offset,
    output logic [2:0]                rp_mps_supported,
    output logic [2:0]                ep_mps_supported,
    output logic [2:0]                selected_mps,
    output logic [2:0]                rp_mps_configured,
    output logic [2:0]                ep_mps_configured,
    output logic                      mps_programmed,

    // Compact debug probes.
    output logic [CFG_ADDR_WIDTH-1:0] last_cfg_addr,
    output logic [31:0]               last_csr_addr,
    output logic [31:0]               last_csr_write_data,
    output logic [MMIO_ADDR_WIDTH-1:0] last_mmio_addr,
    output logic [63:0]               last_read_data
);

    localparam logic [1:0] AXI_OKAY = 2'b00;

    // Stable numeric encodings make ILA state decoding repeatable.
    typedef enum logic [7:0] {
        ST_IDLE                    = 8'h00,
        ST_WAIT_LINK               = 8'h01,

        ST_RP_BUS_WR_REQ           = 8'h10,
        ST_RP_BUS_WR_RSP           = 8'h11,
        ST_RP_BAR0_ORIG_RD_REQ     = 8'h12,
        ST_RP_BAR0_ORIG_RD_RSP     = 8'h13,
        ST_RP_BAR1_ORIG_RD_REQ     = 8'h14,
        ST_RP_BAR1_ORIG_RD_RSP     = 8'h15,
        ST_RP_BAR0_PROBE_WR_REQ    = 8'h16,
        ST_RP_BAR0_PROBE_WR_RSP    = 8'h17,
        ST_RP_BAR1_PROBE_WR_REQ    = 8'h18,
        ST_RP_BAR1_PROBE_WR_RSP    = 8'h19,
        ST_RP_BAR0_MASK_RD_REQ     = 8'h1A,
        ST_RP_BAR0_MASK_RD_RSP     = 8'h1B,
        ST_RP_BAR1_MASK_RD_REQ     = 8'h1C,
        ST_RP_BAR1_MASK_RD_RSP     = 8'h1D,
        ST_RP_BAR_CALCULATE        = 8'h1E,
        ST_RP_BAR0_ASSIGN_WR_REQ   = 8'h1F,
        ST_RP_BAR0_ASSIGN_WR_RSP   = 8'h20,
        ST_RP_BAR1_ASSIGN_WR_REQ   = 8'h21,
        ST_RP_BAR1_ASSIGN_WR_RSP   = 8'h22,

        ST_EP_ID_RD_REQ            = 8'h30,
        ST_EP_ID_RD_RSP            = 8'h31,
        ST_EP_CLASS_RD_REQ         = 8'h32,
        ST_EP_CLASS_RD_RSP         = 8'h33,
        ST_EP_CMD_RD_REQ           = 8'h34,
        ST_EP_CMD_RD_RSP           = 8'h35,
        ST_EP_CMD_DISABLE_WR_REQ   = 8'h36,
        ST_EP_CMD_DISABLE_WR_RSP   = 8'h37,
        ST_BAR0_ORIG_RD_REQ        = 8'h38,
        ST_BAR0_ORIG_RD_RSP        = 8'h39,
        ST_BAR1_ORIG_RD_REQ        = 8'h3A,
        ST_BAR1_ORIG_RD_RSP        = 8'h3B,
        ST_BAR0_PROBE_WR_REQ       = 8'h3C,
        ST_BAR0_PROBE_WR_RSP       = 8'h3D,
        ST_BAR1_PROBE_WR_REQ       = 8'h3E,
        ST_BAR1_PROBE_WR_RSP       = 8'h3F,
        ST_BAR0_MASK_RD_REQ        = 8'h40,
        ST_BAR0_MASK_RD_RSP        = 8'h41,
        ST_BAR1_MASK_RD_REQ        = 8'h42,
        ST_BAR1_MASK_RD_RSP        = 8'h43,
        ST_BAR_CALCULATE           = 8'h44,
        ST_BAR0_ASSIGN_WR_REQ      = 8'h45,
        ST_BAR0_ASSIGN_WR_RSP      = 8'h46,
        ST_BAR1_ASSIGN_WR_REQ      = 8'h47,
        ST_BAR1_ASSIGN_WR_RSP      = 8'h48,
        ST_RP_MEM_WR_REQ           = 8'h49,
        ST_RP_MEM_WR_RSP           = 8'h4A,
        ST_RP_CMD_RD_REQ           = 8'h4B,
        ST_RP_CMD_RD_RSP           = 8'h4C,
        ST_RP_CMD_WR_REQ           = 8'h4D,
        ST_RP_CMD_WR_RSP           = 8'h4E,
        ST_EP_CMD_ENABLE_WR_REQ    = 8'h4F,
        ST_EP_CMD_ENABLE_WR_RSP    = 8'h50,

        ST_WAIT_CSR_READY          = 8'h60,
        ST_CSR_WRITE_REQ           = 8'h61,
        ST_CSR_WRITE_RSP           = 8'h62,

        ST_NVME_CAP_RD_REQ         = 8'h70,
        ST_NVME_CAP_RD_RSP         = 8'h71,
        ST_NVME_VS_RD_REQ          = 8'h72,
        ST_NVME_VS_RD_RSP          = 8'h73,

        ST_RP_CAP_PTR_RD_REQ       = 8'h80,
        ST_RP_CAP_PTR_RD_RSP       = 8'h81,
        ST_RP_CAP_HDR_RD_REQ       = 8'h82,
        ST_RP_CAP_HDR_RD_RSP       = 8'h83,
        ST_RP_DEVCAP_RD_REQ        = 8'h84,
        ST_RP_DEVCAP_RD_RSP        = 8'h85,
        ST_EP_CAP_PTR_RD_REQ       = 8'h86,
        ST_EP_CAP_PTR_RD_RSP       = 8'h87,
        ST_EP_CAP_HDR_RD_REQ       = 8'h88,
        ST_EP_CAP_HDR_RD_RSP       = 8'h89,
        ST_EP_DEVCAP_RD_REQ        = 8'h8A,
        ST_EP_DEVCAP_RD_RSP        = 8'h8B,
        ST_MPS_SELECT              = 8'h8C,
        ST_RP_DEVCTL_RD_REQ        = 8'h8D,
        ST_RP_DEVCTL_RD_RSP        = 8'h8E,
        ST_RP_DEVCTL_WR_REQ        = 8'h8F,
        ST_RP_DEVCTL_WR_RSP        = 8'h90,
        ST_RP_DEVCTL_VERIFY_REQ    = 8'h91,
        ST_RP_DEVCTL_VERIFY_RSP    = 8'h92,
        ST_EP_DEVCTL_RD_REQ        = 8'h93,
        ST_EP_DEVCTL_RD_RSP        = 8'h94,
        ST_EP_DEVCTL_WR_REQ        = 8'h95,
        ST_EP_DEVCTL_WR_RSP        = 8'h96,
        ST_EP_DEVCTL_VERIFY_REQ    = 8'h97,
        ST_EP_DEVCTL_VERIFY_RSP    = 8'h98,

        ST_DONE                    = 8'hFE,
        ST_ERROR                   = 8'hFF
    } state_t;

    // Error encodings retained from the first version where possible.
    localparam logic [7:0] ERR_NONE              = 8'h00;
    localparam logic [7:0] ERR_LINK_LOST         = 8'h01;
    localparam logic [7:0] ERR_CFG_TIMEOUT       = 8'h02;
    localparam logic [7:0] ERR_CFG_AXI           = 8'h03;
    localparam logic [7:0] ERR_NO_DEVICE         = 8'h04;
    localparam logic [7:0] ERR_NOT_NVME          = 8'h05;
    localparam logic [7:0] ERR_BAR_IS_IO         = 8'h06;
    localparam logic [7:0] ERR_BAR_TYPE          = 8'h07;
    localparam logic [7:0] ERR_BAR_PREFETCH      = 8'h08;
    localparam logic [7:0] ERR_BAR_SIZE          = 8'h09;
    localparam logic [7:0] ERR_BAR_ADDRESS       = 8'h0A;
    localparam logic [7:0] ERR_MMIO_TIMEOUT      = 8'h0B;
    localparam logic [7:0] ERR_MMIO_AXI          = 8'h0C;
    localparam logic [7:0] ERR_CAP_INVALID       = 8'h0D;
    localparam logic [7:0] ERR_VS_INVALID        = 8'h0E;
    localparam logic [7:0] ERR_CSR_NOT_READY     = 8'h0F;
    localparam logic [7:0] ERR_CSR_TIMEOUT       = 8'h10;
    localparam logic [7:0] ERR_CSR_AXI           = 8'h11;
    localparam logic [7:0] ERR_BDF_WINDOW        = 8'h12;
    localparam logic [7:0] ERR_RP_BAR_TYPE       = 8'h13;
    localparam logic [7:0] ERR_RP_BAR_SIZE       = 8'h14;
    localparam logic [7:0] ERR_RP_BAR_ADDRESS    = 8'h15;
    localparam logic [7:0] ERR_RP_PCIE_CAP       = 8'h16;
    localparam logic [7:0] ERR_EP_PCIE_CAP       = 8'h17;
    localparam logic [7:0] ERR_MPS_ENCODING      = 8'h18;
    localparam logic [7:0] ERR_MPS_VERIFY        = 8'h19;

    localparam logic [7:0] PCIE_CAPABILITY_ID = 8'h10;
    localparam logic [5:0] CAP_MAX_HOPS = 6'd48;

    localparam integer LINK_COUNT_MAX =
        (LINK_SETTLE_CYCLES < 2) ? 2 : LINK_SETTLE_CYCLES;
    localparam integer LINK_COUNT_WIDTH = $clog2(LINK_COUNT_MAX);
    localparam integer LINK_SETTLE_LIMIT =
        (LINK_SETTLE_CYCLES < 1) ? 1 : LINK_SETTLE_CYCLES;
    localparam logic [LINK_COUNT_WIDTH-1:0] LINK_SETTLE_LAST_COUNT =
        LINK_SETTLE_LIMIT - 1;

    localparam integer CSR_READY_COUNT_MAX =
        (CSR_READY_TIMEOUT_CYCLES < 2) ? 2 : CSR_READY_TIMEOUT_CYCLES;
    localparam integer CSR_READY_COUNT_WIDTH = $clog2(CSR_READY_COUNT_MAX);
    localparam integer CSR_READY_LIMIT =
        (CSR_READY_TIMEOUT_CYCLES < 1) ? 1 :
        CSR_READY_TIMEOUT_CYCLES;
    localparam logic [CSR_READY_COUNT_WIDTH-1:0]
        CSR_READY_LAST_COUNT = CSR_READY_LIMIT - 1;

    state_t state;
    logic [LINK_COUNT_WIDTH-1:0] link_settle_count;
    logic [CSR_READY_COUNT_WIDTH-1:0] csr_ready_count;
    logic [2:0] csr_write_index;

    logic [31:0] rp_bar0_original;
    logic [31:0] rp_bar1_original;
    logic [31:0] rp_bar0_mask;
    logic [31:0] rp_bar1_mask;
    logic [31:0] bar0_original;
    logic [31:0] bar1_original;
    logic [31:0] bar0_mask;
    logic [31:0] bar1_mask;
    logic [31:0] rp_command_dword;
    logic [31:0] ep_command_dword;
    logic [7:0] rp_cap_scan_offset;
    logic [7:0] ep_cap_scan_offset;
    logic [5:0] cap_hop_count;
    logic [31:0] rp_device_control_dword;
    logic [31:0] ep_device_control_dword;

    logic [63:0] rp_bar_mask_calculated;
    logic [63:0] rp_bar_size_calculated;
    logic [63:0] rp_bar_limit_calculated;
    logic [63:0] bar_mask_calculated;
    logic [63:0] bar_size_calculated;
    logic [63:0] bar_limit_calculated;
    logic [31:0] rp_memory_window_dword;
    logic [25:0] bdf_window_size_field;

    wire link_ready =
        user_lnk_up && (!REQUIRE_PHY_READY || phy_ready);
    wire cfg_response_failed =
        cfg_rsp_timeout || (cfg_rsp_resp != AXI_OKAY);
    wire csr_response_failed =
        csr_rsp_timeout || (csr_rsp_resp != AXI_OKAY);
    wire mmio_response_failed =
        mmio_rsp_timeout || (mmio_rsp_resp != AXI_OKAY);

    assign cfg_rsp_ready  = 1'b1;
    assign csr_rsp_ready  = 1'b1;
    assign mmio_rsp_ready = 1'b1;

    assign busy = (state != ST_IDLE) &&
                  (state != ST_DONE) &&
                  (state != ST_ERROR);
    assign done = (state == ST_DONE);
    assign error = (state == ST_ERROR);
    assign state_dbg = state;

    // ECAM offset: [27:20] bus, [19:15] device, [14:12] function,
    // [11:0] register.  PG344 normal S_AXIL address bit 28 must remain zero.
    function automatic logic [CFG_ADDR_WIDTH-1:0] make_ecam_addr (
        input logic [7:0]  bus_number,
        input logic [4:0]  device_number,
        input logic [2:0]  function_number,
        input logic [11:0] register_offset
    );
        logic [27:0] ecam_offset;
        begin
            ecam_offset = {
                bus_number,
                device_number,
                function_number,
                register_offset
            };
            make_ecam_addr = ECAM_BASE + ecam_offset;
        end
    endfunction

    // BAR sizing and Type-1 Memory Base/Limit encoding.
    always_comb begin
        rp_bar_mask_calculated =
            {rp_bar1_mask, rp_bar0_mask & 32'hFFFF_FFF0};
        rp_bar_size_calculated =
            (~rp_bar_mask_calculated) + 64'd1;
        rp_bar_limit_calculated =
            RP_DMA_PCIE_BASE + rp_bar_size_calculated - 64'd1;

        if (bar_is_64)
            bar_mask_calculated =
                {bar1_mask, bar0_mask & 32'hFFFF_FFF0};
        else
            bar_mask_calculated = {
                32'hFFFF_FFFF,
                bar0_mask & 32'hFFFF_FFF0
            };

        bar_size_calculated =
            (~bar_mask_calculated) + 64'd1;
        bar_limit_calculated =
            NVME_PCIE_BAR_BASE + bar_size_calculated - 64'd1;

        // Type-1 non-prefetchable memory windows have 1 MiB granularity.
        rp_memory_window_dword = {
            bar_limit_calculated[31:20],
            4'b0000,
            NVME_PCIE_BAR_BASE[31:20],
            4'b0000
        };

        // PG344 register 0x2430 encodes size in 4 KiB units.
        bdf_window_size_field = bar_size[37:12];
    end

    // One fixed ECAM operation is driven in each request state.
    always_comb begin
        cfg_cmd_valid = 1'b0;
        cfg_cmd_write = 1'b0;
        cfg_cmd_addr  = '0;
        cfg_cmd_wdata = '0;
        cfg_cmd_wstrb = 4'b0000;

        case (state)
            ST_RP_BUS_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h018);
                // Primary=0, Secondary=1, Subordinate=1, latency=0.
                cfg_cmd_wdata = 32'h0001_0100;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_RP_BAR0_ORIG_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h010);
            end

            ST_RP_BAR1_ORIG_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h014);
            end

            ST_RP_BAR0_PROBE_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h010);
                cfg_cmd_wdata = 32'hFFFF_FFFF;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_RP_BAR1_PROBE_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h014);
                cfg_cmd_wdata = 32'hFFFF_FFFF;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_RP_BAR0_MASK_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h010);
            end

            ST_RP_BAR1_MASK_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h014);
            end

            ST_RP_BAR0_ASSIGN_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h010);
                cfg_cmd_wdata =
                    RP_DMA_PCIE_BASE[31:0] & 32'hFFFF_FFF0;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_RP_BAR1_ASSIGN_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h014);
                cfg_cmd_wdata = RP_DMA_PCIE_BASE[63:32];
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_EP_ID_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h000);
            end

            ST_EP_CLASS_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h008);
            end

            // Locate the conventional PCI Express capability independently
            // for the Root Port and endpoint.  Capability offsets are not
            // assumed to be the same across devices.
            ST_RP_CAP_PTR_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h034);
            end

            ST_RP_CAP_HDR_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd0, 5'd0, 3'd0, {4'd0, rp_cap_scan_offset}
                );
            end

            ST_RP_DEVCAP_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd0, 5'd0, 3'd0,
                    {4'd0, rp_pcie_cap_offset} + 12'h004
                );
            end

            ST_EP_CAP_PTR_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h034);
            end

            ST_EP_CAP_HDR_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd1, 5'd0, 3'd0, {4'd0, ep_cap_scan_offset}
                );
            end

            ST_EP_DEVCAP_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd1, 5'd0, 3'd0,
                    {4'd0, ep_pcie_cap_offset} + 12'h004
                );
            end

            ST_RP_DEVCTL_RD_REQ,
            ST_RP_DEVCTL_VERIFY_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd0, 5'd0, 3'd0,
                    {4'd0, rp_pcie_cap_offset} + 12'h008
                );
            end

            ST_RP_DEVCTL_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd0, 5'd0, 3'd0,
                    {4'd0, rp_pcie_cap_offset} + 12'h008
                );
                cfg_cmd_wdata =
                    (rp_device_control_dword & 32'h0000_FF1F) |
                    {24'd0, selected_mps, 5'd0};
                // Device Status occupies the upper halfword and contains W1C
                // bits, so update Device Control only.
                cfg_cmd_wstrb = 4'b0011;
            end

            ST_EP_DEVCTL_RD_REQ,
            ST_EP_DEVCTL_VERIFY_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd1, 5'd0, 3'd0,
                    {4'd0, ep_pcie_cap_offset} + 12'h008
                );
            end

            ST_EP_DEVCTL_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr = make_ecam_addr(
                    8'd1, 5'd0, 3'd0,
                    {4'd0, ep_pcie_cap_offset} + 12'h008
                );
                cfg_cmd_wdata =
                    (ep_device_control_dword & 32'h0000_FF1F) |
                    {24'd0, selected_mps, 5'd0};
                cfg_cmd_wstrb = 4'b0011;
            end

            ST_EP_CMD_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h004);
            end

            ST_EP_CMD_DISABLE_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h004);
                cfg_cmd_wdata = {
                    16'h0000,
                    ep_command_dword[15:0] & 16'hFFF9
                };
                // Do not write back W1C Status bits in the upper halfword.
                cfg_cmd_wstrb = 4'b0011;
            end

            ST_BAR0_ORIG_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h010);
            end

            ST_BAR1_ORIG_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h014);
            end

            ST_BAR0_PROBE_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h010);
                cfg_cmd_wdata = 32'hFFFF_FFFF;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_BAR1_PROBE_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h014);
                cfg_cmd_wdata = 32'hFFFF_FFFF;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_BAR0_MASK_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h010);
            end

            ST_BAR1_MASK_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h014);
            end

            ST_BAR0_ASSIGN_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h010);
                cfg_cmd_wdata =
                    NVME_PCIE_BAR_BASE[31:0] & 32'hFFFF_FFF0;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_BAR1_ASSIGN_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h014);
                cfg_cmd_wdata = NVME_PCIE_BAR_BASE[63:32];
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_RP_MEM_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h020);
                cfg_cmd_wdata = rp_memory_window_dword;
                cfg_cmd_wstrb = 4'b1111;
            end

            ST_RP_CMD_RD_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h004);
            end

            ST_RP_CMD_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd0, 5'd0, 3'd0, 12'h004);
                cfg_cmd_wdata = {
                    16'h0000,
                    rp_command_dword[15:0] | 16'h0006
                };
                cfg_cmd_wstrb = 4'b0011;
            end

            ST_EP_CMD_ENABLE_WR_REQ: begin
                cfg_cmd_valid = 1'b1;
                cfg_cmd_write = 1'b1;
                cfg_cmd_addr =
                    make_ecam_addr(8'd1, 5'd0, 3'd0, 12'h004);
                cfg_cmd_wdata = {
                    16'h0000,
                    ep_command_dword[15:0] | 16'h0006
                };
                cfg_cmd_wstrb = 4'b0011;
            end

            default: begin
                cfg_cmd_valid = 1'b0;
            end
        endcase
    end

    // Program exactly one BDF-table entry.  PG344 requires all six writes,
    // including zero-valued fields, and requires this order.
    always_comb begin
        csr_cmd_valid = 1'b0;
        csr_cmd_write = 1'b1;
        csr_cmd_addr  = BDF_TABLE_CSR_BASE;
        csr_cmd_wdata = 32'd0;
        csr_cmd_wstrb = 4'b1111;

        if (state == ST_CSR_WRITE_REQ) begin
            csr_cmd_valid = 1'b1;

            case (csr_write_index)
                3'd0: begin
                    csr_cmd_addr  = BDF_TABLE_CSR_BASE + 32'h00;
                    csr_cmd_wdata = BDF_ADDR_TRANSLATION[31:0];
                end
                3'd1: begin
                    csr_cmd_addr  = BDF_TABLE_CSR_BASE + 32'h04;
                    csr_cmd_wdata = BDF_ADDR_TRANSLATION[63:32];
                end
                3'd2: begin
                    csr_cmd_addr  = BDF_TABLE_CSR_BASE + 32'h08;
                    csr_cmd_wdata = 32'd0; // PASID/reserved
                end
                3'd3: begin
                    csr_cmd_addr  = BDF_TABLE_CSR_BASE + 32'h0C;
                    csr_cmd_wdata = {20'd0, BDF_FUNCTION_NUMBER};
                end
                3'd4: begin
                    csr_cmd_addr  = BDF_TABLE_CSR_BASE + 32'h10;
                    csr_cmd_wdata = {
                        2'b11,                 // read/write permission
                        1'b0,                  // R0 access error disabled
                        BDF_PROTECTION_ID,
                        bdf_window_size_field  // 4 KiB units
                    };
                end
                3'd5: begin
                    csr_cmd_addr  = BDF_TABLE_CSR_BASE + 32'h14;
                    csr_cmd_wdata = 32'd0; // reserved
                end
                default: begin
                    csr_cmd_valid = 1'b0;
                end
            endcase
        end
    end

    // Native-width NVMe Controller Property reads.
    always_comb begin
        mmio_cmd_valid = 1'b0;
        mmio_cmd_write = 1'b0;
        mmio_cmd_addr  = '0;
        mmio_cmd_wdata = '0;
        mmio_cmd_wstrb = 8'h00;
        mmio_cmd_size  = 3'd3;

        case (state)
            ST_NVME_CAP_RD_REQ: begin
                mmio_cmd_valid = 1'b1;
                mmio_cmd_addr  = NVME_MMIO_AXI_BASE;
                mmio_cmd_size  = 3'd3; // 8-byte CAP
            end

            ST_NVME_VS_RD_REQ: begin
                mmio_cmd_valid = 1'b1;
                mmio_cmd_addr  = NVME_MMIO_AXI_BASE + 64'h8;
                mmio_cmd_size  = 3'd3; // 4-byte VS but we read 8-byte (for unknown reason 4-byte fails in some build)
            end

            default: begin
                mmio_cmd_valid = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!resetn || soft_reset) begin
            state                  <= ST_IDLE;
            error_code             <= ERR_NONE;
            link_settle_count      <= '0;
            csr_ready_count        <= '0;
            csr_write_index        <= '0;
            device_present         <= 1'b0;
            nvme_class_match       <= 1'b0;
            vendor_id              <= '0;
            device_id              <= '0;
            class_code             <= '0;
            bar_is_64              <= 1'b0;
            bar_prefetchable       <= 1'b0;
            bar_size               <= '0;
            bar_pcie_address       <= '0;
            rp_dma_bar_size        <= '0;
            rp_dma_pcie_base       <= '0;
            rp_dma_pcie_limit      <= '0;
            rp_dma_bar_programmed  <= 1'b0;
            bdf_table_programmed   <= 1'b0;
            nvme_cap               <= '0;
            nvme_vs                <= '0;
            rp_pcie_cap_offset     <= '0;
            ep_pcie_cap_offset     <= '0;
            rp_mps_supported       <= '0;
            ep_mps_supported       <= '0;
            selected_mps           <= '0;
            rp_mps_configured      <= '0;
            ep_mps_configured      <= '0;
            mps_programmed         <= 1'b0;
            rp_bar0_original       <= '0;
            rp_bar1_original       <= '0;
            rp_bar0_mask           <= '0;
            rp_bar1_mask           <= '0;
            bar0_original          <= '0;
            bar1_original          <= '0;
            bar0_mask              <= '0;
            bar1_mask              <= '0;
            rp_command_dword       <= '0;
            ep_command_dword       <= '0;
            rp_cap_scan_offset     <= '0;
            ep_cap_scan_offset     <= '0;
            cap_hop_count          <= '0;
            rp_device_control_dword <= '0;
            ep_device_control_dword <= '0;
            last_cfg_addr          <= '0;
            last_csr_addr          <= '0;
            last_csr_write_data    <= '0;
            last_mmio_addr         <= '0;
            last_read_data         <= '0;
        end else begin
            if (cfg_cmd_valid && cfg_cmd_ready)
                last_cfg_addr <= cfg_cmd_addr;

            if (csr_cmd_valid && csr_cmd_ready) begin
                last_csr_addr       <= csr_cmd_addr;
                last_csr_write_data <= csr_cmd_wdata;
            end

            if (mmio_cmd_valid && mmio_cmd_ready)
                last_mmio_addr <= mmio_cmd_addr;

            if (cfg_rsp_valid)
                last_read_data <= {32'h0000_0000, cfg_rsp_rdata};
            else if (csr_rsp_valid)
                last_read_data <= {32'h0000_0000, csr_rsp_rdata};
            else if (mmio_rsp_valid)
                last_read_data <= mmio_rsp_rdata;

            // A link drop after the settling phase invalidates all in-flight
            // configuration/MMIO work.
            if ((state != ST_IDLE) &&
                (state != ST_WAIT_LINK) &&
                (state != ST_DONE) &&
                (state != ST_ERROR) &&
                !link_ready) begin
                error_code <= ERR_LINK_LOST;
                state      <= ST_ERROR;
            end else begin
                case (state)
                    ST_IDLE: begin
                        error_code            <= ERR_NONE;
                        link_settle_count      <= '0;
                        csr_ready_count        <= '0;
                        csr_write_index        <= '0;
                        rp_dma_bar_programmed <= 1'b0;
                        bdf_table_programmed  <= 1'b0;
                        mps_programmed        <= 1'b0;
                        if (start)
                            state <= ST_WAIT_LINK;
                    end

                    ST_WAIT_LINK: begin
                        if (link_ready) begin
                            if (LINK_SETTLE_CYCLES <= 1) begin
                                link_settle_count <= '0;
                                state <= ST_RP_BUS_WR_REQ;
                            end else if (
                                link_settle_count ==
                                LINK_SETTLE_LAST_COUNT
                            ) begin
                                link_settle_count <= '0;
                                state <= ST_RP_BUS_WR_REQ;
                            end else begin
                                link_settle_count <=
                                    link_settle_count + 1'b1;
                            end
                        end else begin
                            link_settle_count <= '0;
                        end
                    end

                    ST_RP_BUS_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BUS_WR_RSP;

                    ST_RP_BUS_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= PROGRAM_RP_DMA_BAR ?
                                    ST_RP_BAR0_ORIG_RD_REQ :
                                    ST_EP_ID_RD_REQ;
                            end
                        end

                    ST_RP_BAR0_ORIG_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR0_ORIG_RD_RSP;

                    ST_RP_BAR0_ORIG_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (
                                cfg_rsp_rdata[0] ||
                                (cfg_rsp_rdata[2:1] != 2'b10)
                            ) begin
                                error_code <= ERR_RP_BAR_TYPE;
                                state <= ST_ERROR;
                            end else begin
                                rp_bar0_original <= cfg_rsp_rdata;
                                state <= ST_RP_BAR1_ORIG_RD_REQ;
                            end
                        end

                    ST_RP_BAR1_ORIG_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR1_ORIG_RD_RSP;

                    ST_RP_BAR1_ORIG_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_bar1_original <= cfg_rsp_rdata;
                                state <= ST_RP_BAR0_PROBE_WR_REQ;
                            end
                        end

                    ST_RP_BAR0_PROBE_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR0_PROBE_WR_RSP;

                    ST_RP_BAR0_PROBE_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_RP_BAR1_PROBE_WR_REQ;
                            end
                        end

                    ST_RP_BAR1_PROBE_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR1_PROBE_WR_RSP;

                    ST_RP_BAR1_PROBE_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_RP_BAR0_MASK_RD_REQ;
                            end
                        end

                    ST_RP_BAR0_MASK_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR0_MASK_RD_RSP;

                    ST_RP_BAR0_MASK_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_bar0_mask <= cfg_rsp_rdata;
                                state <= ST_RP_BAR1_MASK_RD_REQ;
                            end
                        end

                    ST_RP_BAR1_MASK_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR1_MASK_RD_RSP;

                    ST_RP_BAR1_MASK_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_bar1_mask <= cfg_rsp_rdata;
                                state <= ST_RP_BAR_CALCULATE;
                            end
                        end

                    ST_RP_BAR_CALCULATE: begin
                        if ((rp_bar_size_calculated == 64'd0) ||
                            ((rp_bar_size_calculated &
                              (rp_bar_size_calculated - 64'd1)) !=
                             64'd0) ||
                            ((RP_DMA_EXPECTED_SIZE != 64'd0) &&
                             (rp_bar_size_calculated !=
                              RP_DMA_EXPECTED_SIZE))) begin
                            error_code <= ERR_RP_BAR_SIZE;
                            state <= ST_ERROR;
                        end else if (
                            ((RP_DMA_PCIE_BASE &
                              (rp_bar_size_calculated - 64'd1)) !=
                             64'd0) ||
                            (rp_bar_limit_calculated <
                             RP_DMA_PCIE_BASE)
                        ) begin
                            error_code <= ERR_RP_BAR_ADDRESS;
                            state <= ST_ERROR;
                        end else begin
                            rp_dma_bar_size   <=
                                rp_bar_size_calculated;
                            rp_dma_pcie_base <= RP_DMA_PCIE_BASE;
                            rp_dma_pcie_limit <=
                                rp_bar_limit_calculated;
                            state <= ST_RP_BAR0_ASSIGN_WR_REQ;
                        end
                    end

                    ST_RP_BAR0_ASSIGN_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR0_ASSIGN_WR_RSP;

                    ST_RP_BAR0_ASSIGN_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_RP_BAR1_ASSIGN_WR_REQ;
                            end
                        end

                    ST_RP_BAR1_ASSIGN_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_BAR1_ASSIGN_WR_RSP;

                    ST_RP_BAR1_ASSIGN_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_dma_bar_programmed <= 1'b1;
                                state <= ST_EP_ID_RD_REQ;
                            end
                        end

                    ST_EP_ID_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_ID_RD_RSP;

                    ST_EP_ID_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (
                                (cfg_rsp_rdata == 32'hFFFF_FFFF) ||
                                (cfg_rsp_rdata[15:0] == 16'hFFFF) ||
                                (cfg_rsp_rdata[15:0] == 16'h0000)
                            ) begin
                                error_code <= ERR_NO_DEVICE;
                                state <= ST_ERROR;
                            end else begin
                                vendor_id <= cfg_rsp_rdata[15:0];
                                device_id <= cfg_rsp_rdata[31:16];
                                device_present <= 1'b1;
                                state <= ST_EP_CLASS_RD_REQ;
                            end
                        end

                    ST_EP_CLASS_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_CLASS_RD_RSP;

                    ST_EP_CLASS_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                class_code <= cfg_rsp_rdata[31:8];
                                nvme_class_match <=
                                    (cfg_rsp_rdata[31:8] ==
                                     24'h01_08_02);

                                if (REQUIRE_NVME_CLASS &&
                                    (cfg_rsp_rdata[31:8] !=
                                     24'h01_08_02)) begin
                                    error_code <= ERR_NOT_NVME;
                                    state <= ST_ERROR;
                                end else begin
                                    state <= ST_RP_CAP_PTR_RD_REQ;
                                end
                            end
                        end

                    ST_RP_CAP_PTR_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_CAP_PTR_RD_RSP;

                    ST_RP_CAP_PTR_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (
                                (cfg_rsp_rdata[7:0] == 8'd0) ||
                                (cfg_rsp_rdata[7:0] < 8'h40) ||
                                (cfg_rsp_rdata[1:0] != 2'b00)
                            ) begin
                                error_code <= ERR_RP_PCIE_CAP;
                                state <= ST_ERROR;
                            end else begin
                                rp_cap_scan_offset <= cfg_rsp_rdata[7:0];
                                cap_hop_count <= '0;
                                state <= ST_RP_CAP_HDR_RD_REQ;
                            end
                        end

                    ST_RP_CAP_HDR_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_CAP_HDR_RD_RSP;

                    ST_RP_CAP_HDR_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (
                                cfg_rsp_rdata[7:0] == PCIE_CAPABILITY_ID
                            ) begin
                                rp_pcie_cap_offset <= rp_cap_scan_offset;
                                state <= ST_RP_DEVCAP_RD_REQ;
                            end else if (
                                (cfg_rsp_rdata[15:8] == 8'd0) ||
                                (cfg_rsp_rdata[15:8] < 8'h40) ||
                                (cfg_rsp_rdata[9:8] != 2'b00) ||
                                (cfg_rsp_rdata[15:8] ==
                                 rp_cap_scan_offset) ||
                                (cap_hop_count == CAP_MAX_HOPS - 1'b1)
                            ) begin
                                error_code <= ERR_RP_PCIE_CAP;
                                state <= ST_ERROR;
                            end else begin
                                rp_cap_scan_offset <= cfg_rsp_rdata[15:8];
                                cap_hop_count <= cap_hop_count + 1'b1;
                                state <= ST_RP_CAP_HDR_RD_REQ;
                            end
                        end

                    ST_RP_DEVCAP_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_DEVCAP_RD_RSP;

                    ST_RP_DEVCAP_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (cfg_rsp_rdata[2:0] > 3'd5) begin
                                error_code <= ERR_MPS_ENCODING;
                                state <= ST_ERROR;
                            end else begin
                                rp_mps_supported <= cfg_rsp_rdata[2:0];
                                state <= ST_EP_CAP_PTR_RD_REQ;
                            end
                        end

                    ST_EP_CAP_PTR_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_CAP_PTR_RD_RSP;

                    ST_EP_CAP_PTR_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (
                                (cfg_rsp_rdata[7:0] == 8'd0) ||
                                (cfg_rsp_rdata[7:0] < 8'h40) ||
                                (cfg_rsp_rdata[1:0] != 2'b00)
                            ) begin
                                error_code <= ERR_EP_PCIE_CAP;
                                state <= ST_ERROR;
                            end else begin
                                ep_cap_scan_offset <= cfg_rsp_rdata[7:0];
                                cap_hop_count <= '0;
                                state <= ST_EP_CAP_HDR_RD_REQ;
                            end
                        end

                    ST_EP_CAP_HDR_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_CAP_HDR_RD_RSP;

                    ST_EP_CAP_HDR_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (
                                cfg_rsp_rdata[7:0] == PCIE_CAPABILITY_ID
                            ) begin
                                ep_pcie_cap_offset <= ep_cap_scan_offset;
                                state <= ST_EP_DEVCAP_RD_REQ;
                            end else if (
                                (cfg_rsp_rdata[15:8] == 8'd0) ||
                                (cfg_rsp_rdata[15:8] < 8'h40) ||
                                (cfg_rsp_rdata[9:8] != 2'b00) ||
                                (cfg_rsp_rdata[15:8] ==
                                 ep_cap_scan_offset) ||
                                (cap_hop_count == CAP_MAX_HOPS - 1'b1)
                            ) begin
                                error_code <= ERR_EP_PCIE_CAP;
                                state <= ST_ERROR;
                            end else begin
                                ep_cap_scan_offset <= cfg_rsp_rdata[15:8];
                                cap_hop_count <= cap_hop_count + 1'b1;
                                state <= ST_EP_CAP_HDR_RD_REQ;
                            end
                        end

                    ST_EP_DEVCAP_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_DEVCAP_RD_RSP;

                    ST_EP_DEVCAP_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (cfg_rsp_rdata[2:0] > 3'd5) begin
                                error_code <= ERR_MPS_ENCODING;
                                state <= ST_ERROR;
                            end else begin
                                ep_mps_supported <= cfg_rsp_rdata[2:0];
                                state <= ST_MPS_SELECT;
                            end
                        end

                    ST_MPS_SELECT: begin
                        if (PCIE_TARGET_MPS > 3'd5) begin
                            error_code <= ERR_MPS_ENCODING;
                            state <= ST_ERROR;
                        end else begin
                            if ((PCIE_TARGET_MPS <= rp_mps_supported) &&
                                (PCIE_TARGET_MPS <= ep_mps_supported))
                                selected_mps <= PCIE_TARGET_MPS;
                            else if (rp_mps_supported <= ep_mps_supported)
                                selected_mps <= rp_mps_supported;
                            else
                                selected_mps <= ep_mps_supported;
                            state <= ST_RP_DEVCTL_RD_REQ;
                        end
                    end

                    ST_RP_DEVCTL_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_DEVCTL_RD_RSP;

                    ST_RP_DEVCTL_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_device_control_dword <= cfg_rsp_rdata;
                                state <= ST_RP_DEVCTL_WR_REQ;
                            end
                        end

                    ST_RP_DEVCTL_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_DEVCTL_WR_RSP;

                    ST_RP_DEVCTL_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_RP_DEVCTL_VERIFY_REQ;
                            end
                        end

                    ST_RP_DEVCTL_VERIFY_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_DEVCTL_VERIFY_RSP;

                    ST_RP_DEVCTL_VERIFY_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_mps_configured <= cfg_rsp_rdata[7:5];
                                if (cfg_rsp_rdata[7:5] != selected_mps) begin
                                    error_code <= ERR_MPS_VERIFY;
                                    state <= ST_ERROR;
                                end else begin
                                    state <= ST_EP_DEVCTL_RD_REQ;
                                end
                            end
                        end

                    ST_EP_DEVCTL_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_DEVCTL_RD_RSP;

                    ST_EP_DEVCTL_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                ep_device_control_dword <= cfg_rsp_rdata;
                                state <= ST_EP_DEVCTL_WR_REQ;
                            end
                        end

                    ST_EP_DEVCTL_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_DEVCTL_WR_RSP;

                    ST_EP_DEVCTL_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_EP_DEVCTL_VERIFY_REQ;
                            end
                        end

                    ST_EP_DEVCTL_VERIFY_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_DEVCTL_VERIFY_RSP;

                    ST_EP_DEVCTL_VERIFY_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                ep_mps_configured <= cfg_rsp_rdata[7:5];
                                if (cfg_rsp_rdata[7:5] != selected_mps) begin
                                    error_code <= ERR_MPS_VERIFY;
                                    state <= ST_ERROR;
                                end else begin
                                    mps_programmed <= 1'b1;
                                    state <= ST_EP_CMD_RD_REQ;
                                end
                            end
                        end

                    ST_EP_CMD_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_CMD_RD_RSP;

                    ST_EP_CMD_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                ep_command_dword <= cfg_rsp_rdata;
                                state <= ST_EP_CMD_DISABLE_WR_REQ;
                            end
                        end

                    ST_EP_CMD_DISABLE_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_CMD_DISABLE_WR_RSP;

                    ST_EP_CMD_DISABLE_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_BAR0_ORIG_RD_REQ;
                            end
                        end

                    ST_BAR0_ORIG_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR0_ORIG_RD_RSP;

                    ST_BAR0_ORIG_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                bar0_original <= cfg_rsp_rdata;
                                bar_prefetchable <= cfg_rsp_rdata[3];

                                if (cfg_rsp_rdata[0]) begin
                                    error_code <= ERR_BAR_IS_IO;
                                    state <= ST_ERROR;
                                end else if (
                                    REQUIRE_NON_PREFETCHABLE_BAR &&
                                    cfg_rsp_rdata[3]
                                ) begin
                                    error_code <= ERR_BAR_PREFETCH;
                                    state <= ST_ERROR;
                                end else if (
                                    cfg_rsp_rdata[2:1] == 2'b00
                                ) begin
                                    bar_is_64 <= 1'b0;
                                    state <= ST_BAR0_PROBE_WR_REQ;
                                end else if (
                                    cfg_rsp_rdata[2:1] == 2'b10
                                ) begin
                                    bar_is_64 <= 1'b1;
                                    state <= ST_BAR1_ORIG_RD_REQ;
                                end else begin
                                    error_code <= ERR_BAR_TYPE;
                                    state <= ST_ERROR;
                                end
                            end
                        end

                    ST_BAR1_ORIG_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR1_ORIG_RD_RSP;

                    ST_BAR1_ORIG_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                bar1_original <= cfg_rsp_rdata;
                                state <= ST_BAR0_PROBE_WR_REQ;
                            end
                        end

                    ST_BAR0_PROBE_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR0_PROBE_WR_RSP;

                    ST_BAR0_PROBE_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= bar_is_64 ?
                                    ST_BAR1_PROBE_WR_REQ :
                                    ST_BAR0_MASK_RD_REQ;
                            end
                        end

                    ST_BAR1_PROBE_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR1_PROBE_WR_RSP;

                    ST_BAR1_PROBE_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_BAR0_MASK_RD_REQ;
                            end
                        end

                    ST_BAR0_MASK_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR0_MASK_RD_RSP;

                    ST_BAR0_MASK_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                bar0_mask <= cfg_rsp_rdata;
                                state <= bar_is_64 ?
                                    ST_BAR1_MASK_RD_REQ :
                                    ST_BAR_CALCULATE;
                            end
                        end

                    ST_BAR1_MASK_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR1_MASK_RD_RSP;

                    ST_BAR1_MASK_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                bar1_mask <= cfg_rsp_rdata;
                                state <= ST_BAR_CALCULATE;
                            end
                        end

                    ST_BAR_CALCULATE: begin
                        if ((bar_size_calculated == 64'd0) ||
                            ((bar_size_calculated &
                              (bar_size_calculated - 64'd1)) !=
                             64'd0)) begin
                            error_code <= ERR_BAR_SIZE;
                            state <= ST_ERROR;
                        end else if (
                            (NVME_PCIE_BAR_BASE[63:32] != 32'd0) ||
                            (bar_limit_calculated[63:32] != 32'd0) ||
                            (bar_limit_calculated <
                             NVME_PCIE_BAR_BASE) ||
                            // Simplified Type-1 window requires 1 MiB base.
                            (NVME_PCIE_BAR_BASE[19:0] != 20'd0) ||
                            ((NVME_PCIE_BAR_BASE &
                              (bar_size_calculated - 64'd1)) !=
                             64'd0)
                        ) begin
                            error_code <= ERR_BAR_ADDRESS;
                            state <= ST_ERROR;
                        end else if (
                            PROGRAM_BDF_TABLE &&
                            ((bar_size_calculated < 64'h1000) ||
                             (bar_size_calculated[11:0] != 12'd0) ||
                             (bar_size_calculated[63:38] != 26'd0) ||
                             ((BDF_ADDR_TRANSLATION == 64'd0) &&
                              (NVME_MMIO_AXI_BASE !=
                               NVME_PCIE_BAR_BASE)))
                        ) begin
                            error_code <= ERR_BDF_WINDOW;
                            state <= ST_ERROR;
                        end else begin
                            bar_size <= bar_size_calculated;
                            bar_pcie_address <= NVME_PCIE_BAR_BASE;
                            state <= ST_BAR0_ASSIGN_WR_REQ;
                        end
                    end

                    ST_BAR0_ASSIGN_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR0_ASSIGN_WR_RSP;

                    ST_BAR0_ASSIGN_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= bar_is_64 ?
                                    ST_BAR1_ASSIGN_WR_REQ :
                                    ST_RP_MEM_WR_REQ;
                            end
                        end

                    ST_BAR1_ASSIGN_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_BAR1_ASSIGN_WR_RSP;

                    ST_BAR1_ASSIGN_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_RP_MEM_WR_REQ;
                            end
                        end

                    ST_RP_MEM_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_MEM_WR_RSP;

                    ST_RP_MEM_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_RP_CMD_RD_REQ;
                            end
                        end

                    ST_RP_CMD_RD_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_CMD_RD_RSP;

                    ST_RP_CMD_RD_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                rp_command_dword <= cfg_rsp_rdata;
                                state <= ST_RP_CMD_WR_REQ;
                            end
                        end

                    ST_RP_CMD_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_RP_CMD_WR_RSP;

                    ST_RP_CMD_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else begin
                                state <= ST_EP_CMD_ENABLE_WR_REQ;
                            end
                        end

                    ST_EP_CMD_ENABLE_WR_REQ:
                        if (cfg_cmd_valid && cfg_cmd_ready)
                            state <= ST_EP_CMD_ENABLE_WR_RSP;

                    ST_EP_CMD_ENABLE_WR_RSP:
                        if (cfg_rsp_valid) begin
                            if (cfg_response_failed) begin
                                error_code <= cfg_rsp_timeout ?
                                    ERR_CFG_TIMEOUT : ERR_CFG_AXI;
                                state <= ST_ERROR;
                            end else if (PROGRAM_BDF_TABLE) begin
                                csr_ready_count <= '0;
                                state <= ST_WAIT_CSR_READY;
                            end else begin
                                state <= ST_NVME_CAP_RD_REQ;
                            end
                        end

                    ST_WAIT_CSR_READY: begin
                        if (csr_prog_done) begin
                            csr_ready_count <= '0;
                            csr_write_index <= 3'd0;
                            state <= ST_CSR_WRITE_REQ;
                        end else if (
                            (CSR_READY_TIMEOUT_CYCLES != 0) &&
                            (csr_ready_count ==
                             CSR_READY_LAST_COUNT)
                        ) begin
                            error_code <= ERR_CSR_NOT_READY;
                            state <= ST_ERROR;
                        end else begin
                            csr_ready_count <= csr_ready_count + 1'b1;
                        end
                    end

                    ST_CSR_WRITE_REQ:
                        if (csr_cmd_valid && csr_cmd_ready)
                            state <= ST_CSR_WRITE_RSP;

                    ST_CSR_WRITE_RSP:
                        if (csr_rsp_valid) begin
                            if (csr_response_failed) begin
                                error_code <= csr_rsp_timeout ?
                                    ERR_CSR_TIMEOUT : ERR_CSR_AXI;
                                state <= ST_ERROR;
                            end else if (csr_write_index == 3'd5) begin
                                bdf_table_programmed <= 1'b1;
                                state <= ST_NVME_CAP_RD_REQ;
                            end else begin
                                csr_write_index <= csr_write_index + 1'b1;
                                state <= ST_CSR_WRITE_REQ;
                            end
                        end

                    ST_NVME_CAP_RD_REQ:
                        if (mmio_cmd_valid && mmio_cmd_ready)
                            state <= ST_NVME_CAP_RD_RSP;

                    ST_NVME_CAP_RD_RSP:
                        if (mmio_rsp_valid) begin
                            if (mmio_response_failed) begin
                                error_code <= mmio_rsp_timeout ?
                                    ERR_MMIO_TIMEOUT : ERR_MMIO_AXI;
                                state <= ST_ERROR;
                            end else if (
                                (mmio_rsp_rdata == 64'd0) ||
                                (mmio_rsp_rdata ==
                                 64'hFFFF_FFFF_FFFF_FFFF)
                            ) begin
                                error_code <= ERR_CAP_INVALID;
                                state <= ST_ERROR;
                            end else begin
                                nvme_cap <= mmio_rsp_rdata;
                                state <= ST_NVME_VS_RD_REQ;
                            end
                        end

                    ST_NVME_VS_RD_REQ:
                        if (mmio_cmd_valid && mmio_cmd_ready)
                            state <= ST_NVME_VS_RD_RSP;

                    ST_NVME_VS_RD_RSP:
                        if (mmio_rsp_valid) begin
                            if (mmio_response_failed) begin
                                error_code <= mmio_rsp_timeout ?
                                    ERR_MMIO_TIMEOUT : ERR_MMIO_AXI;
                                state <= ST_ERROR;
                            end else if (
                                (mmio_rsp_rdata[31:0] == 32'd0) ||
                                (mmio_rsp_rdata[31:0] ==
                                 32'hFFFF_FFFF)
                            ) begin
                                error_code <= ERR_VS_INVALID;
                                state <= ST_ERROR;
                            end else begin
                                nvme_vs <= mmio_rsp_rdata[31:0];
                                state <= ST_DONE;
                            end
                        end

                    ST_DONE:
                        state <= ST_DONE;

                    ST_ERROR:
                        state <= ST_ERROR;

                    default: begin
                        error_code <= ERR_CFG_AXI;
                        state <= ST_ERROR;
                    end
                endcase
            end
        end
    end

    // Keep original BAR values available to debug/synthesis tools without
    // adding user-visible ports.
    wire _unused_saved_bars_ok = ^{
        rp_bar0_original,
        rp_bar1_original,
        bar0_original,
        bar1_original
    };

endmodule
