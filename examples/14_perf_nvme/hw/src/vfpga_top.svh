/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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

/**
 * NVMe SSD bandwidth test: per-device FSMs issue commands through a round-robin
 * arbiter into the shared NVMe queue; SW polls bench_done for completion.
 */

import lynxTypes::*;

localparam int BENCH_MAX_DEVS = 4;
localparam int DEV_BITS = $clog2(BENCH_MAX_DEVS);

///////////////////////////////////////
//          CSR INTERFACE           //
/////////////////////////////////////
logic [1:0]               bench_ctrl;
logic [VADDR_BITS-1:0]    bench_vaddr;
logic [31:0]              bench_chunk_size;
logic [31:0]              bench_n_reps;
logic [63:0]              bench_lba;
logic [15:0]              bench_dev_mask;
logic [63:0]              bench_nsid;
logic [31:0]              bench_max_outstanding;

logic [31:0]              bench_sent;
logic [31:0]              bench_done;
logic [63:0]              bench_timer;
logic [15:0]              last_error;

perf_nvme_axi_ctrl_parser inst_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .bench_ctrl(bench_ctrl),
    .bench_vaddr(bench_vaddr),
    .bench_chunk_size(bench_chunk_size),
    .bench_n_reps(bench_n_reps),
    .bench_lba(bench_lba),
    .bench_dev_mask(bench_dev_mask),
    .bench_nsid(bench_nsid),
    .bench_max_outstanding(bench_max_outstanding),
    .bench_sent(bench_sent),
    .bench_done(bench_done),
    .bench_timer(bench_timer),
    .last_error(last_error)
);

///////////////////////////////////////
//           GO PULSE               //
/////////////////////////////////////
// A single-cycle pulse on either CTRL bit (W1S in the parser) starts a new run
logic go_q;
wire  go_pulse = (bench_ctrl[0] | bench_ctrl[1]) & ~go_q;

always_ff @(posedge aclk) begin
    if (!aresetn) go_q <= 1'b0;
    else          go_q <= bench_ctrl[0] | bench_ctrl[1];
end

///////////////////////////////////////
//      LATCHED PARAMETERS          //
/////////////////////////////////////
// Snapshot the CSRs on go_pulse
logic [VADDR_BITS-1:0]      latch_vaddr;
logic [63:0]                latch_lba;
logic [31:0]                latch_chunk_size;
logic [31:0]                latch_n_reps;
logic [31:0]                latch_max_outstanding;
logic                       latch_wr;
logic [BENCH_MAX_DEVS-1:0]  latch_dev_mask;
logic [NSID_BITS-1:0]       latch_nsid;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        latch_vaddr           <= '0;
        latch_lba             <= '0;
        latch_chunk_size      <= '0;
        latch_n_reps          <= '0;
        latch_max_outstanding <= '0;
        latch_wr              <= 1'b0;
        latch_dev_mask        <= '0;
        latch_nsid            <= '0;
    end
    else if (go_pulse) begin
        latch_vaddr           <= bench_vaddr;
        latch_lba             <= bench_lba;
        latch_chunk_size      <= bench_chunk_size;
        latch_n_reps          <= bench_n_reps;
        latch_max_outstanding <= bench_max_outstanding;
        latch_wr              <= bench_ctrl[1];
        latch_dev_mask        <= bench_dev_mask[BENCH_MAX_DEVS-1:0];
        latch_nsid            <= bench_nsid[NSID_BITS-1:0];
    end
end

///////////////////////////////////////
//       PER-DEVICE FSM             //
/////////////////////////////////////
typedef enum logic [1:0] {
    DEV_IDLE = 2'd0,
    DEV_RUN  = 2'd1,
    DEV_DONE = 2'd2
} dev_state_t;

dev_state_t              dev_state    [BENCH_MAX_DEVS];
logic [VADDR_BITS-1:0]   dev_vaddr    [BENCH_MAX_DEVS];
logic [63:0]             dev_offset   [BENCH_MAX_DEVS];
logic [31:0]             dev_sent     [BENCH_MAX_DEVS];
logic [31:0]             dev_done     [BENCH_MAX_DEVS];
logic [31:0]             dev_inflight [BENCH_MAX_DEVS];
logic [63:0]             dev_timer    [BENCH_MAX_DEVS];

// Per-device request to the round-robin arbiter
logic                    dev_req_valid [BENCH_MAX_DEVS];
req_t                    dev_req       [BENCH_MAX_DEVS];
logic                    dev_req_grant [BENCH_MAX_DEVS];

