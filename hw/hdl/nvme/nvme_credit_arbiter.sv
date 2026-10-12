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
 * @brief   NVMe request arbiter (per-region credit, N_ID -> 1)
 *
 * Each region holds a credit, refilled by REFILL when none can send; a request
 * is granted only while its credit covers its length. Equalises granted bytes
 * (not request count) across regions.
 */
module nvme_credit_arbiter #(
    parameter integer N_ID      = N_REGIONS,
    parameter integer N_ID_BITS = N_REGIONS_BITS,
    parameter integer REFILL    = (1 << 17)   // credit refilled per round (bytes)
) (
    input  logic                    aclk,
    input  logic                    aresetn,

    metaIntf.s                      s_meta [N_ID],   // req_t
    metaIntf.m                      m_meta,          // req_t

    output logic [N_ID_BITS-1:0]    id_out
);

localparam integer CRED_BITS = LEN_BITS + 1;

// Unpacked per-region inputs
logic [N_ID-1:0]            valid_snk;
logic [N_ID-1:0]            ready_snk;
req_t                       data_snk [N_ID];
logic [LEN_BITS-1:0]        len_snk  [N_ID];

logic [CRED_BITS-1:0]       cred     [N_ID];
logic [N_ID-1:0]            cred_ok;
logic [N_ID_BITS-1:0]       rr_reg, vfid;
logic                       any_cred, any_valid, refill, grant_fire;

for (genvar i = 0; i < N_ID; i++) begin : gen_io
    assign valid_snk[i]    = s_meta[i].valid;
    assign data_snk[i]     = s_meta[i].data;
    assign len_snk[i]      = data_snk[i].len;
    assign s_meta[i].ready = ready_snk[i];
end

// A region can send while its credit covers the head command length
always_comb begin
    for (int i = 0; i < N_ID; i++)
        cred_ok[i] = valid_snk[i] && (cred[i] >= len_snk[i]);
end

assign any_cred  = |cred_ok;
assign any_valid = |valid_snk;
assign refill    = any_valid && !any_cred;

// Round-robin pick among regions with credit
always_comb begin
    ready_snk = '0;
    vfid      = rr_reg;

    for (int i = 0; i < N_ID; i++) begin
        if (i + rr_reg >= N_ID) begin
            if (cred_ok[i + rr_reg - N_ID]) begin
                vfid = i + rr_reg - N_ID;
                break;
            end
        end
        else begin
            if (cred_ok[i + rr_reg]) begin
                vfid = i + rr_reg;
                break;
            end
        end
    end

    m_meta.valid    = any_cred;
    m_meta.data     = data_snk[vfid];
    ready_snk[vfid] = any_cred && m_meta.ready;
end

assign grant_fire = m_meta.valid && m_meta.ready;
assign id_out     = vfid;

// Spend credit on grant; refill all senders when none can send
always_ff @(posedge aclk) begin
    if (!aresetn) begin
        rr_reg <= '0;
        for (int i = 0; i < N_ID; i++)
            cred[i] <= '0;
    end
    else begin
        if (grant_fire)
            rr_reg <= (rr_reg >= N_ID - 1) ? '0 : rr_reg + 1;

        for (int i = 0; i < N_ID; i++) begin
            if (refill && valid_snk[i])
                cred[i] <= cred[i] + REFILL;
            else if (grant_fire && (i == vfid))
                cred[i] <= cred[i] - len_snk[i];
        end
    end
end

endmodule
