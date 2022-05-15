/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   TLB controller utilizing one of the XDMA channels for fast pull mappings.
 *
 * Pulls the VA -> PA mappings from the host memory.
 *
 *  @param TLB_ORDER    Size of the TLBs
 *  @param PG_BITS      Number of page size bits
 *  @param N_ASSOC      Set associativity
 */
module tlb_controller #(
  parameter integer TLB_ORDER = 10,
  parameter integer PG_BITS = 12,
  parameter integer N_ASSOC = 4,
  parameter integer DBG_L = 0,
  parameter integer DBG_S = 0
) (
  input  logic              aclk,
  input  logic              aresetn,

  AXI4S.s                   s_axis,
  tlbIntf.s                 TLB,
  output logic              done_map
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_ASSOC_BITS = $clog2(N_ASSOC);

localparam integer HASH_BITS = TLB_ORDER;
localparam integer PHY_BITS = PADDR_BITS - PG_BITS;
localparam integer TAG_BITS = VADDR_BITS - TLB_ORDER - PG_BITS;
localparam integer TLB_VAL_BIT = TAG_BITS + PID_BITS;

localparam integer TLB_SIZE = 2**TLB_ORDER;
localparam integer TLB_IDX_BITS = $clog2(N_ASSOC);

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_WAIT, ST_COMP} state_t;
logic [1:0] state_C, state_N;

// -- Internal
AXI4S axis_fifo_out ();
AXI4S #(.AXI4S_DATA_BITS(AXI_TLB_BITS)) axis_s0 ();
logic [AXI_TLB_BITS-1:0] data_C, data_N;
logic last_C, last_N;

logic [N_ASSOC-1:0][TLB_DATA_BITS/8-1:0] tlb_wr_en;
logic [N_ASSOC-1:0][TLB_DATA_BITS-1:0] tlb_data_upd_in;
logic [N_ASSOC-1:0][TLB_DATA_BITS-1:0] tlb_data_upd_out;
logic [N_ASSOC-1:0][TLB_DATA_BITS-1:0] tlb_data_lup;
logic done_C, done_N;

logic [N_ASSOC-1:0] tag_cmp;
logic [TLB_IDX_BITS-1:0] hit_idx;

logic [N_ASSOC_BITS-1:0] nxt_insert_C, nxt_insert_N;
logic [N_ASSOC_BITS-1:0] entry_insert_fe, entry_insert_se;
logic [1:0] entry_insert_min;
logic [1:0] curr_ref;
logic filled;

`ifdef EN_NRU
logic [N_ASSOC-1:0][TLB_SIZE-1:0] ref_r_C, ref_r_N; 
logic [N_ASSOC-1:0][TLB_SIZE-1:0] ref_m_C, ref_m_N; 
logic [31:0] tmr_clr;
logic tmr_clr_valid;

logic [TLB_ORDER-1:0] addr_C, addr_N;
logic wr_C, wr_N;
logic [1:0] val_C, val_N;
logic [TLB_ORDER-1:0] hit_addr_C, hit_addr_N;
logic hit_wr_C, hit_wr_N;
logic hit_val_C, hit_val_N;
logic [TLB_IDX_BITS-1:0] hit_idx_C, hit_idx_N;
`endif

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// Queueing
axis_data_fifo_128_tlb inst_data_q (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(s_axis.tvalid),
    .s_axis_tready(s_axis.tready),
    .s_axis_tdata(s_axis.tdata),
    .s_axis_tlast(s_axis.tlast),
    .m_axis_tvalid(axis_s0.tvalid),
    .m_axis_tready(axis_s0.tready),
    .m_axis_tdata(axis_s0.tdata),
    .m_axis_tlast(axis_s0.tlast)
);

