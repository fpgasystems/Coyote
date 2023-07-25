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
 * @brief   TLB FSM. 
 *
 * TLB state machine. Read-write engine locks. Handles ISR.
 * Resource consumption depends on the config.
 *
 *  @param ID_REG   Number of associated vFPGA
 *  @param RDWR     Read or write requests (Mutex lock)
 */
module tlb_fsm_rd #(
	parameter integer ID_REG = 0,
	parameter integer RDWR = 0
) (
	input logic							aclk,    
	input logic 						aresetn,

	// TLBs
	tlbIntf.m 							lTlb,
	tlbIntf.m							sTlb,

	// User logic
`ifdef EN_STRM
	metaIntf.m   						m_host_done,
`endif

`ifdef EN_MEM
	metaIntf.m   						m_card_done,
	metaIntf.m   						m_sync_done,
`endif

	metaIntf.m  						m_pfault,
	input  logic 						restart,

	// Requests
	metaIntf.s 							s_req,

	// DMA - host
`ifdef EN_STRM
	dmaIntf.m   						m_HDMA, // Host
`endif

	// DMA - card
`ifdef EN_MEM
	dmaIntf.m 							m_DDMA, // Card
	dmaIsrIntf.m 	    				m_IDMA, // Page fault, sync
`endif

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
localparam integer TLB_L_DATA_BITS = TAG_L_BITS + PID_BITS + 1 + 2*PHY_L_BITS;
localparam integer TLB_S_DATA_BITS = TAG_S_BITS + PID_BITS + 1 + 2*PHY_S_BITS;
localparam integer TLB_L_VAL_BIT = TAG_L_BITS + PID_BITS;
localparam integer TLB_S_VAL_BIT = TAG_S_BITS + PID_BITS;
localparam integer PHY_L_OFFS = TAG_L_BITS + PID_BITS + 1;
localparam integer PHY_S_OFFS = TAG_S_BITS + PID_BITS + 1;

// -- FSM ---------------------------------------------------------------------------------------------------
typedef enum logic[3:0]  {ST_IDLE, ST_MUTEX, ST_WAIT, ST_CHECK,
					      ST_HIT_LARGE, ST_HIT_SMALL, ST_CALC_LARGE, ST_CALC_SMALL, // timing extra states
`ifdef EN_STRM
                          ST_HOST_SEND,
`endif
`ifdef EN_MEM
						  ST_ISR_WAIT,
                          ST_CARD_SEND, ST_SYNC_SEND, ST_ISR_SEND,
`endif
                          ST_MISS} state_t;
logic [3:0] state_C, state_N;

// -- Internal registers ------------------------------------------------------------------------------------
// Request
logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] vaddr_C, vaddr_N;
logic sync_C, sync_N;
logic ctl_C, ctl_N;
logic strm_C, strm_N;
logic [DEST_BITS-1:0] dest_C, dest_N;
logic [PID_BITS-1:0] pid_C, pid_N;
logic val_C, val_N;
logic host_C, host_N;

// TLB data
logic [TLB_L_DATA_BITS-1:0] data_l_C, data_l_N;
logic [TLB_S_DATA_BITS-1:0] data_s_C, data_s_N;

// Page fault
logic unlock_C, unlock_N;
logic miss_C, miss_N;
logic [LEN_BITS-1:0] len_miss_C, len_miss_N;
logic [VADDR_BITS-1:0] vaddr_miss_C, vaddr_miss_N;
logic [PID_BITS-1:0] pid_miss_C, pid_miss_N;
logic isr_C, isr_N;

// -- Out
logic [LEN_BITS-1:0] plen_C, plen_N;
logic [PADDR_BITS-1:0] paddr_host_C, paddr_host_N;
logic [PADDR_BITS-1:0] paddr_card_C, paddr_card_N;

// -- Internal signals --------------------------------------------------------------------------------------

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
	sync_C <= 'X;
	ctl_C <= 'X;
	strm_C <= 'X;
	host_C <= 'X;
	dest_C <= 'X;
	pid_C <= 'X;
	val_C <= 1'b0;
	// TLB
	plen_C <= 'X;
	data_l_C <= 'X;
	data_s_C <= 'X;
	paddr_host_C <= 'X;
`ifdef EN_MEM
    paddr_card_C <= 'X;
`endif
    // ISR
	miss_C <= 0;
	unlock_C <= 0;
    isr_C <= 0;
	len_miss_C <= 'X;
	vaddr_miss_C <= 'X;
	pid_miss_C <= 'X;