generate
for (genvar d = 0; d < BENCH_MAX_DEVS; d++) begin : gen_dev

    wire req_accepted = dev_req_valid[d] && dev_req_grant[d];
    wire cpl_for_me   = s_nvme_cpl.valid && s_nvme_cpl.ready &&
                        (s_nvme_cpl.data.dev_id[DEV_BITS-1:0] == d[DEV_BITS-1:0]);

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            dev_state[d]     <= DEV_IDLE;
            dev_vaddr[d]     <= '0;
            dev_offset[d]    <= '0;
            dev_sent[d]      <= '0;
            dev_done[d]      <= '0;
            dev_inflight[d]  <= '0;
            dev_timer[d]     <= '0;
            dev_req_valid[d] <= 1'b0;
            dev_req[d]       <= '0;
        end
        else begin
            // Clear req valid on grant
            if (req_accepted) begin
                dev_req_valid[d] <= 1'b0;
            end

            // go_pulse: priority reset + start on all devices in the mask
            if (go_pulse) begin
                dev_vaddr[d]     <= bench_vaddr;
                dev_offset[d]    <= bench_lba;
                dev_sent[d]      <= '0;
                dev_done[d]      <= '0;
                dev_inflight[d]  <= '0;
                dev_timer[d]     <= '0;
                dev_req_valid[d] <= 1'b0;
                dev_state[d]     <= bench_dev_mask[d] ? DEV_RUN : DEV_IDLE;
            end
            else begin
                case (dev_state[d])
                    DEV_IDLE: ;

                    DEV_RUN: begin
                        dev_timer[d] <= dev_timer[d] + 1;

                        // Inflight counter: +1 on issue, -1 on completion
                        if (req_accepted && !cpl_for_me) begin
                            dev_inflight[d] <= dev_inflight[d] + 1;
                        end
                        else if (!req_accepted && cpl_for_me) begin
                            dev_inflight[d] <= dev_inflight[d] - 1;
                        end

                        // Issue next command while below the outstanding cap
                        if (!dev_req_valid[d] &&
                            dev_sent[d] < latch_n_reps &&
                            dev_inflight[d] < latch_max_outstanding) begin
                            dev_req[d]           <= '0;
                            dev_req[d].strm      <= STRM_NVME;
                            dev_req[d].vfid      <= '0;
                            dev_req[d].last      <= 1'b1;
                            dev_req[d].vaddr     <= dev_vaddr[d];
                            dev_req[d].len       <= latch_chunk_size;
                            dev_req[d].naddr     <= dev_offset[d];
                            dev_req[d].dev_id    <= d[DEV_BITS-1:0];
                            dev_req[d].nsid      <= latch_nsid;
                            dev_req[d].writeRead <= latch_wr;
                            dev_req_valid[d]     <= 1'b1;
                        end

                        // Advance buffer pointer + LBA offset on accepted request
                        if (req_accepted) begin
                            dev_sent[d]   <= dev_sent[d] + 1;
                            dev_vaddr[d]  <= dev_vaddr[d] + latch_chunk_size;
                            dev_offset[d] <= dev_offset[d] + latch_chunk_size;
                        end

                        // Count completions targeting this device
                        if (cpl_for_me) begin
                            dev_done[d] <= dev_done[d] + 1;
                        end

                        // All commands accounted for; freeze the timer
                        if (dev_done[d] >= latch_n_reps && dev_inflight[d] == 0) begin
                            dev_state[d] <= DEV_DONE;
                        end
                    end

                    DEV_DONE: ;

                    default: dev_state[d] <= DEV_IDLE;
                endcase
            end
        end
    end

end
endgenerate

///////////////////////////////////////
//   ROUND-ROBIN ARBITER (N -> 1)   //
/////////////////////////////////////
logic [DEV_BITS-1:0] arb_last;
logic [DEV_BITS-1:0] arb_sel;
logic                arb_found;

always_comb begin
    arb_found = 1'b0;
    arb_sel   = arb_last;
    for (int i = 1; i <= BENCH_MAX_DEVS; i++) begin
        if (!arb_found) begin
            automatic logic [DEV_BITS-1:0] idx = arb_last + i[DEV_BITS-1:0];
            if (dev_req_valid[idx]) begin
                arb_found = 1'b1;
                arb_sel   = idx;
            end
        end
    end
end

always_ff @(posedge aclk) begin
    if (!aresetn)                                arb_last <= '0;
    else if (arb_found && m_nvme_sq.ready)       arb_last <= arb_sel;
end

generate
for (genvar d = 0; d < BENCH_MAX_DEVS; d++) begin : gen_grant
    assign dev_req_grant[d] = arb_found && (arb_sel == d[DEV_BITS-1:0]) && m_nvme_sq.ready;
