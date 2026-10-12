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

`include "lynx_macros.svh"

/**
 * @brief   NVMe top-level
 *
 * Arbitrates all regions into one shared submission pipeline (parse the request,
 * build the SQE and PRP list, ring the doorbell) and returns the completions.
 */
module nvme_top (
    input  logic        aclk,
    input  logic        aresetn,

    // Per-region user interfaces (req_t with strm=STRM_NVME)
    metaIntf.s          s_nvme_user_req [N_REGIONS],  // req_t
    metaIntf.m          m_nvme_user_rsp [N_REGIONS],  // device[15:12], CID[11:4], local error[3:0]
    metaIntf.m          m_nvme_cpl      [N_REGIONS],  // nvme_cqe_t

    // MMU interface (req_t with strm=STRM_NVME → bpss_rd_sq path)
    metaIntf.m          m_nvme_rd_sq,     // req_t
    metaIntf.s          s_nvme_rd_rsp,    // nvme_mmu_rsp_t

`ifdef EN_NVME_HOST
    // Host-connected NVMe: doorbell DMA write (merged upstream via arbiter)
    dmaIntf.m           m_db_wr_req,
    AXI4S.m             m_db_wr_data,
`elsif EN_NVME_PL
    // PL-connected NVMe: doorbell AXI-MM path to design_plnvme
    AXI4.m              m_axi_nvme_mmio,
    input  logic        nvme_pl_ready,
    input  logic        nvme_setup_done,
    input  logic        nvme_setup_error,
    input  logic [7:0]  nvme_setup_error_code,
    input  logic        nvme_namespace_info_valid,
    input  logic        nvme_target_nsid_found,
    input  logic [31:0] nvme_discovered_nsid,
    input  logic [63:0] nvme_discovered_nsze,
    input  logic [31:0] nvme_discovered_lba_bytes,
    input  logic [7:0]  nvme_discovered_mdts,
    input  logic [3:0]  nvme_mpsmin,
`endif

    // Single AXI interfaces (from BD interconnect)
    AXI4L.s             s_nvme_cnfg,
    AXI4.s              s_nvme_prp,
    AXI4.s              s_nvme_sq,
    AXI4.s              s_nvme_cq
);

    // Constants
    // Fixed 16-MiB PRP-list window (1 MiB per device) for every queue depth.
    localparam logic [63:0] PRP_OFFSET = 64'h0500_0000;
    localparam int unsigned N_NVME     = NVME_NUM_DEVICES;
