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
// pl_pcie_nvme_setup_top
// -----------------------------------------------------------------------------
// Compact integration core for discovery, Admin queues, and external I/O queue
// creation.  It intentionally contains no media read/write test datapath.
//
// Vivado block-design connections:
//
//   enumeration M_AXI_MMIO ---------+
//                                    +-> SmartConnect -> PG344/S_AXIB
//   this/M_AXI_MMIO ----------------+
//
//   PG344/M_AXIB -> SmartConnect (width/address adaptation) -> this/S_AXI_DMA
//
// The first SmartConnect arbitrates two PL masters that are naturally
// time-separated by enum_done.  The second commonly converts PG344's wider
// M_AXIB data bus to this wrapper's 64-bit RAM-facing slave.
// -----------------------------------------------------------------------------
module pl_pcie_nvme_setup_top #(
    parameter integer MMIO_ADDR_WIDTH = 64,
    parameter integer MMIO_ID_WIDTH   = 1,
    parameter integer DMA_ADDR_WIDTH  = 64,
    parameter integer DMA_ID_WIDTH    = 4,
    parameter integer RAM_ADDR_WIDTH  = 11,
    parameter integer MMIO_TIMEOUT_CYCLES = 1_000_000,

    parameter logic [MMIO_ADDR_WIDTH-1:0] NVME_MMIO_AXI_BASE =
        64'h0000_0000_8000_0000,
    parameter logic [63:0] RP_DMA_PCIE_BASE =
        64'h0000_1000_0000_0000,
    parameter logic [63:0] RP_DMA_PCIE_SIZE =
        64'h0000_1000_0000_0000,

    parameter logic [63:0] KNOWN_CAP = 64'h1800_C030_1E02_3FFF,
    parameter logic [31:0] KNOWN_VS  = 32'h0002_0000,
    parameter integer QUEUE_DEPTH = 64, // Admin queues remain in 4 KiB pages.
    parameter integer IO_QUEUE_DEPTH = 64,
    parameter integer READY_TIMEOUT_POLLS = 1_000_000,
    parameter integer CQ_TIMEOUT_POLLS    = 1_000_000,
    parameter logic [31:0] NVME_NSID      = 32'd1,
    parameter logic [63:0] DISCOVERY_PCIE_ADDR =
        RP_DMA_PCIE_BASE + RP_DMA_PCIE_SIZE - 64'h4000,
    parameter logic [63:0] ADMIN_SQ_PCIE_ADDR =
        RP_DMA_PCIE_BASE + RP_DMA_PCIE_SIZE - 64'h2000,
    parameter logic [63:0] ADMIN_CQ_PCIE_ADDR =
        RP_DMA_PCIE_BASE + RP_DMA_PCIE_SIZE - 64'h1000,
    parameter logic [63:0] IO_SQ_PCIE_ADDR =
        64'h0000_1FFF_F404_0000, // Fixed for every depth: 16 KiB per device
    parameter logic [63:0] IO_CQ_PCIE_ADDR =
        64'h0000_1FFF_F402_0000,
    parameter bit ENABLE_SETUP_DEBUG = 1'b0
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         enum_done,
    input  wire                         health_snapshot_request,

    // Debug RAM read port for VIO(address/enable) + ILA(data).  FSM accesses
    // take priority; debug_ram_granted marks cycles in which this read won.
    input  wire                         debug_ram_read_enable,
    input  wire [RAM_ADDR_WIDTH-1:0]    debug_ram_read_addr,
    output wire [63:0]                  debug_ram_read_data,
    output wire                         debug_ram_granted,

    // High-level status and ILA probes.
    output wire                         setup_started,
    output wire                         setup_busy,
    output wire                         queues_ready,
    output wire                         setup_done,
    output wire                         setup_error,
    output wire                         discovery_done,
    output wire                         discovery_valid,
    output wire                         controller_info_valid,
    output wire                         namespace_list_valid,
    output wire                         namespace_info_valid,
    output wire                         target_nsid_found,
    output wire [15:0]                  discovered_controller_vid,
    output wire [15:0]                  discovered_controller_ssvid,
    output wire [31:0]                  discovered_controller_version,
    output wire [31:0]                  discovered_controller_nn,
    output wire [7:0]                   discovered_controller_mdts,
    output wire [7:0]                   discovered_controller_sqes,
    output wire [7:0]                   discovered_controller_cqes,
    output wire [31:0]                  discovered_first_nsid,
    output wire [31:0]                  discovered_active_nsid_count,
    output wire [63:0]                  discovered_nsze,
    output wire [63:0]                  discovered_ncap,
    output wire [63:0]                  discovered_nuse,
    output wire [7:0]                   discovered_nlbaf,
    output wire [7:0]                   discovered_flbas,
    output wire [5:0]                   discovered_lba_format_index,
    output wire [7:0]                   discovered_lbads,
    output wire [15:0]                  discovered_metadata_bytes,
    output wire [31:0]                  discovered_lba_bytes,

    // Read-only post-setup diagnostics; see setup_fsm for probe field layouts.
    output wire                         health_snapshot_busy,
    output wire                         health_snapshot_done,
    output wire [31:0]                 health_snapshot_count,
    output wire [4:0]                  health_valid,
    output wire [79:0]                 health_command_status,
    output wire [7:0]                  health_error_code,
    output wire [63:0]                 health_firmware_revision,
    output wire [7:0]                  health_npss,
    output wire [7:0]                  health_apsta,
    output wire [79:0]                 health_thermal_caps,
    output wire [31:0]                 health_power_management,
    output wire [31:0]                 health_apst,
    output wire [31:0]                 health_hctm,
    output wire [63:0]                 health_ps0_summary,
    output wire [63:0]                 health_current_ps_summary,
    output wire                         health_current_ps_valid,
    output wire [63:0]                 health_smart_status,
    output wire [127:0]                health_media_errors,
    output wire [127:0]                health_error_log_entries,
    output wire [63:0]                 health_temperature_time,
    output wire [127:0]                health_temperature_sensors,
    output wire [63:0]                 health_thermal_transitions,
    output wire [63:0]                 health_thermal_time,
    output wire [7:0]                   setup_state,
    output wire [7:0]                   setup_error_code,
    output wire [7:0]                   last_opcode,
    output wire [15:0]                  last_cid,
    output wire [15:0]                  last_completion_cid,
    output wire [15:0]                  last_completion_status,
    output wire [127:0]                 last_cqe,
    output wire [31:0]                  last_mmio_offset,
    output wire [63:0]                  last_mmio_rdata,
    output wire [31:0]                  submitted_command_count,
    output wire [15:0]                  admin_sq_tail,
    output wire [15:0]                  admin_cq_head,
    output wire                         admin_cq_phase,
    output wire [31:0]                  ready_poll_count,
    output wire [31:0]                  cq_poll_count,
    output wire [31:0]                  allocated_io_queues,
    output wire [3:0]                   dma_bridge_state,
    output wire [DMA_ADDR_WIDTH-1:0]    dma_last_axi_addr,
    output wire [1:0]                   dma_last_axi_resp,
    output wire                         dma_protocol_error,

    // Outbound 64-bit AXI4 master -> SmartConnect -> PG344 S_AXIB.
    output wire [MMIO_ID_WIDTH-1:0]     m_axi_mmio_awid,
    output wire [MMIO_ADDR_WIDTH-1:0]   m_axi_mmio_awaddr,
    output wire [7:0]                   m_axi_mmio_awlen,
    output wire [2:0]                   m_axi_mmio_awsize,
    output wire [1:0]                   m_axi_mmio_awburst,
    output wire                         m_axi_mmio_awlock,
    output wire [3:0]                   m_axi_mmio_awcache,
    output wire [2:0]                   m_axi_mmio_awprot,
    output wire [3:0]                   m_axi_mmio_awqos,
    output wire [3:0]                   m_axi_mmio_awregion,
    output wire                         m_axi_mmio_awvalid,
    input  wire                         m_axi_mmio_awready,
    output wire [63:0]                  m_axi_mmio_wdata,
    output wire [7:0]                   m_axi_mmio_wstrb,
    output wire                         m_axi_mmio_wlast,
    output wire                         m_axi_mmio_wvalid,
    input  wire                         m_axi_mmio_wready,
    input  wire [MMIO_ID_WIDTH-1:0]     m_axi_mmio_bid,
    input  wire [1:0]                   m_axi_mmio_bresp,
    input  wire                         m_axi_mmio_bvalid,
    output wire                         m_axi_mmio_bready,
    output wire [MMIO_ID_WIDTH-1:0]     m_axi_mmio_arid,
    output wire [MMIO_ADDR_WIDTH-1:0]   m_axi_mmio_araddr,
    output wire [7:0]                   m_axi_mmio_arlen,
    output wire [2:0]                   m_axi_mmio_arsize,
    output wire [1:0]                   m_axi_mmio_arburst,
    output wire                         m_axi_mmio_arlock,
    output wire [3:0]                   m_axi_mmio_arcache,
    output wire [2:0]                   m_axi_mmio_arprot,
    output wire [3:0]                   m_axi_mmio_arqos,
    output wire [3:0]                   m_axi_mmio_arregion,
    output wire                         m_axi_mmio_arvalid,
    input  wire                         m_axi_mmio_arready,
    input  wire [MMIO_ID_WIDTH-1:0]     m_axi_mmio_rid,
    input  wire [63:0]                  m_axi_mmio_rdata,
    input  wire [1:0]                   m_axi_mmio_rresp,
    input  wire                         m_axi_mmio_rlast,
    input  wire                         m_axi_mmio_rvalid,
    output wire                         m_axi_mmio_rready,

    // Inbound AXI4 slave <- SmartConnect <- PG344 M_AXIB.
    input  wire [DMA_ID_WIDTH-1:0]      s_axi_dma_awid,
    input  wire [DMA_ADDR_WIDTH-1:0]    s_axi_dma_awaddr,
    input  wire [7:0]                   s_axi_dma_awlen,
    input  wire [2:0]                   s_axi_dma_awsize,
    input  wire [1:0]                   s_axi_dma_awburst,
    input  wire                         s_axi_dma_awlock,
    input  wire [3:0]                   s_axi_dma_awcache,
    input  wire [2:0]                   s_axi_dma_awprot,
    input  wire [3:0]                   s_axi_dma_awqos,
    input  wire [3:0]                   s_axi_dma_awregion,
    input  wire                         s_axi_dma_awvalid,
    output wire                         s_axi_dma_awready,
    input  wire [63:0]                  s_axi_dma_wdata,
    input  wire [7:0]                   s_axi_dma_wstrb,
    input  wire                         s_axi_dma_wlast,
    input  wire                         s_axi_dma_wvalid,
    output wire                         s_axi_dma_wready,
    output wire [DMA_ID_WIDTH-1:0]      s_axi_dma_bid,
    output wire [1:0]                   s_axi_dma_bresp,
    output wire                         s_axi_dma_bvalid,
    input  wire                         s_axi_dma_bready,
    input  wire [DMA_ID_WIDTH-1:0]      s_axi_dma_arid,
    input  wire [DMA_ADDR_WIDTH-1:0]    s_axi_dma_araddr,
    input  wire [7:0]                   s_axi_dma_arlen,
    input  wire [2:0]                   s_axi_dma_arsize,
    input  wire [1:0]                   s_axi_dma_arburst,
    input  wire                         s_axi_dma_arlock,
    input  wire [3:0]                   s_axi_dma_arcache,
    input  wire [2:0]                   s_axi_dma_arprot,
    input  wire [3:0]                   s_axi_dma_arqos,
    input  wire [3:0]                   s_axi_dma_arregion,
    input  wire                         s_axi_dma_arvalid,
    output wire                         s_axi_dma_arready,
    output wire [DMA_ID_WIDTH-1:0]      s_axi_dma_rid,
    output wire [63:0]                  s_axi_dma_rdata,
    output wire [1:0]                   s_axi_dma_rresp,
    output wire                         s_axi_dma_rlast,
    output wire                         s_axi_dma_rvalid,
    input  wire                         s_axi_dma_rready
);

    wire internal_aresetn = aresetn;

    // FSM <-> existing single-transaction AXI master adapter.
    wire mmio_cmd_valid_i;
    wire mmio_cmd_ready_i;
    wire mmio_cmd_write_i;
    wire [MMIO_ADDR_WIDTH-1:0] mmio_cmd_addr_i;
    wire [63:0] mmio_cmd_wdata_i;
    wire [7:0]  mmio_cmd_wstrb_i;
    wire [2:0]  mmio_cmd_size_i;
    wire mmio_rsp_valid_i;
    wire mmio_rsp_ready_i;
    wire [63:0] mmio_rsp_rdata_i;
    wire [1:0] mmio_rsp_resp_i;
    wire mmio_rsp_timeout_i;

    // TDP RAM port A is owned by the inbound AXI/DMA bridge.
    wire                       ram_a_en;
    wire [7:0]                 ram_a_we;
    wire [RAM_ADDR_WIDTH-1:0]  ram_a_addr;
    wire [63:0]                ram_a_wdata;
    wire [63:0]                ram_a_rdata;

    // TDP RAM port B is normally owned by the FSM.  A nonintrusive debug read
    // may use it in any cycle in which the FSM does not request the port.
    wire                       fsm_ram_en;
    wire [7:0]                 fsm_ram_we;
    wire [RAM_ADDR_WIDTH-1:0]  fsm_ram_addr;
    wire [63:0]                fsm_ram_wdata;
    wire [63:0]                ram_b_rdata;

    wire ram_b_en;
    wire [7:0] ram_b_we;
    wire [RAM_ADDR_WIDTH-1:0] ram_b_addr;
    wire [63:0] ram_b_wdata = fsm_ram_wdata;

    generate
        if (ENABLE_SETUP_DEBUG) begin : gen_debug_ram
            assign debug_ram_granted = debug_ram_read_enable && !fsm_ram_en;
            assign debug_ram_read_data = ram_b_rdata;
            assign ram_b_en = fsm_ram_en || debug_ram_granted;
            assign ram_b_we = fsm_ram_en ? fsm_ram_we : 8'h00;
            assign ram_b_addr = fsm_ram_en ? fsm_ram_addr : debug_ram_read_addr;
        end else begin : gen_no_debug_ram
            assign debug_ram_granted = 1'b0;
            assign debug_ram_read_data = 64'd0;
            assign ram_b_en = fsm_ram_en;
            assign ram_b_we = fsm_ram_we;
            assign ram_b_addr = fsm_ram_addr;
        end
    endgenerate

    pl_pcie_nvme_setup_fsm #(
        .ENABLE_SETUP_DEBUG(ENABLE_SETUP_DEBUG),
        .MMIO_ADDR_WIDTH(MMIO_ADDR_WIDTH),
        .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
        .NVME_MMIO_AXI_BASE(NVME_MMIO_AXI_BASE),
        .RP_DMA_PCIE_BASE(RP_DMA_PCIE_BASE),
        .RP_DMA_PCIE_SIZE(RP_DMA_PCIE_SIZE),
        .KNOWN_CAP(KNOWN_CAP),
        .KNOWN_VS(KNOWN_VS),
        .QUEUE_DEPTH(QUEUE_DEPTH),
        .IO_QUEUE_DEPTH(IO_QUEUE_DEPTH),
        .DISCOVERY_PCIE_ADDR(DISCOVERY_PCIE_ADDR),
        .ADMIN_SQ_PCIE_ADDR(ADMIN_SQ_PCIE_ADDR),
        .ADMIN_CQ_PCIE_ADDR(ADMIN_CQ_PCIE_ADDR),
        .IO_SQ_PCIE_ADDR(IO_SQ_PCIE_ADDR),
        .IO_CQ_PCIE_ADDR(IO_CQ_PCIE_ADDR),
        .READY_TIMEOUT_POLLS(READY_TIMEOUT_POLLS),
        .CQ_TIMEOUT_POLLS(CQ_TIMEOUT_POLLS),
        .NVME_NSID(NVME_NSID)
    ) setup_fsm_i (
        .clk(aclk),
        .resetn(aresetn),
        .enum_done(enum_done),
        .health_snapshot_request(health_snapshot_request),
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
        .ram_en(fsm_ram_en),
        .ram_we(fsm_ram_we),
        .ram_addr(fsm_ram_addr),
        .ram_wdata(fsm_ram_wdata),
        .ram_rdata(ram_b_rdata),
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
        .state_dbg(setup_state),
        .error_code(setup_error_code),
        .last_opcode(last_opcode),
        .last_cid(last_cid),
        .last_completion_cid(last_completion_cid),
        .last_completion_status(last_completion_status),
        .last_cqe(last_cqe),
        .last_mmio_offset(last_mmio_offset),
        .last_mmio_rdata(last_mmio_rdata),
        .submitted_command_count(submitted_command_count),
        .admin_sq_tail_dbg(admin_sq_tail),
        .admin_cq_head_dbg(admin_cq_head),
        .admin_cq_phase_dbg(admin_cq_phase),
        .ready_poll_count_dbg(ready_poll_count),
        .cq_poll_count_dbg(cq_poll_count),
        .allocated_io_queues(allocated_io_queues)
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

    pl_pcie_nvme_axi4_ram_slave #(
        .ADDR_WIDTH(DMA_ADDR_WIDTH),
        .DATA_WIDTH(64),
        .ID_WIDTH(DMA_ID_WIDTH),
        .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH)
    ) dma_ram_bridge_i (
        .aclk(aclk),
        .aresetn(internal_aresetn),
        .s_axi_awid(s_axi_dma_awid),
        .s_axi_awaddr(s_axi_dma_awaddr),
        .s_axi_awlen(s_axi_dma_awlen),
        .s_axi_awsize(s_axi_dma_awsize),
        .s_axi_awburst(s_axi_dma_awburst),
        .s_axi_awlock(s_axi_dma_awlock),
        .s_axi_awcache(s_axi_dma_awcache),
        .s_axi_awprot(s_axi_dma_awprot),
        .s_axi_awqos(s_axi_dma_awqos),
        .s_axi_awregion(s_axi_dma_awregion),
        .s_axi_awvalid(s_axi_dma_awvalid),
        .s_axi_awready(s_axi_dma_awready),
        .s_axi_wdata(s_axi_dma_wdata),
        .s_axi_wstrb(s_axi_dma_wstrb),
        .s_axi_wlast(s_axi_dma_wlast),
        .s_axi_wvalid(s_axi_dma_wvalid),
        .s_axi_wready(s_axi_dma_wready),
        .s_axi_bid(s_axi_dma_bid),
        .s_axi_bresp(s_axi_dma_bresp),
        .s_axi_bvalid(s_axi_dma_bvalid),
        .s_axi_bready(s_axi_dma_bready),
        .s_axi_arid(s_axi_dma_arid),
        .s_axi_araddr(s_axi_dma_araddr),
        .s_axi_arlen(s_axi_dma_arlen),
        .s_axi_arsize(s_axi_dma_arsize),
        .s_axi_arburst(s_axi_dma_arburst),
        .s_axi_arlock(s_axi_dma_arlock),
        .s_axi_arcache(s_axi_dma_arcache),
        .s_axi_arprot(s_axi_dma_arprot),
        .s_axi_arqos(s_axi_dma_arqos),
        .s_axi_arregion(s_axi_dma_arregion),
        .s_axi_arvalid(s_axi_dma_arvalid),
        .s_axi_arready(s_axi_dma_arready),
        .s_axi_rid(s_axi_dma_rid),
        .s_axi_rdata(s_axi_dma_rdata),
        .s_axi_rresp(s_axi_dma_rresp),
        .s_axi_rlast(s_axi_dma_rlast),
        .s_axi_rvalid(s_axi_dma_rvalid),
        .s_axi_rready(s_axi_dma_rready),
        .ram_en(ram_a_en),
        .ram_we(ram_a_we),
        .ram_addr(ram_a_addr),
        .ram_wdata(ram_a_wdata),
        .ram_rdata(ram_a_rdata),
        .state_dbg(dma_bridge_state),
        .last_axi_addr(dma_last_axi_addr),
        .last_axi_resp(dma_last_axi_resp),
        .protocol_error(dma_protocol_error)
    );

    pl_pcie_nvme_queue_tdp_ram #(
        .ADDR_BITS(RAM_ADDR_WIDTH),
        .DATA_BITS(64)
    ) queue_data_ram_i (
        .clk(aclk),
        .a_en(ram_a_en),
        .a_we(ram_a_we),
        .a_addr(ram_a_addr),
        .a_data_in(ram_a_wdata),
        .a_data_out(ram_a_rdata),
        .b_en(ram_b_en),
        .b_we(ram_b_we),
        .b_addr(ram_b_addr),
        .b_data_in(ram_b_wdata),
        .b_data_out(ram_b_rdata)
    );

endmodule
