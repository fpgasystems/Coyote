/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
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

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   TLB FSM. 
 *
 * TLB state machine. Read-write engine locks. Handles ISR.
 * Resource consumption depends on the config.
 *
 *  @param ID_REG   Number of associated vFPGA
 *  @param RDWR     Read or write requests (Mutex lock)
 */
module tlb_fsm #(
	parameter integer ID_REG = 0,
	parameter integer RDWR = 0
) (
	input logic							aclk,    
	input logic 						aresetn,

	// TLBs
	tlbIntf.m 							lTlb,
	tlbIntf.m							sTlb,

	// DMA
`ifdef EN_STRM
	metaIntf.m   						m_host_done,
    dmaIntf.m   						m_HDMA, // Host
`endif

`ifdef EN_MEM
	metaIntf.m   						m_card_done,
    dmaIntf.m 							m_DDMA [N_CARD_AXI], // Card
`endif

	// Requests
	metaIntf.s 							s_req,

    // IRQ page fault
    metaIntf.m  						m_pfault,
    output logic [LEN_BITS-1:0]         m_pfault_rng,
	metaIntf.s   						s_pfault,

    // IRQ invalidation
    metaIntf.s                          s_invldt,
    metaIntf.m                          m_invldt,

	// Mutex
	output logic 						lock,
	output logic 						unlock,
	input  logic [1:0]					mutex
);

// ----------------------------------------------------------------------------------------------------------
// -- Decl
// ----------------------------------------------------------------------------------------------------------

// -- Constants
localparam integer PG_L_SIZE = 1 << PG_L_BITS;
localparam integer PG_S_SIZE = 1 << PG_S_BITS;
localparam integer HASH_L_BITS = TLB_L_ORDER;
localparam integer HASH_S_BITS = TLB_S_ORDER;
localparam integer PHY_L_BITS = PADDR_BITS - PG_L_BITS;
localparam integer PHY_S_BITS = PADDR_BITS - PG_S_BITS;
localparam integer TAG_L_BITS = VADDR_BITS - HASH_L_BITS - PG_L_BITS;
localparam integer TAG_S_BITS = VADDR_BITS - HASH_S_BITS - PG_S_BITS;
localparam integer PHY_L_OFFS      = TAG_L_BITS + PID_BITS + STRM_BITS + 1;
localparam integer PHY_S_OFFS      = TAG_S_BITS + PID_BITS + STRM_BITS + 1;
localparam integer HPID_L_OFFS     = TAG_L_BITS + PID_BITS + STRM_BITS + 1 + PHY_L_BITS;
localparam integer HPID_S_OFFS     = TAG_S_BITS + PID_BITS + STRM_BITS + 1 + PHY_S_BITS;
localparam integer TLB_L_DATA_BITS = TAG_L_BITS + PID_BITS + STRM_BITS + 1 + PHY_L_BITS + HPID_BITS;
localparam integer TLB_S_DATA_BITS = TAG_S_BITS + PID_BITS + STRM_BITS + 1 + PHY_S_BITS + HPID_BITS;
localparam integer N_OUTSTANDING_BITS = clog2s(N_TLB_ACTV);
localparam integer N_CARD_AXI_BITS = clog2s(N_CARD_AXI);

localparam integer RTRN_IDLE = 0;
localparam integer RTRN_LOCKED = 1;
localparam integer RTRN_MISS = 2;

localparam integer ACK_BUFFER_SIZE = 2 + STRM_BITS + DEST_BITS + PID_BITS;

// -- FSM ---------------------------------------------------------------------------------------------------
typedef enum logic[4:0] {ST_IDLE, ST_LOCKED,
                         ST_MUTEX, ST_WAIT_1, ST_WAIT_2, ST_CHECK,
					     ST_HIT_LARGE, ST_HIT_SMALL, ST_CALC_LARGE, ST_CALC_SMALL, // timing extra states
`ifdef EN_STRM
                         ST_INVLDT_HOST, ST_INVLDT_LUP_HOST, ST_INVLDT_WAIT_HOST, ST_INVLDT_CMP_HOST,
                         ST_HOST_SEND,
`endif
`ifdef EN_MEM
                         ST_INVLDT_CARD, ST_INVLDT_LUP_CARD, ST_INVLDT_WAIT_CARD, ST_INVLDT_CMP_CARD,
                         ST_CARD_SEND,
`endif
                         ST_INVLDT_EVAL,  
                         ST_MISS_CACHE, ST_MISS_LUP_CACHE_CALC, ST_MISS_LUP_CACHE_ASSIGN,
                         ST_MISS_SEND, ST_MISS_IDLE, ST_MISS_LUP_IDLE_CALC, ST_MISS_LUP_IDLE_ASSIGN} state_t;
logic [4:0] state_C, state_N;

// -- Internal registers ------------------------------------------------------------------------------------
// Request
logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] vaddr_C, vaddr_N;
logic last_C, last_N;
logic [STRM_BITS-1:0] strm_C, strm_N;
logic [DEST_BITS-1:0] dest_C, dest_N;
logic [PID_BITS-1:0] pid_C, pid_N;
logic val_C, val_N;
logic host_C, host_N;

// TLB data
logic [TLB_L_DATA_BITS-1:0] data_l_C, data_l_N;
logic [TLB_S_DATA_BITS-1:0] data_s_C, data_s_N;
logic hit;
logic [HPID_BITS-1:0] hpid;

// Return
logic [1:0] rtrn_C, rtrn_N;