// TLBs 
for (genvar i = 0; i < N_ASSOC; i++) begin
  // BRAM instantiation
  ram_tp_c #(
      .ADDR_BITS(TLB_ORDER),
      .DATA_BITS(TLB_DATA_BITS)
  ) inst_pt_host (
      .clk       (aclk),
      .a_en      (1'b1),
      .a_we      (tlb_wr_en[i]),
      .a_addr    (axis_s0.tdata[0+:TLB_ORDER]),
      .b_en      (1'b1),
      .b_addr    (TLB.addr[PG_BITS+:TLB_ORDER]),
      .a_data_in (tlb_data_upd_in[i]),
      .a_data_out(tlb_data_upd_out[i]),
      .b_data_out(tlb_data_lup[i])
    );
end

`ifdef EN_NRU
// TLB Reference map
always_ff @( posedge aclk ) begin : TLB_CLR
    if(aresetn == 1'b0) begin
        tmr_clr_valid <= 1'b0;
        tmr_clr <= 0;
    end
    else begin
        if(tmr_clr_valid) begin
            tmr_clr_valid <= 1'b0;
            tmr_clr <= 0;
        end
        else begin
            if(tmr_clr == TLB_TMR_REF_CLR) begin
                tmr_clr_valid <= 1'b1;
            end
            else begin
                tmr_clr <= tmr_clr + 1;
            end
        end
    end
end
`endif

// REG
always_ff @( posedge aclk ) begin : PROC_LUP
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        data_C = 0;
        last_C = 0;
        done_C <= 1'b0;
        nxt_insert_C <= 0;

`ifdef EN_NRU
        ref_r_C <= 0;
        ref_m_C <= 0;
        addr_C <= 0;
        wr_C <= 1'b0;
        val_C <= 0;
        hit_addr_C <= 0;
        hit_wr_C <= 1'b0;
        hit_val_C <= 1'b0;
        hit_idx_C <= 0;  
`endif
    end
    else begin
        state_C <= state_N;

        data_C  = data_N;
        last_C  = last_N;
        done_C <= done_N;
        nxt_insert_C <= nxt_insert_N;

`ifdef EN_NRU
        ref_r_C <= ref_r_N;
        ref_m_C <= ref_m_N;
        addr_C <= addr_N;
        wr_C <= wr_N;
        val_C <= val_N;
        hit_addr_C <= hit_addr_N;
        hit_wr_C <= hit_wr_N;
        hit_val_C <= hit_val_N;
        hit_idx_C <= hit_idx_N;   
`endif
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
            state_N = axis_s0.tvalid ? ST_WAIT : ST_IDLE; 
            
        ST_WAIT:
            state_N = ST_COMP;

        ST_COMP:
            state_N = ST_IDLE;

	endcase // state_C
end

// DP 
always_comb begin
    data_N  = data_C;
    last_N  = last_C;
    done_N = 1'b0;
    nxt_insert_N = nxt_insert_C;

    // Input
    axis_s0.tready = 1'b0;

    // TLB
    for(int i = 0; i < N_ASSOC; i++) begin
        tlb_data_upd_in[i][0+:TAG_BITS+PID_BITS+1] = data_C[HASH_BITS+:TAG_BITS+PID_BITS+1];
        tlb_data_upd_in[i][TAG_BITS+PID_BITS+1+:2*PHY_BITS] = data_C[64+:2*PHY_BITS];
    end
    tlb_wr_en = 0;

    // Ref
`ifdef EN_NRU
    ref_r_N = ref_r_C;
    ref_m_N = ref_m_C;

    wr_N = TLB.wr;
    addr_N = TLB.addr[PG_BITS+:HASH_BITS];
    val_N[0] = TLB.valid;
    val_N[1] = val_C[0];

    hit_idx_N = hit_idx;
    hit_wr_N = wr_C;
    hit_addr_N = addr_C;
    hit_val_N = val_C[1] & TLB.hit;

    // tmr clr
    if(tmr_clr_valid) begin
        ref_r_N = 0;
    end

    // Update ref
    if(hit_val_C) begin
        if(hit_wr_C) begin
            ref_m_N[hit_idx_C][hit_addr_C] = 1'b1;
        end
        ref_r_N[hit_idx_C][hit_addr_C] = 1'b1;
    end
`endif

    // Main state
    case (state_C)
        ST_IDLE: begin
            axis_s0.tready = 1'b1;
            if(axis_s0.tvalid) begin
                data_N = axis_s0.tdata;
                last_N = axis_s0.tlast;
            end
        end

        ST_COMP: begin
            if(last_C) begin
                done_N = 1'b1;
            end

            if(data_C[HASH_BITS+TLB_VAL_BIT]) begin
                // Insertion
`ifdef EN_NRU
                if(!filled) begin
                    tlb_wr_en[entry_insert_fe] = ~0;    
                end
                else begin
                    tlb_wr_en[entry_insert_se] = ~0;    
                end
`else
                tlb_wr_en[entry_insert_fe] = ~0;  
`endif
                nxt_insert_N = nxt_insert_C + 1;
            end
            else begin
                // Removal
                for(int i = 0; i < N_ASSOC; i++) begin
                    if((tlb_data_upd_out[i][0+:TAG_BITS] == data_C[HASH_BITS+:TAG_BITS]) && // tag
                       (tlb_data_upd_out[i][TAG_BITS+:PID_BITS] == data_C[HASH_BITS+TAG_BITS+:PID_BITS])) begin // pid
                        tlb_wr_en[i] = ~0;
`ifdef EN_NRU
                        ref_r_N[i][data_C[0+:HASH_BITS]] = 0;
                        ref_m_N[i][data_C[0+:HASH_BITS]] = 0;
`endif
                    end
                end
            end
        end

    endcase
end

// Done signal
assign done_map = done_C;

// Find first order
always_comb begin   
    filled = 1'b1;
    entry_insert_fe = 0; // nxt_insert_C;

    for(int i = 0; i < N_ASSOC; i++) begin
        if(!tlb_data_upd_out[i][TLB_VAL_BIT]) begin
            filled = 1'b0;
            entry_insert_fe = i;
            break;
        end
    end
end

// Find second order
`ifdef EN_NRU
always_comb begin   
    entry_insert_se = 0;
    entry_insert_min = 2'b11;
    curr_ref = 0;

    for(int i = 0; i < N_ASSOC; i++) begin
        curr_ref = {ref_r_C[i][data_C[0+:HASH_BITS]], ref_m_C[i][data_C[0+:HASH_BITS]]};
        if(curr_ref <= entry_insert_min) begin
            entry_insert_se = i;
            entry_insert_min = curr_ref;
        end
    end
end
`endif

// Hit/Miss combinational logic
always_comb begin
    tag_cmp = 0;

	TLB.hit = 1'b0;
	hit_idx = 0;

	// Pages
	for (int i = 0; i < N_ASSOC; i++) begin
        // tag cmp
        tag_cmp[i] = 
        (tlb_data_lup[i][0+:TAG_BITS] == TLB.addr[PG_BITS+HASH_BITS+:TAG_BITS]) && // tag hit
        (tlb_data_lup[i][TAG_BITS+:PID_BITS] == TLB.pid) && // pid hit
        tlb_data_lup[i][TLB_VAL_BIT];

        if(tag_cmp[i]) begin 
            TLB.hit = 1'b1;
            hit_idx = i;
        end
	end
end

// Output
assign TLB.data = tlb_data_lup[hit_idx];

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
//`define DBG_TLB_CONTROLLER
`ifdef DBG_TLB_CONTROLLER

    if(DBG_S == 1) begin
        ila_controller_s inst_ila_controller_s (
            .clk(aclk),
            .probe0(s_axis.tvalid),
            .probe1(s_axis.tready),
            .probe2(s_axis.tdata), // 128
            .probe3(s_axis.tlast),
            .probe4(TLB.valid),
            .probe5(TLB.hit),
            .probe6(TLB.wr),
            .probe7(TLB.addr), // 48

            .probe8(data_C), // 128
            .probe9(filled),
            .probe10(entry_insert_fe), // 2

            .probe11(tlb_wr_en[0]), // 12
            .probe12(tlb_wr_en[1]), // 12
            .probe13(tlb_wr_en[2]), // 12
            .probe14(tlb_wr_en[3]), // 12
            
            .probe15(tlb_data_lup[0]), // 96
            .probe16(tlb_data_lup[1]), // 96
            .probe17(tlb_data_lup[2]), // 96
            .probe18(tlb_data_lup[3]), // 96

            .probe19(TLB.data), // 89
            .probe20(hit_idx), // 2
            .probe21(TLB.pid), // 6
            .probe22(tag_cmp) // 4        
        );
    end

    if(DBG_L == 1) begin
        ila_controller_l inst_ila_controller_l (
            .clk(aclk),
            .probe0(s_axis.tvalid),
            .probe1(s_axis.tready),
            .probe2(s_axis.tdata), // 128
            .probe3(s_axis.tlast),
            .probe4(TLB.valid),
            .probe5(TLB.hit),
            .probe6(TLB.wr),
            .probe7(TLB.addr), // 48

            .probe8(data_C), // 128
            .probe9(filled),
            .probe10(entry_insert_fe), // 2

            .probe11(tlb_wr_en[0]), // 12
            .probe12(tlb_wr_en[1]), // 12
            
            .probe13(tlb_data_lup[0]), // 96
            .probe14(tlb_data_lup[1]), // 96

            .probe15(TLB.data), // 63
            .probe16(hit_idx), // 1
            .probe17(TLB.pid), // 6
            .probe18(tag_cmp) // 2    
        );
    end

`endif

endmodule // tlb_controller
