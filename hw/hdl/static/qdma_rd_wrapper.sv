/*
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

import lynxTypes::*;

module qdma_rd_wrapper #(
    parameter integer N_CHAN = 1
) (
    input logic         aclk,
    input logic         aresetn,

    dmaIntf.s           s_dma_rd [N_CHAN],
    qdmaH2CIntf.m       m_qdma_h2c_cmd,
    qdmaH2CSts.s        s_qdma_h2c_sts,

    qdmaH2CS.s          qdma_out,
    AXI4S.m             dyn_out [N_CHAN]
);

///////////////////////////////////////////
//              COMMAND                 //
//////////////////////////////////////////

localparam integer N_CHAN_BITS = clog2s(N_CHAN);

// Round robin arbitration, ensuring each of the channels can fairly issue H2C transfers
logic [N_CHAN_BITS-1:0] rr_reg = 0;
always_ff @(posedge aclk) begin
	if (aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if (dma_rd_actv.valid & dma_rd_actv.ready) begin 
            if (rr_reg == N_CHAN - 1) begin
                rr_reg <= 0;
            end else begin
                rr_reg <= rr_reg + 1;
            end
        end
	end
end

// Find active interface and assign to QDMA interface
dmaIntf dma_rd_actv ();
logic [N_CHAN_BITS-1:0] actv_idx;

// Extract the fields of s_dma_rd to simple logic types so they can be used in the loops below
logic [N_CHAN-1:0] s_dma_rd_valids;
logic [N_CHAN-1:0] s_dma_rd_readys;
dma_req_t [N_CHAN-1:0] s_dma_rd_reqs;

for (genvar i = 0; i < N_CHAN; i++) begin
    assign s_dma_rd_reqs[i]     = s_dma_rd[i].req;
    assign s_dma_rd_valids[i]   = s_dma_rd[i].valid;

    assign s_dma_rd[i].ready    = s_dma_rd_readys[i];

    // Read (H2C) completed, per Tables 77/79 in QDMA specification
    assign s_dma_rd[i].rsp.done = 
        s_qdma_h2c_sts.valid && 
        (s_qdma_h2c_sts.qid == (QDMA_RD_QUEUE_START_IDX + i)) &&        // Each channel translates to a queue
        (s_qdma_h2c_sts.port_id == 0) &&                                // We always set port_id to 0 anyway    
        (s_qdma_h2c_sts.op == 8'h1) &&                                  // OP should match H2C-ST, per Table 77
        !s_qdma_h2c_sts.data[16];                                       // Error bit per Table 79
end

always_comb begin
    actv_idx = 0;
    dma_rd_actv.valid = 1'b0;
    s_dma_rd_readys = 0;

    // Find the next channel for DMA, based on RR arbitration
    for (int i = 0; i < N_CHAN; i++) begin
        if (i + rr_reg >= N_CHAN) begin
            if (s_dma_rd_valids[i + rr_reg - N_CHAN]) begin
                dma_rd_actv.valid = s_dma_rd_valids[i + rr_reg - N_CHAN];
                actv_idx = i + rr_reg - N_CHAN;
                break;
            end
        end
        else begin
            if (s_dma_rd_valids[i + rr_reg]) begin
                dma_rd_actv.valid = s_dma_rd_valids[i + rr_reg];
                actv_idx = i + rr_reg;
                break;
            end
        end
    end
    
    // Assign the found channel the "active" interface
    s_dma_rd_readys[actv_idx]   = dma_rd_actv.ready;
    dma_rd_actv.req             = s_dma_rd_reqs[actv_idx];
    
    // Assign QDMA interfaces
    m_qdma_h2c_cmd.req.addr     = dma_rd_actv.req.paddr;
    m_qdma_h2c_cmd.req.len      = dma_rd_actv.req.len[15:0];

    // NOTE: Unlike for writes, using a single queue for reads is sufficient to achieve line rate
    // Additionally, using multiple queues for reads could (?) lead to out-of-order delivery of data
    // Hence, for now, each shell channel maps to a single (but different) QDMA read queue
    m_qdma_h2c_cmd.req.qid      = QDMA_RD_QUEUE_START_IDX + actv_idx;

    // Set mrkr_req to 1 as we want a completion for every descriptor/command
    // mrkr_req is only acknowledged when EOP = 1, so each packet is then SOP and EOP
    m_qdma_h2c_cmd.req.sop      = 1;
    m_qdma_h2c_cmd.req.eop      = 1;
    m_qdma_h2c_cmd.req.mrkr_req = 1;

    // Handshake signals
    m_qdma_h2c_cmd.valid        = dma_rd_actv.valid;
    dma_rd_actv.ready           = m_qdma_h2c_cmd.ready;

    // Always constant
    m_qdma_h2c_cmd.req.func     = 0;    // Coyote only supports one PF (for now...)
    m_qdma_h2c_cmd.req.error    = 0;    // Assume data and command (coming from the shell) are well-formed, so no error
    m_qdma_h2c_cmd.req.no_dma   = 0;    // Set when no PCIe request is to be issued --- UNUSED
    m_qdma_h2c_cmd.req.sdi      = 0;    // For raising completion interrupts to the driver --- UNUSED
    m_qdma_h2c_cmd.req.port_id  = 0;    // port_id offers even finer granularity than qid --- UNUSED
    m_qdma_h2c_cmd.req.cidx     = 0;    // Completion index; used for QDMA driver-side descriptor updates --- UNUSED

end

///////////////////////////////////////////
//                DATA                  //
//////////////////////////////////////////

localparam integer TKEEP_WIDTH = AXI_DATA_BITS / 8;

// Extract the fields of dyn_out to simple logic types so they can be used in the loops below
logic [N_CHAN-1:0] dyn_out_tvalids;
logic [N_CHAN-1:0] dyn_out_treadys;
logic [N_CHAN-1:0] dyn_out_tlasts;
logic [N_CHAN-1:0][AXI_DATA_BITS-1:0] dyn_out_tdatas;
logic [N_CHAN-1:0][TKEEP_WIDTH-1:0] dyn_out_tkeeps;

for (genvar i = 0; i < N_CHAN; i++) begin
    assign dyn_out[i].tvalid  = dyn_out_tvalids[i];
    assign dyn_out[i].tlast   = dyn_out_tlasts[i];
    assign dyn_out[i].tdata   = dyn_out_tdatas[i];
    assign dyn_out[i].tkeep   = dyn_out_tkeeps[i];
    assign dyn_out_treadys[i] = dyn_out[i].tready;
end

// Route QDMA output to the correct dynamic output channel based on QID
always_comb begin
    qdma_out.tready = 1'b0;

    for (int i = 0; i < N_CHAN; i++) begin
        dyn_out_tvalids[i] = qdma_out.tvalid && (qdma_out.payload.qid == (i + QDMA_RD_QUEUE_START_IDX)) && !qdma_out.payload.err && !qdma_out.payload.zero_byte;
        if (dyn_out_tvalids[i] && dyn_out_treadys[i]) begin
            qdma_out.tready = 1'b1;
        end
        
        dyn_out_tdatas[i] = (dyn_out_tvalids[i] && dyn_out_treadys[i]) ? qdma_out.payload.tdata : 0;
        dyn_out_tlasts[i] = (dyn_out_tvalids[i] && dyn_out_treadys[i]) ? qdma_out.tlast : 0;
        dyn_out_tkeeps[i] = dyn_out_tlasts[i] ? ( {TKEEP_WIDTH{1'b1}} >> qdma_out.payload.mty ) : ~0; 
    end
end

endmodule