`ifdef EN_NVME_PL
    // design_plnvme creates I/O queue 1 and currently assumes CAP.DSTRD=0, hence
    // four-byte doorbell spacing: SQ1=BAR+0x1008 and CQ1=BAR+0x100c.
    // Supporting another queue ID or DSTRD requires making these configurable.
    localparam logic [63:0] PL_NVME_SQ_DB_ADDR = 64'h0000_0000_8000_1008;
    localparam logic [63:0] PL_NVME_CQ_DB_ADDR = 64'h0000_0000_8000_100c;

`ifndef SYNTHESIS
    initial begin
        assert (PL_NVME_CQ_DB_ADDR == PL_NVME_SQ_DB_ADDR + 64'd4)
            else $error("PL NVMe CQ1 doorbell must immediately follow SQ1 for DSTRD=0");
    end
`endif
`endif

    // Config signals
    logic [63:0] fpga_bar_base;
    logic [63:0] fpga_prp_bar_base;
    assign fpga_prp_bar_base = fpga_bar_base + PRP_OFFSET;

    // Arbitrated user interfaces (N_REGIONS → 1)
    metaIntf #(.STYPE(req_t)) user_req_arb   ();
    metaIntf #(.STYPE(req_t)) user_req_arb_q ();
    // CID → region map for completion routing
    logic [N_REGIONS_BITS-1:0]  cid_region [N_NVME][1 << NVME_QUEUE_BITS];
    logic [(1 << NVME_QUEUE_BITS)-1:0] cid_live [N_NVME];
`ifdef MULT_REGIONS
    // Per-(region,device) NVMe outstanding credits (multi-region)
    logic [7:0]                 credit_cnt [N_REGIONS][N_NVME];
`endif

    // Pipeline internal signals
    metaIntf #(.STYPE(nvme_info_req_t))    tbl_req       ();
    metaIntf #(.STYPE(nvme_info_rsp_t))    tbl_rsp       ();
    metaIntf #(.STYPE(req_t))    cmd_parsed        ();
    metaIntf #(.STYPE(nvme_prp_req_t))     prp_req       ();
    metaIntf #(.STYPE(nvme_prp_req_t))     prp_req_q     ();
    metaIntf #(.STYPE(nvme_prp_rsp_t))     prp_rsp       ();
    metaIntf #(.STYPE(nvme_prp_write_t))   prp_write_strm();
    metaIntf #(.STYPE(nvme_cmd_dispatched_t))      cmd_dispatched        ();
    metaIntf #(.STYPE(nvme_sqe_t))      sqe_strm      ();
    metaIntf #(.STYPE(nvme_cqe_t))         cqe_strm      ();
    // nvme_cqe_t carries an 8-bit CID; per-CID tables use the configured depth.
    logic [NVME_QUEUE_BITS-1:0]            cqe_cid;
    assign cqe_cid = cqe_strm.data.cid[NVME_QUEUE_BITS-1:0];

    metaIntf #(.STYPE(sq_db_req_t))        sq_db_strm    ();
    metaIntf #(.STYPE(update_tbl_t))       update_tbl    ();
    metaIntf #(.STYPE(update_tbl_t))       update_tbl_int();
    metaIntf #(.STYPE(nvme_perm_update_t)) perm_update   ();
    metaIntf #(.STYPE(cq_head_update_t))   cq_head_upd   ();
    metaIntf #(.STYPE(req_t))              mmu_req_int   ();

    metaIntf #(.STYPE(nvme_user_rsp_t))    user_rsp_pre  ();
    logic [15:0] cmd_error;
    logic [NVME_QUEUE_BITS-1:0] alloc_cid, cmd_cid, sqe_cid;
    logic prp_fault, abort_valid;
    logic [N_NVME_BITS-1:0] abort_dev;
    logic queue_reset, cq_reset_ready, db_reset_ready;
`ifdef EN_NVME_PL
    logic pl_db_idle;
`endif
    logic cqe_owned, cqe_fire, cqe_release, cqe_cid_in_range;
    logic [15:0] cqe_sq_head;

    // Queue recreation must be quiescent. Wait for command ownership and the
    // current CQ doorbell transaction before resetting per-device ring state.
    assign update_tbl_int.valid = update_tbl.valid &&
        (!update_tbl.data.reset_queue || (cq_reset_ready && db_reset_ready));
    assign update_tbl_int.data = update_tbl.data;
    assign update_tbl.ready = update_tbl_int.ready &&
        (!update_tbl.data.reset_queue || (cq_reset_ready && db_reset_ready));
    assign queue_reset = update_tbl.valid && update_tbl.ready && update_tbl.data.reset_queue &&
                         update_tbl.data.dev_id < N_NVME;
    assign cq_head_upd.ready = 1'b1; // CQ acknowledgement no longer grants SQ space.

    dmaIntf sq_dma_req ();
    dmaIntf cq_dma_req ();
    AXI4S   sq_dma_data (.aclk(aclk));
    AXI4S   cq_dma_data (.aclk(aclk));

`ifdef EN_NVME_PL
    metaIntf #(.STYPE(sq_db_req_t)) pl_sq_db_strm ();
    logic [63:0] pl_sq_db_addr_tbl [N_NVME];
    dmaIntf pl_db_dma_req ();
    AXI4S   pl_db_dma_data (.aclk(aclk));

    // The PL setup engine creates one SSD and queue pair only. Override the
    // host-driver-supplied address for device zero; invalid devices retain zero.
    assign pl_sq_db_strm.valid = sq_db_strm.valid;
    assign pl_sq_db_strm.data.sq_tail = sq_db_strm.data.sq_tail;
    assign pl_sq_db_strm.data.sq_db_addr = PL_NVME_SQ_DB_ADDR;
    assign sq_db_strm.ready = pl_sq_db_strm.ready;
    always_comb begin
        for (int d = 0; d < N_NVME; d++)
            // The tracker sets bit 2 (adds four), so seed it with the desired
            // CQ address minus four, whose bit 2 is clear.
            pl_sq_db_addr_tbl[d] =
                (d == 0) ? (PL_NVME_CQ_DB_ADDR - 64'd4) : 64'd0;
    end
`endif

`ifdef EN_NVME_PL
    // READY can be high with older writes outstanding. Reset must drain all B
    // responses and exclude a new request accepted on the reset edge.
    assign db_reset_ready = pl_db_idle && !pl_db_dma_req.valid;
`else
    // Host queue recreation already requires the host DMA path to be drained.
    assign db_reset_ready = 1'b1;
`endif

    // Per-device doorbell address table
    logic [63:0] sq_db_addr_tbl [N_NVME];

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int d = 0; d < N_NVME; d++)
                sq_db_addr_tbl[d] <= '0;
        end
        else if (update_tbl.valid && update_tbl.ready && update_tbl.data.dev_id < N_NVME) begin
            sq_db_addr_tbl[update_tbl.data.dev_id] <= update_tbl.data.sq_db_addr;
        end
    end

    // N_REGIONS -> 1
`ifdef MULT_REGIONS
    // Per-region credit check + arbiter (fair admission across regions)
    metaIntf #(.STYPE(req_t)) user_req_arb_pre ();
    metaIntf #(.STYPE(req_t)) user_req_cred [N_REGIONS] ();
    logic [N_REGIONS_BITS-1:0] arb_id;

    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_user_req_cred
        wire cred_ok =
            ((s_nvme_user_req[i].data.dev_id >= N_NVME) ? 1'b1 :
             (credit_cnt[i][s_nvme_user_req[i].data.dev_id] < NVME_N_OUTSTANDING))
`ifdef EN_NVME_PL
            && nvme_pl_ready
`endif
            ;
        assign user_req_cred[i].valid  = s_nvme_user_req[i].valid && cred_ok;
        assign user_req_cred[i].data   = s_nvme_user_req[i].data;
        assign s_nvme_user_req[i].ready = user_req_cred[i].ready && cred_ok;
    end

    nvme_credit_arbiter #(
        .N_ID(N_REGIONS),
        .N_ID_BITS(N_REGIONS_BITS)
    ) inst_user_req_arb (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_meta(user_req_cred),
        .m_meta(user_req_arb_pre),
        .id_out(arb_id)
    );

    assign user_req_arb.valid = user_req_arb_pre.valid;
    assign user_req_arb_pre.ready = user_req_arb.ready;
    always_comb begin
        user_req_arb.data        = user_req_arb_pre.data;
        user_req_arb.data.vfid   = arb_id;
    end
