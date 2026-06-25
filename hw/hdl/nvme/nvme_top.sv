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
    metaIntf.m          m_nvme_user_rsp [N_REGIONS],  // logic[15:0] (error code)
    metaIntf.m          m_nvme_cpl      [N_REGIONS],  // nvme_cqe_t

    // MMU interface (req_t with strm=STRM_NVME → bpss_rd_sq path)
    metaIntf.m          m_nvme_rd_sq,     // req_t
    metaIntf.s          s_nvme_rd_rsp,    // nvme_mmu_rsp_t

    // Doorbell DMA write (merged upstream via arbiter)
    dmaIntf.m           m_db_wr_req,
    AXI4S.m             m_db_wr_data,

    // Single AXI interfaces (from BD interconnect)
    AXI4L.s             s_nvme_cnfg,
    AXI4.s              s_nvme_prp,
    AXI4.s              s_nvme_sq,
    AXI4.s              s_nvme_cq
);

    // Constants
    localparam logic [63:0] PRP_OFFSET = 64'h0480_0000;
    localparam int unsigned N_NVME     = (1 << N_NVME_BITS);

    // Config signals
    logic [63:0] fpga_bar_base;
    logic [63:0] fpga_prp_bar_base;
    assign fpga_prp_bar_base = fpga_bar_base + PRP_OFFSET;

    // Arbitrated user interfaces (N_REGIONS → 1)
    metaIntf #(.STYPE(req_t)) user_req_arb   ();
    metaIntf #(.STYPE(req_t)) user_req_arb_q ();
    // Per-(region,device) NVMe outstanding credits + CID->region map for completion routing
    logic [7:0]                 credit_cnt [N_REGIONS][N_NVME];
    logic [N_REGIONS_BITS-1:0]  cid_region [N_NVME][1 << NVME_QUEUE_BITS];

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

    metaIntf #(.STYPE(sq_db_req_t))        sq_db_strm    ();
    metaIntf #(.STYPE(update_tbl_t))       update_tbl    ();
    metaIntf #(.STYPE(nvme_perm_update_t)) perm_update   ();
    metaIntf #(.STYPE(cq_head_update_t))   cq_head_upd   ();
    metaIntf #(.STYPE(req_t))              mmu_req_int   ();

    metaIntf #(.STYPE(nvme_user_rsp_t))    user_rsp_pre  ();

    dmaIntf sq_dma_req ();
    dmaIntf cq_dma_req ();
    AXI4S   sq_dma_data (.aclk(aclk));
    AXI4S   cq_dma_data (.aclk(aclk));

    // Per-device doorbell address table
    logic [63:0] sq_db_addr_tbl [N_NVME];

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int d = 0; d < N_NVME; d++)
                sq_db_addr_tbl[d] <= '0;
        end
        else if (update_tbl.valid && update_tbl.ready) begin
            sq_db_addr_tbl[update_tbl.data.dev_id] <= update_tbl.data.sq_db_addr;
        end
    end

    // Per-region credit check + N_REGIONS → 1 arbiter
    metaIntf #(.STYPE(req_t)) user_req_arb_pre ();
    metaIntf #(.STYPE(req_t)) user_req_cred [N_REGIONS] ();
    logic [N_REGIONS_BITS-1:0] arb_id;

    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_user_req_cred
        wire cred_ok = credit_cnt[i][s_nvme_user_req[i].data.dev_id] < NVME_N_OUTSTANDING;
        assign user_req_cred[i].valid  = s_nvme_user_req[i].valid && cred_ok;
        assign user_req_cred[i].data   = s_nvme_user_req[i].data;
        assign s_nvme_user_req[i].ready = user_req_cred[i].ready && cred_ok;
    end

    meta_arbiter #(
        .N_ID(N_REGIONS),
        .N_ID_BITS(N_REGIONS_BITS),
        .DATA_BITS($bits(req_t))
    ) inst_user_req_arb (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_meta(user_req_cred),
        .m_meta(user_req_arb_pre),
        .id_out(arb_id)
    );

    always_comb begin
        user_req_arb.valid       = user_req_arb_pre.valid;
        user_req_arb.data        = user_req_arb_pre.data;
        user_req_arb.data.vfid   = arb_id;
        user_req_arb_pre.ready   = user_req_arb.ready;
    end

    // Per-(region,device) credit: ++ on grant, -- on response drain
    logic [N_REGIONS-1:0]   cpl_pop, rsp_pop;
    logic [N_NVME_BITS-1:0] cpl_dev [N_REGIONS];
    logic [N_NVME_BITS-1:0] rsp_dev [N_REGIONS];
    wire grant_fire = user_req_arb.valid && user_req_arb.ready;

    // CID → region map (CID = sq_tail), written when a command is dispatched to the SQ.
    always_ff @(posedge aclk) begin
        if (cmd_dispatched.valid && cmd_dispatched.ready)
            cid_region[cmd_dispatched.data.dev_id][cmd_dispatched.data.sq_tail] <= cmd_dispatched.data.vfid;
    end

    // Completion routing: cqe → owning region (via CID map) → per-region FIFO
    metaIntf #(.STYPE(nvme_cqe_t)) cpl_fin [N_REGIONS] ();
    logic [N_REGIONS-1:0] cpl_fin_rdy;
    wire [N_REGIONS_BITS-1:0] cpl_region = cid_region[cqe_strm.data.dev_id][cqe_strm.data.cid];

    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_cpl_route
        assign cpl_fin[i].valid = cqe_strm.valid && (cpl_region == i);
        assign cpl_fin[i].data  = cqe_strm.data;
        assign cpl_fin_rdy[i]   = cpl_fin[i].ready;
        queue_meta #(.QDEPTH(NVME_N_OUTSTANDING*N_NVME)) inst_cpl_fifo (.aclk(aclk), .aresetn(aresetn), .s_meta(cpl_fin[i]), .m_meta(m_nvme_cpl[i]));
        assign cpl_pop[i] = m_nvme_cpl[i].valid && m_nvme_cpl[i].ready;
        assign cpl_dev[i] = m_nvme_cpl[i].data.dev_id;
    end
    assign cqe_strm.ready = cpl_fin_rdy[cpl_region];

    // Error response routing: user_rsp → owning region (via vfid) → per-region FIFO
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
        assign rsp_pop[i] = rsp_out[i].valid && rsp_out[i].ready;
        assign rsp_dev[i] = rsp_out[i].data.dev_id;
    end
    assign user_rsp_pre.ready = rsp_fin_rdy[rsp_region];

    // Per-(region,device) credit counter update
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
        .s_cq_head_update(cq_head_upd),
        .s_update_tbl    (update_tbl),
        .s_perm_update   (perm_update)
    );

    // Stage 1: Lookup info table, generate PRP request
    nvme_prp_dispatch inst_nvme_prp_dispatch (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_nvme_cmd_parsed   (cmd_parsed),
        .s_nvme_info_rsp (tbl_rsp),
        .m_nvme_user_rsp (user_rsp_pre),
        .m_nvme_prp_req  (prp_req),
        .m_nvme_cmd_dispatched   (cmd_dispatched)
    );

    // PRP Manager
    nvme_prp_builder inst_nvme_prp_builder (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .s_nvme_prp_req       (prp_req_q),
        .m_nvme_prp_rsp       (prp_rsp),
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
        .m_sq_db_req    (sq_db_strm)
    );

    // SQ Controller (BRAM storage)
    nvme_sq_ctrl #(
        .SQ_ADDR_BITS (6),
        .N_NVME_BITS  (N_NVME_BITS)
    ) inst_nvme_sq_ctrl (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_sqe         (sqe_strm),
        .s_axi_nvme_sq (s_nvme_sq)
    );

    // CQ Controller (BRAM storage + polling FSM)
    nvme_cq_ctrl #(
        .CQ_ADDR_BITS  (6),
        .READ_LATENCY  (1)
    ) inst_nvme_cq_ctrl (
        .aclk          (aclk),
        .aresetn       (aresetn),
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
        .m_update_tbl      (update_tbl),
        .m_perm_update     (perm_update),
        .fpga_bar_base     (fpga_bar_base)
    );

    // SQ Doorbell Writer
    nvme_sq_doorbell_writer inst_sq_doorbell_writer (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .s_sq_db_req  (sq_db_strm),
        .m_dma_wr_req (sq_dma_req),
        .m_dma_wr_data(sq_dma_data)
    );

    // CQ Head Tracker
    nvme_cq_head_tracker #(
        .NVME_QUEUE_BITS (6),
        .N_NVME_BITS     (N_NVME_BITS),
        .BATCH_SIZE      (4),
        .TIMEOUT_CYCLES  (80)
    ) inst_cq_head_tracker (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .cqe_valid       (cqe_strm.valid && cqe_strm.ready),
        .cqe_dev_id      (cqe_strm.data.dev_id),
        .m_cq_head_update(cq_head_upd),
        .m_cq_dma_req    (cq_dma_req),
        .m_cq_dma_data   (cq_dma_data),
        .sq_db_addr_tbl  (sq_db_addr_tbl)
    );

    // DMA Arbiter (SQ doorbell + CQ head → single DMA channel)
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

endmodule