end
else
	state_C <= state_N;

    // Requests
	len_C <= len_N;
	vaddr_C <= vaddr_N;
	sync_C <= sync_N;
	ctl_C <= ctl_N;
	strm_C <= strm_N;
	host_C <= host_N;
	dest_C <= dest_N;
	pid_C <= pid_N;
	val_C <= val_N;
    // TLB
	plen_C <= plen_N;
	data_l_C <= data_l_N;	
	data_s_C <= data_s_N;	
	paddr_host_C <= paddr_host_N;
`ifdef EN_MEM
    paddr_card_C <= paddr_card_N;
`endif
    // ISR
	miss_C <= miss_N;
	unlock_C <= unlock_N;
    isr_C <= isr_N;
    len_miss_C <= len_miss_N;
	vaddr_miss_C <= vaddr_miss_N;
	pid_miss_C <= pid_miss_N;
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		// Wait until request queue is not empty
		ST_IDLE: 
			state_N = (s_req.valid) ? (s_req.data.len == 0 ? ST_IDLE : ST_MUTEX) : ST_IDLE;
		
        // Obtain mutex
        ST_MUTEX:
			state_N = ((mutex[1] == RDWR) && (mutex[0] == 1'b0)) ? ST_WAIT : ST_MUTEX;

		// Wait on BRAM (out reg) - only with high freq. clk
		ST_WAIT:
			state_N = ST_CHECK;

		// Check hits
		ST_CHECK:
            state_N = lTlb.hit ? ST_HIT_LARGE : sTlb.hit ? ST_HIT_SMALL : ST_MISS;

        // Page parsing
		ST_HIT_LARGE:
			state_N = ST_CALC_LARGE;
		ST_HIT_SMALL:
			state_N = ST_CALC_SMALL;
		
		// Calc.
		ST_CALC_LARGE:
`ifdef EN_STRM
    `ifdef EN_MEM
			if(strm_C) 
				state_N = ST_HOST_SEND;
			else
				state_N = isr_C ? ST_ISR_SEND : sync_C ? ST_SYNC_SEND : ST_CARD_SEND;
    `else
			state_N = ST_HOST_SEND;
    `endif
`else
			state_N = isr_C ? ST_ISR_SEND : sync_C ? ST_SYNC_SEND : ST_CARD_SEND;
`endif
		ST_CALC_SMALL:
`ifdef EN_STRM
	`ifdef EN_MEM
			if(strm_C) 
				state_N = ST_HOST_SEND;
			else
				state_N = isr_C ? ST_ISR_SEND : sync_C ? ST_SYNC_SEND : ST_CARD_SEND;
	`else
			state_N = ST_HOST_SEND;
	`endif
`else
			state_N = isr_C ? ST_ISR_SEND : sync_C ? ST_SYNC_SEND : ST_CARD_SEND;
`endif

        // Send DMA requests
`ifdef EN_STRM
		ST_HOST_SEND:
			if(m_HDMA.ready)
				state_N = len_C ? ST_MUTEX : ST_IDLE;
`endif

`ifdef EN_MEM
		ST_CARD_SEND:
            if(m_DDMA.ready)
                state_N = len_C ? ST_MUTEX : ST_IDLE;    
        ST_SYNC_SEND: 
            if(m_IDMA.ready) 
                state_N = len_C ? ST_MUTEX : ST_IDLE;
        ST_ISR_SEND:
            if(m_IDMA.ready)
                state_N = len_C ? ST_MUTEX : ST_ISR_WAIT;

		// Wait until data is fetched
		ST_ISR_WAIT:
            state_N = m_IDMA.rsp.done && m_IDMA.rsp.isr ? ST_MUTEX : ST_ISR_WAIT;
`endif
		
		// Page fault
		ST_MISS:
			state_N = restart ? ST_MUTEX : ST_MISS;

	endcase // state_C
end

// DP
always_comb begin: DP
	// Requests
    len_N = len_C;
	vaddr_N = vaddr_C;
	sync_N = sync_C;
	ctl_N = ctl_C;
	strm_N = strm_C;
	host_N = host_C;
	dest_N = dest_C;
	pid_N = pid_C;
	val_N = 1'b0;

	// TLB
    data_l_N = data_l_C;
	data_s_N = data_s_C;
    
	// Out
	plen_N = plen_C;
	paddr_host_N = paddr_host_C;
`ifdef EN_MEM
    paddr_card_N = paddr_card_C;
`endif

    // ISR
	unlock_N = 1'b0;
	miss_N = 1'b0;
	vaddr_miss_N = vaddr_miss_C;
    len_miss_N = len_miss_C;
	pid_miss_N = pid_miss_C;
    isr_N = isr_C;

	// mutex
	lock = 1'b0;
	unlock = unlock_C;

	// Requests
	s_req.ready = 1'b0;

	// Config
`ifdef EN_STRM
	m_host_done.valid = m_HDMA.rsp.done;
	m_host_done.data.done = m_HDMA.rsp.done;
	m_host_done.data.host = m_HDMA.rsp.host;
	m_host_done.data.stream = m_HDMA.rsp.stream;
	m_host_done.data.dest = m_HDMA.rsp.dest;
	m_host_done.data.pid = m_HDMA.rsp.pid;
`endif

`ifdef EN_MEM
	m_card_done.valid = m_DDMA.rsp.done;
	m_card_done.data.done = m_DDMA.rsp.done;
	m_card_done.data.host = m_DDMA.rsp.host;
	m_card_done.data.stream = m_DDMA.rsp.stream;
	m_card_done.data.dest = m_DDMA.rsp.dest;
	m_card_done.data.pid = m_DDMA.rsp.pid;

	m_sync_done.valid = m_IDMA.rsp.done & ~m_IDMA.rsp.isr;
	m_sync_done.data.done = m_IDMA.rsp.done;
	m_sync_done.data.host = m_IDMA.rsp.host;
	m_sync_done.data.stream = m_IDMA.rsp.stream;
	m_sync_done.data.dest = m_IDMA.rsp.dest;
	m_sync_done.data.pid = m_IDMA.rsp.pid;
`endif

	m_pfault.valid = miss_C;
	m_pfault.data[0+:VADDR_BITS] = vaddr_miss_C;
	m_pfault.data[VADDR_BITS+:LEN_BITS] = len_miss_C;
	m_pfault.data[VADDR_BITS+LEN_BITS+:PID_BITS] = pid_miss_C;

	// TLB
	lTlb.addr = vaddr_C;
	lTlb.wr = 1'b0;
	lTlb.pid = pid_C;
	lTlb.valid = val_C;

	sTlb.addr = vaddr_C;
	sTlb.wr = 1'b0;
	sTlb.pid = pid_C;
	sTlb.valid = val_C;

`ifdef EN_STRM
	// m_HDMA
	m_HDMA.req.paddr = paddr_host_C;
	m_HDMA.req.len = plen_C;
	m_HDMA.req.ctl = 1'b0;
	m_HDMA.req.dest = dest_C;
	m_HDMA.req.pid = pid_C;
	m_HDMA.req.stream = strm_C;
	m_HDMA.req.host = host_C;
	m_HDMA.req.rsrvd = 0;
	m_HDMA.valid = 1'b0;
`endif

`ifdef EN_MEM
	// m_DDMA
	m_DDMA.req.paddr = paddr_card_C;
	m_DDMA.req.len = plen_C;
	m_DDMA.req.ctl = 1'b0;
	m_DDMA.req.dest = dest_C;
	m_DDMA.req.pid = pid_C;
	m_DDMA.req.stream = strm_C;
	m_DDMA.req.host = host_C;
	m_DDMA.req.rsrvd = 0;
	m_DDMA.valid = 1'b0;

	// m_IDMA
	m_IDMA.req.paddr_card = paddr_card_C;
    m_IDMA.req.paddr_host = paddr_host_C;
	m_IDMA.req.len = plen_C;
	m_IDMA.req.ctl = 1'b0;
	m_IDMA.req.dest = dest_C;
	m_IDMA.req.pid = pid_C;
    m_IDMA.req.isr = 1'b0;
	m_IDMA.req.stream = strm_C;
	m_IDMA.req.host = host_C;
	m_IDMA.req.rsrvd = 0;
	m_IDMA.valid = 1'b0;
`endif

	case(state_C)
		ST_IDLE: begin			
			isr_N = 1'b0;
			s_req.ready = 1'b1;
            if(s_req.valid) begin // RR
				// Lock the mutex
                lock = 1'b1;

                // Request
				len_N = s_req.data.len;
				vaddr_N = s_req.data.vaddr;
				sync_N = s_req.data.sync;
				ctl_N = s_req.data.ctl;
				strm_N = s_req.data.stream;
				host_N = s_req.data.host;
				dest_N = s_req.data.dest;
				pid_N = s_req.data.pid;
				val_N = 1'b1;
			end
		end
		
		ST_MUTEX: 
			lock = 1'b1;

		ST_CHECK:
`ifdef EN_STRM
	`ifdef EN_MEM
			if(lTlb.hit || sTlb.hit) begin
				if(strm_C)
					unlock_N = 1'b1;
				else
					unlock_N = (isr_C || sync_C) ? 1'b0 : 1'b1;
			end
	`else
			if(lTlb.hit || sTlb.hit) begin
				unlock_N = 1'b1;
			end
	`endif
`else
			if(lTlb.hit || sTlb.hit) begin
				unlock_N = (isr_C || sync_C) ? 1'b0 : 1'b1;
			end
`endif
			else begin
				miss_N = 1'b1;
				vaddr_miss_N = vaddr_C;
				len_miss_N = len_C;
				pid_miss_N = pid_C;
				isr_N = 1'b1;
			end

		ST_HIT_LARGE: begin
			data_l_N = lTlb.data[TLB_L_DATA_BITS-1:0];
		end

		ST_HIT_SMALL: begin
            data_s_N = sTlb.data[TLB_S_DATA_BITS-1:0];
		end

		ST_CALC_LARGE: begin
			paddr_host_N = {data_l_C[PHY_L_OFFS+:PHY_L_BITS], vaddr_C[0+:PG_L_BITS]};
`ifdef EN_MEM
			paddr_card_N = {data_l_C[PHY_L_OFFS+PHY_L_BITS+:PHY_L_BITS], vaddr_C[0+:PG_L_BITS]};
`endif
			if(len_C + vaddr_C[PG_L_BITS-1:0] > PG_L_SIZE) begin
				plen_N = PG_L_SIZE - vaddr_C[PG_L_BITS-1:0];
				len_N = len_C - (PG_L_SIZE - vaddr_C[PG_L_BITS-1:0]);
				vaddr_N += PG_L_SIZE - vaddr_C[PG_L_BITS-1:0];
			end
			else begin
				plen_N = len_C;
				len_N = 0;
			end
		end

		ST_CALC_SMALL: begin
			paddr_host_N = {data_s_C[PHY_S_OFFS+:PHY_S_BITS], vaddr_C[0+:PG_S_BITS]};
`ifdef EN_MEM
			paddr_card_N = {data_s_C[PHY_S_OFFS+PHY_S_BITS+:PHY_S_BITS], vaddr_C[0+:PG_S_BITS]};
`endif
			if(len_C + vaddr_C[PG_S_BITS-1:0] > PG_S_SIZE) begin
				plen_N = PG_S_SIZE - vaddr_C[PG_S_BITS-1:0];
				len_N = len_C - (PG_S_SIZE - vaddr_C[PG_S_BITS-1:0]);
				vaddr_N += PG_S_SIZE - vaddr_C[PG_S_BITS-1:0];
			end
			else begin
				plen_N = len_C;
				len_N = 0;
			end
		end

`ifdef EN_STRM
		ST_HOST_SEND: begin
			m_HDMA.valid = m_HDMA.ready;
			m_HDMA.req.ctl = m_HDMA.valid && !len_C && ctl_C;
			val_N = m_HDMA.ready && len_C;
		end
`endif

`ifdef EN_MEM
        ST_CARD_SEND: begin
            m_DDMA.valid = m_DDMA.ready;
            m_DDMA.req.ctl = m_DDMA.valid && !len_C && ctl_C;
			val_N = m_DDMA.ready && len_C;
        end

        ST_SYNC_SEND: begin
            m_IDMA.valid = m_IDMA.ready;
            m_IDMA.req.ctl = m_IDMA.valid && !len_C && ctl_C;
            m_IDMA.req.isr = 1'b0;
			unlock_N = m_IDMA.valid && !len_C;
			val_N = m_IDMA.ready && len_C;
        end

        ST_ISR_SEND: begin
            m_IDMA.valid = m_IDMA.ready;
            m_IDMA.req.ctl = m_IDMA.valid && !len_C;
            m_IDMA.req.isr = 1'b1;
			unlock_N = m_IDMA.valid && !len_C;
			val_N = m_IDMA.ready && len_C;
        end

        ST_ISR_WAIT: begin
            vaddr_N = vaddr_miss_C;
            len_N = len_miss_C;
            isr_N = 1'b0;
			lock = m_IDMA.rsp.done && m_IDMA.rsp.isr;
			val_N = m_IDMA.rsp.done && m_IDMA.rsp.isr;
        end
`endif

		ST_MISS: begin
			val_N = restart;
		end

        default: ;

	endcase // state_C
end

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
//`define DBG_TLB_FSM_RD
`ifdef DBG_TLB_FSM_RD
ila_fsm inst_ila_rd (
	.clk(aclk),
	.probe0(len_C), // 28
	.probe1(vaddr_C), // 48
	.probe2(ctl_C),
	.probe3(val_C),
	.probe4(pid_C), // 6
	.probe5(state_C), // 4
	.probe6(plen_C), // 28
	.probe7(paddr_host_C), // 40
	.probe8(data_l_C), // 63
	.probe9(data_s_C) // 89
);

`endif

endmodule