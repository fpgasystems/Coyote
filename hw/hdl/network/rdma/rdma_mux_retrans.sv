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
 * @brief   RDMA retrans multiplexer
 * Used for split-up of the interfaces: 1 Interface towards the HLS stack, 2 interfaces exposed to the roce_stack 
 *
 */
module rdma_mux_retrans (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req_net, // Incoming read requests from the HLS-stack
    metaIntf.m              m_req_user, // Outgoing read requests to the roce_stack
    AXI4S.s                 s_axis_user_req, // Incoming data (rd_req) from the roce_stack
    AXI4S.s                 s_axis_user_rsp, // Incoming data (rd_rsp) from the roce_stack 
    AXI4S.m                 m_axis_net, // Outgoing data to the HLS-stack 

    metaIntf.m              m_req_ddr_rd, // Outgoing read commands to the roce_stack
    metaIntf.m              m_req_ddr_wr, // Outgoing write commands to the roce_stack
    AXI4S.s                 s_axis_ddr, // Incoming data (mem_rd) from the roce_stack 
    AXI4S.m                 m_axis_ddr // Outgoing data (mem_wr) to the roce_stack 

    // Write data from the HLS-stack to the roce_stack are directly forwarded, as well as WRITE-requests / commands 
);

// Parameter for the number of outstanding bits, with a bit-counter 
localparam integer RDMA_N_OST = RDMA_N_WR_OUTSTANDING;
localparam integer RDMA_OST_BITS = $clog2(RDMA_N_OST);

// sink and source signals for requests and commands 
logic seq_snk_valid;
logic seq_snk_ready;
logic seq_src_valid;
logic seq_src_ready;

// Signals for 
logic [LEN_BITS-1:0] len_snk;
logic [LEN_BITS-1:0] len_next;
logic actv_snk;
logic actv_next;
logic rd_snk;
logic rd_next;

// Signals to connect to the queues that lead to the control signals toward the top-level module 
metaIntf #(.STYPE(req_t)) req_user ();
metaIntf #(.STYPE(logic[MEM_CMD_BITS-1:0])) req_ddr_rd ();
metaIntf #(.STYPE(logic[MEM_CMD_BITS-1:0])) req_ddr_wr ();

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------

// Queues for all control interfaces to / from the top-level-design 
meta_queue #(.DATA_BITS($bits(req_t))) inst_meta_user_q (.aclk(aclk), .aresetn(aresetn), .s_meta(req_user), .m_meta(m_req_user));
meta_queue #(.DATA_BITS(MEM_CMD_BITS)) inst_meta_ddr_rd_q (.aclk(aclk), .aresetn(aresetn), .s_meta(req_ddr_rd), .m_meta(m_req_ddr_rd));
meta_queue #(.DATA_BITS(MEM_CMD_BITS)) inst_meta_ddr_wr_q (.aclk(aclk), .aresetn(aresetn), .s_meta(req_ddr_wr), .m_meta(m_req_ddr_wr));

// Get the sink-values from incoming mem-read-command from the HLS-networking stack
assign len_snk = s_req_net.data.len[LEN_BITS-1:0];
assign actv_snk = s_req_net.data.actv;
assign rd_snk = is_opcode_rd_resp(s_req_net.data.opcode);

// --------------------------------------------------------------------------------
// Mux command
// --------------------------------------------------------------------------------
always_comb begin
    if(actv_snk) begin
        // User - action initiated by the active signals set in the s_req_net port, which is connected to the HLS-networking-stack
        if(rd_snk) begin
            // Case: READ RESPONSE 
            seq_snk_valid = seq_snk_ready & req_user.ready & s_req_net.valid;
            req_user.valid = seq_snk_valid;
            req_ddr_rd.valid = 1'b0;
            req_ddr_wr.valid = 1'b0;

            s_req_net.ready = seq_snk_ready & req_user.ready;
        end
        else begin
            // case: WRITE (probably? But why do you need to request data for this? Shouldn't it be automatically delivered to the stack?)
            seq_snk_valid = seq_snk_ready & req_ddr_wr.ready & s_req_net.valid;
            req_user.valid = 1'b0;
            req_ddr_rd.valid = 1'b0;
            req_ddr_wr.valid = seq_snk_valid;

            s_req_net.ready = seq_snk_ready & req_ddr_wr.ready;
        end
    end
    else begin
        // Retrans - no active signal set in the s_req_net port, indicates a required retransmission
        seq_snk_valid = seq_snk_ready & req_ddr_rd.ready & s_req_net.valid;
        req_user.valid = 1'b0;
        req_ddr_rd.valid = seq_snk_valid;
        req_ddr_wr.valid = 1'b0;

        s_req_net.ready = seq_snk_ready & req_ddr_rd.ready;
    end