// Page fault
logic unlock_C, unlock_N;
irq_pft_t pf_miss_C, pf_miss_N;
logic [LEN_BITS-1:0] pf_rng_C, pf_rng_N;
logic [VADDR_BITS-1:0] pf_miss_end_C, pf_miss_end_N;
logic [LEN_BITS-1:0] pf_miss_len_C, pf_miss_len_N;

// Out
logic [LEN_BITS-1:0] plen_C, plen_N;
logic [PADDR_BITS-1:0] paddr_C, paddr_N;

// Cache buffer
metaIntf #(.STYPE(req_t)) cch_buff_sink (.*);
metaIntf #(.STYPE(req_t)) cch_buff_src (.*);
logic [7:0] cch_cnt_C, cch_cnt_N;
logic [7:0] cch_size_C, cch_size_N;
req_t cch_req_C, cch_req_N;
 
// In flight
logic [N_OUTSTANDING_BITS-1:0] invldt_pntr_C, invldt_pntr_N;
logic in_flight_C, in_flight_N;
inv_t invldt_C, invldt_N;

// In flight and ack buffers
`ifdef EN_STRM
logic [N_OUTSTANDING_BITS-1:0] head_host_C, head_host_N;
logic [N_OUTSTANDING_BITS-1:0] tail_host_C, tail_host_N;
logic issued_host_C, issued_host_N;

// in flight buff
logic [N_OUTSTANDING_BITS-1:0] req_host_addr;
logic [HPID_BITS+LEN_BITS+VADDR_BITS-1:0] req_host_in_data;
logic [HPID_BITS+LEN_BITS+VADDR_BITS-1:0] req_host_out_data;
logic [3:0] req_host_tmp;
logic [(4+HPID_BITS+LEN_BITS+VADDR_BITS)/8-1:0] req_host_in_we;

// ack buffs
logic ack_buff_host_sink_valid;
logic ack_buff_host_sink_ready;
logic [ACK_BUFFER_SIZE - 1:0] ack_buff_host_sink_data;

logic ack_buff_host_src_valid;
logic ack_buff_host_src_ready;
logic [ACK_BUFFER_SIZE - 1:0] ack_buff_host_src_data;

// I/O 
logic hdma_valid;
logic hdma_ready;
dma_req_t hdma_req;
dma_rsp_t hdma_rsp;

`endif 

`ifdef EN_MEM
logic [N_CARD_AXI-1:0][N_OUTSTANDING_BITS-1:0] head_card_C, head_card_N;
logic [N_CARD_AXI-1:0][N_OUTSTANDING_BITS-1:0] tail_card_C, tail_card_N;
logic [N_CARD_AXI-1:0] issued_card_C, issued_card_N;
logic [N_CARD_AXI_BITS-1:0] card_dest_C, card_dest_N; //
logic [N_CARD_AXI_BITS-1:0] ccurr_dest;

// in flight buff
logic [N_CARD_AXI-1:0][N_OUTSTANDING_BITS-1:0] req_card_addr;
logic [N_CARD_AXI-1:0][HPID_BITS+LEN_BITS+VADDR_BITS-1:0] req_card_in_data;
logic [N_CARD_AXI-1:0][HPID_BITS+LEN_BITS+VADDR_BITS-1:0] req_card_out_data;
logic [N_CARD_AXI-1:0][3:0] req_card_tmp;
logic [N_CARD_AXI-1:0][(4+HPID_BITS+LEN_BITS+VADDR_BITS)/8-1:0] req_card_in_we;

// ack buffs can't use meta here (Xilinx will never fix the interfaces ...)
logic [N_CARD_AXI-1:0] ack_buff_card_sink_valid;
logic [N_CARD_AXI-1:0] ack_buff_card_sink_ready;
logic [N_CARD_AXI-1:0][ACK_BUFFER_SIZE - 1:0] ack_buff_card_sink_data;

logic [N_CARD_AXI-1:0] ack_buff_card_src_valid;
logic [N_CARD_AXI-1:0] ack_buff_card_src_ready;
logic [N_CARD_AXI-1:0][ACK_BUFFER_SIZE - 1:0] ack_buff_card_src_data;

// I/O 
logic [N_CARD_AXI-1:0] ddma_valid;
logic [N_CARD_AXI-1:0] ddma_ready;
dma_req_t [N_CARD_AXI-1:0] ddma_req;
dma_rsp_t [N_CARD_AXI-1:0] ddma_rsp;

metaIntf #(.STYPE(ack_t)) card_done [N_CARD_AXI] (.*);
metaIntf #(.STYPE(ack_t)) card_done_q [N_CARD_AXI] (.*);

`endif

// Intermediate results for better timing
logic [VADDR_BITS-1:0] vaddr_delta_L_N, vaddr_delta_L_C;
logic [VADDR_BITS-1:0] vaddr_delta_S_N, vaddr_delta_S_C;

// -- I/O ---------------------------------------------------------------------------------------------------
`ifdef EN_STRM
assign m_HDMA.valid = hdma_valid;
assign hdma_ready = m_HDMA.ready;
assign m_HDMA.req = hdma_req;
assign hdma_rsp = m_HDMA.rsp;
`endif 

`ifdef EN_MEM
for(genvar i = 0; i < N_CARD_AXI; i++) begin
    assign m_DDMA[i].valid = ddma_valid[i];
    assign ddma_ready[i] = m_DDMA[i].ready;
    assign m_DDMA[i].req = ddma_req[i];
    assign ddma_rsp[i] = m_DDMA[i].rsp;
end
`endif