`else
    // Single region: direct, no arbitration
`ifdef EN_NVME_PL
    assign user_req_arb.valid = s_nvme_user_req[0].valid && nvme_pl_ready;
    assign s_nvme_user_req[0].ready = user_req_arb.ready && nvme_pl_ready;
`else
    assign user_req_arb.valid = s_nvme_user_req[0].valid;
    assign s_nvme_user_req[0].ready = user_req_arb.ready;
`endif
    always_comb begin
        user_req_arb.data        = s_nvme_user_req[0].data;
        user_req_arb.data.vfid   = '0;
    end
`endif

    // Completion/terminal-error drain handshakes (per region, per device)
    logic [N_REGIONS-1:0]   cpl_pop, rsp_pop;
    logic [N_NVME_BITS-1:0] cpl_dev [N_REGIONS];
    logic [N_NVME_BITS-1:0] rsp_dev [N_REGIONS];

    // CID owns the region independently of the SQ slot. Mark it completable
    // only once its SQE is stored. Once routed into a region FIFO, the packet
    // no longer depends on the CID map, so that CID/PRP slot can be reused.
    for (genvar d = 0; d < N_NVME; d++) begin : gen_cid_device
        wire store_region = cmd_dispatched.valid && cmd_dispatched.ready && cmd_error == 0 &&
                            cmd_dispatched.data.dev_id == N_NVME_BITS'(d);
        wire publish_device = sqe_strm.valid && sqe_strm.ready &&
                              sqe_strm.data.dev_id == N_NVME_BITS'(d);
        wire retire_device = cqe_release && cqe_strm.data.dev_id == N_NVME_BITS'(d);
        wire reset_device = queue_reset && update_tbl.data.dev_id == N_NVME_BITS'(d);
        // Keep the single-write region map eligible for RAM inference.
        always_ff @(posedge aclk)
            if (aresetn && store_region) cid_region[d][cmd_cid] <= cmd_dispatched.data.vfid;
        for (genvar c = 0; c < (1 << NVME_QUEUE_BITS); c++) begin : gen_cid
            // Constant indices make feedback local. Preserve reset > set > clear.
            always_ff @(posedge aclk) begin
                if (!aresetn || reset_device) cid_live[d][c] <= 1'b0;
                else if (publish_device && sqe_cid == NVME_QUEUE_BITS'(c)) cid_live[d][c] <= 1'b1;
                else if (retire_device && cqe_cid == NVME_QUEUE_BITS'(c)) cid_live[d][c] <= 1'b0;
            end
        end
    end

    // Completion routing: cqe → owning region (via CID map) → per-region FIFO
    metaIntf #(.STYPE(nvme_cqe_t)) cpl_fin [N_REGIONS] ();
    logic [N_REGIONS-1:0] cpl_fin_rdy;
    wire [N_REGIONS_BITS-1:0] cpl_region = (cqe_strm.data.dev_id < N_NVME) ?
        cid_region[cqe_strm.data.dev_id][cqe_cid] : '0;
    assign cqe_owned = (cqe_strm.data.dev_id < N_NVME) ?
        cqe_cid_in_range && cid_live[cqe_strm.data.dev_id][cqe_cid] : 1'b0;
    assign cqe_fire = cqe_strm.valid && cqe_strm.ready;
    assign cqe_release = cqe_fire && cqe_owned;

    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_cpl_route
        assign cpl_fin[i].valid = cqe_strm.valid && cqe_owned && (cpl_region == i);
        assign cpl_fin[i].data  = cqe_strm.data;
        assign cpl_fin_rdy[i]   = cpl_fin[i].ready;
        queue_meta #(.QDEPTH(NVME_N_OUTSTANDING*N_NVME)) inst_cpl_fifo (.aclk(aclk), .aresetn(aresetn), .s_meta(cpl_fin[i]), .m_meta(m_nvme_cpl[i]));
        assign cpl_pop[i] = m_nvme_cpl[i].valid && m_nvme_cpl[i].ready;
        assign cpl_dev[i] = m_nvme_cpl[i].data.dev_id;
    end
    // Consume unexpected/duplicate CIDs without notifying a region or freeing
    // an aliased live CID. Full CID and SQID remain visible in CQ ILA probes.
    assign cqe_strm.ready = !cqe_owned || cpl_fin_rdy[cpl_region];

    // The SQE builder serializes success, lookup error and preparation error
    // responses in command order. Existing per-region FIFOs preserve that order.
    metaIntf #(.STYPE(nvme_user_rsp_t)) rsp_fin [N_REGIONS] ();
    metaIntf #(.STYPE(nvme_user_rsp_t)) rsp_out [N_REGIONS] ();
    logic [N_REGIONS-1:0] rsp_fin_rdy;
    wire [N_REGIONS_BITS-1:0] rsp_region = user_rsp_pre.data.vfid;

    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_rsp_route
        assign rsp_fin[i].valid = user_rsp_pre.valid && (rsp_region == i);
        assign rsp_fin[i].data  = user_rsp_pre.data;
        assign rsp_fin_rdy[i]   = rsp_fin[i].ready;
        queue_meta #(.QDEPTH(NVME_N_OUTSTANDING*N_NVME)) inst_rsp_fifo (.aclk(aclk), .aresetn(aresetn), .s_meta(rsp_fin[i]), .m_meta(rsp_out[i]));
        assign m_nvme_user_rsp[i].valid = rsp_out[i].valid;
        assign m_nvme_user_rsp[i].data  = rsp_out[i].data.error;
        assign rsp_out[i].ready         = m_nvme_user_rsp[i].ready;
        // Successful CID assignment is not command completion and returns no
        // outstanding credit. Only a terminal local error does so here.
        assign rsp_pop[i] = rsp_out[i].valid && rsp_out[i].ready &&
                            (rsp_out[i].data.error[NVME_RSP_ERROR_BITS-1:0] != 0);
        assign rsp_dev[i] = rsp_out[i].data.dev_id;
    end
    assign user_rsp_pre.ready = rsp_fin_rdy[rsp_region];

`ifdef MULT_REGIONS
    // Per-(region,device) credit: ++ on grant, -- on completion or local error
    wire grant_fire = user_req_arb.valid && user_req_arb.ready;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int r = 0; r < N_REGIONS; r++)
                for (int d = 0; d < N_NVME; d++) credit_cnt[r][d] <= '0;
        end
        else begin
            for (int r = 0; r < N_REGIONS; r++)
                for (int d = 0; d < N_NVME; d++)
                    credit_cnt[r][d] <= credit_cnt[r][d]
                        + ((grant_fire && (arb_id == r) && (user_req_arb.data.dev_id == d)) ? 1'b1 : 1'b0)
                        - ((cpl_pop[r] && (cpl_dev[r] == d)) ? 1'b1 : 1'b0)
                        - ((rsp_pop[r] && (rsp_dev[r] == d)) ? 1'b1 : 1'b0);
        end
    end