end
endgenerate

///////////////////////////////////////
//   AGGREGATION (2-stage pipe)     //
/////////////////////////////////////
// Two register stages on the cross-device reduction

logic [63:0] masked_timer [BENCH_MAX_DEVS];
logic [31:0] masked_sent  [BENCH_MAX_DEVS];
logic [31:0] masked_done  [BENCH_MAX_DEVS];

always_comb begin
    for (int d = 0; d < BENCH_MAX_DEVS; d++) begin
        masked_timer[d] = latch_dev_mask[d] ? dev_timer[d] : '0;
        masked_sent[d]  = latch_dev_mask[d] ? dev_sent[d]  : '0;
        masked_done[d]  = latch_dev_mask[d] ? dev_done[d]  : '0;
    end
end

logic [63:0] max_s1_01, max_s1_23;
logic [31:0] sent_s1_01, sent_s1_23;
logic [31:0] done_s1_01, done_s1_23;

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        max_s1_01  <= '0; max_s1_23  <= '0;
        sent_s1_01 <= '0; sent_s1_23 <= '0;
        done_s1_01 <= '0; done_s1_23 <= '0;
    end
    else begin
        max_s1_01  <= (masked_timer[0] > masked_timer[1]) ? masked_timer[0] : masked_timer[1];
        max_s1_23  <= (masked_timer[2] > masked_timer[3]) ? masked_timer[2] : masked_timer[3];
        sent_s1_01 <= masked_sent[0] + masked_sent[1];
        sent_s1_23 <= masked_sent[2] + masked_sent[3];
        done_s1_01 <= masked_done[0] + masked_done[1];
        done_s1_23 <= masked_done[2] + masked_done[3];
    end
end

always_ff @(posedge aclk) begin
    if (!aresetn) begin
        bench_timer <= '0;
        bench_sent  <= '0;
        bench_done  <= '0;
    end
    else begin
        bench_timer <= (max_s1_01 > max_s1_23) ? max_s1_01 : max_s1_23;
        bench_sent  <= sent_s1_01 + sent_s1_23;
        bench_done  <= done_s1_01 + done_s1_23;
    end
end

// Sticky error capture; cleared on next go pulse
always_ff @(posedge aclk) begin
    if (!aresetn)                                                last_error <= '0;
    else if (go_pulse)                                           last_error <= '0;
    else if (s_nvme_cq_rsp.valid && s_nvme_cq_rsp.data != 16'h0) last_error <= s_nvme_cq_rsp.data;
end

///////////////////////////////////////
//      COMBINATIONAL OUTPUTS       //
/////////////////////////////////////
always_comb begin
    m_nvme_sq.valid   = arb_found;
    m_nvme_sq.data    = dev_req[arb_sel];

    s_nvme_cq_rsp.ready = 1'b1;
    s_nvme_cpl.ready    = 1'b1;
end

///////////////////////////////////////
//       TIE OFF UNUSED IFs         //
/////////////////////////////////////
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

always_comb begin
    axis_host_recv[0].tready = 1'b1;
    axis_host_send[0].tvalid = 1'b0;
    axis_host_send[0].tdata  = '0;
    axis_host_send[0].tkeep  = '0;
    axis_host_send[0].tlast  = 1'b0;
end

///////////////////////////////////////
//       ILA FOR DEBUGGING          //
/////////////////////////////////////
ila_perf_nvme inst_ila_perf_nvme (
    .clk    (aclk),
    .probe0 ({dev_state[3], dev_state[2], dev_state[1], dev_state[0]}),  // 8
    .probe1 (bench_ctrl),                                                 // 2
    .probe2 (bench_sent),                                                 // 32
    .probe3 (bench_done),                                                 // 32
    .probe4 (arb_found),                                                  // 1
    .probe5 (arb_sel),                                                    // 2
    .probe6 (m_nvme_sq.valid),                                            // 1
    .probe7 (m_nvme_sq.ready),                                            // 1
    .probe8 (s_nvme_cpl.valid),                                           // 1
    .probe9 (s_nvme_cpl.data.dev_id),                                     // N_NVME_BITS = 4
    .probe10(bench_timer[31:0]),                                          // 32
    .probe11(last_error),                                                 // 16
    .probe12(s_nvme_cq_rsp.valid),                                        // 1
    .probe13(s_nvme_cq_rsp.data),                                         // 16
    .probe14(latch_dev_mask[BENCH_MAX_DEVS-1:0]),                         // 4
    .probe15(go_pulse)                                                    // 1
);