// ----------------------------------------------------------------------------------------------------------
// -- Def
// ----------------------------------------------------------------------------------------------------------

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        // Requests
        len_C <= 'X;
        vaddr_C <= 'X;
        last_C <= 'X;
        strm_C <= 'X;
        host_C <= 'X;
        dest_C <= 'X;
        pid_C <= 'X;
        val_C <= 1'b0;
        // TLB
        plen_C <= 'X;
        data_l_C <= 'X;
        data_s_C <= 'X;
        paddr_C <= 'X;
        // RTRN
        rtrn_C <= 'X;
        // ISR
        unlock_C <= 0;
        pf_miss_C <= 'X;
        pf_rng_C <= 'X;
        pf_miss_end_C <= 'X;    
        pf_miss_len_C <= 'X;    
        // Invalidations
        in_flight_C <= 'X;
        invldt_pntr_C <= 'X;
        invldt_C <= 'X;
        // Cache
        cch_cnt_C <= 0;
        cch_size_C <= 0;
        cch_req_C <= 'X;
        // Intermediate results
        vaddr_delta_L_C <= 'X;
        vaddr_delta_S_C <= 'X;

    `ifdef EN_STRM
        head_host_C <= 0;
        tail_host_C <= 0;
        issued_host_C <= 1'b0;
    `endif
    `ifdef EN_MEM
        head_card_C <= 0;
        tail_card_C <= 0;
        issued_card_C <= 1'b0;
        card_dest_C <= 'X;
    `endif

    end else begin
        state_C <= state_N;

        // Requests
        len_C <= len_N;
        vaddr_C <= vaddr_N;
        last_C <= last_N;
        strm_C <= strm_N;
        host_C <= host_N;
        dest_C <= dest_N;
        pid_C <= pid_N;
        val_C <= val_N;
        // TLB
        plen_C <= plen_N;
        data_l_C <= data_l_N;	
        data_s_C <= data_s_N;	
        paddr_C <= paddr_N;
        // RTRN
        rtrn_C <= rtrn_N;
        // ISR
        unlock_C <= unlock_N;
        pf_miss_C <= pf_miss_N;
        pf_rng_C <= pf_rng_N;
        pf_miss_end_C <= pf_miss_end_N;
        pf_miss_len_C <= pf_miss_len_N;
        // Invalidations
        in_flight_C <= in_flight_N;
        invldt_pntr_C <= invldt_pntr_N;
        invldt_C <= invldt_N;
        // Cache
        cch_cnt_C <= cch_cnt_N;
        cch_size_C <= cch_size_N;
        cch_req_C <= cch_req_N;
        // Intermediate results
        vaddr_delta_L_C <= vaddr_delta_L_N;
        vaddr_delta_S_C <= vaddr_delta_S_N;

    `ifdef EN_STRM
        head_host_C <= head_host_N;
        tail_host_C <= tail_host_N;
        issued_host_C <= issued_host_N;
    `endif
    `ifdef EN_MEM
        head_card_C <= head_card_N;
        tail_card_C <= tail_card_N;
        issued_card_C <= issued_card_N;
        card_dest_C <= card_dest_N;
    `endif
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	unique case(state_C)

        //
        // Init state
        //

		ST_IDLE: begin
            if(s_invldt.valid) begin
                if(s_invldt.data.lock) begin
                    state_N = ST_LOCKED;
                end
                else begin
`ifdef EN_MEM
                    state_N = ST_INVLDT_CARD;
`endif
`ifdef EN_STRM
                    state_N = ST_INVLDT_HOST;
`endif 
                end
            end
			else if(cch_buff_src.valid) begin
				if(cch_buff_src.data.len != 0) begin
					state_N = ST_MUTEX;
				end
			end
            else if(s_req.valid) begin
                if(s_req.data.len != 0) begin
                    state_N = ST_MUTEX;
                end
            end
        end

        // 
        // Locked (user triggered)
        //
        ST_LOCKED: begin
            if(s_invldt.valid) begin
                if(s_invldt.data.lock) begin
                    state_N = ST_IDLE;
                end
                else begin
`ifdef EN_MEM
                    state_N = ST_INVLDT_CARD;
`endif
`ifdef EN_STRM
                    state_N = ST_INVLDT_HOST;
`endif 
                end
            end
        end 

        //
        // Invalidation states
        //

`ifdef EN_STRM
        // Host invalidate
        ST_INVLDT_HOST: begin
            if(issued_host_C) begin
                state_N = ST_INVLDT_LUP_HOST;
            end
            else begin
                state_N = ST_INVLDT_EVAL;
`ifdef EN_MEM
                state_N = ST_INVLDT_CARD;
`endif
            end
        end

        ST_INVLDT_LUP_HOST: begin
            state_N = ST_INVLDT_WAIT_HOST;
        end

        ST_INVLDT_WAIT_HOST: begin
            state_N = ST_INVLDT_CMP_HOST;
        end

        ST_INVLDT_CMP_HOST: begin
            if(head_host_C == invldt_pntr_C) begin
                state_N = ST_INVLDT_EVAL;
`ifdef EN_MEM
                state_N = ST_INVLDT_CARD;
`endif   
            end
            else begin
                state_N = ST_INVLDT_LUP_HOST;
            end
        end
`endif

