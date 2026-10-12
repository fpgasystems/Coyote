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

// Verilog-2001 module-reference wrapper for Vivado block designs.
//
// This is the only Verilog module-reference wrapper in the artifact.  It
// combines unchanged PCIe enumeration with compact, automatic NVMe discovery
// and queue creation.  No VIO start or soft-reset controls are required.
module pl_pcie_nvme_top_wrapper #(
    parameter CFG_ADDR_WIDTH = 32,
    parameter MMIO_ADDR_WIDTH = 64,
    parameter MMIO_ID_WIDTH = 1,
    parameter DMA_ADDR_WIDTH = 64,
    parameter DMA_ID_WIDTH = 4,
    parameter RAM_ADDR_WIDTH = 11,
    parameter CFG_TIMEOUT_CYCLES = 1000000,
    parameter CSR_TIMEOUT_CYCLES = 1000000,
    parameter MMIO_TIMEOUT_CYCLES = 1000000,
    parameter LINK_SETTLE_CYCLES = 1024,
    parameter CSR_READY_TIMEOUT_CYCLES = 1000000,
    parameter [2:0] PCIE_TARGET_MPS = 3'd3,

    parameter [CFG_ADDR_WIDTH-1:0] ECAM_BASE = {CFG_ADDR_WIDTH{1'b0}},
    parameter [MMIO_ADDR_WIDTH-1:0] NVME_MMIO_AXI_BASE = 64'h0000_0000_8000_0000,
    parameter [63:0] NVME_PCIE_BAR_BASE = 64'h0000_0000_8000_0000,

    parameter PROGRAM_RP_DMA_BAR = 1'b1,
    parameter [63:0] RP_DMA_PCIE_BASE = 64'h0000_1000_0000_0000,
    parameter [63:0] RP_DMA_EXPECTED_SIZE = 64'h0000_1000_0000_0000,

    parameter PROGRAM_BDF_TABLE = 1'b1,
    parameter [31:0] BDF_TABLE_CSR_BASE = 32'h0000_2420,
    parameter [63:0] BDF_ADDR_TRANSLATION = 64'd0,
    parameter [11:0] BDF_FUNCTION_NUMBER = 12'd0,
    parameter [2:0] BDF_PROTECTION_ID = 3'b000,

    parameter REQUIRE_PHY_READY = 1'b1,
    parameter REQUIRE_NVME_CLASS = 1'b1,
    parameter REQUIRE_NON_PREFETCHABLE_BAR = 1'b1,

    parameter [63:0] KNOWN_CAP = 64'h1800_C030_1E02_3FFF,
    parameter [31:0] KNOWN_VS = 32'h0002_0000,
    parameter QUEUE_DEPTH = 64, // Admin queues
    parameter IO_QUEUE_DEPTH = 64,
    parameter READY_TIMEOUT_POLLS = 1000000,
    parameter CQ_TIMEOUT_POLLS = 1000000,
    parameter [31:0] NVME_NSID = 32'd1,
    parameter [63:0] DISCOVERY_PCIE_ADDR = 64'h0000_1FFF_FFFF_C000,
        // RP_DMA_PCIE_BASE + RP_DMA_EXPECTED_SIZE - 64'h4000,
    parameter [63:0] ADMIN_SQ_PCIE_ADDR = 64'h0000_1FFF_FFFF_E000,
        // RP_DMA_PCIE_BASE + RP_DMA_EXPECTED_SIZE - 64'h2000,
    parameter [63:0] ADMIN_CQ_PCIE_ADDR = 64'h0000_1FFF_FFFF_F000,
        // RP_DMA_PCIE_BASE + RP_DMA_EXPECTED_SIZE - 64'h1000,
    parameter [63:0] IO_SQ_PCIE_ADDR = 64'h0000_1FFF_F404_0000, // Fixed for every depth: 16 KiB per device
    parameter [63:0] IO_CQ_PCIE_ADDR = 64'h0000_1FFF_F402_0000,
    // Keep all ports present; production builds disable optional diagnostics.
    parameter ENABLE_SETUP_DEBUG = 1'b0
) (
    input  wire                           aclk,
    input  wire                           aresetn,
    input  wire                           user_lnk_up,
    input  wire                           phy_ready,
    input  wire                           csr_prog_done,

    output wire                           enum_busy,
    output wire                           enum_done,
    output wire                           enum_error,
    output wire [7:0]                     enum_state,
    output wire [7:0]                     enum_error_code,
    output wire                           device_present,
    output wire                           nvme_class_match,
    output wire [15:0]                    vendor_id,
    output wire [15:0]                    device_id,
    output wire [23:0]                    class_code,
    output wire                           bar_is_64,
    output wire                           bar_prefetchable,
    output wire [63:0]                    bar_size,
    output wire [63:0]                    bar_pcie_address,
    output wire [63:0]                    rp_dma_bar_size,
    output wire [63:0]                    rp_dma_pcie_base,
    output wire [63:0]                    rp_dma_pcie_limit,
    output wire                           rp_dma_bar_programmed,
    output wire                           bdf_table_programmed,
    output wire [63:0]                    nvme_cap,
    output wire [31:0]                    nvme_vs,
    output wire [7:0]                     rp_pcie_cap_offset,
    output wire [7:0]                     ep_pcie_cap_offset,
    output wire [2:0]                     rp_mps_supported,
    output wire [2:0]                     ep_mps_supported,
    output wire [2:0]                     selected_mps,
    output wire [2:0]                     rp_mps_configured,
    output wire [2:0]                     ep_mps_configured,
    output wire                           mps_programmed,
    output wire [CFG_ADDR_WIDTH-1:0]      last_cfg_addr,
    output wire [31:0]                    last_csr_addr,
    output wire [31:0]                    last_csr_write_data,
    output wire [MMIO_ADDR_WIDTH-1:0]     last_mmio_addr,
    output wire [63:0]                    last_read_data,

    output wire [CFG_ADDR_WIDTH-1:0]      m_axil_ecam_awaddr,
    output wire [2:0]                     m_axil_ecam_awprot,
    output wire [12:0]                    m_axil_ecam_awuser,
    output wire                           m_axil_ecam_awvalid,
    input  wire                           m_axil_ecam_awready,
    output wire [31:0]                    m_axil_ecam_wdata,
    output wire [3:0]                     m_axil_ecam_wstrb,
    output wire                           m_axil_ecam_wvalid,
    input  wire                           m_axil_ecam_wready,
    input  wire [1:0]                     m_axil_ecam_bresp,
    input  wire                           m_axil_ecam_bvalid,
    output wire                           m_axil_ecam_bready,
    output wire [CFG_ADDR_WIDTH-1:0]      m_axil_ecam_araddr,
    output wire [2:0]                     m_axil_ecam_arprot,
    output wire [12:0]                    m_axil_ecam_aruser,
    output wire                           m_axil_ecam_arvalid,
    input  wire                           m_axil_ecam_arready,
    input  wire [31:0]                    m_axil_ecam_rdata,
    input  wire [1:0]                     m_axil_ecam_rresp,
    input  wire                           m_axil_ecam_rvalid,
    output wire                           m_axil_ecam_rready,

    output wire [31:0]                    m_axil_csr_awaddr,
    output wire [2:0]                     m_axil_csr_awprot,
    output wire                           m_axil_csr_awvalid,
    input  wire                           m_axil_csr_awready,
    output wire [31:0]                    m_axil_csr_wdata,
    output wire [3:0]                     m_axil_csr_wstrb,
    output wire                           m_axil_csr_wvalid,
    input  wire                           m_axil_csr_wready,
    input  wire [1:0]                     m_axil_csr_bresp,
    input  wire                           m_axil_csr_bvalid,
    output wire                           m_axil_csr_bready,
    output wire [31:0]                    m_axil_csr_araddr,
    output wire [2:0]                     m_axil_csr_arprot,
    output wire                           m_axil_csr_arvalid,
    input  wire                           m_axil_csr_arready,
    input  wire [31:0]                    m_axil_csr_rdata,
    input  wire [1:0]                     m_axil_csr_rresp,
    input  wire                           m_axil_csr_rvalid,
    output wire                           m_axil_csr_rready,

    output wire [MMIO_ID_WIDTH-1:0]       m_axi_mmio_awid,
    output wire [MMIO_ADDR_WIDTH-1:0]     m_axi_mmio_awaddr,
    output wire [7:0]                     m_axi_mmio_awlen,
    output wire [2:0]                     m_axi_mmio_awsize,
    output wire [1:0]                     m_axi_mmio_awburst,
    output wire                           m_axi_mmio_awlock,
    output wire [3:0]                     m_axi_mmio_awcache,
    output wire [2:0]                     m_axi_mmio_awprot,
    output wire [3:0]                     m_axi_mmio_awqos,
    output wire [3:0]                     m_axi_mmio_awregion,
    output wire                           m_axi_mmio_awvalid,
    input  wire                           m_axi_mmio_awready,
    output wire [63:0]                    m_axi_mmio_wdata,
    output wire [7:0]                     m_axi_mmio_wstrb,
    output wire                           m_axi_mmio_wlast,
    output wire                           m_axi_mmio_wvalid,
    input  wire                           m_axi_mmio_wready,
    input  wire [MMIO_ID_WIDTH-1:0]       m_axi_mmio_bid,
    input  wire [1:0]                     m_axi_mmio_bresp,
    input  wire                           m_axi_mmio_bvalid,
    output wire                           m_axi_mmio_bready,
    output wire [MMIO_ID_WIDTH-1:0]       m_axi_mmio_arid,
    output wire [MMIO_ADDR_WIDTH-1:0]     m_axi_mmio_araddr,
    output wire [7:0]                     m_axi_mmio_arlen,
    output wire [2:0]                     m_axi_mmio_arsize,
    output wire [1:0]                     m_axi_mmio_arburst,
    output wire                           m_axi_mmio_arlock,
    output wire [3:0]                     m_axi_mmio_arcache,
    output wire [2:0]                     m_axi_mmio_arprot,
    output wire [3:0]                     m_axi_mmio_arqos,
    output wire [3:0]                     m_axi_mmio_arregion,
    output wire                           m_axi_mmio_arvalid,
    input  wire                           m_axi_mmio_arready,
    input  wire [MMIO_ID_WIDTH-1:0]       m_axi_mmio_rid,
    input  wire [63:0]                    m_axi_mmio_rdata,
    input  wire [1:0]                     m_axi_mmio_rresp,
    input  wire                           m_axi_mmio_rlast,
    input  wire                           m_axi_mmio_rvalid,
    output wire                           m_axi_mmio_rready,

    input  wire                           health_snapshot_request,
    input  wire                           debug_ram_read_enable,
    input  wire [RAM_ADDR_WIDTH-1:0]      debug_ram_read_addr,
    output wire [63:0]                    debug_ram_read_data,
    output wire                           debug_ram_granted,
    output wire                           setup_started,
    output wire                           setup_busy,
    output wire                           queues_ready,
    output wire                           setup_done,
    output wire                           setup_error,
    output wire                           discovery_done,
    output wire                           discovery_valid,
    output wire                           controller_info_valid,
    output wire                           namespace_list_valid,
    output wire                           namespace_info_valid,
    output wire                           target_nsid_found,
    output wire [15:0]                    discovered_controller_vid,
    output wire [15:0]                    discovered_controller_ssvid,
    output wire [31:0]                    discovered_controller_version,
    output wire [31:0]                    discovered_controller_nn,
    output wire [7:0]                     discovered_controller_mdts,
    output wire [7:0]                     discovered_controller_sqes,
    output wire [7:0]                     discovered_controller_cqes,
    output wire [31:0]                    discovered_first_nsid,
    output wire [31:0]                    discovered_active_nsid_count,
    output wire [63:0]                    discovered_nsze,
    output wire [63:0]                    discovered_ncap,
    output wire [63:0]                    discovered_nuse,
    output wire [7:0]                     discovered_nlbaf,
    output wire [7:0]                     discovered_flbas,
    output wire [5:0]                     discovered_lba_format_index,
    output wire [7:0]                     discovered_lbads,
    output wire [15:0]                    discovered_metadata_bytes,
    output wire [31:0]                    discovered_lba_bytes,

    // Read-only post-setup diagnostics; see setup_fsm for probe field layouts.
    output wire                           health_snapshot_busy,
    output wire                           health_snapshot_done,
    output wire [31:0]                   health_snapshot_count,
    output wire [4:0]                    health_valid,
    output wire [79:0]                   health_command_status,
    output wire [7:0]                    health_error_code,
    output wire [63:0]                   health_firmware_revision,
    output wire [7:0]                    health_npss,
    output wire [7:0]                    health_apsta,
    output wire [79:0]                   health_thermal_caps,
    output wire [31:0]                   health_power_management,
    output wire [31:0]                   health_apst,
    output wire [31:0]                   health_hctm,
    output wire [63:0]                   health_ps0_summary,
    output wire [63:0]                   health_current_ps_summary,
    output wire                           health_current_ps_valid,
    output wire [63:0]                   health_smart_status,
    output wire [127:0]                  health_media_errors,
    output wire [127:0]                  health_error_log_entries,
    output wire [63:0]                   health_temperature_time,
    output wire [127:0]                  health_temperature_sensors,
    output wire [63:0]                   health_thermal_transitions,
    output wire [63:0]                   health_thermal_time,
    output wire [7:0]                     setup_state,
    output wire [7:0]                     setup_error_code,
    output wire [7:0]                     last_opcode,
    output wire [15:0]                    last_cid,
    output wire [15:0]                    last_completion_cid,
    output wire [15:0]                    last_completion_status,
    output wire [127:0]                   last_cqe,
    output wire [31:0]                    last_mmio_offset,
    output wire [63:0]                    last_mmio_rdata,
    output wire [31:0]                    submitted_command_count,
    output wire [15:0]                    admin_sq_tail,
    output wire [15:0]                    admin_cq_head,
    output wire                           admin_cq_phase,
    output wire [31:0]                    ready_poll_count,
    output wire [31:0]                    cq_poll_count,
    output wire [31:0]                    allocated_io_queues,
    output wire [3:0]                     dma_bridge_state,
    output wire [DMA_ADDR_WIDTH-1:0]      dma_last_axi_addr,
    output wire [1:0]                     dma_last_axi_resp,
    output wire                           dma_protocol_error,

    input  wire [DMA_ID_WIDTH-1:0]        s_axi_dma_awid,
    input  wire [DMA_ADDR_WIDTH-1:0]      s_axi_dma_awaddr,
    input  wire [7:0]                     s_axi_dma_awlen,
    input  wire [2:0]                     s_axi_dma_awsize,
    input  wire [1:0]                     s_axi_dma_awburst,
    input  wire                           s_axi_dma_awlock,
    input  wire [3:0]                     s_axi_dma_awcache,
    input  wire [2:0]                     s_axi_dma_awprot,
    input  wire [3:0]                     s_axi_dma_awqos,
    input  wire [3:0]                     s_axi_dma_awregion,
    input  wire                           s_axi_dma_awvalid,
    output wire                           s_axi_dma_awready,
    input  wire [63:0]                    s_axi_dma_wdata,
    input  wire [7:0]                     s_axi_dma_wstrb,
    input  wire                           s_axi_dma_wlast,
    input  wire                           s_axi_dma_wvalid,
    output wire                           s_axi_dma_wready,
    output wire [DMA_ID_WIDTH-1:0]        s_axi_dma_bid,
    output wire [1:0]                     s_axi_dma_bresp,
    output wire                           s_axi_dma_bvalid,
    input  wire                           s_axi_dma_bready,
    input  wire [DMA_ID_WIDTH-1:0]        s_axi_dma_arid,
    input  wire [DMA_ADDR_WIDTH-1:0]      s_axi_dma_araddr,
    input  wire [7:0]                     s_axi_dma_arlen,
    input  wire [2:0]                     s_axi_dma_arsize,
    input  wire [1:0]                     s_axi_dma_arburst,
    input  wire                           s_axi_dma_arlock,
    input  wire [3:0]                     s_axi_dma_arcache,
    input  wire [2:0]                     s_axi_dma_arprot,
    input  wire [3:0]                     s_axi_dma_arqos,
    input  wire [3:0]                     s_axi_dma_arregion,
    input  wire                           s_axi_dma_arvalid,
    output wire                           s_axi_dma_arready,
    output wire [DMA_ID_WIDTH-1:0]        s_axi_dma_rid,
    output wire [63:0]                    s_axi_dma_rdata,
    output wire [1:0]                     s_axi_dma_rresp,
    output wire                           s_axi_dma_rlast,
    output wire                           s_axi_dma_rvalid,
    input  wire                           s_axi_dma_rready
);

    // Enumeration owns the controller MMIO path until it has completed its
    // final read response.  Setup then owns the same physical AXI interface
    // for the remainder of the boot sequence.
    wire mmio_select_setup = enum_done;

    wire [MMIO_ID_WIDTH-1:0]   enum_mmio_awid;
    wire [MMIO_ADDR_WIDTH-1:0] enum_mmio_awaddr;
    wire [7:0]                 enum_mmio_awlen;
    wire [2:0]                 enum_mmio_awsize;
    wire [1:0]                 enum_mmio_awburst;
    wire                       enum_mmio_awlock;
    wire [3:0]                 enum_mmio_awcache;
    wire [2:0]                 enum_mmio_awprot;
    wire [3:0]                 enum_mmio_awqos;
    wire [3:0]                 enum_mmio_awregion;
    wire                       enum_mmio_awvalid;
    wire [63:0]                enum_mmio_wdata;
    wire [7:0]                 enum_mmio_wstrb;
    wire                       enum_mmio_wlast;
    wire                       enum_mmio_wvalid;
    wire                       enum_mmio_bready;
    wire [MMIO_ID_WIDTH-1:0]   enum_mmio_arid;
    wire [MMIO_ADDR_WIDTH-1:0] enum_mmio_araddr;
    wire [7:0]                 enum_mmio_arlen;
    wire [2:0]                 enum_mmio_arsize;
    wire [1:0]                 enum_mmio_arburst;
    wire                       enum_mmio_arlock;
    wire [3:0]                 enum_mmio_arcache;
    wire [2:0]                 enum_mmio_arprot;
    wire [3:0]                 enum_mmio_arqos;
    wire [3:0]                 enum_mmio_arregion;
    wire                       enum_mmio_arvalid;
    wire                       enum_mmio_rready;

    wire [MMIO_ID_WIDTH-1:0]   setup_mmio_awid;
    wire [MMIO_ADDR_WIDTH-1:0] setup_mmio_awaddr;
    wire [7:0]                 setup_mmio_awlen;
    wire [2:0]                 setup_mmio_awsize;
    wire [1:0]                 setup_mmio_awburst;
    wire                       setup_mmio_awlock;
    wire [3:0]                 setup_mmio_awcache;
    wire [2:0]                 setup_mmio_awprot;
    wire [3:0]                 setup_mmio_awqos;
    wire [3:0]                 setup_mmio_awregion;
    wire                       setup_mmio_awvalid;
    wire [63:0]                setup_mmio_wdata;
    wire [7:0]                 setup_mmio_wstrb;
    wire                       setup_mmio_wlast;
    wire                       setup_mmio_wvalid;
    wire                       setup_mmio_bready;
    wire [MMIO_ID_WIDTH-1:0]   setup_mmio_arid;
    wire [MMIO_ADDR_WIDTH-1:0] setup_mmio_araddr;
    wire [7:0]                 setup_mmio_arlen;
    wire [2:0]                 setup_mmio_arsize;
    wire [1:0]                 setup_mmio_arburst;
    wire                       setup_mmio_arlock;
    wire [3:0]                 setup_mmio_arcache;
    wire [2:0]                 setup_mmio_arprot;
    wire [3:0]                 setup_mmio_arqos;
    wire [3:0]                 setup_mmio_arregion;
    wire                       setup_mmio_arvalid;
    wire                       setup_mmio_rready;

    assign m_axi_mmio_awid = mmio_select_setup ? setup_mmio_awid : enum_mmio_awid;
    assign m_axi_mmio_awaddr = mmio_select_setup ? setup_mmio_awaddr : enum_mmio_awaddr;
    assign m_axi_mmio_awlen = mmio_select_setup ? setup_mmio_awlen : enum_mmio_awlen;
    assign m_axi_mmio_awsize = mmio_select_setup ? setup_mmio_awsize : enum_mmio_awsize;
    assign m_axi_mmio_awburst = mmio_select_setup ? setup_mmio_awburst : enum_mmio_awburst;
    assign m_axi_mmio_awlock = mmio_select_setup ? setup_mmio_awlock : enum_mmio_awlock;
    assign m_axi_mmio_awcache = mmio_select_setup ? setup_mmio_awcache : enum_mmio_awcache;
    assign m_axi_mmio_awprot = mmio_select_setup ? setup_mmio_awprot : enum_mmio_awprot;
    assign m_axi_mmio_awqos = mmio_select_setup ? setup_mmio_awqos : enum_mmio_awqos;
    assign m_axi_mmio_awregion = mmio_select_setup ? setup_mmio_awregion : enum_mmio_awregion;
    assign m_axi_mmio_awvalid = mmio_select_setup ? setup_mmio_awvalid : enum_mmio_awvalid;
    assign m_axi_mmio_wdata = mmio_select_setup ? setup_mmio_wdata : enum_mmio_wdata;
    assign m_axi_mmio_wstrb = mmio_select_setup ? setup_mmio_wstrb : enum_mmio_wstrb;
    assign m_axi_mmio_wlast = mmio_select_setup ? setup_mmio_wlast : enum_mmio_wlast;
    assign m_axi_mmio_wvalid = mmio_select_setup ? setup_mmio_wvalid : enum_mmio_wvalid;
    assign m_axi_mmio_bready = mmio_select_setup ? setup_mmio_bready : enum_mmio_bready;
    assign m_axi_mmio_arid = mmio_select_setup ? setup_mmio_arid : enum_mmio_arid;
    assign m_axi_mmio_araddr = mmio_select_setup ? setup_mmio_araddr : enum_mmio_araddr;
    assign m_axi_mmio_arlen = mmio_select_setup ? setup_mmio_arlen : enum_mmio_arlen;
    assign m_axi_mmio_arsize = mmio_select_setup ? setup_mmio_arsize : enum_mmio_arsize;
    assign m_axi_mmio_arburst = mmio_select_setup ? setup_mmio_arburst : enum_mmio_arburst;
    assign m_axi_mmio_arlock = mmio_select_setup ? setup_mmio_arlock : enum_mmio_arlock;
    assign m_axi_mmio_arcache = mmio_select_setup ? setup_mmio_arcache : enum_mmio_arcache;
    assign m_axi_mmio_arprot = mmio_select_setup ? setup_mmio_arprot : enum_mmio_arprot;
    assign m_axi_mmio_arqos = mmio_select_setup ? setup_mmio_arqos : enum_mmio_arqos;
    assign m_axi_mmio_arregion = mmio_select_setup ? setup_mmio_arregion : enum_mmio_arregion;
    assign m_axi_mmio_arvalid = mmio_select_setup ? setup_mmio_arvalid : enum_mmio_arvalid;
    assign m_axi_mmio_rready = mmio_select_setup ? setup_mmio_rready : enum_mmio_rready;

    pl_pcie_nvme_enum_top #(
        .CFG_ADDR_WIDTH(CFG_ADDR_WIDTH),
        .MMIO_ADDR_WIDTH(MMIO_ADDR_WIDTH),
        .MMIO_ID_WIDTH(MMIO_ID_WIDTH),
        .CFG_TIMEOUT_CYCLES(CFG_TIMEOUT_CYCLES),
        .CSR_TIMEOUT_CYCLES(CSR_TIMEOUT_CYCLES),
        .MMIO_TIMEOUT_CYCLES(MMIO_TIMEOUT_CYCLES),
        .LINK_SETTLE_CYCLES(LINK_SETTLE_CYCLES),
        .CSR_READY_TIMEOUT_CYCLES(CSR_READY_TIMEOUT_CYCLES),
        .PCIE_TARGET_MPS(PCIE_TARGET_MPS),
        .ECAM_BASE(ECAM_BASE),
        .NVME_MMIO_AXI_BASE(NVME_MMIO_AXI_BASE),
        .NVME_PCIE_BAR_BASE(NVME_PCIE_BAR_BASE),
        .PROGRAM_RP_DMA_BAR(PROGRAM_RP_DMA_BAR),
        .RP_DMA_PCIE_BASE(RP_DMA_PCIE_BASE),
        .RP_DMA_EXPECTED_SIZE(RP_DMA_EXPECTED_SIZE),
        .PROGRAM_BDF_TABLE(PROGRAM_BDF_TABLE),
        .BDF_TABLE_CSR_BASE(BDF_TABLE_CSR_BASE),
        .BDF_ADDR_TRANSLATION(BDF_ADDR_TRANSLATION),
        .BDF_FUNCTION_NUMBER(BDF_FUNCTION_NUMBER),
        .BDF_PROTECTION_ID(BDF_PROTECTION_ID),
        .REQUIRE_PHY_READY(REQUIRE_PHY_READY),
        .REQUIRE_NVME_CLASS(REQUIRE_NVME_CLASS),
        .REQUIRE_NON_PREFETCHABLE_BAR(REQUIRE_NON_PREFETCHABLE_BAR)
    ) enum_i (
        .aclk(aclk),
        .aresetn(aresetn),
        .enum_start(1'b1),
        .enum_soft_reset(1'b0),
        .user_lnk_up(user_lnk_up),
        .phy_ready(phy_ready),
        .csr_prog_done(csr_prog_done),
        .enum_busy(enum_busy),
        .enum_done(enum_done),
        .enum_error(enum_error),
        .enum_state(enum_state),
        .enum_error_code(enum_error_code),
        .device_present(device_present),
        .nvme_class_match(nvme_class_match),
        .vendor_id(vendor_id),
        .device_id(device_id),
        .class_code(class_code),
        .bar_is_64(bar_is_64),
        .bar_prefetchable(bar_prefetchable),
        .bar_size(bar_size),
        .bar_pcie_address(bar_pcie_address),
        .rp_dma_bar_size(rp_dma_bar_size),
        .rp_dma_pcie_base(rp_dma_pcie_base),
        .rp_dma_pcie_limit(rp_dma_pcie_limit),
        .rp_dma_bar_programmed(rp_dma_bar_programmed),
        .bdf_table_programmed(bdf_table_programmed),
        .nvme_cap(nvme_cap),
        .nvme_vs(nvme_vs),
        .rp_pcie_cap_offset(rp_pcie_cap_offset),
        .ep_pcie_cap_offset(ep_pcie_cap_offset),
        .rp_mps_supported(rp_mps_supported),
        .ep_mps_supported(ep_mps_supported),
        .selected_mps(selected_mps),
        .rp_mps_configured(rp_mps_configured),
        .ep_mps_configured(ep_mps_configured),
        .mps_programmed(mps_programmed),
        .last_cfg_addr(last_cfg_addr),
        .last_csr_addr(last_csr_addr),
        .last_csr_write_data(last_csr_write_data),
        .last_mmio_addr(last_mmio_addr),
        .last_read_data(last_read_data),
        .m_axil_ecam_awaddr(m_axil_ecam_awaddr),
        .m_axil_ecam_awprot(m_axil_ecam_awprot),
        .m_axil_ecam_awuser(m_axil_ecam_awuser),
        .m_axil_ecam_awvalid(m_axil_ecam_awvalid),
        .m_axil_ecam_awready(m_axil_ecam_awready),
        .m_axil_ecam_wdata(m_axil_ecam_wdata),
        .m_axil_ecam_wstrb(m_axil_ecam_wstrb),
        .m_axil_ecam_wvalid(m_axil_ecam_wvalid),
        .m_axil_ecam_wready(m_axil_ecam_wready),
        .m_axil_ecam_bresp(m_axil_ecam_bresp),
        .m_axil_ecam_bvalid(m_axil_ecam_bvalid),
        .m_axil_ecam_bready(m_axil_ecam_bready),
        .m_axil_ecam_araddr(m_axil_ecam_araddr),
        .m_axil_ecam_arprot(m_axil_ecam_arprot),
        .m_axil_ecam_aruser(m_axil_ecam_aruser),
        .m_axil_ecam_arvalid(m_axil_ecam_arvalid),
        .m_axil_ecam_arready(m_axil_ecam_arready),
        .m_axil_ecam_rdata(m_axil_ecam_rdata),
        .m_axil_ecam_rresp(m_axil_ecam_rresp),
        .m_axil_ecam_rvalid(m_axil_ecam_rvalid),
        .m_axil_ecam_rready(m_axil_ecam_rready),
        .m_axil_csr_awaddr(m_axil_csr_awaddr),
        .m_axil_csr_awprot(m_axil_csr_awprot),
        .m_axil_csr_awvalid(m_axil_csr_awvalid),
        .m_axil_csr_awready(m_axil_csr_awready),
        .m_axil_csr_wdata(m_axil_csr_wdata),
        .m_axil_csr_wstrb(m_axil_csr_wstrb),
        .m_axil_csr_wvalid(m_axil_csr_wvalid),
        .m_axil_csr_wready(m_axil_csr_wready),
        .m_axil_csr_bresp(m_axil_csr_bresp),
        .m_axil_csr_bvalid(m_axil_csr_bvalid),
        .m_axil_csr_bready(m_axil_csr_bready),
        .m_axil_csr_araddr(m_axil_csr_araddr),
        .m_axil_csr_arprot(m_axil_csr_arprot),
        .m_axil_csr_arvalid(m_axil_csr_arvalid),
        .m_axil_csr_arready(m_axil_csr_arready),
        .m_axil_csr_rdata(m_axil_csr_rdata),
        .m_axil_csr_rresp(m_axil_csr_rresp),
        .m_axil_csr_rvalid(m_axil_csr_rvalid),
        .m_axil_csr_rready(m_axil_csr_rready),
        .m_axi_mmio_awid(enum_mmio_awid),
        .m_axi_mmio_awaddr(enum_mmio_awaddr),
        .m_axi_mmio_awlen(enum_mmio_awlen),
        .m_axi_mmio_awsize(enum_mmio_awsize),
        .m_axi_mmio_awburst(enum_mmio_awburst),
        .m_axi_mmio_awlock(enum_mmio_awlock),
        .m_axi_mmio_awcache(enum_mmio_awcache),
        .m_axi_mmio_awprot(enum_mmio_awprot),
        .m_axi_mmio_awqos(enum_mmio_awqos),
        .m_axi_mmio_awregion(enum_mmio_awregion),
        .m_axi_mmio_awvalid(enum_mmio_awvalid),
        .m_axi_mmio_awready(!mmio_select_setup && m_axi_mmio_awready),
        .m_axi_mmio_wdata(enum_mmio_wdata),
        .m_axi_mmio_wstrb(enum_mmio_wstrb),
        .m_axi_mmio_wlast(enum_mmio_wlast),
        .m_axi_mmio_wvalid(enum_mmio_wvalid),
        .m_axi_mmio_wready(!mmio_select_setup && m_axi_mmio_wready),
        .m_axi_mmio_bid(m_axi_mmio_bid),
        .m_axi_mmio_bresp(m_axi_mmio_bresp),
        .m_axi_mmio_bvalid(!mmio_select_setup && m_axi_mmio_bvalid),
        .m_axi_mmio_bready(enum_mmio_bready),
        .m_axi_mmio_arid(enum_mmio_arid),
        .m_axi_mmio_araddr(enum_mmio_araddr),
        .m_axi_mmio_arlen(enum_mmio_arlen),
        .m_axi_mmio_arsize(enum_mmio_arsize),
        .m_axi_mmio_arburst(enum_mmio_arburst),
        .m_axi_mmio_arlock(enum_mmio_arlock),
        .m_axi_mmio_arcache(enum_mmio_arcache),
        .m_axi_mmio_arprot(enum_mmio_arprot),
        .m_axi_mmio_arqos(enum_mmio_arqos),
        .m_axi_mmio_arregion(enum_mmio_arregion),
        .m_axi_mmio_arvalid(enum_mmio_arvalid),
        .m_axi_mmio_arready(!mmio_select_setup && m_axi_mmio_arready),
        .m_axi_mmio_rid(m_axi_mmio_rid),
        .m_axi_mmio_rdata(m_axi_mmio_rdata),
        .m_axi_mmio_rresp(m_axi_mmio_rresp),
        .m_axi_mmio_rlast(m_axi_mmio_rlast),
        .m_axi_mmio_rvalid(!mmio_select_setup && m_axi_mmio_rvalid),
        .m_axi_mmio_rready(enum_mmio_rready)
    );

    pl_pcie_nvme_setup_top #(
        .ENABLE_SETUP_DEBUG(ENABLE_SETUP_DEBUG),
        .MMIO_ADDR_WIDTH(MMIO_ADDR_WIDTH),
        .MMIO_ID_WIDTH(MMIO_ID_WIDTH),
        .DMA_ADDR_WIDTH(DMA_ADDR_WIDTH),
        .DMA_ID_WIDTH(DMA_ID_WIDTH),
        .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
        .MMIO_TIMEOUT_CYCLES(MMIO_TIMEOUT_CYCLES),
        .NVME_MMIO_AXI_BASE(NVME_MMIO_AXI_BASE),
        .RP_DMA_PCIE_BASE(RP_DMA_PCIE_BASE),
        .RP_DMA_PCIE_SIZE(RP_DMA_EXPECTED_SIZE),
        .KNOWN_CAP(KNOWN_CAP),
        .KNOWN_VS(KNOWN_VS),
        .QUEUE_DEPTH(QUEUE_DEPTH),
        .IO_QUEUE_DEPTH(IO_QUEUE_DEPTH),
        .READY_TIMEOUT_POLLS(READY_TIMEOUT_POLLS),
        .CQ_TIMEOUT_POLLS(CQ_TIMEOUT_POLLS),
        .NVME_NSID(NVME_NSID),
        .DISCOVERY_PCIE_ADDR(DISCOVERY_PCIE_ADDR),
        .ADMIN_SQ_PCIE_ADDR(ADMIN_SQ_PCIE_ADDR),
        .ADMIN_CQ_PCIE_ADDR(ADMIN_CQ_PCIE_ADDR),
        .IO_SQ_PCIE_ADDR(IO_SQ_PCIE_ADDR),
        .IO_CQ_PCIE_ADDR(IO_CQ_PCIE_ADDR)
    ) setup_i (
        .aclk(aclk),
        .aresetn(aresetn),
        .enum_done(enum_done),
        .health_snapshot_request(health_snapshot_request),
        .debug_ram_read_enable(debug_ram_read_enable),
        .debug_ram_read_addr(debug_ram_read_addr),
        .debug_ram_read_data(debug_ram_read_data),
        .debug_ram_granted(debug_ram_granted),
        .setup_started(setup_started),
        .setup_busy(setup_busy),
        .queues_ready(queues_ready),
        .setup_done(setup_done),
        .setup_error(setup_error),
        .discovery_done(discovery_done),
        .discovery_valid(discovery_valid),
        .controller_info_valid(controller_info_valid),
        .namespace_list_valid(namespace_list_valid),
        .namespace_info_valid(namespace_info_valid),
        .target_nsid_found(target_nsid_found),
        .discovered_controller_vid(discovered_controller_vid),
        .discovered_controller_ssvid(discovered_controller_ssvid),
        .discovered_controller_version(discovered_controller_version),
        .discovered_controller_nn(discovered_controller_nn),
        .discovered_controller_mdts(discovered_controller_mdts),
        .discovered_controller_sqes(discovered_controller_sqes),
        .discovered_controller_cqes(discovered_controller_cqes),
        .discovered_first_nsid(discovered_first_nsid),
        .discovered_active_nsid_count(discovered_active_nsid_count),
        .discovered_nsze(discovered_nsze),
        .discovered_ncap(discovered_ncap),
        .discovered_nuse(discovered_nuse),
        .discovered_nlbaf(discovered_nlbaf),
        .discovered_flbas(discovered_flbas),
        .discovered_lba_format_index(discovered_lba_format_index),
        .discovered_lbads(discovered_lbads),
        .discovered_metadata_bytes(discovered_metadata_bytes),
        .discovered_lba_bytes(discovered_lba_bytes),
        .health_snapshot_busy(health_snapshot_busy),
        .health_snapshot_done(health_snapshot_done),
        .health_snapshot_count(health_snapshot_count),
        .health_valid(health_valid),
        .health_command_status(health_command_status),
        .health_error_code(health_error_code),
        .health_firmware_revision(health_firmware_revision),
        .health_npss(health_npss),
        .health_apsta(health_apsta),
        .health_thermal_caps(health_thermal_caps),
        .health_power_management(health_power_management),
        .health_apst(health_apst),
        .health_hctm(health_hctm),
        .health_ps0_summary(health_ps0_summary),
        .health_current_ps_summary(health_current_ps_summary),
        .health_current_ps_valid(health_current_ps_valid),
        .health_smart_status(health_smart_status),
        .health_media_errors(health_media_errors),
        .health_error_log_entries(health_error_log_entries),
        .health_temperature_time(health_temperature_time),
        .health_temperature_sensors(health_temperature_sensors),
        .health_thermal_transitions(health_thermal_transitions),
        .health_thermal_time(health_thermal_time),
        .setup_state(setup_state),
        .setup_error_code(setup_error_code),
        .last_opcode(last_opcode),
        .last_cid(last_cid),
        .last_completion_cid(last_completion_cid),
        .last_completion_status(last_completion_status),
        .last_cqe(last_cqe),
        .last_mmio_offset(last_mmio_offset),
        .last_mmio_rdata(last_mmio_rdata),
        .submitted_command_count(submitted_command_count),
        .admin_sq_tail(admin_sq_tail),
        .admin_cq_head(admin_cq_head),
        .admin_cq_phase(admin_cq_phase),
        .ready_poll_count(ready_poll_count),
        .cq_poll_count(cq_poll_count),
        .allocated_io_queues(allocated_io_queues),
        .dma_bridge_state(dma_bridge_state),
        .dma_last_axi_addr(dma_last_axi_addr),
        .dma_last_axi_resp(dma_last_axi_resp),
        .dma_protocol_error(dma_protocol_error),
        .m_axi_mmio_awid(setup_mmio_awid),
        .m_axi_mmio_awaddr(setup_mmio_awaddr),
        .m_axi_mmio_awlen(setup_mmio_awlen),
        .m_axi_mmio_awsize(setup_mmio_awsize),
        .m_axi_mmio_awburst(setup_mmio_awburst),
        .m_axi_mmio_awlock(setup_mmio_awlock),
        .m_axi_mmio_awcache(setup_mmio_awcache),
        .m_axi_mmio_awprot(setup_mmio_awprot),
        .m_axi_mmio_awqos(setup_mmio_awqos),
        .m_axi_mmio_awregion(setup_mmio_awregion),
        .m_axi_mmio_awvalid(setup_mmio_awvalid),
        .m_axi_mmio_awready(mmio_select_setup && m_axi_mmio_awready),
        .m_axi_mmio_wdata(setup_mmio_wdata),
        .m_axi_mmio_wstrb(setup_mmio_wstrb),
        .m_axi_mmio_wlast(setup_mmio_wlast),
        .m_axi_mmio_wvalid(setup_mmio_wvalid),
        .m_axi_mmio_wready(mmio_select_setup && m_axi_mmio_wready),
        .m_axi_mmio_bid(m_axi_mmio_bid),
        .m_axi_mmio_bresp(m_axi_mmio_bresp),
        .m_axi_mmio_bvalid(mmio_select_setup && m_axi_mmio_bvalid),
        .m_axi_mmio_bready(setup_mmio_bready),
        .m_axi_mmio_arid(setup_mmio_arid),
        .m_axi_mmio_araddr(setup_mmio_araddr),
        .m_axi_mmio_arlen(setup_mmio_arlen),
        .m_axi_mmio_arsize(setup_mmio_arsize),
        .m_axi_mmio_arburst(setup_mmio_arburst),
        .m_axi_mmio_arlock(setup_mmio_arlock),
        .m_axi_mmio_arcache(setup_mmio_arcache),
        .m_axi_mmio_arprot(setup_mmio_arprot),
        .m_axi_mmio_arqos(setup_mmio_arqos),
        .m_axi_mmio_arregion(setup_mmio_arregion),
        .m_axi_mmio_arvalid(setup_mmio_arvalid),
        .m_axi_mmio_arready(mmio_select_setup && m_axi_mmio_arready),
        .m_axi_mmio_rid(m_axi_mmio_rid),
        .m_axi_mmio_rdata(m_axi_mmio_rdata),
        .m_axi_mmio_rresp(m_axi_mmio_rresp),
        .m_axi_mmio_rlast(m_axi_mmio_rlast),
        .m_axi_mmio_rvalid(mmio_select_setup && m_axi_mmio_rvalid),
        .m_axi_mmio_rready(setup_mmio_rready),
        .s_axi_dma_awid(s_axi_dma_awid),
        .s_axi_dma_awaddr(s_axi_dma_awaddr),
        .s_axi_dma_awlen(s_axi_dma_awlen),
        .s_axi_dma_awsize(s_axi_dma_awsize),
        .s_axi_dma_awburst(s_axi_dma_awburst),
        .s_axi_dma_awlock(s_axi_dma_awlock),
        .s_axi_dma_awcache(s_axi_dma_awcache),
        .s_axi_dma_awprot(s_axi_dma_awprot),
        .s_axi_dma_awqos(s_axi_dma_awqos),
        .s_axi_dma_awregion(s_axi_dma_awregion),
        .s_axi_dma_awvalid(s_axi_dma_awvalid),
        .s_axi_dma_awready(s_axi_dma_awready),
        .s_axi_dma_wdata(s_axi_dma_wdata),
        .s_axi_dma_wstrb(s_axi_dma_wstrb),
        .s_axi_dma_wlast(s_axi_dma_wlast),
        .s_axi_dma_wvalid(s_axi_dma_wvalid),
        .s_axi_dma_wready(s_axi_dma_wready),
        .s_axi_dma_bid(s_axi_dma_bid),
        .s_axi_dma_bresp(s_axi_dma_bresp),
        .s_axi_dma_bvalid(s_axi_dma_bvalid),
        .s_axi_dma_bready(s_axi_dma_bready),
        .s_axi_dma_arid(s_axi_dma_arid),
        .s_axi_dma_araddr(s_axi_dma_araddr),
        .s_axi_dma_arlen(s_axi_dma_arlen),
        .s_axi_dma_arsize(s_axi_dma_arsize),
        .s_axi_dma_arburst(s_axi_dma_arburst),
        .s_axi_dma_arlock(s_axi_dma_arlock),
        .s_axi_dma_arcache(s_axi_dma_arcache),
        .s_axi_dma_arprot(s_axi_dma_arprot),
        .s_axi_dma_arqos(s_axi_dma_arqos),
        .s_axi_dma_arregion(s_axi_dma_arregion),
        .s_axi_dma_arvalid(s_axi_dma_arvalid),
        .s_axi_dma_arready(s_axi_dma_arready),
        .s_axi_dma_rid(s_axi_dma_rid),
        .s_axi_dma_rdata(s_axi_dma_rdata),
        .s_axi_dma_rresp(s_axi_dma_rresp),
        .s_axi_dma_rlast(s_axi_dma_rlast),
        .s_axi_dma_rvalid(s_axi_dma_rvalid),
        .s_axi_dma_rready(s_axi_dma_rready)
    );

endmodule