`endif

    // Single shared queue (arbiter → FIFO → pipeline)
    queue_meta #(.QDEPTH(32)) inst_user_req_q (.aclk(aclk), .aresetn(aresetn), .s_meta(user_req_arb),   .m_meta(user_req_arb_q));
    queue_meta #(.QDEPTH(8))  inst_prp_req_q  (.aclk(aclk), .aresetn(aresetn), .s_meta(prp_req),        .m_meta(prp_req_q));
    queue_meta #(.QDEPTH(8))  inst_mmu_req_q  (.aclk(aclk), .aresetn(aresetn), .s_meta(mmu_req_int),    .m_meta(m_nvme_rd_sq));

    // Stage 0: Parse user request
    nvme_req_parser inst_nvme_req_parser (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_nvme_user_req (user_req_arb_q),
        .m_nvme_info_req (tbl_req),
        .m_nvme_cmd_parsed   (cmd_parsed)
    );

    // Info Table
    nvme_info_table inst_nvme_info_table (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_tbl_req       (tbl_req),
        .m_tbl_rsp       (tbl_rsp),
        .alloc_cid      (alloc_cid),
        .cpl_valid      (cqe_release),
        .cpl_dev        (cqe_strm.data.dev_id),
        .cpl_cid        (cqe_cid),
        .cpl_sq_head    (cqe_sq_head),
        .resolve_valid (abort_valid || (sqe_strm.valid && sqe_strm.ready)),
        .resolve_abort (abort_valid),
        .resolve_dev   (abort_valid ? abort_dev : sqe_strm.data.dev_id),
        .resolve_cid   (sqe_cid),
        .s_update_tbl    (update_tbl_int),
        .s_perm_update   (perm_update)
    );

    // Stage 1: Lookup info table, generate PRP request
    nvme_prp_dispatch inst_nvme_prp_dispatch (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_nvme_cmd_parsed   (cmd_parsed),
        .s_nvme_info_rsp (tbl_rsp),
        .s_alloc_cid     (alloc_cid),
        .m_cmd_cid       (cmd_cid),
        .m_cmd_error     (cmd_error),
        .m_nvme_prp_req  (prp_req),
        .m_nvme_cmd_dispatched   (cmd_dispatched)
    );

    // PRP Manager
    nvme_prp_builder inst_nvme_prp_builder (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .s_nvme_prp_req       (prp_req_q),
        .m_nvme_prp_rsp       (prp_rsp),
        .m_prp_fault          (prp_fault),
        .m_nvme_mmu_req       (mmu_req_int),
        .s_nvme_mmu_rsp       (s_nvme_rd_rsp),
        .m_nvme_prp_write_req (prp_write_strm),
        .FPGA_BAR_BASE        (fpga_bar_base),
        .FPGA_PRP_BAR_BASE    (fpga_prp_bar_base)
    );

    // Stage 2: Combine cmd_dispatched + prp_rsp → SQE + doorbell
    nvme_sqe_builder inst_nvme_sqe_builder (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_nvme_cmd_dispatched  (cmd_dispatched),
        .s_nvme_prp_rsp (prp_rsp),
        .m_nvme_cmd_sqe  (sqe_strm),
        .m_sq_db_req    (sq_db_strm),
        .s_cmd_cid      (cmd_cid),
        .s_cmd_error    (cmd_error),
        .s_prp_fault    (prp_fault),
        .m_sqe_cid      (sqe_cid),
        .abort_valid    (abort_valid),
        .abort_dev      (abort_dev),
        .m_nvme_user_rsp(user_rsp_pre)
    );

    // SQ Controller (BRAM storage)
    nvme_sq_ctrl #(
        .SQ_ADDR_BITS (NVME_QUEUE_BITS),
        .N_NVME_BITS  (N_NVME_BITS)
    ) inst_nvme_sq_ctrl (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_sqe         (sqe_strm),
        .s_cid         (sqe_cid),
        .s_axi_nvme_sq (s_nvme_sq)
    );

    // CQ Controller (BRAM storage + polling FSM)
    nvme_cq_ctrl #(
        .CQ_ADDR_BITS  (NVME_QUEUE_BITS),
        .N_NVME_BITS   (N_NVME_BITS),
        .READ_LATENCY  (2)
    ) inst_nvme_cq_ctrl (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .queue_reset   (queue_reset),
        .queue_reset_dev(update_tbl.data.dev_id),
        .m_sq_head     (cqe_sq_head),
        .m_cid_in_range(cqe_cid_in_range),
        .m_cqe         (cqe_strm),
        .s_axi_nvme_cq (s_nvme_cq)
    );

    // PRP List Controller (BRAM storage)
    nvme_prp_ctrl inst_nvme_prp_ctrl (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_prp          (prp_write_strm),
        .s_axi_nvme_prp (s_nvme_prp)
    );

    // Config Slave (AXI-Lite register bank)
    nvme_cnfg_slave inst_nvme_cnfg_slave (
        .aclk              (aclk),
        .aresetn           (aresetn),
        .s_nvme_cnfg       (s_nvme_cnfg),
`ifdef EN_NVME_PL
        .pl_ready           (nvme_pl_ready),
        .pl_setup_done      (nvme_setup_done),
        .pl_setup_error     (nvme_setup_error),
        .pl_setup_error_code(nvme_setup_error_code),
        .pl_namespace_valid (nvme_namespace_info_valid),
        .pl_target_found    (nvme_target_nsid_found),
        .pl_nsid            (nvme_discovered_nsid),
        .pl_nsze            (nvme_discovered_nsze),
        .pl_lba_bytes       (nvme_discovered_lba_bytes),
        .pl_mdts            (nvme_discovered_mdts),
        .pl_mpsmin          (nvme_mpsmin),