`ifdef EN_MEM
        // Card invalidate
        ST_INVLDT_CARD: begin
            if(issued_card_C[card_dest_C]) begin
                state_N = ST_INVLDT_LUP_CARD;
            end
            else begin
                state_N = (card_dest_C == N_CARD_AXI - 1) ? ST_INVLDT_EVAL : ST_INVLDT_CARD;
            end
        end

        ST_INVLDT_LUP_CARD: begin
            state_N = ST_INVLDT_WAIT_CARD;
        end

        ST_INVLDT_WAIT_CARD: begin
            state_N = ST_INVLDT_CMP_CARD;
        end

        ST_INVLDT_CMP_CARD: begin
            if(head_card_C[card_dest_C] == invldt_pntr_C) begin
                state_N = (card_dest_C == N_CARD_AXI - 1) ? ST_INVLDT_EVAL : ST_INVLDT_CARD;
            end
            else begin
                state_N = ST_INVLDT_LUP_CARD;
            end
        end
`endif

        // Invalidation evaluation
        ST_INVLDT_EVAL: begin
            if(in_flight_C) begin
`ifdef EN_MEM
                state_N = ST_INVLDT_CARD;
`endif
`ifdef EN_STRM
                state_N = ST_INVLDT_HOST;
`endif 
            end
            else begin
                if(invldt_C.last) begin
                    if(m_invldt.ready) begin
                        state_N = (rtrn_C == RTRN_LOCKED) ? ST_LOCKED : ((rtrn_C == RTRN_MISS) ? ST_MISS_IDLE : ST_IDLE);
                    end
                end
                else begin
                    state_N = (rtrn_C == RTRN_LOCKED) ? ST_LOCKED : ((rtrn_C == RTRN_MISS) ? ST_MISS_IDLE : ST_IDLE);
                end  
            end
        end

        //
        // Request states
        //
		
        // Obtain mutex
        ST_MUTEX:
			state_N = ((mutex[1] == RDWR) && (mutex[0] == 1'b0)) ? ST_WAIT_1 : ST_MUTEX;

		// Wait on BRAM (out reg) - only with high freq. clk
		ST_WAIT_1:
			state_N = ST_WAIT_2;
        ST_WAIT_2:
			state_N = ST_CHECK;

		// Check hits
		ST_CHECK: begin
            if(hit) begin
                state_N = lTlb.hit ? ST_HIT_LARGE : ST_HIT_SMALL;    
            end
            else begin
                state_N = ST_MISS_CACHE;
            end    
        end

        // Page parsing
		ST_HIT_LARGE:
			state_N = ST_CALC_LARGE;
		ST_HIT_SMALL:
			state_N = ST_CALC_SMALL;
		
		// Calc.
		ST_CALC_LARGE:
`ifdef EN_STRM
    `ifdef EN_MEM
			if(strm_C == STRM_HOST) 
				state_N = ST_HOST_SEND;
			else
				state_N = ST_CARD_SEND;
    `else
			state_N = ST_HOST_SEND;
    `endif
`else
			state_N = ST_CARD_SEND;
`endif
		ST_CALC_SMALL:
`ifdef EN_STRM
	`ifdef EN_MEM
			if(strm_C == STRM_HOST) 
				state_N = ST_HOST_SEND;
			else
				state_N = ST_CARD_SEND;
	`else
			state_N = ST_HOST_SEND;
	`endif
`else
			state_N = ST_CARD_SEND;
`endif

        // Send DMA requests
`ifdef EN_STRM
		ST_HOST_SEND:
			if(hdma_ready && (!issued_host_C || (head_host_C != tail_host_C)))
				state_N = len_C ? ST_MUTEX : ST_IDLE; 
`endif

`ifdef EN_MEM
		ST_CARD_SEND:
    `ifdef MULT_CARD_AXI
        if(ddma_ready[ccurr_dest] && (!issued_card_C[ccurr_dest] || (head_card_C[ccurr_dest] != tail_card_C[ccurr_dest])))
                state_N = len_C ? ST_MUTEX : ST_IDLE; 
    `else
        if(ddma_ready[0] && (!issued_card_C[0] || (head_card_C[0] != tail_card_C[0])))
                state_N = len_C ? ST_MUTEX : ST_IDLE;    
    `endif   
`endif
		
		// Page fault
        ST_MISS_CACHE:
            state_N = (cch_size_C == cch_cnt_C) ? ST_MISS_SEND : ST_MISS_LUP_CACHE_CALC;
        
        ST_MISS_LUP_CACHE_CALC:
            state_N = ST_MISS_LUP_CACHE_ASSIGN;
        
        ST_MISS_LUP_CACHE_ASSIGN:
            state_N = ST_MISS_CACHE;

		ST_MISS_SEND:
			state_N = m_pfault.ready ? ST_MISS_IDLE : ST_MISS_SEND;
            
        ST_MISS_IDLE: begin
            if(s_invldt.valid) begin
`ifdef EN_MEM
                state_N = ST_INVLDT_CARD;
`endif
`ifdef EN_STRM
                state_N = ST_INVLDT_HOST;
`endif 
            end
            else if(s_pfault.valid) begin
                if(s_pfault.data)
                    state_N = ST_MUTEX;
                else
                    state_N = ST_IDLE;
            end
            else if(s_req.valid && cch_size_C <= CACHE_MAX_SIZE) begin
                state_N = ST_MISS_LUP_IDLE_CALC;
            end
        end 
        
        ST_MISS_LUP_IDLE_CALC:
            state_N = ST_MISS_LUP_IDLE_ASSIGN;

        ST_MISS_LUP_IDLE_ASSIGN:
            state_N = ST_MISS_IDLE;

	endcase // state_C
end

// DP
always_comb begin: DP
	// Requests
    len_N = len_C;
	vaddr_N = vaddr_C;
	last_N = last_C;
	strm_N = strm_C;
    host_N = host_C;
	dest_N = dest_C;
	pid_N = pid_C;
	val_N = 1'b0;

    // Return
    rtrn_N = rtrn_C;

	// TLB
    data_l_N = data_l_C;
	data_s_N = data_s_C;
    hpid = lTlb.hit ? data_l_C[HPID_L_OFFS+:HPID_BITS] : data_s_C[HPID_S_OFFS+:HPID_BITS];
    
	// Out
	plen_N = plen_C;
	paddr_N = paddr_C;

    // ISR
	unlock_N = 1'b0;
    pf_miss_N = pf_miss_C;
    pf_rng_N = pf_miss_C.len;
    pf_miss_end_N = pf_miss_end_C;
    pf_miss_len_N = pf_miss_len_C;

	// Invalidations
	in_flight_N = in_flight_C;
    invldt_pntr_N = invldt_pntr_C;
    invldt_N = invldt_C;

    // Cache
    cch_size_N = cch_size_C;
    cch_cnt_N = cch_cnt_C;
    cch_req_N = cch_req_C;

	// mutex
	lock = 1'b0;
	unlock = unlock_C;

	// Requests
	s_req.ready = 1'b0;

    // Pf ctrl
    s_pfault.ready = 1'b0;

	// Cache buff
	cch_buff_sink.valid = 1'b0;
	cch_buff_sink.data = s_req.data;

	cch_buff_src.ready = 1'b0;

    // IRQ
	m_pfault.valid = 1'b0;
	m_pfault.data.vaddr = pf_miss_C.vaddr;
	m_pfault.data.pid = pf_miss_C.pid;
    m_pfault.data.strm = pf_miss_C.strm;
    
    s_invldt.ready = 1'b0;
    
    m_invldt.valid = 1'b0;
    m_invldt.data = invldt_C.hpid;

	// TLB
	lTlb.addr = vaddr_C;
	lTlb.wr = RDWR;
	lTlb.pid = pid_C;
    lTlb.strm = strm_C;
	lTlb.valid = val_C;

	sTlb.addr = vaddr_C;
	sTlb.wr = RDWR;
	sTlb.pid = pid_C;
    sTlb.strm = strm_C;
	sTlb.valid = val_C;

    hit = lTlb.hit | sTlb.hit;

`ifdef EN_STRM
    head_host_N = head_host_C;
    tail_host_N = hdma_rsp.done ? tail_host_C + 1 : tail_host_C;
    issued_host_N = (hdma_rsp.done && (tail_host_N == head_host_C)) ? 1'b0 : issued_host_C;

    // acks
    ack_buff_host_sink_valid = 1'b0;
    ack_buff_host_sink_data[0+:PID_BITS] = pid_C;
    ack_buff_host_sink_data[PID_BITS+:DEST_BITS] = dest_C;
    ack_buff_host_sink_data[PID_BITS+DEST_BITS+:STRM_BITS] = strm_C;
    ack_buff_host_sink_data[PID_BITS+DEST_BITS+STRM_BITS+:1] = host_C;
    ack_buff_host_sink_data[PID_BITS+DEST_BITS+STRM_BITS+1+:1] = !len_C && last_C;

    // Circ. buff.
    req_host_addr = head_host_C;
    req_host_in_we = 0;
    req_host_in_data = {len_C, vaddr_C};

    // m_HDMA
	hdma_req.paddr = paddr_C;
	hdma_req.len = plen_C;
	hdma_req.last = !len_C && last_C;
	hdma_req.rsrvd = 0;
	hdma_valid = 1'b0;
`endif 

`ifdef EN_MEM
    head_card_N = head_card_C;
    card_dest_N = card_dest_C;

    // acks
    for(int i = 0; i < N_CARD_AXI; i++) begin
        tail_card_N[i] = ddma_rsp[i].done ? tail_card_C[i] + 1 : tail_card_C[i];
        issued_card_N[i] = (ddma_rsp[i].done && (tail_card_N[i] == head_card_C[i])) ? 1'b0 : issued_card_C[i];

        ack_buff_card_sink_valid[i] = 1'b0;
        ack_buff_card_sink_data[i][0+:PID_BITS] = pid_C;
        ack_buff_card_sink_data[i][PID_BITS+:DEST_BITS] = dest_C;
        ack_buff_card_sink_data[i][PID_BITS+DEST_BITS+:STRM_BITS] = strm_C;
        ack_buff_card_sink_data[i][PID_BITS+DEST_BITS+STRM_BITS+:1] = host_C;
        ack_buff_card_sink_data[i][PID_BITS+DEST_BITS+STRM_BITS+1+:1] = !len_C && last_C;

        // Circ. buff.
        req_card_addr[i] = head_card_C[i];
        req_card_in_we[i] = 0;
        req_card_in_data[i] = {len_C, vaddr_C};
    end

    // m_DDMA
    for(int i = 0; i < N_CARD_AXI; i++) begin
        ddma_req[i].paddr = paddr_C;
        ddma_req[i].len = plen_C;
        ddma_req[i].last = !len_C && last_C;
        ddma_req[i].rsrvd = 0;
        ddma_valid[i] = 1'b0;
    end
`endif 

    // Intermediate results
    vaddr_delta_L_N = vaddr_delta_L_C;
    vaddr_delta_S_N = vaddr_delta_S_C;

	unique case(state_C)

        //
        // Init state
        //

		ST_IDLE: begin
            if(s_invldt.valid) begin
                s_invldt.ready = 1'b1;

                if(!s_invldt.data.lock) begin
                    // latch the invalidation
                    invldt_N = s_invldt.data;

                    in_flight_N = 1'b0;
`ifdef EN_MEM
                    card_dest_N = 0;
`endif   
                    rtrn_N = RTRN_IDLE;
                end
            end
			else if(cch_buff_src.valid) begin
				cch_buff_src.ready = 1'b1;
                cch_size_N = cch_size_C - 1;

				if(cch_buff_src.data.len != 0) begin
					// Lock the mutex (next state)
					lock = 1'b1;

					// Latch the request
					pid_N = cch_buff_src.data.pid;
					dest_N = cch_buff_src.data.dest;
					last_N = cch_buff_src.data.last;
                    host_N = cch_buff_src.data.host;
            `ifdef EN_STRM
                `ifdef EN_MEM
					strm_N = cch_buff_src.data.strm;
                `else
                    strm_N = STRM_HOST;
                `endif
            `else
                `ifdef EN_MEM
                    strm_N = STRM_CARD;
                `endif
            `endif
					vaddr_N = cch_buff_src.data.vaddr;
					len_N = cch_buff_src.data.len;
					val_N = 1'b1;
				end
			end
            else if(s_req.valid) begin
                s_req.ready = 1'b1;

				if(s_req.data.len != 0) begin
					// Lock the mutex
					lock = 1'b1;

					// Request
					pid_N = s_req.data.pid;
					dest_N = s_req.data.dest;
					last_N = s_req.data.last;
                    host_N = s_req.data.host;
			`ifdef EN_STRM
                `ifdef EN_MEM
					strm_N = s_req.data.strm;
                `else
                    strm_N = STRM_HOST;
                `endif
            `else
                `ifdef EN_MEM
                        strm_N = STRM_CARD;
                `endif
            `endif
					vaddr_N = s_req.data.vaddr;
					len_N = s_req.data.len;
					val_N = 1'b1;
				end
            end
		end

        //
        // Locked
        //

        ST_LOCKED: begin
            if(s_invldt.valid) begin
                s_invldt.ready = 1'b1;

                if(!s_invldt.data.lock) begin
                    // latch the invalidation
                    invldt_N = s_invldt.data;

                    in_flight_N = 1'b0;
`ifdef EN_MEM
                    card_dest_N = 0;
`endif   
                    rtrn_N = RTRN_LOCKED;
                end
            end
        end

        // 
        // Invalidations 
        //

`ifdef EN_STRM
        // Host invalidate
        ST_INVLDT_HOST: begin
            invldt_pntr_N = tail_host_C + 1;
        end

        ST_INVLDT_LUP_HOST: begin
            req_host_addr = invldt_pntr_C - 1;
        end

        ST_INVLDT_CMP_HOST: begin
            if( ((invldt_C.vaddr <= req_host_out_data[0+:VADDR_BITS]) && 
                (invldt_C.vaddr + invldt_C.len >= req_host_out_data[0+:VADDR_BITS])) || 
                ((invldt_C.vaddr >= req_host_out_data[0+:VADDR_BITS]) &&
                (invldt_C.vaddr < req_host_out_data[0+:VADDR_BITS] + req_host_out_data[VADDR_BITS+:LEN_BITS])) &&
                (invldt_C.hpid == req_host_out_data[VADDR_BITS+LEN_BITS+:HPID_BITS]) ) begin
                
                in_flight_N = 1'b1;
            end

            invldt_pntr_N = invldt_pntr_C + 1;
        end
`endif

`ifdef EN_MEM
        // Card invalidate
        ST_INVLDT_CARD: begin
            invldt_pntr_N = tail_card_C[card_dest_C] + 1;

            if(!issued_card_C[card_dest_C]) begin
                card_dest_N = card_dest_C + 1;
            end
        end

        ST_INVLDT_LUP_CARD: begin
            req_card_addr[card_dest_C] = invldt_pntr_C - 1;
        end

        ST_INVLDT_CMP_CARD: begin
            if( ((invldt_C.vaddr <= req_card_out_data[card_dest_C][0+:VADDR_BITS]) && 
                (invldt_C.vaddr + invldt_C.len >= req_card_out_data[card_dest_C][0+:VADDR_BITS])) || 
                ((invldt_C.vaddr >= req_card_out_data[card_dest_C][0+:VADDR_BITS]) &&
                (invldt_C.vaddr < req_card_out_data[card_dest_C][0+:VADDR_BITS] + req_card_out_data[card_dest_C][VADDR_BITS+:LEN_BITS])) &&
                (invldt_C.hpid == req_card_out_data[card_dest_C][VADDR_BITS+LEN_BITS+:HPID_BITS]) ) begin
                
                in_flight_N = 1'b1;
            end

            invldt_pntr_N = invldt_pntr_C + 1;

            if(head_card_C[card_dest_C] == invldt_pntr_C) begin
                card_dest_N = card_dest_C + 1;
            end
        end
`endif

        // Invalidation evaluation
        ST_INVLDT_EVAL: begin
            if(~in_flight_C && invldt_C.last)
                m_invldt.valid = 1'b1;
            else
                in_flight_N = 1'b0;
        end
		
        //
        // Requests
        //

		ST_MUTEX: begin 
			lock = 1'b1;
        end

		ST_CHECK: begin
            if(hit) begin
                unlock_N = 1'b1;
            end
            else begin
                pf_miss_N.vaddr = vaddr_C;
                pf_miss_N.len = len_C;
                pf_miss_N.pid = pid_C;
                pf_miss_N.strm = strm_C;
                cch_cnt_N = 0;
            end
        end

		ST_HIT_LARGE: begin
			data_l_N = lTlb.data;
            vaddr_delta_L_N = PG_L_SIZE - vaddr_C[PG_L_BITS-1:0];
		end

		ST_HIT_SMALL: begin
            data_s_N = sTlb.data;
            vaddr_delta_S_N = PG_S_SIZE - vaddr_C[PG_S_BITS-1:0];
		end

		ST_CALC_LARGE: begin
			paddr_N =  {data_l_C[PHY_L_OFFS+:PHY_L_BITS], vaddr_C[0+:PG_L_BITS]};
			if(len_C > vaddr_delta_L_C) begin
				plen_N = vaddr_delta_L_C;
				len_N = len_C - vaddr_delta_L_C;
				vaddr_N += vaddr_delta_L_C;
			end
			else begin
				plen_N = len_C;
				len_N = 0;
			end
		end

		ST_CALC_SMALL: begin
			paddr_N = {data_s_C[PHY_S_OFFS+:PHY_S_BITS], vaddr_C[0+:PG_S_BITS]};
			if(len_C > vaddr_delta_S_C) begin
				plen_N = vaddr_delta_S_C;
				len_N = len_C - vaddr_delta_S_C;
				vaddr_N += vaddr_delta_S_C;
			end
			else begin
				plen_N = len_C;
				len_N = 0;
			end
		end

`ifdef EN_STRM
		ST_HOST_SEND: begin
            if(hdma_ready && (!issued_host_C || (head_host_C != tail_host_C))) begin
                hdma_valid = 1'b1;
                ack_buff_host_sink_valid = 1'b1;
                
                head_host_N = head_host_C + 1;
                issued_host_N = 1'b1;
                val_N = len_C;
            end
            req_host_in_we = ~0;
		end
`endif

`ifdef EN_MEM
        ST_CARD_SEND: begin
    `ifdef MULT_CARD_AXI
            if(ddma_ready[ccurr_dest] && (!issued_card_C[ccurr_dest] || (head_card_C[ccurr_dest] != tail_card_C[ccurr_dest]))) begin
                ddma_valid[ccurr_dest] = 1'b1;
                ack_buff_card_sink_valid[ccurr_dest] = 1'b1;
                
                head_card_N[ccurr_dest] = head_card_C[ccurr_dest] + 1;
                issued_card_N[ccurr_dest] = 1'b1;
                val_N = len_C;
            end
            req_card_in_we[ccurr_dest] = ~0;
    `else
            if(ddma_ready[0] && (!issued_card_C[0] || (head_card_C[0] != tail_card_C[0]))) begin
                ddma_valid[0] = 1'b1;
                ack_buff_card_sink_valid[0] = 1'b1;

                head_card_N[0] = head_card_C[0] + 1;
                issued_card_N[0] = 1'b1;
                val_N = len_C;
            end 
            req_card_in_we[0] = ~0;
    `endif     
        end
`endif

		ST_MISS_CACHE: begin
            if(cch_size_C != cch_cnt_C) begin
                cch_cnt_N = cch_cnt_C + 1;

                cch_buff_src.ready = 1'b1;
                cch_req_N = cch_buff_src.data;
            end
		end

        ST_MISS_LUP_CACHE_CALC: begin
            pf_miss_end_N = pf_miss_C.vaddr + pf_miss_C.len;
            pf_miss_len_N = pf_miss_C.len + cch_req_C.len;
        end

        ST_MISS_LUP_CACHE_ASSIGN: begin
            if((cch_req_C.vaddr == pf_miss_end_C) && (cch_req_C.pid == pf_miss_C.pid) && (cch_req_C.strm == pf_miss_C.strm)) begin
                pf_miss_N.len = pf_miss_len_C;
            end

            cch_buff_sink.valid = 1'b1;
            cch_buff_sink.data = cch_req_C;
        end

        ST_MISS_SEND: begin
            m_pfault.valid = 1'b1;
            unlock_N = 1'b1;
        end

        ST_MISS_IDLE: begin
            if(s_invldt.valid) begin
                s_invldt.ready = 1'b1;

                if(!s_invldt.data.lock) begin
                    // latch the invalidation
                    invldt_N = s_invldt.data;

                    in_flight_N = 1'b0;
`ifdef EN_MEM
                    card_dest_N = 0;
`endif   
                    rtrn_N = RTRN_MISS;
                end
            end
            else if(s_pfault.valid) begin
                s_pfault.ready = 1'b1;
                if(s_pfault.data) begin
                    val_N = 1'b1;
                end
                else begin
                    unlock_N = 1'b1;
                end
            end
            else if(s_req.valid && cch_size_C <= CACHE_MAX_SIZE) begin
                cch_size_N = cch_size_C + 1;

                s_req.ready = 1'b1;
                cch_req_N = s_req.data;
            end
        end

        ST_MISS_LUP_IDLE_CALC: begin
            pf_miss_end_N = pf_miss_C.vaddr + pf_miss_C.len;
            pf_miss_len_N = pf_miss_C.len + cch_req_C.len;
        end

        ST_MISS_LUP_IDLE_ASSIGN: begin
            if((cch_req_C.vaddr == pf_miss_end_C) && (cch_req_C.pid == pf_miss_C.pid) && (cch_req_C.strm == pf_miss_C.strm)) begin
                pf_miss_N.len = pf_miss_len_C;
            end

            cch_buff_sink.valid = 1'b1;
            cch_buff_sink.data = cch_req_C;
        end

        default: ;

	endcase // state_C
end

// Cache buff.
axis_data_fifo_cch_req_128 inst_cch_buff (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(cch_buff_sink.valid),
  .s_axis_tready(cch_buff_sink.ready),
  .s_axis_tdata (cch_buff_sink.data),
  .m_axis_tvalid(cch_buff_src.valid),
  .m_axis_tready(cch_buff_src.ready),
  .m_axis_tdata (cch_buff_src.data)
);

assign m_pfault_rng = pf_rng_C;

// buff.
`ifdef EN_STRM
ram_sp_c #(
    .ADDR_BITS(N_OUTSTANDING_BITS),
    .DATA_BITS(4+HPID_BITS+LEN_BITS+VADDR_BITS)
) inst_host_ssn (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(req_host_in_we),
    .a_addr(req_host_addr),
    .a_data_in({4'h0, req_host_in_data}),
    .a_data_out({req_host_tmp, req_host_out_data})
);

queue_stream #(
    .QDEPTH(N_TLB_ACTV),
    .QTYPE(logic[2+STRM_BITS+DEST_BITS+PID_BITS-1:0])
) inst_ack_host_buff (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(ack_buff_host_sink_valid),
    .rdy_snk(ack_buff_host_sink_ready),
    .data_snk(ack_buff_host_sink_data),
    .val_src(ack_buff_host_src_valid),
    .rdy_src(ack_buff_host_src_ready),
    .data_src(ack_buff_host_src_data)
);
assign ack_buff_host_src_ready = hdma_rsp.done;

// Completions
assign m_host_done.valid = hdma_rsp.done && ack_buff_host_src_data[PID_BITS+DEST_BITS+STRM_BITS+1+:1];
assign m_host_done.data.pid = ack_buff_host_src_data[0+:PID_BITS];
assign m_host_done.data.dest = ack_buff_host_src_data[PID_BITS+:DEST_BITS];
assign m_host_done.data.strm = ack_buff_host_src_data[PID_BITS+DEST_BITS+:STRM_BITS];
assign m_host_done.data.host = ack_buff_host_src_data[PID_BITS+DEST_BITS+STRM_BITS+:1];
assign m_host_done.data.opcode = RDWR ? LOCAL_WRITE : LOCAL_READ;
assign m_host_done.data.remote = 1'b0;
assign m_host_done.data.vfid = ID_REG;
`endif

`ifdef EN_MEM
for(genvar i = 0; i < N_CARD_AXI; i++) begin
    ram_sp_c #(
        .ADDR_BITS(N_OUTSTANDING_BITS),
        .DATA_BITS(4+HPID_BITS+LEN_BITS+VADDR_BITS)
    ) inst_card_ssn (
        .clk(aclk),
        .a_en(1'b1),
        .a_we(req_card_in_we[i]),
        .a_addr(req_card_addr[i]),
        .a_data_in({4'h0, req_card_in_data[i]}),
        .a_data_out({req_card_tmp[i], req_card_out_data[i]})
    );

    queue_stream #(
        .QDEPTH(N_TLB_ACTV),
        .QTYPE(logic[2+STRM_BITS+DEST_BITS+PID_BITS-1:0])
    ) inst_ack_card_buff (
        .aclk(aclk),
        .aresetn(aresetn),
        .val_snk(ack_buff_card_sink_valid[i]),
        .rdy_snk(ack_buff_card_sink_ready[i]),
        .data_snk(ack_buff_card_sink_data[i]),
        .val_src(ack_buff_card_src_valid[i]),
        .rdy_src(ack_buff_card_src_ready[i]),
        .data_src(ack_buff_card_src_data[i])
    );
    assign ack_buff_card_src_ready[i] = ddma_rsp[i].done;

    // Completions
    assign card_done[i].valid = ddma_rsp[i].done && ack_buff_card_src_data[i][PID_BITS+DEST_BITS+STRM_BITS+1+:1];
    assign card_done[i].data.pid = ack_buff_card_src_data[i][0+:PID_BITS];
    assign card_done[i].data.dest = ack_buff_card_src_data[i][PID_BITS+:DEST_BITS];
    assign card_done[i].data.strm = ack_buff_card_src_data[i][PID_BITS+DEST_BITS+:STRM_BITS];
    assign card_done[i].data.host = ack_buff_card_src_data[i][PID_BITS+DEST_BITS+STRM_BITS+:1];
    assign card_done[i].data.opcode = RDWR ? LOCAL_WRITE : LOCAL_READ;
    assign card_done[i].data.remote = 1'b0;
    assign card_done[i].data.vfid = ID_REG;
    assign card_done[i].data.rsrvd = 0;

    // Current card destination
    assign ccurr_dest = dest_C[N_CARD_AXI_BITS-1:0];
end

`ifdef MULT_CARD_AXI
    for(genvar i = 0; i < N_CARD_AXI; i++)
        queue_meta #(.QDEPTH(8)) inst_cmpl_q (.aclk(aclk), .aresetn(aresetn), .s_meta(card_done[i]), .m_meta(card_done_q[i]));

    meta_arbiter #(.N_ID(N_CARD_AXI), .N_ID_BITS(N_CARD_AXI_BITS), .DATA_BITS($bits(ack_t))) inst_arb_card_done (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_meta(card_done_q),
        .m_meta(m_card_done)
    ); 
`else
    queue_meta #(.QDEPTH(8)) inst_cmpl_q (.aclk(aclk), .aresetn(aresetn), .s_meta(card_done[0]), .m_meta(card_done_q[0]));
    `META_ASSIGN(card_done_q[0], m_card_done)
`endif
`endif

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
//`define DBG_TLB_FSM
`ifdef DBG_TLB_FSM

`endif

endmodule