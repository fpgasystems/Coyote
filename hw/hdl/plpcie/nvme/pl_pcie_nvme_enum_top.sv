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
// pl_pcie_nvme_enum_top
// -----------------------------------------------------------------------------
// PG344 bridge-mode integration wrapper for the PL-only NVMe recognizer.
//
// Direct Vivado connections:
//
//   M_AXIL_ECAM -> PG344 S_AXIL
//       ECAM accesses to Root Port 00:00.0 and endpoint 01:00.0.
//       AWUSER/ARUSER are tied to function zero by this wrapper.
//
//   M_AXIL_CSR  -> PG344 S_AXIL_CSR
//       Local bridge CSR accesses.  This wrapper uses it to program the six
//       registers of BDF-table entry zero before any S_AXIB request.
//
//   M_AXI_MMIO  -> AXI SmartConnect -> PG344 S_AXIB
//       Outbound NVMe BAR reads.  SmartConnect is required because PG344's
//       slave bridge does not accept narrow AXI bursts and is commonly wider
//       than this wrapper's native 64-bit data path.
//
// PG344 M_AXIB is not connected to this module.  M_AXIB is the inbound path
// for later NVMe DMA and should be routed through address translation/firewall
// logic to DDR or HBM.
// -----------------------------------------------------------------------------
module pl_pcie_nvme_enum_top #(
    parameter integer CFG_ADDR_WIDTH = 32,
    parameter integer MMIO_ADDR_WIDTH = 64,
    parameter integer MMIO_ID_WIDTH = 1,
    parameter integer CFG_TIMEOUT_CYCLES = 1_000_000,
    parameter integer CSR_TIMEOUT_CYCLES = 1_000_000,
    parameter integer MMIO_TIMEOUT_CYCLES = 1_000_000,
    parameter integer LINK_SETTLE_CYCLES = 1024,
    parameter integer CSR_READY_TIMEOUT_CYCLES = 1_000_000,
    parameter logic [2:0] PCIE_TARGET_MPS = 3'd3,

    parameter logic [CFG_ADDR_WIDTH-1:0] ECAM_BASE = '0,
    parameter logic [MMIO_ADDR_WIDTH-1:0] NVME_MMIO_AXI_BASE =
        64'h0000_0000_8000_0000,
    parameter logic [63:0] NVME_PCIE_BAR_BASE =
        64'h0000_0000_8000_0000,

    parameter bit          PROGRAM_RP_DMA_BAR = 1'b1,
    parameter logic [63:0] RP_DMA_PCIE_BASE =
        64'h0000_1000_0000_0000,
    parameter logic [63:0] RP_DMA_EXPECTED_SIZE =
        64'h0000_1000_0000_0000,

    parameter bit          PROGRAM_BDF_TABLE = 1'b1,
    parameter logic [31:0] BDF_TABLE_CSR_BASE = 32'h0000_2420,
    parameter logic [63:0] BDF_ADDR_TRANSLATION = 64'd0,
    parameter logic [11:0] BDF_FUNCTION_NUMBER = 12'd0,
    parameter logic [2:0]  BDF_PROTECTION_ID = 3'b000,

    parameter bit REQUIRE_PHY_READY = 1'b1,
    parameter bit REQUIRE_NVME_CLASS = 1'b1,
    parameter bit REQUIRE_NON_PREFETCHABLE_BAR = 1'b1
) (
    input  wire                           aclk,
    input  wire                           aresetn,

    // VIO controls.
    input  wire                           enum_start,
    input  wire                           enum_soft_reset,

    // PG344 global outputs, synchronous to axi_aclk.
    input  wire                           user_lnk_up,
    input  wire                           phy_ready,
    input  wire                           csr_prog_done,

    // Latched results/debug probes.
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

    // AXI4-Lite ECAM master -> PG344 normal S_AXIL.
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

    // AXI4-Lite bridge-CSR master -> PG344 S_AXIL_CSR.
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

    // 64-bit AXI4 outbound MMIO master -> SmartConnect -> PG344 S_AXIB.
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
    output wire                           m_axi_mmio_rready
);

    wire internal_aresetn = aresetn && !enum_soft_reset;

    // PG344 S_AXIL user fields select function zero for the local Root Port.
    assign m_axil_ecam_awuser = 13'd0;
    assign m_axil_ecam_aruser = 13'd0;

    // Abstract ECAM command/response.
    wire cfg_cmd_valid_i;
    wire cfg_cmd_ready_i;
    wire cfg_cmd_write_i;
    wire [CFG_ADDR_WIDTH-1:0] cfg_cmd_addr_i;
    wire [31:0] cfg_cmd_wdata_i;
    wire [3:0] cfg_cmd_wstrb_i;
    wire cfg_rsp_valid_i;
    wire cfg_rsp_ready_i;
    wire [31:0] cfg_rsp_rdata_i;
    wire [1:0] cfg_rsp_resp_i;
    wire cfg_rsp_timeout_i;

    // Abstract bridge-CSR command/response.
    wire csr_cmd_valid_i;
    wire csr_cmd_ready_i;
    wire csr_cmd_write_i;
    wire [31:0] csr_cmd_addr_i;
    wire [31:0] csr_cmd_wdata_i;
    wire [3:0] csr_cmd_wstrb_i;
    wire csr_rsp_valid_i;
    wire csr_rsp_ready_i;
    wire [31:0] csr_rsp_rdata_i;
    wire [1:0] csr_rsp_resp_i;
    wire csr_rsp_timeout_i;

    // Abstract endpoint-MMIO command/response.
    wire mmio_cmd_valid_i;
    wire mmio_cmd_ready_i;
    wire mmio_cmd_write_i;
    wire [MMIO_ADDR_WIDTH-1:0] mmio_cmd_addr_i;
    wire [63:0] mmio_cmd_wdata_i;
    wire [7:0] mmio_cmd_wstrb_i;
    wire [2:0] mmio_cmd_size_i;
    wire mmio_rsp_valid_i;
    wire mmio_rsp_ready_i;
    wire [63:0] mmio_rsp_rdata_i;
    wire [1:0] mmio_rsp_resp_i;
    wire mmio_rsp_timeout_i;

    pl_pcie_nvme_enum_fsm #(
        .CFG_ADDR_WIDTH(CFG_ADDR_WIDTH),
        .MMIO_ADDR_WIDTH(MMIO_ADDR_WIDTH),
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
        .LINK_SETTLE_CYCLES(LINK_SETTLE_CYCLES),
        .CSR_READY_TIMEOUT_CYCLES(CSR_READY_TIMEOUT_CYCLES),
        .PCIE_TARGET_MPS(PCIE_TARGET_MPS),
        .REQUIRE_PHY_READY(REQUIRE_PHY_READY),
        .REQUIRE_NVME_CLASS(REQUIRE_NVME_CLASS),
        .REQUIRE_NON_PREFETCHABLE_BAR(
            REQUIRE_NON_PREFETCHABLE_BAR
        )
    ) enum_fsm_i (
        .clk(aclk),
        .resetn(aresetn),
        .soft_reset(enum_soft_reset),
        .start(enum_start),
        .user_lnk_up(user_lnk_up),
        .phy_ready(phy_ready),
        .csr_prog_done(csr_prog_done),

        .cfg_cmd_valid(cfg_cmd_valid_i),
        .cfg_cmd_ready(cfg_cmd_ready_i),
        .cfg_cmd_write(cfg_cmd_write_i),
        .cfg_cmd_addr(cfg_cmd_addr_i),
        .cfg_cmd_wdata(cfg_cmd_wdata_i),
        .cfg_cmd_wstrb(cfg_cmd_wstrb_i),
        .cfg_rsp_valid(cfg_rsp_valid_i),
        .cfg_rsp_ready(cfg_rsp_ready_i),
        .cfg_rsp_rdata(cfg_rsp_rdata_i),
        .cfg_rsp_resp(cfg_rsp_resp_i),
        .cfg_rsp_timeout(cfg_rsp_timeout_i),

        .csr_cmd_valid(csr_cmd_valid_i),
        .csr_cmd_ready(csr_cmd_ready_i),
        .csr_cmd_write(csr_cmd_write_i),
        .csr_cmd_addr(csr_cmd_addr_i),
        .csr_cmd_wdata(csr_cmd_wdata_i),
        .csr_cmd_wstrb(csr_cmd_wstrb_i),
        .csr_rsp_valid(csr_rsp_valid_i),
        .csr_rsp_ready(csr_rsp_ready_i),
        .csr_rsp_rdata(csr_rsp_rdata_i),
        .csr_rsp_resp(csr_rsp_resp_i),
        .csr_rsp_timeout(csr_rsp_timeout_i),

        .mmio_cmd_valid(mmio_cmd_valid_i),
        .mmio_cmd_ready(mmio_cmd_ready_i),
        .mmio_cmd_write(mmio_cmd_write_i),
        .mmio_cmd_addr(mmio_cmd_addr_i),
        .mmio_cmd_wdata(mmio_cmd_wdata_i),
        .mmio_cmd_wstrb(mmio_cmd_wstrb_i),
        .mmio_cmd_size(mmio_cmd_size_i),
        .mmio_rsp_valid(mmio_rsp_valid_i),
        .mmio_rsp_ready(mmio_rsp_ready_i),
        .mmio_rsp_rdata(mmio_rsp_rdata_i),
        .mmio_rsp_resp(mmio_rsp_resp_i),
        .mmio_rsp_timeout(mmio_rsp_timeout_i),

        .busy(enum_busy),
        .done(enum_done),
        .error(enum_error),
        .state_dbg(enum_state),
        .error_code(enum_error_code),
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
        .last_read_data(last_read_data)
    );

    pl_pcie_nvme_axi_lite_single_master #(
        .ADDR_WIDTH(CFG_ADDR_WIDTH),
        .TIMEOUT_CYCLES(CFG_TIMEOUT_CYCLES)
    ) ecam_master_i (
        .aclk(aclk),
        .aresetn(internal_aresetn),
        .cmd_valid(cfg_cmd_valid_i),
        .cmd_ready(cfg_cmd_ready_i),
        .cmd_write(cfg_cmd_write_i),
        .cmd_addr(cfg_cmd_addr_i),
        .cmd_wdata(cfg_cmd_wdata_i),
        .cmd_wstrb(cfg_cmd_wstrb_i),
        .rsp_valid(cfg_rsp_valid_i),
        .rsp_ready(cfg_rsp_ready_i),
        .rsp_rdata(cfg_rsp_rdata_i),
        .rsp_resp(cfg_rsp_resp_i),
        .rsp_timeout(cfg_rsp_timeout_i),
        .m_axi_awaddr(m_axil_ecam_awaddr),
        .m_axi_awprot(m_axil_ecam_awprot),
        .m_axi_awvalid(m_axil_ecam_awvalid),
        .m_axi_awready(m_axil_ecam_awready),
        .m_axi_wdata(m_axil_ecam_wdata),
        .m_axi_wstrb(m_axil_ecam_wstrb),
        .m_axi_wvalid(m_axil_ecam_wvalid),
        .m_axi_wready(m_axil_ecam_wready),
        .m_axi_bresp(m_axil_ecam_bresp),
        .m_axi_bvalid(m_axil_ecam_bvalid),
        .m_axi_bready(m_axil_ecam_bready),
        .m_axi_araddr(m_axil_ecam_araddr),
        .m_axi_arprot(m_axil_ecam_arprot),
        .m_axi_arvalid(m_axil_ecam_arvalid),
        .m_axi_arready(m_axil_ecam_arready),
        .m_axi_rdata(m_axil_ecam_rdata),
        .m_axi_rresp(m_axil_ecam_rresp),
        .m_axi_rvalid(m_axil_ecam_rvalid),
        .m_axi_rready(m_axil_ecam_rready)
    );

    pl_pcie_nvme_axi_lite_single_master #(
        .ADDR_WIDTH(32),
        .TIMEOUT_CYCLES(CSR_TIMEOUT_CYCLES)
    ) csr_master_i (
        .aclk(aclk),
        .aresetn(internal_aresetn),
        .cmd_valid(csr_cmd_valid_i),
        .cmd_ready(csr_cmd_ready_i),
        .cmd_write(csr_cmd_write_i),
        .cmd_addr(csr_cmd_addr_i),
        .cmd_wdata(csr_cmd_wdata_i),
        .cmd_wstrb(csr_cmd_wstrb_i),
        .rsp_valid(csr_rsp_valid_i),
        .rsp_ready(csr_rsp_ready_i),
        .rsp_rdata(csr_rsp_rdata_i),
        .rsp_resp(csr_rsp_resp_i),
        .rsp_timeout(csr_rsp_timeout_i),
        .m_axi_awaddr(m_axil_csr_awaddr),
        .m_axi_awprot(m_axil_csr_awprot),
        .m_axi_awvalid(m_axil_csr_awvalid),
        .m_axi_awready(m_axil_csr_awready),
        .m_axi_wdata(m_axil_csr_wdata),
        .m_axi_wstrb(m_axil_csr_wstrb),
        .m_axi_wvalid(m_axil_csr_wvalid),
        .m_axi_wready(m_axil_csr_wready),
        .m_axi_bresp(m_axil_csr_bresp),
        .m_axi_bvalid(m_axil_csr_bvalid),
        .m_axi_bready(m_axil_csr_bready),
        .m_axi_araddr(m_axil_csr_araddr),
        .m_axi_arprot(m_axil_csr_arprot),
        .m_axi_arvalid(m_axil_csr_arvalid),
        .m_axi_arready(m_axil_csr_arready),
        .m_axi_rdata(m_axil_csr_rdata),
        .m_axi_rresp(m_axil_csr_rresp),
        .m_axi_rvalid(m_axil_csr_rvalid),
        .m_axi_rready(m_axil_csr_rready)
    );

    pl_pcie_nvme_axi4_single_master_64 #(
        .ADDR_WIDTH(MMIO_ADDR_WIDTH),
        .ID_WIDTH(MMIO_ID_WIDTH),
        .TIMEOUT_CYCLES(MMIO_TIMEOUT_CYCLES)
    ) mmio_master_i (
        .aclk(aclk),
        .aresetn(internal_aresetn),
        .cmd_valid(mmio_cmd_valid_i),
        .cmd_ready(mmio_cmd_ready_i),
        .cmd_write(mmio_cmd_write_i),
        .cmd_addr(mmio_cmd_addr_i),
        .cmd_wdata(mmio_cmd_wdata_i),
        .cmd_wstrb(mmio_cmd_wstrb_i),
        .cmd_size(mmio_cmd_size_i),
        .rsp_valid(mmio_rsp_valid_i),
        .rsp_ready(mmio_rsp_ready_i),
        .rsp_rdata(mmio_rsp_rdata_i),
        .rsp_resp(mmio_rsp_resp_i),
        .rsp_timeout(mmio_rsp_timeout_i),
        .m_axi_awid(m_axi_mmio_awid),
        .m_axi_awaddr(m_axi_mmio_awaddr),
        .m_axi_awlen(m_axi_mmio_awlen),
        .m_axi_awsize(m_axi_mmio_awsize),
        .m_axi_awburst(m_axi_mmio_awburst),
        .m_axi_awlock(m_axi_mmio_awlock),
        .m_axi_awcache(m_axi_mmio_awcache),
        .m_axi_awprot(m_axi_mmio_awprot),
        .m_axi_awqos(m_axi_mmio_awqos),
        .m_axi_awregion(m_axi_mmio_awregion),
        .m_axi_awvalid(m_axi_mmio_awvalid),
        .m_axi_awready(m_axi_mmio_awready),
        .m_axi_wdata(m_axi_mmio_wdata),
        .m_axi_wstrb(m_axi_mmio_wstrb),
        .m_axi_wlast(m_axi_mmio_wlast),
        .m_axi_wvalid(m_axi_mmio_wvalid),
        .m_axi_wready(m_axi_mmio_wready),
        .m_axi_bid(m_axi_mmio_bid),
        .m_axi_bresp(m_axi_mmio_bresp),
        .m_axi_bvalid(m_axi_mmio_bvalid),
        .m_axi_bready(m_axi_mmio_bready),
        .m_axi_arid(m_axi_mmio_arid),
        .m_axi_araddr(m_axi_mmio_araddr),
        .m_axi_arlen(m_axi_mmio_arlen),
        .m_axi_arsize(m_axi_mmio_arsize),
        .m_axi_arburst(m_axi_mmio_arburst),
        .m_axi_arlock(m_axi_mmio_arlock),
        .m_axi_arcache(m_axi_mmio_arcache),
        .m_axi_arprot(m_axi_mmio_arprot),
        .m_axi_arqos(m_axi_mmio_arqos),
        .m_axi_arregion(m_axi_mmio_arregion),
        .m_axi_arvalid(m_axi_mmio_arvalid),
        .m_axi_arready(m_axi_mmio_arready),
        .m_axi_rid(m_axi_mmio_rid),
        .m_axi_rdata(m_axi_mmio_rdata),
        .m_axi_rresp(m_axi_mmio_rresp),
        .m_axi_rlast(m_axi_mmio_rlast),
        .m_axi_rvalid(m_axi_mmio_rvalid),
        .m_axi_rready(m_axi_mmio_rready)
    );

endmodule