`endif
        .m_update_tbl      (update_tbl),
        .m_perm_update     (perm_update),
        .fpga_bar_base     (fpga_bar_base)
    );

    // SQ Doorbell Writer
    nvme_sq_doorbell_writer inst_sq_doorbell_writer (
        .aclk         (aclk),
        .aresetn      (aresetn),
`ifdef EN_NVME_PL
        .s_sq_db_req  (pl_sq_db_strm),
`else
        .s_sq_db_req  (sq_db_strm),
`endif
        .m_dma_wr_req (sq_dma_req),
        .m_dma_wr_data(sq_dma_data)
    );

    // CQ Head Tracker
    nvme_cq_head_tracker #(
        .NVME_QUEUE_BITS (NVME_QUEUE_BITS),
        .N_NVME_BITS     (N_NVME_BITS),
        .BATCH_SIZE      (NVME_PL_FLOW ? ((NVME_QUEUE_DEPTH == 64) ? 16 : 32) : 4),
        .TIMEOUT_CYCLES  (NVME_PL_FLOW ? 1000 : 80)
    ) inst_cq_head_tracker (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .queue_reset     (queue_reset),
        .queue_reset_dev (update_tbl.data.dev_id),
        .reset_ready     (cq_reset_ready),
        .cqe_valid       (cqe_fire),
        .cqe_dev_id      (cqe_strm.data.dev_id),
        .m_cq_head_update(cq_head_upd),
        .m_cq_dma_req    (cq_dma_req),
        .m_cq_dma_data   (cq_dma_data),
`ifdef EN_NVME_PL
        // nvme_cq_head_tracker adds its fixed four-byte CQ offset, producing
        // PL_NVME_CQ_DB_ADDR from the hardcoded SQ address above.
        .sq_db_addr_tbl  (pl_sq_db_addr_tbl)
`else
        .sq_db_addr_tbl  (sq_db_addr_tbl)
`endif
    );

`ifdef EN_NVME_HOST
    // DMA Arbiter (SQ doorbell + CQ head → single host DMA channel)
    nvme_doorbell_arb inst_dma_req_mux (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_dma_req_0   (sq_dma_req),
        .s_axis_0      (sq_dma_data),
        .s_dma_req_1   (cq_dma_req),
        .s_axis_1      (cq_dma_data),
        .m_dma_req     (m_db_wr_req),
        .m_axis        (m_db_wr_data)
    );
`elsif EN_NVME_PL
    // Keep the existing SQ/CQ scheduling logic, but turn its merged DMA-style
    // doorbell request into an AXI-MM write accepted by design_plnvme.
    nvme_doorbell_arb inst_nvme_pl_doorbell_arb (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_dma_req_0   (sq_dma_req),
        .s_axis_0      (sq_dma_data),
        .s_dma_req_1   (cq_dma_req),
        .s_axis_1      (cq_dma_data),
        .m_dma_req     (pl_db_dma_req),
        .m_axis        (pl_db_dma_data)
    );

    nvme_doorbell_axi_writer inst_nvme_pl_doorbell_writer (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .setup_done    (nvme_pl_ready),
        .s_dma_req     (pl_db_dma_req),
        .s_axis_data   (pl_db_dma_data),
        .m_axi_mmio    (m_axi_nvme_mmio),
        .idle          (pl_db_idle)
    );
`endif

endmodule
