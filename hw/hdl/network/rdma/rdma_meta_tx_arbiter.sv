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
 * @brief   RDMA TX meta arbitration
 *
 * Arbitration layer between all present user regions
 */
module rdma_meta_tx_arbiter (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                          s_meta [N_REGIONS],
    metaIntf.m                          m_meta,

    // Data
    AXI4S.s                             s_axis_rd [N_REGIONS],
    AXI4S.m                             m_axis_rd,                      

    // ID
    output logic [N_REGIONS_BITS-1:0]   vfid
);

`ifdef MULT_REGIONS

logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
dreq_t [N_REGIONS-1:0] req_snk;

logic ready_src;
logic valid_src;
dreq_t [N_REGIONS-1:0] req_src;

logic [N_REGIONS_BITS-1:0] rr_reg;

metaIntf #(.STYPE(dreq_t)) meta_que [N_REGIONS] ();

logic is_read;

logic [N_REGIONS_BITS-1:0] vfid;
logic [N_REGIONS_BITS-1:0] vfid_next;
logic [LEN_BITS-1:0] len_next;

metaIntf #(.STYPE(logic[N_REGIONS_BITS+LEN_BITS-1:0])) user_seq_in ();
logic seq_src_valid;
logic seq_src_ready;

// -------------------------------------------------------------------------------- 
// I/O !!! interface 
// -------------------------------------------------------------------------------- 
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = meta_que[i].valid;
    assign meta_que[i].ready = ready_snk[i];
    assign req_snk[i] = meta_que[i].data;    
end

assign m_meta.valid = valid_src;
assign ready_src = m_meta.ready;
assign m_meta.data = req_src;

for(genvar i = 0; i < N_REGIONS; i++) begin
    axis_data_fifo_cnfg_rdma_256 inst_tx_queue (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta[i].valid),
        .s_axis_tready(s_meta[i].ready),
        .s_axis_tdata(s_meta[i].data),
        .m_axis_tvalid(meta_que[i].valid),
        .m_axis_tready(meta_que[i].ready),
        .m_axis_tdata(meta_que[i].data),
        .axis_wr_data_count()
    );
end

// -------------------------------------------------------------------------------- 
// RR 
// -------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_REGIONS-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    vfid = 0;
    
    for(int i = 0; i < N_REGIONS; i++) begin
        if(i+rr_reg >= N_REGIONS) begin
            if(valid_snk[i+rr_reg-N_REGIONS]) begin
                vfid = i+rr_reg-N_REGIONS;
                is_read = is_opcode_rd_req(req_snk[vfid].req_1.opcode);

                if(is_read) begin
                    valid_src = valid_snk[vfid];
                end
                else begin
                    valid_src = valid_snk[vfid] & user_seq_in.ready;
                end
                
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                vfid = i+rr_reg;
                is_read = is_opcode_rd_req(req_snk[vfid].req_1.opcode);

                if(is_read) begin
                    valid_src = valid_snk[vfid];
                end
                else begin
                    valid_src = valid_snk[vfid] & user_seq_in.ready;
                end

                break;
            end
        end
    end

    ready_snk[vfid] = ready_src && (is_read ? 1'b1 : user_seq_in.ready);
    req_src = req_snk[vfid];
end

assign user_seq_in.valid = valid_src & ready_src;
assign user_seq_in.data = {vfid, request_snk[vfid].req_1.len};

// Multiplexer sequence
queue_stream #(
    .QTYPE(logic [N_REGIONS_BITS+LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(user_seq_in.valid),
    .rdy_snk(user_seq_in.ready),
    .data_snk(user_seq_in.data),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({vfid_next, len_next})
);

// --------------------------------------------------------------------------------
// Mux data
// --------------------------------------------------------------------------------

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;

logic tr_done; 

logic [AXI_NET_BITS-1:0] m_axis_rd_tdata;
logic [AXI_NET_BITS/8-1:0] m_axis_rd_tkeep;
logic m_axis_rd_tlast;
logic m_axis_rd_tvalid;
logic m_axis_rd_tready;

logic [N_REGIONS-1:0][AXI_NET_BITS-1:0] s_axis_rd_tdata;
logic [N_REGIONS-1:0][AXI_NET_BITS/8-1:0] s_axis_rd_tkeep;
logic [N_REGIONS-1:0] s_axis_rd_tlast;
logic [N_REGIONS-1:0] s_axis_rd_tvalid;
logic [N_REGIONS-1:0] s_axis_rd_tready;

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    axis_data_fifo_512_used inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_axis_rd[i].tvalid),
        .s_axis_tready(s_axis_rd[i].tready),
        .s_axis_tdata(s_axis_rd[i].tdata),
        .s_axis_tkeep(s_axis_rd[i].tkeep),
        .s_axis_tlast(s_axis_rd[i].tlast),
        .m_axis_tvalid(s_axis_rd_tvalid[i]),
        .m_axis_tready(s_axis_rd_tready[i]),
        .m_axis_tdata(s_axis_rd_tdata[i]),
        .m_axis_tkeep(s_axis_rd_tkeep[i]),
        .m_axis_tlast(s_axis_rd_tlast[i]),
        .axis_wr_data_count()
    );
end

assign m_axis_rd.tvalid = m_axis_rd_tvalid;
assign m_axis_rd.tdata  = m_axis_rd_tdata;
assign m_axis_rd.tkeep  = m_axis_rd_tkeep;
assign m_axis_rd.tlast  = m_axis_rd_tlast;
assign m_axis_rd_tready = m_axis_rd.tready;

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
        vfid_C <= vfid_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (seq_src_valid) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (seq_src_valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;
    vfid_N = vfid_C;
    
    // Transfer done
    tr_done = (cnt_C == 0) && (m_axis_rd_tvalid & m_axis_rd_tready);

    seq_src_ready = 1'b0;

    // Last gen (not needed)
    //m_axis_rd_tlast = 1'b0;

    case(state_C)
        ST_IDLE: begin
            if(seq_src_valid) begin
                seq_src_ready = 1'b1;
                vfid_N = vfid_next;
                cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(seq_src_valid) begin
                    seq_src_ready = 1'b1;
                    vfid_N = vfid_next;
                    cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                cnt_N = (m_axis_rd_tvalid & m_axis_rd_tready) ? cnt_C - 1 : cnt_C;
            end
        end

    endcase
end

// Mux
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign s_axis_rd_tready[i] = (state_C == ST_MUX) ? ((i == vfid_C) ? m_axis_rd_tready : 1'b0) : 1'b0; 
end

assign m_axis_rd_tvalid = (state_C == ST_MUX) ? s_axis_rd_tvalid[vfid_C] : 1'b0;
assign m_axis_rd_tdata = s_axis_rd_tdata[vfid_C];
assign m_axis_rd_tkeep = s_axis_rd_tkeep[vfid_C];
assign m_axis_rd_tlast = s_axis_rd_tlast[vfid_C];

`else

    axis_data_fifo_cnfg_rdma_256 inst_tx_queue (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_meta[0].valid),
        .s_axis_tready(s_meta[0].ready),
        .s_axis_tdata(s_meta[0].data),
        .m_axis_tvalid(m_meta.valid),
        .m_axis_tready(m_meta.ready),
        .m_axis_tdata(m_meta.data),
        .axis_wr_data_count()
    );

    axis_data_fifo_512_used inst_data_que (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_axis_rd[0].tvalid),
        .s_axis_tready(s_axis_rd[0].tready),
        .s_axis_tdata (s_axis_rd[0].tdata),
        .s_axis_tkeep (s_axis_rd[0].tkeep),
        .s_axis_tlast (s_axis_rd[0].tlast),
        .m_axis_tvalid(m_axis_rd.tvalid),
        .m_axis_tready(m_axis_rd.tready),
        .m_axis_tdata (m_axis_rd.tdata),
        .m_axis_tkeep (m_axis_rd.tkeep),
        .m_axis_tlast (m_axis_rd.tlast),
        .axis_wr_data_count()
    );

`endif

endmodule