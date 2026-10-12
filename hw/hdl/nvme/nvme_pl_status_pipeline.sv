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

/**
 * @brief Pipeline the PL-NVMe discovery result before it crosses into nvme_top.
 *
 * The block-design setup FSM holds these values after setup completes. Keeping
 * every field in one uniformly pipelined record preserves their association and
 * breaks the long route from the PCIe block design to the shell configuration
 * registers. The final ready bit is deliberately stricter than setup_done: the
 * namespace must also have been identified successfully.
 */
module nvme_pl_status_pipeline #(
    parameter int unsigned PIPE_STAGES = 3
) (
    input  logic        aclk,
    input  logic        aresetn,

    input  logic        s_setup_done,
    input  logic        s_setup_error,
    input  logic [7:0]  s_setup_error_code,
    input  logic        s_namespace_info_valid,
    input  logic        s_target_nsid_found,
    input  logic [31:0] s_nsid,
    input  logic [63:0] s_nsze,
    input  logic [31:0] s_lba_bytes,
    input  logic [7:0]  s_mdts,
    input  logic [3:0]  s_mpsmin,

    output logic        m_ready,
    output logic        m_setup_done,
    output logic        m_setup_error,
    output logic [7:0]  m_setup_error_code,
    output logic        m_namespace_info_valid,
    output logic        m_target_nsid_found,
    output logic [31:0] m_nsid,
    output logic [63:0] m_nsze,
    output logic [31:0] m_lba_bytes,
    output logic [7:0]  m_mdts,
    output logic [3:0]  m_mpsmin
);

    typedef struct packed {
        logic        setup_done;
        logic        setup_error;
        logic [7:0]  setup_error_code;
        logic        namespace_info_valid;
        logic        target_nsid_found;
        logic [31:0] nsid;
        logic [63:0] nsze;
        logic [31:0] lba_bytes;
        logic [7:0]  mdts;
        logic [3:0]  mpsmin;
    } pl_nvme_status_t;

    (* shreg_extract = "no" *) pl_nvme_status_t status_pipe [PIPE_STAGES];

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int i = 0; i < PIPE_STAGES; i++)
                status_pipe[i] <= '0;
        end
        else begin
            status_pipe[0].setup_done          <= s_setup_done;
            status_pipe[0].setup_error         <= s_setup_error;
            status_pipe[0].setup_error_code    <= s_setup_error_code;
            status_pipe[0].namespace_info_valid <= s_namespace_info_valid;
            status_pipe[0].target_nsid_found   <= s_target_nsid_found;
            status_pipe[0].nsid                <= s_nsid;
            status_pipe[0].nsze                <= s_nsze;
            status_pipe[0].lba_bytes           <= s_lba_bytes;
            status_pipe[0].mdts                <= s_mdts;
            status_pipe[0].mpsmin              <= s_mpsmin;

            for (int i = 1; i < PIPE_STAGES; i++)
                status_pipe[i] <= status_pipe[i-1];
        end
    end

    always_comb begin
        m_setup_done           = status_pipe[PIPE_STAGES-1].setup_done;
        m_setup_error          = status_pipe[PIPE_STAGES-1].setup_error;
        m_setup_error_code     = status_pipe[PIPE_STAGES-1].setup_error_code;
        m_namespace_info_valid = status_pipe[PIPE_STAGES-1].namespace_info_valid;
        m_target_nsid_found    = status_pipe[PIPE_STAGES-1].target_nsid_found;
        m_nsid                 = status_pipe[PIPE_STAGES-1].nsid;
        m_nsze                 = status_pipe[PIPE_STAGES-1].nsze;
        m_lba_bytes            = status_pipe[PIPE_STAGES-1].lba_bytes;
        m_mdts                 = status_pipe[PIPE_STAGES-1].mdts;
        m_mpsmin               = status_pipe[PIPE_STAGES-1].mpsmin;
        m_ready                = m_setup_done && !m_setup_error &&
                                 m_namespace_info_valid && m_target_nsid_found;
    end

`ifndef SYNTHESIS
    initial begin
        assert (PIPE_STAGES > 0)
            else $fatal(1, "nvme_pl_status_pipeline requires PIPE_STAGES > 0");
    end
`endif

endmodule