end

// Construct the required control-signals towards the top-level-module from the s_req_net-port that is fed by the HLS-stack
always_comb begin
    req_ddr_rd.data = 0;
    req_ddr_rd.data[0+:64] = (64'b0 | 
                             (s_req_net.data.vfid << PID_BITS + RDMA_OST_BITS + $clog2(PMTU_BYTES)) | 
                             (s_req_net.data.pid   << RDMA_OST_BITS + $clog2(PMTU_BYTES)) | 
                             (s_req_net.data.offs  << $clog2(PMTU_BYTES))) << RDMA_MEM_SHIFT;
    req_ddr_rd.data[64+:32] = s_req_net.data.len;

    req_ddr_wr.data = 0;
    req_ddr_wr.data[0+:64] = (64'b0 | 
                             (s_req_net.data.vfid << PID_BITS + RDMA_OST_BITS + $clog2(PMTU_BYTES)) | 
                             (s_req_net.data.pid   << RDMA_OST_BITS + $clog2(PMTU_BYTES)) | 
                             (s_req_net.data.offs  << $clog2(PMTU_BYTES))) << RDMA_MEM_SHIFT;
    req_ddr_wr.data[64+:32] = s_req_net.data.len;

    req_user.data = s_req_net.data;
end

// Queue for requests with sink and source 
queue_stream #(
    .QTYPE(logic [1+1+LEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que_snk (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(seq_snk_valid),
    .rdy_snk(seq_snk_ready),
    .data_snk({rd_snk, actv_snk, len_snk}),
    .val_src(seq_src_valid),
    .rdy_src(seq_src_ready),
    .data_src({rd_next, actv_next, len_next})
);

// --------------------------------------------------------------------------------
// Mux data
// --------------------------------------------------------------------------------

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

logic rd_C, rd_N;
logic actv_C, actv_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N, cnt_ddr_wr;

logic tr_done; 

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_net ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_ddr_wr ();

// --------------------------------------------------------------------------------
// I/O !!! interface 
// --------------------------------------------------------------------------------

// Queue for data towards the HLS-stack 
axis_data_fifo_512 inst_data_que_net (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(axis_net.tvalid),
    .s_axis_tready(axis_net.tready),
    .s_axis_tdata (axis_net.tdata),
    .s_axis_tkeep (axis_net.tkeep),
    .s_axis_tlast (axis_net.tlast),
    .m_axis_tvalid(m_axis_net.tvalid),
    .m_axis_tready(m_axis_net.tready),
    .m_axis_tdata (m_axis_net.tdata),
    .m_axis_tkeep (m_axis_net.tkeep),
    .m_axis_tlast (m_axis_net.tlast)
);

// Queue for data towards the top-level module 
axis_data_fifo_512 inst_data_que_ddr (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(axis_ddr_wr.tvalid),
    .s_axis_tready(axis_ddr_wr.tready),
    .s_axis_tdata (axis_ddr_wr.tdata),
    .s_axis_tkeep (axis_ddr_wr.tkeep),
    .s_axis_tlast (axis_ddr_wr.tlast),
    .m_axis_tvalid(m_axis_ddr.tvalid),
    .m_axis_tready(m_axis_ddr.tready),
    .m_axis_tdata (m_axis_ddr.tdata),
    .m_axis_tkeep (m_axis_ddr.tkeep),
    .m_axis_tlast (m_axis_ddr.tlast)
);

// REG - move on states of the FSM according 
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;

        cnt_C <= 0;
        actv_C <= 'X;
        rd_C <= 'X;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
        actv_C <= actv_N;
        rd_C <= rd_N;
    end
end

// NSL - state transition function 
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
        // If there's a valid request coming from the source, switch to MUX-state
		ST_IDLE: 
			state_N = (seq_src_valid) ? ST_MUX : ST_IDLE;

        // If done, switch back to IDLE 
        ST_MUX:
            state_N = tr_done ? (seq_src_valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// DP
always_comb begin: DP
    cnt_N = cnt_C;
    actv_N = actv_C;
    rd_N = rd_C;
    
    // Transfer done if the counter-value is at 0 and interfaces are ready 
    tr_done = (cnt_C == 0) && 
        (actv_C ? 
            (rd_C ? (s_axis_user_rsp.tvalid & s_axis_user_rsp.tready) : 
                    (s_axis_user_req.tvalid & s_axis_user_req.tready) ) :
            (s_axis_ddr.tvalid & s_axis_ddr.tready) );

    seq_src_ready = 1'b0;

    case(state_C)
        ST_IDLE: begin
            // Get the values for the counter etc. from the sink/source-queue 
            if(seq_src_valid) begin
                seq_src_ready = 1'b1;
                rd_N = rd_next;
                actv_N = actv_next;
                cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
            end
        end
            
        ST_MUX: begin
            if(tr_done) begin
                // If done, set the counter next to 0 
                cnt_N = 0;
                // Get the next values from the sink/source-queue
                if(seq_src_valid) begin
                    seq_src_ready = 1'b1;
                    rd_N = rd_next;
                    actv_N = actv_next;
                    cnt_N = (len_next[BEAT_LOG_BITS-1:0] != 0) ? len_next[LEN_BITS-1:BEAT_LOG_BITS] : len_next[LEN_BITS-1:BEAT_LOG_BITS] - 1;
                end
            end
            else begin
                // If not done, decrement the counter according to transmission state on the data-ports 
                cnt_N = actv_C ? 
                   (rd_C ? ( (s_axis_user_rsp.tvalid & s_axis_user_rsp.tready ? cnt_C - 1 : cnt_C) ) : 
                           ( (s_axis_user_req.tvalid & s_axis_user_req.tready ? cnt_C - 1 : cnt_C) ) ) :
                   ( (s_axis_ddr.tvalid & s_axis_ddr.tready ? cnt_C - 1 : cnt_C) );
            end
        end

    endcase
end

// Counting the outgoing data transmissions to the retrans buffer 
always_ff @ (posedge aclk) begin 

    if(aresetn == 1'b0) begin 
        cnt_ddr_wr <= 1'b0; 
    end else begin 
        if(s_req_net.valid) begin 
            // Once a new command comes in, set the transmission counter to the length transmitted via the command interface 
            cnt_ddr_wr <= s_req_net.data.len[LEN_BITS-1:0]/64; 
        end else begin
            // Decrement the counter with every successfull write to the retrans-memory 
            cnt_ddr_wr <= (axis_ddr_wr.tvalid & axis_ddr_wr.tready) ? (cnt_ddr_wr-1) : cnt_ddr_wr; 
        end 
    end 
end 

// Mux
always_comb begin
    if(state_C == ST_MUX) begin
        if(actv_C) begin
            if(rd_C) begin
                s_axis_user_req.tready = 1'b0;
                s_axis_user_rsp.tready = axis_net.tready;
                s_axis_ddr.tready = 1'b0;

                axis_net.tvalid = s_axis_user_rsp.tvalid;
                axis_ddr_wr.tvalid = 1'b0;
            end
            else begin
                s_axis_user_req.tready = axis_net.tready & axis_ddr_wr.tready;
                s_axis_user_rsp.tready = 1'b0;
                s_axis_ddr.tready = 1'b0;

                axis_net.tvalid = s_axis_user_req.tvalid & s_axis_user_req.tready;
                axis_ddr_wr.tvalid = s_axis_user_req.tvalid & s_axis_user_req.tready;
            end
        end
        else begin
            s_axis_user_req.tready = 1'b0;
            s_axis_user_rsp.tready = 1'b0;
            s_axis_ddr.tready = axis_net.tready;

            axis_net.tvalid = s_axis_ddr.tvalid;
            axis_ddr_wr.tvalid = 1'b0;
        end
    end
    else begin
        s_axis_user_req.tready = 1'b0;
        s_axis_user_rsp.tready = 1'b0;
        s_axis_ddr.tready = 1'b0;

        axis_net.tvalid = 1'b0;
        axis_ddr_wr.tvalid = 1'b0;
    end
end

// MUX: Decide which data is forwarded towards the HLS-networking-stack 
assign axis_net.tdata = actv_C ? (rd_C ? s_axis_user_rsp.tdata : s_axis_user_req.tdata) : s_axis_ddr.tdata;
assign axis_net.tkeep = actv_C ? (rd_C ? s_axis_user_rsp.tkeep : s_axis_user_req.tkeep) : s_axis_ddr.tkeep;
assign axis_net.tlast = actv_C ? (rd_C ? s_axis_user_rsp.tlast : s_axis_user_req.tlast) : s_axis_ddr.tlast;

// Data-loop? Not exactly what this is for. Seems to loop data back from the top-level module to the top-level module 
assign axis_ddr_wr.tdata = s_axis_user_req.tdata;
assign axis_ddr_wr.tkeep = s_axis_user_req.tkeep;
assign axis_ddr_wr.tlast = (cnt_ddr_wr == 1);

//
// DEBUG
//

/* ila_retrans inst_ila_retrans (
    .clk(aclk), 
    .probe0(s_req_net.valid), 
    .probe1(s_req_net.data),            // 128
    .probe2(s_req_net.ready), 
    .probe3(s_axis_user_req.tvalid), 
    .probe4(s_axis_user_req.tdata),     // 512
    .probe5(s_axis_user_req.tkeep),     // 64
    .probe6(s_axis_user_req.tready), 
    .probe7(s_axis_user_req.tlast), 
    .probe8(m_axis_net.tvalid), 
    .probe9(m_axis_net.tdata),          // 512
    .probe10(m_axis_net.tkeep),         // 64
    .probe11(m_axis_net.tready), 
    .probe12(m_axis_net.tlast), 
    .probe13(m_req_ddr_wr.valid), 
    .probe14(m_req_ddr_wr.data),        // 128
    .probe15(m_req_ddr_wr.ready), 
    .probe16(m_axis_ddr.tvalid), 
    .probe17(m_axis_ddr.tdata),         // 512
    .probe18(m_axis_ddr.tkeep),         // 64
    .probe19(m_axis_ddr.tready),
    .probe20(m_axis_ddr.tlast), 
    .probe21(seq_snk_valid), 
    .probe22(seq_snk_ready), 
    .probe23(rd_snk), 
    .probe24(actv_snk),         
    .probe25(cnt_C),                    // 26
    .probe26(state_C),                      
    .probe27(cnt_ddr_wr),               // 26
    .probe28(tr_done)
); */ 

/*
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_retrans
set_property -dict [list CONFIG.C_PROBE29_WIDTH {22} CONFIG.C_PROBE23_WIDTH {28} CONFIG.C_NUM_OF_PROBES {35} CONFIG.Component_Name {ila_retrans} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_PROBE34_MU_CNT {2} CONFIG.C_PROBE33_MU_CNT {2} CONFIG.C_PROBE32_MU_CNT {2} CONFIG.C_PROBE31_MU_CNT {2} CONFIG.C_PROBE30_MU_CNT {2} CONFIG.C_PROBE29_MU_CNT {2} CONFIG.C_PROBE28_MU_CNT {2} CONFIG.C_PROBE27_MU_CNT {2} CONFIG.C_PROBE26_MU_CNT {2} CONFIG.C_PROBE25_MU_CNT {2} CONFIG.C_PROBE24_MU_CNT {2} CONFIG.C_PROBE23_MU_CNT {2} CONFIG.C_PROBE22_MU_CNT {2} CONFIG.C_PROBE21_MU_CNT {2} CONFIG.C_PROBE20_MU_CNT {2} CONFIG.C_PROBE19_MU_CNT {2} CONFIG.C_PROBE18_MU_CNT {2} CONFIG.C_PROBE17_MU_CNT {2} CONFIG.C_PROBE16_MU_CNT {2} CONFIG.C_PROBE15_MU_CNT {2} CONFIG.C_PROBE14_MU_CNT {2} CONFIG.C_PROBE13_MU_CNT {2} CONFIG.C_PROBE12_MU_CNT {2} CONFIG.C_PROBE11_MU_CNT {2} CONFIG.C_PROBE10_MU_CNT {2} CONFIG.C_PROBE9_MU_CNT {2} CONFIG.C_PROBE8_MU_CNT {2} CONFIG.C_PROBE7_MU_CNT {2} CONFIG.C_PROBE6_MU_CNT {2} CONFIG.C_PROBE5_MU_CNT {2} CONFIG.C_PROBE4_MU_CNT {2} CONFIG.C_PROBE3_MU_CNT {2} CONFIG.C_PROBE2_MU_CNT {2} CONFIG.C_PROBE1_MU_CNT {2} CONFIG.C_PROBE0_MU_CNT {2} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_retrans]
*/
 
endmodule