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
// nvme_setup_fsm
// -----------------------------------------------------------------------------
// Processor-free NVMe controller/queue initialization sequencer.
//
// This FSM is deliberately separate from pl_pcie_nvme_enum_fsm.  It starts when
// pl_pcie_nvme_enum_top asserts enum_done and assumes enumeration has already:
//
//   * assigned the endpoint BAR and enabled Memory Space + Bus Master,
//   * programmed the PG344 outbound BDF table, and
//   * assigned the Root Port's inbound DMA BAR.
//
// The fixed assumptions come from the measured controller registers:
// Some of them are not relevant to this module
//
//   CAP = 64'h1800_C030_1E02_3FFF
//     MQES   = 16'h3fff  (up to 16384 entries)
//     CQR    = 0         (queues need not be physically contiguous)
//     TO     = 8'h1e
//     DSTRD  = 0         (4-byte doorbell stride)
//     CSS.NVM= 1         (NVM command set supported)
//     MPSMIN = MPSMAX = 0 (4-KiB memory pages)
//
//   VS = 32'h0002_0000   (NVMe 2.0)
//
// Queue depth is a parameter with a default of 64.  At that depth an SQ uses
// exactly one 4-KiB page (64 entries * 64 bytes), while a CQ consumes 1 KiB
// (64 entries * 16 bytes) and is given its own 4-KiB page.
//
// Non-destructive discovery is mandatory.  Identify Controller, Active
// Namespace List, and Identify Namespace reuse one DMA page.  The final
// artifact deliberately contains no NVM read/write test datapath.
// -----------------------------------------------------------------------------
module pl_pcie_nvme_setup_fsm #(
    parameter integer MMIO_ADDR_WIDTH = 64,
    parameter integer RAM_ADDR_WIDTH  = 11,

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

    // The three Identify payloads are sequential and share one 4-KiB page.
    // Admin SQ and CQ have separate pages for an unambiguous 16-KiB layout.
    parameter logic [31:0] DISCOVERY_RAM_OFFSET  = 32'h0000_0000,
    parameter logic [31:0] ADMIN_SQ_RAM_OFFSET   = 32'h0000_2000,
    parameter logic [31:0] ADMIN_CQ_RAM_OFFSET   = 32'h0000_3000,
    parameter logic [63:0] DISCOVERY_PCIE_ADDR   =
        RP_DMA_PCIE_BASE + RP_DMA_PCIE_SIZE - 64'h4000,
    parameter logic [63:0] ADMIN_SQ_PCIE_ADDR    =
        RP_DMA_PCIE_BASE + RP_DMA_PCIE_SIZE - 64'h2000,
    parameter logic [63:0] ADMIN_CQ_PCIE_ADDR    =
        RP_DMA_PCIE_BASE + RP_DMA_PCIE_SIZE - 64'h1000,

    // I/O queues are owned by the surrounding system and are deliberately
    // not backed by this module's RAM. The SQ window is fixed for every
    // depth: 16 KiB (256 entries) per device.
    parameter logic [63:0] IO_SQ_PCIE_ADDR       =
        64'h0000_1FFF_F404_0000,
    parameter logic [63:0] IO_CQ_PCIE_ADDR       =
        64'h0000_1FFF_F402_0000,

    parameter integer READY_TIMEOUT_POLLS = 1_000_000,
    parameter integer CQ_TIMEOUT_POLLS    = 1_000_000,
    parameter logic [31:0] NVME_NSID      = 32'd1,
    // Elaboration-time switch for health snapshots and debug-only captures.
    // Mandatory discovery, queue setup, timeouts and error_code remain active.
    parameter bit ENABLE_SETUP_DEBUG = 1'b0
) (
    input  wire                         clk,
    input  wire                         resetn,

    // Connect directly to pl_pcie_nvme_enum_top.enum_done.
    input  wire                         enum_done,
    // Same-clock rising edge requests another read-only snapshot after setup.
    // Requests while a snapshot is active are ignored.
    input  wire                         health_snapshot_request,

    // Abstract single-transaction endpoint-MMIO interface.  The standalone
    // wrapper connects this to pl_pcie_nvme_axi4_single_master_64.
    output wire                         mmio_cmd_valid,
    input  wire                         mmio_cmd_ready,
    output wire                         mmio_cmd_write,
    output wire [MMIO_ADDR_WIDTH-1:0]   mmio_cmd_addr,
    output wire [63:0]                  mmio_cmd_wdata,
    output wire [7:0]                   mmio_cmd_wstrb,
    output wire [2:0]                   mmio_cmd_size,

    input  wire                         mmio_rsp_valid,
    output wire                         mmio_rsp_ready,
    input  wire [63:0]                  mmio_rsp_rdata,
    input  wire [1:0]                   mmio_rsp_resp,
    input  wire                         mmio_rsp_timeout,

    // Native 64-bit RAM port.  ram_rdata is valid one clock after ram_en.
    output logic                        ram_en,
    output logic [7:0]                  ram_we,
    output logic [RAM_ADDR_WIDTH-1:0]   ram_addr,
    output logic [63:0]                 ram_wdata,
    input  wire [63:0]                  ram_rdata,

    // High-level status.
    output wire                         setup_started,
    output wire                         setup_busy,
    output wire                         queues_ready,
    output wire                         setup_done,
    output wire                         setup_error,

    // Mandatory, non-destructive discovery results.  These are populated by
    // parsing the Identify Controller, Active Namespace List, and Identify
    // Namespace DMA buffers before any I/O queue is created.
    output logic                        discovery_done,
    output logic                        discovery_valid,
    output logic                        controller_info_valid,
    output logic                        namespace_list_valid,
    output logic                        namespace_info_valid,
    output logic                        target_nsid_found,
    output logic [15:0]                 discovered_controller_vid,
    output logic [15:0]                 discovered_controller_ssvid,
    output logic [31:0]                 discovered_controller_version,
    output logic [31:0]                 discovered_controller_nn,
    output logic [7:0]                  discovered_controller_mdts,
    output logic [7:0]                  discovered_controller_sqes,
    output logic [7:0]                  discovered_controller_cqes,
    output logic [31:0]                 discovered_first_nsid,
    output logic [31:0]                 discovered_active_nsid_count,
    output logic [63:0]                 discovered_nsze,
    output logic [63:0]                 discovered_ncap,
    output logic [63:0]                 discovered_nuse,
    output logic [7:0]                  discovered_nlbaf,
    output logic [7:0]                  discovered_flbas,
    output logic [5:0]                  discovered_lba_format_index,
    output logic [7:0]                  discovered_lbads,
    output logic [15:0]                 discovered_metadata_bytes,
    output logic [31:0]                 discovered_lba_bytes,

    // Optional diagnostics are zero when ENABLE_SETUP_DEBUG=0. When enabled,
    // they run only AFTER queues_ready/setup_done. Neither
    // unsupported commands nor diagnostic transport faults invalidate setup.
    output logic                        health_snapshot_busy,
    output logic                        health_snapshot_done,
    output logic [31:0]                 health_snapshot_count,
    // Bit/16-bit lane order: Identify Controller, FID 02, FID 0C, FID 10, SMART.
    // Status is CQE status >> 1 (phase removed); ffff means no completion.
    output logic [4:0]                  health_valid,
    output logic [79:0]                 health_command_status,
    output logic [7:0]                  health_error_code,
    output logic [63:0]                 health_firmware_revision,
    output logic [7:0]                  health_npss,
    output logic [7:0]                  health_apsta,
    // Low to high 16-bit lanes: WCTEMP, CCTEMP, HCTMA, MNTMT, MXTMT.
    output logic [79:0]                 health_thermal_caps,
    // Raw Get Features completion DW0. Power state is [4:0], APSTE is [0],
    // HCTM has TMT1 in [31:16] and TMT2 in [15:0]. Temperatures are Kelvin.
    output logic [31:0]                 health_power_management,
    output logic [31:0]                 health_apst,
    output logic [31:0]                 health_hctm,
    // PSD summary: [31:0] = descriptor bytes 0..3 (MP/reserved/flags),
    // [63:32] = bytes 12..15 (RRT/RRL/RWT/RWL). Preserve MP scale in flags.
    output logic [63:0]                 health_ps0_summary,
    output logic [63:0]                 health_current_ps_summary,
    output logic                        health_current_ps_valid,
    // SMART bytes 0..7: critical warning, composite temperature, spare,
    // spare threshold, percentage used, endurance warning, reserved.
    output logic [63:0]                 health_smart_status,
    output logic [127:0]                health_media_errors,
    output logic [127:0]                health_error_log_entries,
    // SMART bytes 192..199: warning/critical temperature time (minutes).
    output logic [63:0]                 health_temperature_time,
    output logic [127:0]                health_temperature_sensors,
    // Low/high DW: TMT1/TMT2 transitions and total time (seconds).
    output logic [63:0]                 health_thermal_transitions,
    output logic [63:0]                 health_thermal_time,

    // Stable, compact ILA probes; zero when disabled, except functional error_code.
    output wire [7:0]                   state_dbg,
    output logic [7:0]                  error_code,
    output logic [7:0]                  last_opcode,
    output logic [15:0]                 last_cid,
    output logic [15:0]                 last_completion_cid,
    output logic [15:0]                 last_completion_status,
    output logic [127:0]                last_cqe,
    output logic [31:0]                 last_mmio_offset,
    output logic [63:0]                 last_mmio_rdata,
    output logic [31:0]                 submitted_command_count,
    output logic [15:0]                 admin_sq_tail_dbg,
    output logic [15:0]                 admin_cq_head_dbg,
    output logic                        admin_cq_phase_dbg,
    output logic [31:0]                 ready_poll_count_dbg,
    output logic [31:0]                 cq_poll_count_dbg,
    output logic [31:0]                 allocated_io_queues
);

    localparam logic [1:0] AXI_OKAY = 2'b00;

    // NVMe controller register offsets.
    localparam logic [31:0] NVME_CC      = 32'h0000_0014;
    localparam logic [31:0] NVME_CSTS    = 32'h0000_001c;
    localparam logic [31:0] NVME_AQA     = 32'h0000_0024;
    localparam logic [31:0] NVME_ASQ     = 32'h0000_0028;
    localparam logic [31:0] NVME_ACQ     = 32'h0000_0030;
    localparam logic [31:0] NVME_DB_BASE = 32'h0000_1000;

    // DSTRD == 0: each successive doorbell is four bytes apart.
    localparam logic [31:0] ADMIN_SQ_TAIL_DB = NVME_DB_BASE + 32'h0;
    localparam logic [31:0] ADMIN_CQ_HEAD_DB = NVME_DB_BASE + 32'h4;

    localparam logic [31:0] AQA_VALUE =
        ((QUEUE_DEPTH - 1) << 16) | (QUEUE_DEPTH - 1);

    // IOSQES=6 (64-byte SQE), IOCQES=4 (16-byte CQE), MPS=0, CSS=0,
    // AMS=0, and EN=1.
    localparam logic [31:0] CC_ENABLE_VALUE = 32'h0046_0001;

    localparam integer RAM_BYTES  = (1 << RAM_ADDR_WIDTH) * 8;
    localparam integer READY_LIMIT =
        (READY_TIMEOUT_POLLS < 1) ? 1 : READY_TIMEOUT_POLLS;
    localparam integer CQ_LIMIT =
        (CQ_TIMEOUT_POLLS < 1) ? 1 : CQ_TIMEOUT_POLLS;

    // Error codes are stable so an ILA capture can be decoded without an HDL
    // waveform database.
    localparam logic [7:0] ERR_NONE              = 8'h00;
    localparam logic [7:0] ERR_ENUM_LOST         = 8'h01;
    localparam logic [7:0] ERR_MMIO_AXI          = 8'h10;
    localparam logic [7:0] ERR_MMIO_TIMEOUT      = 8'h11;
    localparam logic [7:0] ERR_CSTS_CFS          = 8'h20;
    localparam logic [7:0] ERR_RDY0_TIMEOUT      = 8'h21;
    localparam logic [7:0] ERR_RDY1_TIMEOUT      = 8'h22;
    localparam logic [7:0] ERR_CQ_TIMEOUT        = 8'h30;
    localparam logic [7:0] ERR_CQ_CID            = 8'h31;
    localparam logic [7:0] ERR_CQ_SQID           = 8'h32;
    localparam logic [7:0] ERR_CQ_STATUS         = 8'h33;
    localparam logic [7:0] ERR_DISC_CTRL_INVALID = 8'h50;
    localparam logic [7:0] ERR_DISC_NSID_MISSING = 8'h51;
    localparam logic [7:0] ERR_DISC_NS_INVALID   = 8'h52;
    localparam logic [7:0] ERR_DISC_LBA_INVALID  = 8'h53;

    typedef enum logic [3:0] {
        CMD_NONE             = 4'h0,
        CMD_IDENTIFY_CTRL    = 4'h1,
        CMD_IDENTIFY_LIST    = 4'h2,
        CMD_IDENTIFY_NS      = 4'h3,
        CMD_SET_NUM_QUEUES   = 4'h4,
        CMD_CREATE_IO_CQ     = 4'h5,
        CMD_CREATE_IO_SQ     = 4'h6,
        CMD_HEALTH_CTRL      = 4'h7,
        CMD_HEALTH_POWER     = 4'h8,
        CMD_HEALTH_APST      = 4'h9,
        CMD_HEALTH_HCTM      = 4'ha,
        CMD_HEALTH_SMART     = 4'hb
    } command_t;

    // Explicit encodings reserve groups for controller setup and Admin queue
    // execution, making ILA traces easy to scan.
    typedef enum logic [7:0] {
        ST_IDLE                  = 8'h00,
        ST_CLEAR_RAM             = 8'h01,

        ST_DISABLE_CC            = 8'h10,
        ST_RDY0_READ             = 8'h11,
        ST_RDY0_CHECK            = 8'h12,
        ST_WRITE_AQA             = 8'h13,
        ST_WRITE_ASQ             = 8'h14,
        ST_WRITE_ACQ             = 8'h15,
        ST_ENABLE_CC             = 8'h16,
        ST_RDY1_READ             = 8'h17,
        ST_RDY1_CHECK            = 8'h18,

        ST_PREP_IDENTIFY_CTRL    = 8'h20,
        ST_PREP_IDENTIFY_LIST    = 8'h21,
        ST_PREP_IDENTIFY_NS      = 8'h22,
        ST_PREP_SET_NUM_QUEUES   = 8'h23,
        ST_PREP_CREATE_IO_CQ     = 8'h24,
        ST_PREP_CREATE_IO_SQ     = 8'h25,

        ST_SQE_WRITE             = 8'h40,
        ST_SQ_DOORBELL           = 8'h41,
        ST_CQ_POLL_START         = 8'h42,
        ST_CQ_READ0_REQ          = 8'h43,
        ST_CQ_READ0_WAIT         = 8'h44,
        ST_CQ_READ1_REQ          = 8'h45,
        ST_CQ_READ1_WAIT         = 8'h46,
        ST_CQ_CHECK              = 8'h47,
        ST_CQ_ACK                = 8'h48,
        ST_COMMAND_COMPLETE      = 8'h49,
        ST_CQ_RESULT_REQ         = 8'h4a,
        ST_CQ_RESULT_WAIT        = 8'h4b,

        // Mandatory discovery parsing.  Keeping these states in a separate
        // range makes the non-destructive phase obvious in an ILA trace.
        ST_DISC_CTRL_W0_REQ       = 8'h80,
        ST_DISC_CTRL_W0_WAIT      = 8'h81,
        ST_DISC_CTRL_W9_REQ       = 8'h82,
        ST_DISC_CTRL_W9_WAIT      = 8'h83,
        ST_DISC_CTRL_W10_REQ      = 8'h84,
        ST_DISC_CTRL_W10_WAIT     = 8'h85,
        ST_DISC_CTRL_W64_REQ      = 8'h86,
        ST_DISC_CTRL_W64_WAIT     = 8'h87,
        ST_DISC_CTRL_CHECK        = 8'h88,
        ST_DISC_LIST_REQ          = 8'h89,
        ST_DISC_LIST_WAIT         = 8'h8a,
        ST_DISC_LIST_CHECK        = 8'h8b,
        ST_DISC_NS_W0_REQ         = 8'h90,
        ST_DISC_NS_W0_WAIT        = 8'h91,
        ST_DISC_NS_W1_REQ         = 8'h92,
        ST_DISC_NS_W1_WAIT        = 8'h93,
        ST_DISC_NS_W2_REQ         = 8'h94,
        ST_DISC_NS_W2_WAIT        = 8'h95,
        ST_DISC_NS_W3_REQ         = 8'h96,
        ST_DISC_NS_W3_WAIT        = 8'h97,
        ST_DISC_LBAF_REQ          = 8'h98,
        ST_DISC_LBAF_WAIT         = 8'h99,
        ST_DISC_NS_CHECK          = 8'h9a,

        ST_HEALTH_START           = 8'ha0,
        ST_HEALTH_CTRL_REQ        = 8'ha1,
        ST_HEALTH_CTRL_WAIT       = 8'ha2,
        ST_HEALTH_PS_REQ          = 8'ha3,
        ST_HEALTH_PS_WAIT         = 8'ha4,
        ST_HEALTH_SMART_REQ       = 8'ha5,
        ST_HEALTH_SMART_WAIT      = 8'ha6,
        ST_HEALTH_FINISH          = 8'ha7,

        ST_MMIO_REQ               = 8'hf0,
        ST_MMIO_RSP               = 8'hf1,
        ST_DONE                   = 8'hfe,
        ST_ERROR                  = 8'hff
    } state_t;

    state_t state;
    state_t mmio_return_state;

    command_t pending_command;
    logic [15:0] pending_cid;
    logic [15:0] next_cid;
    logic [2:0]  sqe_word_index;

    logic [15:0] admin_sq_tail;
    logic [15:0] admin_cq_head;
    logic        admin_cq_phase;

    logic [15:0] doorbell_value;
    logic [63:0] cqe_word0;
    logic [63:0] cqe_word1;

    logic [RAM_ADDR_WIDTH-1:0] clear_word_index;
    logic [31:0] ready_poll_count;
    logic [31:0] cq_poll_count;
    logic        started_latch;
    logic        queues_ready_latch;
    logic        health_request_d;
    logic [3:0]  health_word_index;
    wire health_command = ENABLE_SETUP_DEBUG &&
                          (pending_command >= CMD_HEALTH_CTRL) &&
                          (pending_command <= CMD_HEALTH_SMART);
    wire [3:0] health_command_index = ENABLE_SETUP_DEBUG ?
                                     pending_command - CMD_HEALTH_CTRL : 4'd0;

    logic [8:0]  namespace_list_word_index;
    logic [63:0] namespace_list_read_data;
    logic [31:0] selected_lba_format;

    logic                        mmio_write_reg;
    logic [MMIO_ADDR_WIDTH-1:0]  mmio_addr_reg;
    logic [63:0]                 mmio_wdata_reg;
    logic [7:0]                  mmio_wstrb_reg;
    logic [2:0]                  mmio_size_reg;
    logic [31:0]                 mmio_read32_data;

    wire expected_cq_phase = admin_cq_phase;
    wire [15:0] expected_sqid = 16'd0;

    wire [31:0] namespace_list_nsid0 = namespace_list_read_data[31:0];
    wire [31:0] namespace_list_nsid1 = namespace_list_read_data[63:32];
    wire [1:0] namespace_list_valid_entries =
        {1'b0, (namespace_list_nsid0 != 32'd0)} +
        {1'b0, (namespace_list_nsid1 != 32'd0)};
    wire namespace_list_current_match =
        (namespace_list_nsid0 == NVME_NSID) ||
        (namespace_list_nsid1 == NVME_NSID);

    wire controller_queue_formats_valid =
        (discovered_controller_sqes[3:0] <= 4'd6) &&
        (discovered_controller_sqes[7:4] >= 4'd6) &&
        (discovered_controller_cqes[3:0] <= 4'd4) &&
        (discovered_controller_cqes[7:4] >= 4'd4);

    wire selected_lba_format_index_valid =
        ({2'd0, discovered_lba_format_index} <= discovered_nlbaf);
    wire selected_lbads_valid =
        (selected_lba_format[23:16] >= 8'd9) &&
        (selected_lba_format[23:16] < 8'd32);
    wire [31:0] selected_lba_bytes_value = selected_lbads_valid ?
        (32'd1 << selected_lba_format[23:16]) : 32'd0;
    wire namespace_capacity_valid =
        (discovered_nsze != 64'd0) &&
        (discovered_ncap != 64'd0) &&
        (discovered_ncap <= discovered_nsze) &&
        (discovered_nuse <= discovered_ncap);
    assign mmio_cmd_valid = (state == ST_MMIO_REQ);
    assign mmio_cmd_write = mmio_write_reg;
    assign mmio_cmd_addr  = mmio_addr_reg;
    assign mmio_cmd_wdata = mmio_wdata_reg;
    assign mmio_cmd_wstrb = mmio_wstrb_reg;
    assign mmio_cmd_size  = mmio_size_reg;
    assign mmio_rsp_ready = (state == ST_MMIO_RSP);

    assign setup_started       = started_latch;
    assign setup_busy          = (state != ST_IDLE) &&
                                 (state != ST_DONE) &&
                                 (state != ST_ERROR) && !queues_ready_latch;
    assign queues_ready        = queues_ready_latch;
    assign setup_done          = queues_ready_latch;
    assign setup_error         = (state == ST_ERROR);
    assign state_dbg           = ENABLE_SETUP_DEBUG ? state : 8'd0;

    always_comb begin
        admin_sq_tail_dbg   = ENABLE_SETUP_DEBUG ? admin_sq_tail : 16'd0;
        admin_cq_head_dbg   = ENABLE_SETUP_DEBUG ? admin_cq_head : 16'd0;
        admin_cq_phase_dbg  = ENABLE_SETUP_DEBUG ? admin_cq_phase : 1'b0;
        ready_poll_count_dbg= ENABLE_SETUP_DEBUG ? ready_poll_count : 32'd0;
        cq_poll_count_dbg   = ENABLE_SETUP_DEBUG ? cq_poll_count : 32'd0;
    end

    function automatic logic [7:0] command_opcode(input command_t command);
        begin
            case (command)
                CMD_IDENTIFY_CTRL,
                CMD_IDENTIFY_LIST,
                CMD_IDENTIFY_NS:    command_opcode = 8'h06;
                CMD_HEALTH_CTRL:    command_opcode = ENABLE_SETUP_DEBUG ? 8'h06 : 8'h00;
                CMD_HEALTH_POWER,
                CMD_HEALTH_APST,
                CMD_HEALTH_HCTM:     command_opcode = ENABLE_SETUP_DEBUG ? 8'h0a : 8'h00;
                CMD_HEALTH_SMART:    command_opcode = ENABLE_SETUP_DEBUG ? 8'h02 : 8'h00;
                CMD_SET_NUM_QUEUES: command_opcode = 8'h09;
                CMD_CREATE_IO_CQ:   command_opcode = 8'h05;
                CMD_CREATE_IO_SQ:   command_opcode = 8'h01;
                default:            command_opcode = 8'h00;
            endcase
        end
    endfunction

    function automatic logic [63:0] command_prp1(input command_t command);
        begin
            case (command)
                CMD_IDENTIFY_CTRL,
                CMD_IDENTIFY_LIST,
                CMD_IDENTIFY_NS:
                    command_prp1 = DISCOVERY_PCIE_ADDR;
                CMD_HEALTH_CTRL,
                CMD_HEALTH_APST,
                CMD_HEALTH_SMART:
                    command_prp1 = ENABLE_SETUP_DEBUG ? DISCOVERY_PCIE_ADDR : 64'd0;
                CMD_CREATE_IO_CQ:
                    command_prp1 = IO_CQ_PCIE_ADDR;
                CMD_CREATE_IO_SQ:
                    command_prp1 = IO_SQ_PCIE_ADDR;
                default:
                    command_prp1 = 64'd0;
            endcase
        end
    endfunction

    // Construct one 64-bit word of a 64-byte NVMe SQ entry.  The explicit
    // DWord packing mirrors the NVMe command diagrams and is convenient for
    // inspecting the queue through ILA/debug RAM reads.
    function automatic logic [63:0] sqe_word(
        input command_t command,
        input logic [15:0] cid,
        input logic [2:0] word_number
    );
        logic [31:0] dw0;
        logic [31:0] dw1;
        logic [31:0] dw10;
        logic [31:0] dw11;
        logic [31:0] dw12;
        logic [63:0] prp1;
        begin
            dw0  = {cid, 8'h00, command_opcode(command)};
            dw1  = (command == CMD_IDENTIFY_NS) ? NVME_NSID : 32'd0;
            if (ENABLE_SETUP_DEBUG && command == CMD_HEALTH_SMART)
                dw1 = 32'hffff_ffff; // Controller-wide SMART, not per-namespace.
            dw10 = 32'd0;
            dw11 = 32'd0;
            dw12 = 32'd0;
            prp1 = command_prp1(command);

            case (command)
                CMD_IDENTIFY_CTRL: begin
                    dw10 = 32'd1; // CNS=01h: Identify Controller
                end
                CMD_HEALTH_CTRL: if (ENABLE_SETUP_DEBUG) dw10 = 32'd1;
                CMD_IDENTIFY_LIST: begin
                    dw10 = 32'd2; // CNS=02h: Active Namespace ID list
                end
                CMD_IDENTIFY_NS: begin
                    dw10 = 32'd0; // CNS=00h: Identify Namespace
                end
                CMD_HEALTH_POWER: if (ENABLE_SETUP_DEBUG) dw10 = 32'h02; // SEL=0.
                CMD_HEALTH_APST:  if (ENABLE_SETUP_DEBUG) dw10 = 32'h0c; // DMA table.
                CMD_HEALTH_HCTM:  if (ENABLE_SETUP_DEBUG) dw10 = 32'h10;
                CMD_HEALTH_SMART: if (ENABLE_SETUP_DEBUG) begin
                    // LID=02h, RAE=1, NUMD=127: retain events, read 512 bytes.
                    dw10 = 32'h007f_8002;
                end
                CMD_SET_NUM_QUEUES: begin
                    dw10 = 32'd7; // FID=07h: Number of Queues
                    dw11 = 32'd0; // Request one SQ and one CQ (zero based)
                end
                CMD_CREATE_IO_CQ: begin
                    dw10 = ((IO_QUEUE_DEPTH - 1) << 16) | 16'd1;
                    dw11 = 32'h0000_0001; // PC=1, IEN=0, IV=0
                end
                CMD_CREATE_IO_SQ: begin
                    dw10 = ((IO_QUEUE_DEPTH - 1) << 16) | 16'd1;
                    dw11 = 32'h0001_0001; // CQID=1, QPRIO=0, PC=1
                end
                default: begin
                    dw10 = 32'd0;
                    dw11 = 32'd0;
                    dw12 = 32'd0;
                end
            endcase

            case (word_number)
                3'd0: sqe_word = {dw1, dw0};
                3'd1: sqe_word = 64'd0;       // DW2..DW3
                3'd2: sqe_word = 64'd0;       // MPTR, DW4..DW5
                3'd3: sqe_word = prp1;        // PRP1, DW6..DW7
                3'd4: sqe_word = 64'd0;       // PRP2, DW8..DW9
                3'd5: sqe_word = {dw11, dw10};
                3'd6: sqe_word = {32'd0, dw12};
                default: sqe_word = 64'd0;    // DW14..DW15
            endcase
        end
    endfunction

    // These tasks only load the generic MMIO engine's registers.  All command
    // and response handshakes still occur in ST_MMIO_REQ/ST_MMIO_RSP.
    task automatic launch_write32(
        input logic [MMIO_ADDR_WIDTH-1:0] address,
        input logic [31:0] data,
        input state_t return_state
    );
        integer lane_shift;
        begin
            lane_shift       = address[2:0] * 8;
            mmio_write_reg   <= 1'b1;
            mmio_addr_reg    <= address;
            mmio_wdata_reg   <= ({32'd0, data} << lane_shift);
            mmio_wstrb_reg   <= (8'h0f << address[2:0]);
            mmio_size_reg    <= 3'd2;
            mmio_return_state<= return_state;
            state            <= ST_MMIO_REQ;
        end
    endtask

    task automatic launch_write64(
        input logic [MMIO_ADDR_WIDTH-1:0] address,
        input logic [63:0] data,
        input state_t return_state
    );
        begin
            mmio_write_reg   <= 1'b1;
            mmio_addr_reg    <= address;
            mmio_wdata_reg   <= data;
            mmio_wstrb_reg   <= 8'hff;
            mmio_size_reg    <= 3'd3;
            mmio_return_state<= return_state;
            state            <= ST_MMIO_REQ;
        end
    endtask

    task automatic launch_read32(
        input logic [MMIO_ADDR_WIDTH-1:0] address,
        input state_t return_state
    );
        begin
            mmio_write_reg   <= 1'b0;
            mmio_addr_reg    <= address;
            mmio_wdata_reg   <= 64'd0;
            mmio_wstrb_reg   <= 8'h00;
            mmio_size_reg    <= 3'd2;
            mmio_return_state<= return_state;
            state            <= ST_MMIO_REQ;
        end
    endtask

    task automatic prepare_command(input command_t command);
        begin
            pending_command <= command;
            pending_cid     <= next_cid;
            if (ENABLE_SETUP_DEBUG) begin
                last_cid    <= next_cid;
                last_opcode <= command_opcode(command);
            end
            next_cid        <= next_cid + 1'b1;
            sqe_word_index  <= 3'd0;
            state           <= ST_SQE_WRITE;
        end
    endtask

    // A failed diagnostic transport cannot safely be reused: a late CQE or
    // DMA may still arrive. Stop diagnostics until reset, but keep I/O ready.
    task automatic fail_transaction(input logic [7:0] reason);
        begin
            if (ENABLE_SETUP_DEBUG && queues_ready_latch) begin
                health_error_code    <= reason;
                health_snapshot_busy <= 1'b0;
                health_snapshot_done <= 1'b1;
                health_snapshot_count<= health_snapshot_count + 1'b1;
                state                <= ST_DONE;
            end else begin
                error_code <= reason;
                state      <= ST_ERROR;
            end
        end
    endtask

    // Local setup-FSM access to TDP-RAM port B.
    always_comb begin
        ram_en    = 1'b0;
        ram_we    = 8'h00;
        ram_addr  = '0;
        ram_wdata = 64'd0;

        case (state)
            ST_CLEAR_RAM: begin
                ram_en    = 1'b1;
                ram_we    = 8'hff;
                ram_addr  = clear_word_index;
                ram_wdata = 64'd0;
            end

            ST_SQE_WRITE: begin
                ram_en   = 1'b1;
                ram_we   = 8'hff;
                // Buffers are 4-KiB (512-word) aligned and the index stays
                // below 512 words (QUEUE_DEPTH <= 64), so OR equals the sum.
                ram_addr = (ADMIN_SQ_RAM_OFFSET >> 3) |
                           (admin_sq_tail * 8) | sqe_word_index;
                ram_wdata = sqe_word(
                    pending_command, pending_cid, sqe_word_index
                );
            end

            ST_CQ_READ0_REQ,
            ST_CQ_RESULT_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (ADMIN_CQ_RAM_OFFSET >> 3) |
                           (admin_cq_head * 2);
            end

            ST_CQ_READ1_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (ADMIN_CQ_RAM_OFFSET >> 3) |
                           (admin_cq_head * 2) | 1;
            end

            ST_DISC_CTRL_W0_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3);
            end

            ST_DISC_CTRL_W9_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) + 9;
            end

            ST_DISC_CTRL_W10_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) + 10;
            end

            ST_DISC_CTRL_W64_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) + 64;
            end

            ST_DISC_LIST_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) |
                           namespace_list_word_index;
            end

            ST_DISC_NS_W0_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3);
            end

            ST_DISC_NS_W1_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) + 1;
            end

            ST_DISC_NS_W2_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) + 2;
            end

            ST_DISC_NS_W3_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) + 3;
            end

            ST_DISC_LBAF_REQ: begin
                ram_en   = 1'b1;
                ram_we   = 8'h00;
                // LBA format descriptors start at byte 128 and are four
                // bytes each; two descriptors therefore share one RAM word.
                ram_addr = (DISCOVERY_RAM_OFFSET >> 3) |
                           (16 + (discovered_lba_format_index >> 1));
            end

            ST_HEALTH_CTRL_REQ: if (ENABLE_SETUP_DEBUG) begin
                ram_en = 1'b1;
                case (health_word_index)
                    4'd0: ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 8);   // FR
                    4'd1: ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 32);  // NPSS
                    4'd2: ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 33);  // APSTA/temps
                    4'd3: ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 40);  // HCTMA/limits
                    4'd4: ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 256); // PSD0 bytes 0..7
                    default: ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 257);
                endcase
            end

            ST_HEALTH_PS_REQ: if (ENABLE_SETUP_DEBUG) begin
                ram_en = 1'b1;
                // Get Features FID 02 has no DMA payload, so Identify's PSDs
                // are still intact. Read before APST/SMART reuse the page.
                ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) + 256 +
                           ({27'd0, health_power_management[4:0]} << 2) +
                           {28'd0, health_word_index});
            end

            ST_HEALTH_SMART_REQ: if (ENABLE_SETUP_DEBUG) begin
                ram_en = 1'b1;
                // First read bytes 0..7, then contiguous bytes 160..231.
                ram_addr = RAM_ADDR_WIDTH'((DISCOVERY_RAM_OFFSET >> 3) +
                           ((health_word_index == 0) ? 0 :
                            (19 + {28'd0, health_word_index})));
            end

            default: begin
                ram_en    = 1'b0;
                ram_we    = 8'h00;
                ram_addr  = '0;
                ram_wdata = 64'd0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!resetn) begin
            state                    <= ST_IDLE;
            mmio_return_state        <= ST_IDLE;
            pending_command          <= CMD_NONE;
            pending_cid              <= 16'd0;
            next_cid                 <= 16'd1;
            sqe_word_index           <= 3'd0;
            admin_sq_tail            <= 16'd0;
            admin_cq_head            <= 16'd0;
            admin_cq_phase           <= 1'b1;
            doorbell_value           <= 16'd0;
            cqe_word0                <= 64'd0;
            cqe_word1                <= 64'd0;
            clear_word_index         <= '0;
            ready_poll_count         <= 32'd0;
            cq_poll_count            <= 32'd0;
            started_latch            <= 1'b0;
            queues_ready_latch       <= 1'b0;
            health_request_d         <= 1'b0;
            health_word_index        <= 4'd0;
            health_snapshot_busy     <= 1'b0;
            health_snapshot_done     <= 1'b0;
            health_snapshot_count    <= 32'd0;
            health_valid             <= 5'd0;
            health_command_status    <= ENABLE_SETUP_DEBUG ? {80{1'b1}} : 80'd0;
            health_error_code        <= 8'd0;
            health_firmware_revision <= 64'd0;
            health_npss              <= 8'd0;
            health_apsta             <= 8'd0;
            health_thermal_caps      <= 80'd0;
            health_power_management  <= 32'd0;
            health_apst              <= 32'd0;
            health_hctm              <= 32'd0;
            health_ps0_summary       <= 64'd0;
            health_current_ps_summary<= 64'd0;
            health_current_ps_valid  <= 1'b0;
            health_smart_status      <= 64'd0;
            health_media_errors      <= 128'd0;
            health_error_log_entries <= 128'd0;
            health_temperature_time  <= 64'd0;
            health_temperature_sensors <= 128'd0;
            health_thermal_transitions <= 64'd0;
            health_thermal_time      <= 64'd0;
            namespace_list_word_index<= 9'd0;
            namespace_list_read_data <= 64'd0;
            selected_lba_format      <= 32'd0;
            mmio_write_reg           <= 1'b0;
            mmio_addr_reg            <= '0;
            mmio_wdata_reg           <= 64'd0;
            mmio_wstrb_reg           <= 8'h00;
            mmio_size_reg            <= 3'd2;
            mmio_read32_data         <= 32'd0;
            discovery_done           <= 1'b0;
            discovery_valid          <= 1'b0;
            controller_info_valid    <= 1'b0;
            namespace_list_valid     <= 1'b0;
            namespace_info_valid     <= 1'b0;
            target_nsid_found        <= 1'b0;
            discovered_controller_vid<= 16'd0;
            discovered_controller_ssvid <= 16'd0;
            discovered_controller_version <= 32'd0;
            discovered_controller_nn <= 32'd0;
            discovered_controller_mdts <= 8'd0;
            discovered_controller_sqes <= 8'd0;
            discovered_controller_cqes <= 8'd0;
            discovered_first_nsid    <= 32'd0;
            discovered_active_nsid_count <= 32'd0;
            discovered_nsze          <= 64'd0;
            discovered_ncap          <= 64'd0;
            discovered_nuse          <= 64'd0;
            discovered_nlbaf         <= 8'd0;
            discovered_flbas         <= 8'd0;
            discovered_lba_format_index <= 6'd0;
            discovered_lbads         <= 8'd0;
            discovered_metadata_bytes<= 16'd0;
            discovered_lba_bytes     <= 32'd0;
            error_code               <= ERR_NONE;
            last_opcode              <= 8'h00;
            last_cid                 <= 16'd0;
            last_completion_cid      <= 16'd0;
            last_completion_status   <= 16'd0;
            last_cqe                 <= 128'd0;
            last_mmio_offset         <= 32'd0;
            last_mmio_rdata          <= 64'd0;
            submitted_command_count  <= 32'd0;
            allocated_io_queues      <= 32'd0;
        end else begin
            health_request_d <= ENABLE_SETUP_DEBUG && health_snapshot_request;
            // enum_done is latched by the enumeration FSM.  If it disappears
            // while setup is active, continuing to touch the endpoint is not
            // safe because BAR/BDF state may have been reset.
            if (started_latch &&
                (state != ST_IDLE) &&
                (state != ST_DONE) &&
                (state != ST_ERROR) &&
                !enum_done) begin
                fail_transaction(ERR_ENUM_LOST);
            end else begin
                case (state)
                    ST_IDLE: begin
                        if (enum_done) begin
                            started_latch           <= 1'b1;
                            queues_ready_latch      <= 1'b0;
                            discovery_done          <= 1'b0;
                            discovery_valid         <= 1'b0;
                            controller_info_valid   <= 1'b0;
                            namespace_list_valid    <= 1'b0;
                            namespace_info_valid    <= 1'b0;
                            target_nsid_found       <= 1'b0;
                            discovered_first_nsid   <= 32'd0;
                            discovered_active_nsid_count <= 32'd0;
                            error_code              <= ERR_NONE;
                            submitted_command_count <= 32'd0;
                            clear_word_index        <= '0;
                            state                   <= ST_DISABLE_CC;
                        end
                    end

                    ST_CLEAR_RAM: begin
                        if (&clear_word_index) begin
                            clear_word_index <= '0;
                            state <= ST_WRITE_AQA;
                        end else begin
                            clear_word_index <= clear_word_index + 1'b1;
                        end
                    end

                    // Always request CC.EN=0 first.  This safely recovers from
                    // a prior partially initialized controller, then waits for
                    // CSTS.RDY to deassert before replacing queue registers.
                    ST_DISABLE_CC: begin
                        ready_poll_count <= 32'd0;
                        launch_write32(
                            NVME_MMIO_AXI_BASE + NVME_CC,
                            32'd0,
                            ST_RDY0_READ
                        );
                    end

                    ST_RDY0_READ: begin
                        launch_read32(
                            NVME_MMIO_AXI_BASE + NVME_CSTS,
                            ST_RDY0_CHECK
                        );
                    end

                    ST_RDY0_CHECK: begin
                        if (mmio_read32_data[1]) begin
                            error_code <= ERR_CSTS_CFS;
                            state      <= ST_ERROR;
                        end else if (!mmio_read32_data[0]) begin
                            ready_poll_count <= 32'd0;
                            clear_word_index <= '0;
                            state <= ST_CLEAR_RAM;
                        end else if (ready_poll_count >= (READY_LIMIT - 1)) begin
                            error_code <= ERR_RDY0_TIMEOUT;
                            state      <= ST_ERROR;
                        end else begin
                            ready_poll_count <= ready_poll_count + 1'b1;
                            state <= ST_RDY0_READ;
                        end
                    end

                    ST_WRITE_AQA: begin
                        launch_write32(
                            NVME_MMIO_AXI_BASE + NVME_AQA,
                            AQA_VALUE,
                            ST_WRITE_ASQ
                        );
                    end

                    ST_WRITE_ASQ: begin
                        launch_write64(
                            NVME_MMIO_AXI_BASE + NVME_ASQ,
                            ADMIN_SQ_PCIE_ADDR,
                            ST_WRITE_ACQ
                        );
                    end

                    ST_WRITE_ACQ: begin
                        launch_write64(
                            NVME_MMIO_AXI_BASE + NVME_ACQ,
                            ADMIN_CQ_PCIE_ADDR,
                            ST_ENABLE_CC
                        );
                    end

                    ST_ENABLE_CC: begin
                        launch_write32(
                            NVME_MMIO_AXI_BASE + NVME_CC,
                            CC_ENABLE_VALUE,
                            ST_RDY1_READ
                        );
                    end

                    ST_RDY1_READ: begin
                        launch_read32(
                            NVME_MMIO_AXI_BASE + NVME_CSTS,
                            ST_RDY1_CHECK
                        );
                    end

                    ST_RDY1_CHECK: begin
                        if (mmio_read32_data[1]) begin
                            error_code <= ERR_CSTS_CFS;
                            state      <= ST_ERROR;
                        end else if (mmio_read32_data[0]) begin
                            ready_poll_count <= 32'd0;
                            state <= ST_PREP_IDENTIFY_CTRL;
                        end else if (ready_poll_count >= (READY_LIMIT - 1)) begin
                            error_code <= ERR_RDY1_TIMEOUT;
                            state      <= ST_ERROR;
                        end else begin
                            ready_poll_count <= ready_poll_count + 1'b1;
                            state <= ST_RDY1_READ;
                        end
                    end

                    // ---------------------------------------------------------
                    // Mandatory non-destructive discovery parsing.
                    //
                    // Identify commands transfer complete 4-KiB data
                    // structures into RAM.  Only the fields required for a
                    // safe first I/O are read back through the native port;
                    // the entire pages remain available through debug RAM.
                    // ---------------------------------------------------------
                    ST_DISC_CTRL_W0_REQ:
                        state <= ST_DISC_CTRL_W0_WAIT;

                    ST_DISC_CTRL_W0_WAIT: begin
                        discovered_controller_vid   <= ram_rdata[15:0];
                        discovered_controller_ssvid <= ram_rdata[31:16];
                        state <= ST_DISC_CTRL_W9_REQ;
                    end

                    ST_DISC_CTRL_W9_REQ:
                        state <= ST_DISC_CTRL_W9_WAIT;

                    ST_DISC_CTRL_W9_WAIT: begin
                        // Identify Controller byte 77 is MDTS.
                        discovered_controller_mdts <= ram_rdata[47:40];
                        state <= ST_DISC_CTRL_W10_REQ;
                    end

                    ST_DISC_CTRL_W10_REQ:
                        state <= ST_DISC_CTRL_W10_WAIT;

                    ST_DISC_CTRL_W10_WAIT: begin
                        // Identify Controller bytes 80:83 mirror VS.
                        discovered_controller_version <= ram_rdata[31:0];
                        state <= ST_DISC_CTRL_W64_REQ;
                    end

                    ST_DISC_CTRL_W64_REQ:
                        state <= ST_DISC_CTRL_W64_WAIT;

                    ST_DISC_CTRL_W64_WAIT: begin
                        // Bytes 512, 513, and 516:519 are SQES, CQES, and NN.
                        discovered_controller_sqes <= ram_rdata[7:0];
                        discovered_controller_cqes <= ram_rdata[15:8];
                        discovered_controller_nn   <= ram_rdata[63:32];
                        state <= ST_DISC_CTRL_CHECK;
                    end

                    ST_DISC_CTRL_CHECK: begin
                        if ((discovered_controller_vid == 16'd0) ||
                            (discovered_controller_vid == 16'hffff) ||
                            (discovered_controller_version == 32'd0) ||
                            (discovered_controller_nn == 32'd0) ||
                            !controller_queue_formats_valid) begin
                            discovery_done <= 1'b1;
                            error_code <= ERR_DISC_CTRL_INVALID;
                            state <= ST_ERROR;
                        end else begin
                            controller_info_valid <= 1'b1;
                            state <= ST_PREP_IDENTIFY_LIST;
                        end
                    end

                    ST_DISC_LIST_REQ:
                        state <= ST_DISC_LIST_WAIT;

                    ST_DISC_LIST_WAIT: begin
                        namespace_list_read_data <= ram_rdata;
                        state <= ST_DISC_LIST_CHECK;
                    end

                    ST_DISC_LIST_CHECK: begin
                        if ((namespace_list_word_index == 9'd0) &&
                            (namespace_list_nsid0 != 32'd0))
                            discovered_first_nsid <= namespace_list_nsid0;

                        discovered_active_nsid_count <=
                            discovered_active_nsid_count +
                            namespace_list_valid_entries;

                        if (namespace_list_current_match)
                            target_nsid_found <= 1'b1;

                        // The list is packed with zero termination and holds at
                        // most 1,024 NSIDs (512 native 64-bit RAM words).
                        if ((namespace_list_nsid0 == 32'd0) ||
                            (namespace_list_nsid1 == 32'd0) ||
                            (namespace_list_word_index == 9'd511)) begin
                            if (!(target_nsid_found ||
                                  namespace_list_current_match)) begin
                                discovery_done <= 1'b1;
                                error_code <= ERR_DISC_NSID_MISSING;
                                state <= ST_ERROR;
                            end else begin
                                namespace_list_valid <= 1'b1;
                                state <= ST_PREP_IDENTIFY_NS;
                            end
                        end else begin
                            namespace_list_word_index <=
                                namespace_list_word_index + 1'b1;
                            state <= ST_DISC_LIST_REQ;
                        end
                    end

                    ST_DISC_NS_W0_REQ:
                        state <= ST_DISC_NS_W0_WAIT;

                    ST_DISC_NS_W0_WAIT: begin
                        discovered_nsze <= ram_rdata;
                        state <= ST_DISC_NS_W1_REQ;
                    end

                    ST_DISC_NS_W1_REQ:
                        state <= ST_DISC_NS_W1_WAIT;

                    ST_DISC_NS_W1_WAIT: begin
                        discovered_ncap <= ram_rdata;
                        state <= ST_DISC_NS_W2_REQ;
                    end

                    ST_DISC_NS_W2_REQ:
                        state <= ST_DISC_NS_W2_WAIT;

                    ST_DISC_NS_W2_WAIT: begin
                        discovered_nuse <= ram_rdata;
                        state <= ST_DISC_NS_W3_REQ;
                    end

                    ST_DISC_NS_W3_REQ:
                        state <= ST_DISC_NS_W3_WAIT;

                    ST_DISC_NS_W3_WAIT: begin
                        // Bytes 25 and 26 are NLBAF and FLBAS.  NVMe 2.x may
                        // extend the format index with FLBAS bits 6:5.
                        discovered_nlbaf <= ram_rdata[15:8];
                        discovered_flbas <= ram_rdata[23:16];
                        discovered_lba_format_index <=
                            {ram_rdata[22:21], ram_rdata[19:16]};
                        state <= ST_DISC_LBAF_REQ;
                    end

                    ST_DISC_LBAF_REQ:
                        state <= ST_DISC_LBAF_WAIT;

                    ST_DISC_LBAF_WAIT: begin
                        if (discovered_lba_format_index[0])
                            selected_lba_format <= ram_rdata[63:32];
                        else
                            selected_lba_format <= ram_rdata[31:0];
                        state <= ST_DISC_NS_CHECK;
                    end

                    ST_DISC_NS_CHECK: begin
                        discovered_metadata_bytes <= selected_lba_format[15:0];
                        discovered_lbads <= selected_lba_format[23:16];
                        discovered_lba_bytes <= selected_lba_bytes_value;
                        discovery_done <= 1'b1;

                        if (!namespace_capacity_valid) begin
                            error_code <= ERR_DISC_NS_INVALID;
                            state <= ST_ERROR;
                        end else if (!selected_lba_format_index_valid ||
                                     !selected_lbads_valid) begin
                            error_code <= ERR_DISC_LBA_INVALID;
                            state <= ST_ERROR;
                        end else begin
                            namespace_info_valid <= 1'b1;
                            discovery_valid      <= 1'b1;
                            state <= ST_PREP_SET_NUM_QUEUES;
                        end
                    end

                    ST_PREP_IDENTIFY_CTRL:
                        prepare_command(CMD_IDENTIFY_CTRL);

                    ST_PREP_IDENTIFY_LIST:
                        prepare_command(CMD_IDENTIFY_LIST);

                    ST_PREP_IDENTIFY_NS:
                        prepare_command(CMD_IDENTIFY_NS);

                    ST_PREP_SET_NUM_QUEUES:
                        prepare_command(CMD_SET_NUM_QUEUES);

                    ST_PREP_CREATE_IO_CQ:
                        prepare_command(CMD_CREATE_IO_CQ);

                    ST_PREP_CREATE_IO_SQ:
                        prepare_command(CMD_CREATE_IO_SQ);

                    ST_SQE_WRITE: begin
                        if (sqe_word_index == 3'd7) begin
                            sqe_word_index <= 3'd0;
                            if (admin_sq_tail == (QUEUE_DEPTH - 1)) begin
                                doorbell_value <= 16'd0;
                                admin_sq_tail  <= 16'd0;
                            end else begin
                                doorbell_value <= admin_sq_tail + 1'b1;
                                admin_sq_tail  <= admin_sq_tail + 1'b1;
                            end
                            state <= ST_SQ_DOORBELL;
                        end else begin
                            sqe_word_index <= sqe_word_index + 1'b1;
                        end
                    end

                    ST_SQ_DOORBELL: begin
                        launch_write32(
                            NVME_MMIO_AXI_BASE + ADMIN_SQ_TAIL_DB,
                            {16'd0, doorbell_value},
                            ST_CQ_POLL_START
                        );
                    end

                    ST_CQ_POLL_START: begin
                        cq_poll_count <= 32'd0;
                        if (ENABLE_SETUP_DEBUG)
                            submitted_command_count <= submitted_command_count + 1'b1;
                        state <= ST_CQ_READ0_REQ;
                    end

                    ST_CQ_READ0_REQ:
                        state <= ST_CQ_READ0_WAIT;

                    ST_CQ_READ0_WAIT: begin
                        cqe_word0 <= ram_rdata;
                        state <= ST_CQ_READ1_REQ;
                    end

                    ST_CQ_READ1_REQ:
                        state <= ST_CQ_READ1_WAIT;

                    ST_CQ_READ1_WAIT: begin
                        cqe_word1 <= ram_rdata;
                        state <= ST_CQ_CHECK;
                    end

                    ST_CQ_CHECK: begin
                        if (ENABLE_SETUP_DEBUG)
                            last_cqe <= {cqe_word1, cqe_word0};

                        // P is bit 16 of CQE DW3, hence bit 48 of the upper
                        // 64-bit RAM word.  A mismatched phase means empty.
                        if (cqe_word1[48] != expected_cq_phase) begin
                            if (cq_poll_count >= (CQ_LIMIT - 1)) begin
                                fail_transaction(ERR_CQ_TIMEOUT);
                            end else begin
                                cq_poll_count <= cq_poll_count + 1'b1;
                                state <= ST_CQ_READ0_REQ;
                            end
                        end else if (cqe_word1[47:32] != pending_cid) begin
                            if (ENABLE_SETUP_DEBUG)
                                last_completion_cid <= cqe_word1[47:32];
                            fail_transaction(ERR_CQ_CID);
                        end else if (cqe_word1[31:16] != expected_sqid) begin
                            fail_transaction(ERR_CQ_SQID);
                        end else if (health_command) begin
                            last_completion_cid <= cqe_word1[47:32];
                            last_completion_status <= {1'b0, cqe_word1[63:49]};
                            health_command_status[health_command_index*16 +: 16] <=
                                {1'b0, cqe_word1[63:49]};
                            // Even an unsupported optional command must be
                            // consumed and acknowledged before the next one.
                            state <= ST_CQ_RESULT_REQ;
                        end else if (cqe_word1[63:49] != 15'd0) begin
                            if (ENABLE_SETUP_DEBUG)
                                last_completion_status <= {1'b0, cqe_word1[63:49]};
                            error_code <= ERR_CQ_STATUS;
                            state      <= ST_ERROR;
                        end else begin
                            if (ENABLE_SETUP_DEBUG) begin
                                last_completion_cid    <= cqe_word1[47:32];
                                last_completion_status <= 16'd0;
                            end
                            state <= ST_CQ_RESULT_REQ;
                        end
                    end

                    ST_CQ_RESULT_REQ:
                        state <= ST_CQ_RESULT_WAIT;

                    ST_CQ_RESULT_WAIT: begin
                        // A completion may arrive between the initial DW0
                        // and phase reads. Re-read DW0 only after ownership,
                        // CID and SQID are validated, before acknowledging.
                        cqe_word0 <= ram_rdata;
                        if (ENABLE_SETUP_DEBUG)
                            last_cqe <= {cqe_word1, ram_rdata};
                        state <= ST_CQ_ACK;
                    end

                    ST_CQ_ACK: begin
                        if (admin_cq_head == (QUEUE_DEPTH - 1)) begin
                            admin_cq_head      <= 16'd0;
                            admin_cq_phase     <= ~admin_cq_phase;
                            launch_write32(
                                NVME_MMIO_AXI_BASE + ADMIN_CQ_HEAD_DB,
                                32'd0,
                                ST_COMMAND_COMPLETE
                            );
                        end else begin
                            admin_cq_head      <= admin_cq_head + 1'b1;
                            launch_write32(
                                NVME_MMIO_AXI_BASE + ADMIN_CQ_HEAD_DB,
                                {16'd0, (admin_cq_head + 1'b1)},
                                ST_COMMAND_COMPLETE
                            );
                        end
                    end

                    ST_COMMAND_COMPLETE: begin
                        case (pending_command)
                            CMD_IDENTIFY_CTRL:
                                state <= ST_DISC_CTRL_W0_REQ;
                            CMD_IDENTIFY_LIST: begin
                                namespace_list_word_index    <= 9'd0;
                                namespace_list_read_data     <= 64'd0;
                                discovered_first_nsid        <= 32'd0;
                                discovered_active_nsid_count <= 32'd0;
                                target_nsid_found            <= 1'b0;
                                state <= ST_DISC_LIST_REQ;
                            end
                            CMD_IDENTIFY_NS:
                                state <= ST_DISC_NS_W0_REQ;
                            CMD_SET_NUM_QUEUES: begin
                                if (ENABLE_SETUP_DEBUG)
                                    allocated_io_queues <= cqe_word0[31:0];
                                state <= ST_PREP_CREATE_IO_CQ;
                            end
                            CMD_CREATE_IO_CQ:
                                state <= ST_PREP_CREATE_IO_SQ;
                            CMD_CREATE_IO_SQ: begin
                                queues_ready_latch <= 1'b1;
                                state <= ST_DONE;
                            end
                            CMD_HEALTH_CTRL: if (ENABLE_SETUP_DEBUG) begin
                                health_word_index <= 4'd0;
                                if (cqe_word1[63:49] == 0)
                                    state <= ST_HEALTH_CTRL_REQ;
                                else
                                    prepare_command(CMD_HEALTH_POWER);
                            end
                            CMD_HEALTH_POWER: if (ENABLE_SETUP_DEBUG) begin
                                if (cqe_word1[63:49] == 0) begin
                                    health_valid[1] <= 1'b1;
                                    health_power_management <= cqe_word0[31:0];
                                    health_word_index <= 4'd0;
                                    if (health_valid[0] &&
                                        ({3'd0, cqe_word0[4:0]} <= health_npss))
                                        state <= ST_HEALTH_PS_REQ;
                                    else
                                        prepare_command(CMD_HEALTH_APST);
                                end else
                                    prepare_command(CMD_HEALTH_APST);
                            end
                            CMD_HEALTH_APST: if (ENABLE_SETUP_DEBUG) begin
                                if (cqe_word1[63:49] == 0) begin
                                    health_valid[2] <= 1'b1;
                                    health_apst <= cqe_word0[31:0];
                                end
                                prepare_command(CMD_HEALTH_HCTM);
                            end
                            CMD_HEALTH_HCTM: if (ENABLE_SETUP_DEBUG) begin
                                if (cqe_word1[63:49] == 0) begin
                                    health_valid[3] <= 1'b1;
                                    health_hctm <= cqe_word0[31:0];
                                end
                                prepare_command(CMD_HEALTH_SMART);
                            end
                            CMD_HEALTH_SMART: if (ENABLE_SETUP_DEBUG) begin
                                health_word_index <= 4'd0;
                                state <= (cqe_word1[63:49] == 0) ? ST_HEALTH_SMART_REQ :
                                                                 ST_HEALTH_FINISH;
                            end
                            default: begin
                                error_code <= ERR_CQ_STATUS;
                                state <= ST_ERROR;
                            end
                        endcase
                    end

                    ST_MMIO_REQ: begin
                        if (mmio_cmd_valid && mmio_cmd_ready) begin
                            if (ENABLE_SETUP_DEBUG)
                                last_mmio_offset <= mmio_addr_reg - NVME_MMIO_AXI_BASE;
                            state <= ST_MMIO_RSP;
                        end
                    end

                    ST_MMIO_RSP: begin
                        if (mmio_rsp_valid) begin
                            if (ENABLE_SETUP_DEBUG)
                                last_mmio_rdata <= mmio_rsp_rdata;
                            if (mmio_rsp_timeout) begin
                                fail_transaction(ERR_MMIO_TIMEOUT);
                            end else if (mmio_rsp_resp != AXI_OKAY) begin
                                fail_transaction(ERR_MMIO_AXI);
                            end else begin
                                mmio_read32_data <=
                                    mmio_rsp_rdata >>
                                    (mmio_addr_reg[2:0] * 8);
                                state <= mmio_return_state;
                            end
                        end
                    end

                    ST_DONE: begin
                        // Initial snapshot is automatic; later ones need a
                        // VIO rising edge. Production builds stay idle here.
                        // Never reset or recreate queues.
                        if (ENABLE_SETUP_DEBUG && enum_done && (health_error_code == 0) &&
                            (!health_snapshot_done ||
                             (health_snapshot_request && !health_request_d)))
                            state <= ST_HEALTH_START;
                    end

                    ST_HEALTH_START: if (ENABLE_SETUP_DEBUG) begin
                        health_snapshot_busy <= 1'b1;
                        health_snapshot_done <= 1'b0;
                        health_valid <= 5'd0;
                        health_command_status <= {80{1'b1}};
                        health_current_ps_valid <= 1'b0;
                        // Payload registers retain the previous snapshot
                        // until replaced; only health_valid qualifies them.
                        prepare_command(CMD_HEALTH_CTRL);
                    end

                    ST_HEALTH_CTRL_REQ: if (ENABLE_SETUP_DEBUG) state <= ST_HEALTH_CTRL_WAIT;
                    ST_HEALTH_CTRL_WAIT: if (ENABLE_SETUP_DEBUG) begin
                        case (health_word_index)
                            4'd0: health_firmware_revision <= ram_rdata;
                            4'd1: health_npss <= ram_rdata[63:56];
                            4'd2: begin
                                health_apsta <= ram_rdata[15:8];
                                health_thermal_caps[31:0] <= ram_rdata[47:16];
                            end
                            4'd3: health_thermal_caps[79:32] <= ram_rdata[63:16];
                            4'd4: health_ps0_summary[31:0] <= ram_rdata[31:0];
                            default: health_ps0_summary[63:32] <= ram_rdata[63:32];
                        endcase
                        if (health_word_index == 4'd5) begin
                            health_valid[0] <= 1'b1;
                            prepare_command(CMD_HEALTH_POWER);
                        end else begin
                            health_word_index <= health_word_index + 1'b1;
                            state <= ST_HEALTH_CTRL_REQ;
                        end
                    end

                    ST_HEALTH_PS_REQ: if (ENABLE_SETUP_DEBUG) state <= ST_HEALTH_PS_WAIT;
                    ST_HEALTH_PS_WAIT: if (ENABLE_SETUP_DEBUG) begin
                        if (health_word_index == 0) begin
                            health_current_ps_summary[31:0] <= ram_rdata[31:0];
                            health_word_index <= 4'd1;
                            state <= ST_HEALTH_PS_REQ;
                        end else begin
                            health_current_ps_summary[63:32] <= ram_rdata[63:32];
                            health_current_ps_valid <= 1'b1;
                            prepare_command(CMD_HEALTH_APST);
                        end
                    end

                    ST_HEALTH_SMART_REQ: if (ENABLE_SETUP_DEBUG) state <= ST_HEALTH_SMART_WAIT;
                    ST_HEALTH_SMART_WAIT: if (ENABLE_SETUP_DEBUG) begin
                        case (health_word_index)
                            4'd0: health_smart_status <= ram_rdata;
                            4'd1: health_media_errors[63:0] <= ram_rdata;
                            4'd2: health_media_errors[127:64] <= ram_rdata;
                            4'd3: health_error_log_entries[63:0] <= ram_rdata;
                            4'd4: health_error_log_entries[127:64] <= ram_rdata;
                            4'd5: health_temperature_time <= ram_rdata;
                            4'd6: health_temperature_sensors[63:0] <= ram_rdata;
                            4'd7: health_temperature_sensors[127:64] <= ram_rdata;
                            4'd8: health_thermal_transitions <= ram_rdata;
                            4'd9: health_thermal_time <= ram_rdata;
                            default: ;
                        endcase
                        if (health_word_index == 4'd9) begin
                            health_valid[4] <= 1'b1;
                            state <= ST_HEALTH_FINISH;
                        end else begin
                            health_word_index <= health_word_index + 1'b1;
                            state <= ST_HEALTH_SMART_REQ;
                        end
                    end

                    ST_HEALTH_FINISH: if (ENABLE_SETUP_DEBUG) begin
                        health_snapshot_busy <= 1'b0;
                        health_snapshot_done <= 1'b1;
                        health_snapshot_count <= health_snapshot_count + 1'b1;
                        state <= ST_DONE;
                    end

                    ST_ERROR: begin
                        // Latched until reset; no automatic retry.
                    end

                    default: begin
                        error_code <= ERR_CQ_STATUS;
                        state <= ST_ERROR;
                    end
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    // The RAM word indices above are OR-ed into these offsets.
    initial assert ((DISCOVERY_RAM_OFFSET[11:0] == 12'd0) &&
                    (ADMIN_SQ_RAM_OFFSET[11:0] == 12'd0) &&
                    (ADMIN_CQ_RAM_OFFSET[11:0] == 12'd0) &&
                    (QUEUE_DEPTH <= 64))
        else $fatal(1, "pl_pcie_nvme_setup_fsm: RAM buffers must be 4-KiB aligned and admin queues <= 64 entries");
`endif

    initial begin
        if ((IO_QUEUE_DEPTH < 2) || (IO_QUEUE_DEPTH > 256) ||
            ((IO_QUEUE_DEPTH & (IO_QUEUE_DEPTH - 1)) != 0))
            $error("pl_pcie_nvme_setup_fsm: IO_QUEUE_DEPTH must be a power of two in [2,256]");
        if ((KNOWN_CAP[15:0] + 1) < IO_QUEUE_DEPTH)
            $error("pl_pcie_nvme_setup_fsm: IO_QUEUE_DEPTH exceeds known CAP.MQES");
        if ((QUEUE_DEPTH < 2) || (QUEUE_DEPTH > 64) ||
            ((QUEUE_DEPTH & (QUEUE_DEPTH - 1)) != 0))
            $error("pl_pcie_nvme_setup_fsm: QUEUE_DEPTH must be a power of two in [2,64] (4 KiB admin SQ)");
        if ((KNOWN_CAP[15:0] + 1) < QUEUE_DEPTH)
            $error("pl_pcie_nvme_setup_fsm: QUEUE_DEPTH exceeds known CAP.MQES");
        if ((KNOWN_CAP[35:32] != 4'd0) ||
            (KNOWN_CAP[51:48] != 4'd0) ||
            (KNOWN_CAP[55:52] != 4'd0) || !KNOWN_CAP[37])
            $error("pl_pcie_nvme_setup_fsm: fixed DSTRD/MPS/CSS assumptions do not match KNOWN_CAP");
        if (KNOWN_VS != 32'h0002_0000)
            $warning("pl_pcie_nvme_setup_fsm: code was validated against NVMe VS 2.0");
        if (NVME_NSID == 32'd0)
            $error("pl_pcie_nvme_setup_fsm: NVME_NSID zero is not usable");
        if ((DISCOVERY_PCIE_ADDR[11:0] != 0) ||
            (ADMIN_SQ_PCIE_ADDR[11:0] != 0) ||
            (ADMIN_CQ_PCIE_ADDR[11:0] != 0) ||
            (IO_SQ_PCIE_ADDR[11:0] != 0) ||
            (IO_CQ_PCIE_ADDR[11:0] != 0))
            $error("pl_pcie_nvme_setup_fsm: queue/PRP addresses must be 4-KiB aligned");
        if ((DISCOVERY_RAM_OFFSET + 4096 > RAM_BYTES) ||
            (ADMIN_SQ_RAM_OFFSET + 4096 > RAM_BYTES) ||
            (ADMIN_CQ_RAM_OFFSET + 4096 > RAM_BYTES))
            $error("pl_pcie_nvme_setup_fsm: local buffers exceed RAM");
    end

endmodule
