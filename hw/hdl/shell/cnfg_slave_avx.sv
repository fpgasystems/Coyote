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

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module cnfg_slave_avx #(
    parameter integer           ID_REG = 0 
) (
    input  logic                aclk,
    input  logic                aresetn,

    // Control bus (HOST)
    AXI4.s                      s_axim_ctrl,

    // Host request
    metaIntf.m                  m_host_sq,
    metaIntf.m                  m_bpss_done_rd,
    metaIntf.m                  m_bpss_done_wr,

    // Host
`ifdef EN_STRM
    metaIntf.s                  s_host_done_rd,
    metaIntf.s                  s_host_done_wr,
`endif
    
    // Memory
`ifdef EN_MEM
    dmaIsrIntf.m                m_dma_offload,
    dmaIsrIntf.m                m_dma_sync,
    metaIntf.s                  s_card_done_rd,
    metaIntf.s                  s_card_done_wr,
`endif

    // Network
`ifdef EN_NET
    metaIntf.m                  m_arp_lookup_request,
`endif

    // RDMA
`ifdef EN_RDMA
    metaIntf.m                  m_rdma_qp_interface,
    metaIntf.m                  m_rdma_conn_interface,
    metaIntf.s                  s_rdma_done,
`endif

    // Writeback
`ifdef EN_WB
    metaIntf.m                  m_wback,
`endif

    // IRQ
    metaIntf.s                  s_invldt_rd,
    metaIntf.s                  s_invldt_wr,
    metaIntf.m                  m_invldt_rd,
    metaIntf.m                  m_invldt_wr,

    metaIntf.s                  s_pfault_rd,
    input  logic [LEN_BITS-1:0] s_pfault_rd_rng,    
    metaIntf.s                  s_pfault_wr,
    input  logic [LEN_BITS-1:0] s_pfault_wr_rng,
    metaIntf.m                  m_pfault_rd,
    metaIntf.m                  m_pfault_wr,

    metaIntf.s                  s_notify,

    // Control
    output logic                usr_irq
);

// -- Decl -------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// Constants
localparam integer N_REGS = 2 * (2**PID_BITS);
localparam integer ADDR_LSB = $clog2(AVX_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AVX_ADDR_BITS = ADDR_LSB + ADDR_MSB;
localparam integer N_WBS_BITS = $clog2(N_WBS);

//
// AXI
//
logic [AVX_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic axi_wready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic [AVX_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [AVX_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rlast;
logic axi_rvalid;

logic [1:0] axi_arburst;
logic [1:0] axi_awburst;
logic [7:0] axi_arlen;
logic [7:0] axi_awlen;
logic [7:0] axi_awlen_cntr;
logic [7:0] axi_arlen_cntr;

logic aw_wrap_en;
logic ar_wrap_en;
logic [31:0] aw_wrap_size; 
logic [31:0] ar_wrap_size; 

logic axi_awv_awr_flag;
logic axi_arv_arr_flag; 

logic [AVX_DATA_BITS-1:0] axi_rdata_bram;
logic axi_mux;

//
// Slave registers
//

logic [N_REGS-1:0][AVX_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;

// Internal signals
logic local_post, remote_post;
logic invldt_post;
logic post;
logic irq_pending;

// IRQ
metaIntf #(.STYPE(irq_pft_t)) pfault_irq_rd ();
logic [LEN_BITS-1:0] pfault_rng_rd;
metaIntf #(.STYPE(irq_pft_t)) pfault_irq_wr ();
logic [LEN_BITS-1:0] pfault_rng_wr;
metaIntf #(.STYPE(irq_inv_t)) invldt_irq_rd ();
metaIntf #(.STYPE(irq_inv_t)) invldt_irq_wr ();
metaIntf #(.STYPE(irq_not_t)) notify_irq ();

metaIntf #(.STYPE(pf_t)) pfault_rd_ctrl ();
metaIntf #(.STYPE(pf_t)) pfault_wr_ctrl ();
metaIntf #(.STYPE(inv_t)) invldt_rd_ctrl ();
metaIntf #(.STYPE(inv_t)) invldt_wr_ctrl ();

logic [PID_BITS-1:0] pid_C;
logic [HPID_BITS-1:0] hpid_C;
logic [VADDR_BITS-1:0] vaddr_C;
logic [STRM_BITS-1:0] strm_C;
logic [NOTIFY_BITS-1:0] value_C;
logic pwr_C;

// Queue used
logic [31:0] local_queue_used;

// Completion read
metaIntf #(.STYPE(ack_t)) meta_done_rd ();

logic rd_C;
logic [3:0] a_we_rd;
logic [PID_BITS-1:0] a_addr_rd;
logic [PID_BITS-1:0] b_addr_rd;
logic [31:0] a_data_in_rd;
logic [31:0] a_data_out_rd;
logic [31:0] b_data_out_rd;
logic rd_clear;
logic [PID_BITS-1:0] rd_clear_addr;

// Completion write
metaIntf #(.STYPE(ack_t)) meta_done_wr ();

logic wr_C;
logic [3:0] a_we_wr;
logic [PID_BITS-1:0] a_addr_wr;
logic [PID_BITS-1:0] b_addr_wr;
logic [31:0] a_data_in_wr;
logic [31:0] a_data_out_wr;
logic [31:0] b_data_out_wr;
logic wr_clear;
logic [PID_BITS-1:0] wr_clear_addr;

`ifdef EN_WB
// Writeback
metaIntf #(.STYPE(wback_t)) wback [N_WBS] ();
metaIntf #(.STYPE(wback_t)) wback_q [N_WBS] ();
metaIntf #(.STYPE(wback_t)) wback_arb ();
`endif

`ifdef EN_MEM
logic offload_post, sync_post;

logic [31:0] offload_queue_used;
logic [31:0] sync_queue_used;

metaIntf #(.STYPE(dma_isr_req_t)) offload_req ();
metaIntf #(.STYPE(dma_isr_req_t)) sync_req ();
logic offload_rsp;
logic sync_rsp;
`endif

`ifdef EN_RDMA
// Completion RDMA
metaIntf #(.STYPE(ack_t)) rdma_done_rd ();
metaIntf #(.STYPE(ack_t)) rdma_done_wr ();
metaIntf #(.STYPE(ack_t)) rdma_done ();

logic rdma_rd_C;
logic [3:0] a_we_rdma_rd;
logic [PID_BITS-1:0] a_addr_rdma_rd;
logic [PID_BITS-1:0] b_addr_rdma_rd;
logic [31:0] a_data_in_rdma_rd;
logic [31:0] a_data_out_rdma_rd;
logic [31:0] b_data_out_rdma_rd;
logic rdma_clear_rd;
logic [PID_BITS-1:0] rdma_clear_addr_rd;

logic rdma_wr_C;
logic [3:0] a_we_rdma_wr;
logic [PID_BITS-1:0] a_addr_rdma_wr;
logic [PID_BITS-1:0] b_addr_rdma_wr;
logic [31:0] a_data_in_rdma_wr;
logic [31:0] a_data_out_rdma_wr;
logic [31:0] b_data_out_rdma_wr;
logic rdma_clear_wr;
logic [PID_BITS-1:0] rdma_clear_addr_wr;
`endif


// -- Def --------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// 0 (W1S|W1C|R) : Control 
localparam integer CTRL_REG                                 = 0;
    // WR
    localparam integer CTRL_OPCODE_OFFS     = 0;
    localparam integer CTRL_OPC_MODE        = 5;
    localparam integer CTRL_OPC_RDMA        = 6;
    localparam integer CTRL_OPC_REMOTE      = 7;
    localparam integer CTRL_STRM_OFFS       = 8;
    localparam integer CTRL_PID_OFFS        = 10;
    localparam integer CTRL_DEST_OFFS       = 16;
    localparam integer CTRL_LAST_OFFS       = 20;
    localparam integer CTRL_ACTV_OFFS       = 21;
    localparam integer CTRL_CLR_STAT        = 22;
    localparam integer CTRL_LEN_OFFS        = 32;
    localparam integer CTRL_VADDR_OFFS      = 64;
    localparam integer WR_OFFS              = 128;
    // RD
    localparam integer CTRL_USED_OFFS       = 0;

// 4 (RW) : ISR
localparam integer ISR_REG                                  = 1;
    // WR
    localparam integer ISR_CLR_IRQ_PENDING  = 0;
    localparam integer ISR_RESTART_RD       = 1; // pf ctrl
    localparam integer ISR_RESTART_WR       = 2; //
    localparam integer ISR_SUCCESS          = 3;
    localparam integer ISR_INVLDT           = 4; // invldt ctrl
    localparam integer ISR_INVLDT_LAST      = 5;
    localparam integer ISR_INVLDT_LOCK      = 6;
    // RD
    localparam integer TYPE_MISS_OFFS       = 16;
    localparam integer STAT_READY_OFFS      = 32;
    localparam integer STRM_MISS_OFFS       = 48;
    localparam integer WR_MISS_OFFS         = 56;

    localparam integer ISR_PID_OFFS         = 64;
    localparam integer ISR_HPID_OFFS        = 96;
    localparam integer ISR_VADDR_OFFS       = 128;
    localparam integer ISR_LEN_OFFS         = 192;
    localparam integer ISR_VAL_OFFS         = 224;

// 10, 11 (RO) : Status
localparam integer STAT_REG_0                               = 2;
    localparam integer STAT_SENT_LOCAL_RD_OFFS  = 0;
    localparam integer STAT_SENT_LOCAL_WR_OFFS  = 64;
    localparam integer STAT_SENT_REMOTE_RD_OFFS = 128;
    localparam integer STAT_SENT_REMOTE_WR_OFFS = 192;

localparam integer STAT_REG_1                               = 3;
    localparam integer STAT_INVLDT_OFFS         = 0;
    localparam integer STAT_PFAULT_OFFS         = 64;
    localparam integer STAT_NOTIFY_OFFS         = 128;

// 17 (RW) : Writeback locations
localparam integer WBACK_REG                                = 4;
    localparam integer WBACK_LCL_RD_OFFS        = 0;
    localparam integer WBACK_LCL_WR_OFFS        = 64;
    localparam integer WBACK_RMT_RD_OFFS        = 128;
    localparam integer WBACK_RMT_WR_OFFS        = 192;

// MEMORY 
// 32 (RW) : Offload
localparam integer OFFL_CTRL_REG                            = 5;
    // WR
    localparam integer MEM_START                = 0;
    localparam integer MEM_CTL                  = 1;
    localparam integer MEM_CLR                  = 2;
    localparam integer MEM_LEN_OFFS             = 32;
    localparam integer MEM_HOST_OFFS            = 64;
    localparam integer MEM_CARD_OFFS            = 128;
    
    // RD
    localparam integer MEM_USED_OFFS            = 0;
// 33 (RO) : Status
localparam integer OFFL_STAT_REG                            = 6;
  localparam integer MEM_CNT_OFFS              = 0;
// 34 (WO) : Sync
localparam integer SYNC_CTRL_REG                            = 7;
// 35 (RO) : Status
localparam integer SYNC_STAT_REG                            = 8;

// NETWORK
// 48 (W1S) : ARP lookup
localparam integer NET_ARP_REG                              = 9;
// RDMA
// 49 (RW) : Write QP context
localparam integer RDMA_CTX_REG                             = 10;
// 50 (RW) : Write QP connection
localparam integer RDMA_CONN_REG                            = 11;
// TCP
// 51 - 55 - (RW) : TCP/IP conn mgmt
localparam integer TCP_OPEN_PORT_REG                        = 12;
localparam integer TCP_OPEN_PORT_STAT_REG                   = 13;
localparam integer TCP_OPEN_CONN_REG                        = 14;
localparam integer TCP_OPEN_CONN_STAT_REG                   = 15;

// 64 (RO) : Status DMA completion
localparam integer STAT_DMA_REG                             = 2**PID_BITS;
//

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && s_axim_ctrl.wvalid;

always_ff @(posedge aclk) begin
    if ( aresetn == 1'b0 ) begin
        slv_reg <= 'X;

        slv_reg[CTRL_REG][31:0] <= 0;
        slv_reg[ISR_REG][7:0] <= 0;
        slv_reg[OFFL_CTRL_REG][31:0] <= 0;
        slv_reg[SYNC_CTRL_REG][31:0] <= 0;

        local_post <= 1'b0;
        remote_post <= 1'b0;
        invldt_post <= 1'b0;
`ifdef EN_MEM        
        offload_post <= 1'b0;
        sync_post <= 1'b0;
        offload_rsp <= 1'b0;
        sync_rsp <= 1'b0;
`endif        
        post <= 1'b0;

        irq_pending <= 1'b0;
        pfault_irq_rd.ready <= 1'b0;
        pfault_irq_wr.ready <= 1'b0;
        invldt_irq_rd.ready <= 1'b0;
        invldt_irq_wr.ready <= 1'b0;
        notify_irq.ready <= 1'b0;

        pfault_rng_rd <= 'X;
        pfault_rng_wr <= 'X;

        pid_C <= 'X;
        hpid_C <= 'X;
        vaddr_C <= 'X;
        strm_C <= 'X;
        value_C <= 'X;
        pwr_C <= 'X;

`ifdef EN_NET
        m_arp_lookup_request.valid <= 1'b0;
        m_arp_lookup_request.data <= 0;
`endif

`ifdef EN_RDMA
        m_rdma_qp_interface.valid <= 1'b0;
        m_rdma_conn_interface.valid <= 1'b0;
`endif 

    end
    else begin

        slv_reg[CTRL_REG][31:0] <= 0; // Control
        slv_reg[ISR_REG][7:0] <= 0;
        slv_reg[OFFL_CTRL_REG][31:0] <= 0;
        slv_reg[SYNC_CTRL_REG][31:0] <= 0;

        local_post <= 1'b0;
        remote_post <= 1'b0;
        invldt_post <= 1'b0;

`ifdef EN_MEM                
        offload_post <= 1'b0;
        sync_post <= 1'b0;
`endif        
        post <= 1'b0;

        pfault_irq_rd.ready <= 1'b0;
        pfault_irq_wr.ready <= 1'b0;
        invldt_irq_rd.ready <= 1'b0;
        invldt_irq_wr.ready <= 1'b0;
        notify_irq.ready <= 1'b0;

        pfault_rng_rd <= s_pfault_rd_rng;
        pfault_rng_wr <= s_pfault_wr_rng;

`ifdef EN_NET
        m_arp_lookup_request.valid <= m_arp_lookup_request.ready ? 1'b0 : m_arp_lookup_request.valid;
`endif

`ifdef EN_RDMA
        m_rdma_qp_interface.valid <= m_rdma_qp_interface.ready ? 1'b0 : m_rdma_qp_interface.valid;
        m_rdma_conn_interface.valid <= m_rdma_conn_interface.ready ? 1'b0 : m_rdma_conn_interface.valid;
`endif

`ifdef EN_MEM                
        offload_rsp <= m_dma_offload.rsp.done ? 1'b1 : offload_rsp;
        sync_rsp <= m_dma_sync.rsp.done ? 1'b1 : sync_rsp;

        // 
        // IRQs
        //
        if(offload_rsp & ~irq_pending) begin
            irq_pending <= 1'b1;
            offload_rsp <= 1'b0;

            slv_reg[ISR_REG][TYPE_MISS_OFFS+:16] <= IRQ_OFFL;

            slv_reg[OFFL_STAT_REG][MEM_CNT_OFFS+:32] <= slv_reg[OFFL_STAT_REG][MEM_CNT_OFFS+:32] + 1;
        end
        else if(sync_rsp & ~irq_pending) begin
            irq_pending <= 1'b1;
            sync_rsp <= 1'b0;

            slv_reg[ISR_REG][TYPE_MISS_OFFS+:16] <= IRQ_SYNC;

            slv_reg[SYNC_STAT_REG][MEM_CNT_OFFS+:32] <= slv_reg[SYNC_STAT_REG][MEM_CNT_OFFS+:32] + 1;
        end     
        else if(invldt_irq_rd.valid & invldt_irq_wr.valid & ~irq_pending) begin
`else
        if(invldt_irq_rd.valid & invldt_irq_wr.valid & ~irq_pending) begin
`endif           
            irq_pending <= 1'b1;
            invldt_irq_rd.ready <= 1'b1;
            invldt_irq_wr.ready <= 1'b1;
            
            slv_reg[ISR_REG][TYPE_MISS_OFFS+:16] <= IRQ_INVLDT;
            hpid_C <= invldt_irq_rd.data.hpid;

            slv_reg[STAT_REG_1][STAT_INVLDT_OFFS+:32] <=  slv_reg[STAT_REG_1][STAT_INVLDT_OFFS+:32] + 1;
        end
        else if(pfault_irq_rd.valid & ~irq_pending) begin
            irq_pending <= 1'b1;
            pfault_irq_rd.ready <= 1'b1;

            slv_reg[ISR_REG][TYPE_MISS_OFFS+:16] <= IRQ_PFAULT;
            vaddr_C <= pfault_irq_rd.data.vaddr;
            pid_C <= pfault_irq_rd.data.pid;
            strm_C <= pfault_irq_rd.data.strm;
            pwr_C <= 1'b0;

            slv_reg[STAT_REG_1][STAT_PFAULT_OFFS+:32] <=  slv_reg[STAT_REG_1][STAT_PFAULT_OFFS+:32] + 1;
        end
        else if(pfault_irq_wr.valid & ~irq_pending) begin
            irq_pending <= 1'b1;
            pfault_irq_wr.ready <= 1'b1;

            slv_reg[ISR_REG][TYPE_MISS_OFFS+:16] <= IRQ_PFAULT;
            vaddr_C <= pfault_irq_wr.data.vaddr;
            pid_C <= pfault_irq_wr.data.pid;
            strm_C <= pfault_irq_wr.data.strm;
            pwr_C <= 1'b1;

            slv_reg[STAT_REG_1][STAT_PFAULT_OFFS+:32] <=  slv_reg[STAT_REG_1][STAT_PFAULT_OFFS+:32] + 1;
        end
        else if(notify_irq.valid & ~irq_pending) begin
            irq_pending <= 1'b1;
            notify_irq.ready <= 1'b1;

            slv_reg[ISR_REG][TYPE_MISS_OFFS+:16] <= IRQ_NOTIFY;
            pid_C <= notify_irq.data.pid;
            value_C <= notify_irq.data.value;

            slv_reg[STAT_REG_1][STAT_NOTIFY_OFFS+:32] <=  slv_reg[STAT_REG_1][STAT_NOTIFY_OFFS+:32] + 1;
        end
    
        if(slv_reg[ISR_REG][ISR_CLR_IRQ_PENDING]) begin
            irq_pending <= 1'b0;
        end

        //
        // Slave write
        //
        if(slv_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+:ADDR_MSB]) 
                CTRL_REG: begin // Control
                    if( (s_axim_ctrl.wdata[CTRL_ACTV_OFFS] & s_axim_ctrl.wdata[WR_OFFS+CTRL_ACTV_OFFS]) ) begin
                        local_post <= 1'b1;
                        slv_reg[STAT_REG_0][STAT_SENT_LOCAL_RD_OFFS+:32] <= slv_reg[STAT_REG_0][STAT_SENT_LOCAL_RD_OFFS+:32] + 1;
                        slv_reg[STAT_REG_0][STAT_SENT_LOCAL_WR_OFFS+:32] <= slv_reg[STAT_REG_0][STAT_SENT_LOCAL_WR_OFFS+:32] + 1;
                    end
                    else if(s_axim_ctrl.wdata[CTRL_ACTV_OFFS]) begin
                        if(is_strm_local(s_axim_ctrl.wdata[CTRL_STRM_OFFS+:STRM_BITS])) begin
                            local_post <= 1'b1;
                            slv_reg[STAT_REG_0][STAT_SENT_LOCAL_RD_OFFS+:32] <= slv_reg[STAT_REG_0][STAT_SENT_LOCAL_RD_OFFS+:32] + 1;
                        end
                        else begin
                            remote_post <=  1'b1;
                            slv_reg[STAT_REG_0][STAT_SENT_REMOTE_RD_OFFS+:32] <= slv_reg[STAT_REG_0][STAT_SENT_REMOTE_RD_OFFS+:32] + 1;
                        end
                    end
                    else if(s_axim_ctrl.wdata[WR_OFFS+CTRL_ACTV_OFFS]) begin
                        if(is_strm_local(s_axim_ctrl.wdata[WR_OFFS+CTRL_STRM_OFFS+:STRM_BITS])) begin
                            local_post <= 1'b1;
                            slv_reg[STAT_REG_0][STAT_SENT_LOCAL_WR_OFFS+:32] <= slv_reg[STAT_REG_0][STAT_SENT_LOCAL_WR_OFFS+:32] + 1;
                        end
                        else begin
                            remote_post <=  1'b1;
                            slv_reg[STAT_REG_0][STAT_SENT_REMOTE_WR_OFFS+:32] <= slv_reg[STAT_REG_0][STAT_SENT_REMOTE_WR_OFFS+:32] + 1;
                        end
                    end
    
                    post <= 1'b1;

                    for (int i = 0; i < (AVX_DATA_BITS/8); i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                end

                ISR_REG: begin // ISR
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[ISR_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end

                    if (s_axim_ctrl.wstrb[0] == 1'b1) begin
                        invldt_post <= s_axim_ctrl.wdata[ISR_INVLDT];
                    end
                end

`ifdef EN_WB
                WBACK_REG: // Writeback
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[WBACK_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
`endif

`ifdef EN_MEM
                OFFL_CTRL_REG: // OFFL control
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[OFFL_CTRL_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                        offload_post <= 1'b1;
                    end

                SYNC_CTRL_REG: // SYNC control
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[SYNC_CTRL_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                        end
                        sync_post <= 1'b1;
                    end
`endif

`ifdef EN_NET
                NET_ARP_REG: // ARP lookup
                    for (int i = 0; i < 4; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            m_arp_lookup_request.data[(i*8)+:8] <= s_axim_ctrl.wdata[(24-i*8)+:8];
                            m_arp_lookup_request.valid <= 1'b1;
                        end
                    end

`endif 

`ifdef EN_RDMA
                RDMA_CTX_REG: // Context
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_CTX_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                            m_rdma_qp_interface.valid <= 1'b1;
                        end
                    end
                RDMA_CONN_REG: // Connection
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(s_axim_ctrl.wstrb[i]) begin
                            slv_reg[RDMA_CONN_REG][(i*8)+:8] <= s_axim_ctrl.wdata[(i*8)+:8];
                            m_rdma_conn_interface.valid <= 1'b1;
                        end
                    end
`endif 

                default: ;
            endcase
        end

    end
end

// ---------------------------------------------------------------------------------------- 
// Read process 
// ----------------------------------------------------------------------------------------
assign slv_reg_rden = axi_arv_arr_flag; // & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 'X;
    axi_mux <= 'X;

  end
  else begin

    if(slv_reg_rden) begin
      axi_rdata <= 0;
      axi_mux <= 1'b0;

      case (axi_araddr[ADDR_LSB+:ADDR_MSB]) inside
        [CTRL_REG:CTRL_REG]:
            axi_rdata[31:0] <= local_queue_used[31:0];
       
        [ISR_REG:ISR_REG]: begin
            axi_rdata[TYPE_MISS_OFFS+:16] <= slv_reg[ISR_REG][TYPE_MISS_OFFS+:16];
            axi_rdata[STAT_READY_OFFS]   <= invldt_rd_ctrl.ready & invldt_wr_ctrl.ready;
            axi_rdata[STAT_READY_OFFS+1] <= pfault_rd_ctrl.ready & pfault_wr_ctrl.ready;
            axi_rdata[STRM_MISS_OFFS+:STRM_BITS] <= strm_C;
            axi_rdata[WR_MISS_OFFS] <= pwr_C;
            
            axi_rdata[ISR_PID_OFFS+:PID_BITS] <= pid_C; // shared
            axi_rdata[ISR_HPID_OFFS+:HPID_BITS] <= hpid_C;
            axi_rdata[ISR_VADDR_OFFS+:VADDR_BITS] <= vaddr_C;
            axi_rdata[ISR_LEN_OFFS+:LEN_BITS] <= pwr_C ? pfault_rng_wr : pfault_rng_rd;
            axi_rdata[ISR_VAL_OFFS+:NOTIFY_BITS] <= value_C;
        end
        [STAT_REG_0:STAT_REG_0]: begin
            axi_rdata <= slv_reg[STAT_REG_0];        
        end
        [STAT_REG_1:STAT_REG_1]: begin
            axi_rdata <= slv_reg[STAT_REG_1];        
        end

`ifdef EN_WB
        [WBACK_REG:WBACK_REG]:
            axi_rdata <= slv_reg[WBACK_REG];
`endif

`ifdef EN_MEM
        [OFFL_CTRL_REG:OFFL_CTRL_REG]:
            axi_rdata[31:0] <= offload_queue_used[31:0];
        [OFFL_STAT_REG:OFFL_STAT_REG]:
            axi_rdata <= slv_reg[OFFL_STAT_REG];
        [SYNC_CTRL_REG:SYNC_CTRL_REG]:
            axi_rdata[31:0] <= offload_queue_used[31:0];
        [SYNC_STAT_REG:SYNC_STAT_REG]:
            axi_rdata <= slv_reg[OFFL_STAT_REG];
`endif

`ifdef EN_NET
        [NET_ARP_REG:NET_ARP_REG]:
            axi_rdata[0] <= m_arp_lookup_request.ready;
`endif 

`ifdef EN_RDMA
        [RDMA_CTX_REG:RDMA_CTX_REG]:
            axi_rdata[0] <= m_rdma_qp_interface.ready;
        [RDMA_CONN_REG:RDMA_CONN_REG]:
            axi_rdata[0] <= m_rdma_conn_interface.ready;
`endif 
        [STAT_DMA_REG:STAT_DMA_REG+(2**PID_BITS)-1]: begin
            axi_mux <= 1'b1; 
        end
        
        default: ;
      endcase
    end
  end 
end

assign axi_rdata_bram[AVX_DATA_BITS-1:128] = 0; 
assign axi_rdata_bram[63:0] = {b_data_out_wr, b_data_out_rd};
`ifdef EN_RDMA
assign axi_rdata_bram[64+:64] = {b_data_out_rdma_wr, b_data_out_rdma_rd};
`else 
assign axi_rdata_bram[64+:64] = 0;
`endif

// ---------------------------------------------------------------------------------------- 
// CPID 
// ----------------------------------------------------------------------------------------

// RD
assign rd_clear = post && slv_reg[CTRL_REG][CTRL_CLR_STAT];
assign rd_clear_addr = slv_reg[CTRL_REG][CTRL_PID_OFFS+:PID_BITS];

// Completion muxing
`ifdef EN_STRM
    `ifdef EN_MEM
        metaIntf #(.STYPE(ack_t)) host_done_rd ();
        metaIntf #(.STYPE(ack_t)) card_done_rd ();

        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_host_cmplt_q_rd (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_host_done_rd.valid),
            .rdy_snk (),
            .data_snk(s_host_done_rd.data),
            .val_src (host_done_rd.valid),
            .rdy_src (host_done_rd.ready),
            .data_src(host_done_rd.data)
        );
        assign s_host_done_rd.ready = 1'b1;

        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_card_cmplt_q_rd (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_card_done_rd.valid),
            .rdy_snk (),
            .data_snk(s_card_done_rd.data),
            .val_src (card_done_rd.valid),
            .rdy_src (card_done_rd.ready),
            .data_src(card_done_rd.data)
        );
        assign s_card_done_rd.ready = 1'b1;

        meta_arb_2_1 inst_done_local_q_rd (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .s_meta_0(host_done_rd), 
            .s_meta_1(card_done_rd), 
            .m_meta(meta_done_rd)
        );
    `else
        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_host_cmplt_q_rd (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_host_done_rd.valid),
            .rdy_snk (),
            .data_snk(s_host_done_rd.data),
            .val_src (meta_done_rd.valid),
            .rdy_src (meta_done_rd.ready),
            .data_src(meta_done_rd.data)
        );
        assign s_host_done_rd.ready = 1'b1;
    `endif
`else
    `ifdef EN_MEM
        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_card_cmplt_q_rd (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_card_done_rd.valid),
            .rdy_snk (),
            .data_snk(s_card_done_rd.data),
            .val_src (meta_done_rd.valid),
            .rdy_src (meta_done_rd.ready),
            .data_src(meta_done_rd.data)
        );
        assign s_card_done_rd.ready = 1'b1;
    `endif
`endif

assign m_bpss_done_rd.valid = meta_done_rd.valid & meta_done_rd.ready;
assign m_bpss_done_rd.data  = meta_done_rd.data;

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        rd_C <= 1'b0; 
    end
    else begin
        rd_C <= rd_C ? 1'b0 : (meta_done_rd.valid ? 1'b1 : rd_C);
    end
end
assign meta_done_rd.ready = (rd_C & meta_done_rd.valid);

assign a_we_rd = (rd_clear || rd_C) ? ~0 : 0;
assign a_addr_rd = rd_clear ? rd_clear_addr : meta_done_rd.data.pid;
assign a_data_in_rd = rd_clear ? 0 : a_data_out_rd + 1'b1;
assign b_addr_rd = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_rd_stat (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_rd),
    .a_addr(a_addr_rd),
    .b_en(1'b1),
    .b_addr(b_addr_rd),
    .a_data_in(a_data_in_rd),
    .a_data_out(a_data_out_rd),
    .b_data_out(b_data_out_rd)
);

// WR
assign wr_clear = post && slv_reg[CTRL_REG][WR_OFFS+CTRL_CLR_STAT];
assign wr_clear_addr = slv_reg[CTRL_REG][WR_OFFS+CTRL_PID_OFFS+:PID_BITS];

// Completion muxing
`ifdef EN_STRM
    `ifdef EN_MEM
        metaIntf #(.STYPE(ack_t)) host_done_wr ();
        metaIntf #(.STYPE(ack_t)) card_done_wr ();

        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_host_cmplt_q_wr (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_host_done_wr.valid),
            .rdy_snk (),
            .data_snk(s_host_done_wr.data),
            .val_src (host_done_wr.valid),
            .rdy_src (host_done_wr.ready),
            .data_src(host_done_wr.data)
        );
        assign s_host_done_wr.ready = 1'b1;

        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_card_cmplt_q_wr (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_card_done_wr.valid),
            .rdy_snk (),
            .data_snk(s_card_done_wr.data),
            .val_src (card_done_wr.valid),
            .rdy_src (card_done_wr.ready),
            .data_src(card_done_wr.data)
        );
        assign s_card_done_wr.ready = 1'b1;

        meta_arb_2_1 inst_done_local_q_wr (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .s_meta_0(host_done_wr), 
            .s_meta_1(card_done_wr), 
            .m_meta(meta_done_wr)
        );
    `else
        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_host_cmplt_q_wr (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_host_done_wr.valid),
            .rdy_snk (),
            .data_snk(s_host_done_wr.data),
            .val_src (meta_done_wr.valid),
            .rdy_src (meta_done_wr.ready),
            .data_src(meta_done_wr.data)
        );
        assign s_host_done_wr.ready = 1'b1;
    `endif
`else
    `ifdef EN_MEM
        queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_card_cmplt_q_wr (
            .aclk(aclk), 
            .aresetn(aresetn), 
            .val_snk (s_card_done_wr.valid),
            .rdy_snk (),
            .data_snk(s_card_done_wr.data),
            .val_src (meta_done_wr.valid),
            .rdy_src (meta_done_wr.ready),
            .data_src(meta_done_wr.data)
        );
        assign s_card_done_wr.ready = 1'b1;
    `endif
`endif

assign m_bpss_done_wr.valid = meta_done_wr.valid & meta_done_wr.ready;
assign m_bpss_done_wr.data  = meta_done_wr.data;

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        wr_C <= 1'b0; 
    end
    else begin
        wr_C <= wr_C ? 1'b0 : (meta_done_wr.valid ? 1'b1 : wr_C);
    end
end
assign meta_done_wr.ready = (wr_C & meta_done_wr.valid);

assign a_we_wr = (wr_clear || wr_C) ? ~0 : 0;
assign a_addr_wr = wr_clear ? wr_clear_addr : meta_done_wr.data.pid;
assign a_data_in_wr = wr_clear ? 0 : a_data_out_wr + 1'b1;
assign b_addr_wr = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_wr_stat (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_wr),
    .a_addr(a_addr_wr),
    .b_en(1'b1),
    .b_addr(b_addr_wr),
    .a_data_in(a_data_in_wr),
    .a_data_out(a_data_out_wr),
    .b_data_out(b_data_out_wr)
);

// ---------------------------------------------------------------------------------------- 
// I/O
// ----------------------------------------------------------------------------------------

// IRQ
queue_meta #(.QDEPTH(16)) inst_pfault_rd_irq_q (.aclk(aclk), .aresetn(aresetn), .s_meta(s_pfault_rd), .m_meta(pfault_irq_rd));
queue_meta #(.QDEPTH(16)) inst_pfault_wr_irq_q (.aclk(aclk), .aresetn(aresetn), .s_meta(s_pfault_wr), .m_meta(pfault_irq_wr));
queue_meta #(.QDEPTH(16)) inst_invldt_rd_irq_q (.aclk(aclk), .aresetn(aresetn), .s_meta(s_invldt_rd), .m_meta(invldt_irq_rd));
queue_meta #(.QDEPTH(16)) inst_invldt_wr_irq_q (.aclk(aclk), .aresetn(aresetn), .s_meta(s_invldt_wr), .m_meta(invldt_irq_wr));
queue_meta #(.QDEPTH(16)) inst_notify_irq_q (.aclk(aclk), .aresetn(aresetn), .s_meta(s_notify), .m_meta(notify_irq));

queue_meta #(.QDEPTH(4)) inst_pfault_rd_ctrl (.aclk(aclk), .aresetn(aresetn), .s_meta(pfault_rd_ctrl), .m_meta(m_pfault_rd));
queue_meta #(.QDEPTH(4)) inst_pfault_wr_ctrl (.aclk(aclk), .aresetn(aresetn), .s_meta(pfault_wr_ctrl), .m_meta(m_pfault_wr));
queue_meta #(.QDEPTH(4)) inst_invldt_rd_ctrl (.aclk(aclk), .aresetn(aresetn), .s_meta(invldt_rd_ctrl), .m_meta(m_invldt_rd));
queue_meta #(.QDEPTH(4)) inst_invldt_wr_ctrl (.aclk(aclk), .aresetn(aresetn), .s_meta(invldt_wr_ctrl), .m_meta(m_invldt_wr));

// Invalidate ctrl
assign invldt_rd_ctrl.valid = invldt_post;
assign invldt_rd_ctrl.data.lock = slv_reg[ISR_REG][ISR_INVLDT_LOCK];
assign invldt_rd_ctrl.data.hpid = slv_reg[ISR_REG][ISR_HPID_OFFS+:HPID_BITS];
assign invldt_rd_ctrl.data.vaddr = slv_reg[ISR_REG][ISR_VADDR_OFFS+:VADDR_BITS];
assign invldt_rd_ctrl.data.len = slv_reg[ISR_REG][ISR_LEN_OFFS+:LEN_BITS];
assign invldt_rd_ctrl.data.last = slv_reg[ISR_REG][ISR_INVLDT_LAST];

assign invldt_wr_ctrl.valid = invldt_post;
assign invldt_wr_ctrl.data.lock = slv_reg[ISR_REG][ISR_INVLDT_LOCK];
assign invldt_wr_ctrl.data.hpid = slv_reg[ISR_REG][ISR_HPID_OFFS+:HPID_BITS];
assign invldt_wr_ctrl.data.vaddr = slv_reg[ISR_REG][ISR_VADDR_OFFS+:VADDR_BITS];
assign invldt_wr_ctrl.data.len = slv_reg[ISR_REG][ISR_LEN_OFFS+:LEN_BITS];
assign invldt_wr_ctrl.data.last = slv_reg[ISR_REG][ISR_INVLDT_LAST];

// Pfault ctrl
assign pfault_rd_ctrl.valid = slv_reg[ISR_REG][ISR_RESTART_RD];
assign pfault_rd_ctrl.data = slv_reg[ISR_REG][ISR_SUCCESS]; 

assign pfault_wr_ctrl.valid = slv_reg[ISR_REG][ISR_RESTART_WR];
assign pfault_wr_ctrl.data = slv_reg[ISR_REG][ISR_SUCCESS];

assign usr_irq = irq_pending;

// Host request
metaIntf #(.STYPE(dreq_t)) host_req ();

assign host_req.data.req_1.opcode       = slv_reg[CTRL_REG][CTRL_OPCODE_OFFS+:OPCODE_BITS];
assign host_req.data.req_1.strm         = slv_reg[CTRL_REG][CTRL_STRM_OFFS+:STRM_BITS];
assign host_req.data.req_1.mode         = slv_reg[CTRL_REG][CTRL_OPC_MODE];
assign host_req.data.req_1.rdma         = slv_reg[CTRL_REG][CTRL_OPC_RDMA];
assign host_req.data.req_1.remote       = slv_reg[CTRL_REG][CTRL_OPC_REMOTE];
assign host_req.data.req_1.pid          = slv_reg[CTRL_REG][CTRL_PID_OFFS+:PID_BITS];
assign host_req.data.req_1.vfid         = ID_REG; // RSRVD
assign host_req.data.req_1.dest         = slv_reg[CTRL_REG][CTRL_DEST_OFFS+:DEST_BITS];
assign host_req.data.req_1.last         = slv_reg[CTRL_REG][CTRL_LAST_OFFS];
assign host_req.data.req_1.actv         = slv_reg[CTRL_REG][CTRL_ACTV_OFFS];
assign host_req.data.req_1.host         = 1'b1; // RSRVD
assign host_req.data.req_1.vaddr        = slv_reg[CTRL_REG][CTRL_VADDR_OFFS+:VADDR_BITS];
assign host_req.data.req_1.len          = slv_reg[CTRL_REG][CTRL_LEN_OFFS+:LEN_BITS];
assign host_req.data.req_1.offs         = 0;
assign host_req.data.req_1.rsrvd        = 0;

assign host_req.data.req_2.opcode       = slv_reg[CTRL_REG][WR_OFFS+CTRL_OPCODE_OFFS+:OPCODE_BITS];
assign host_req.data.req_2.strm         = slv_reg[CTRL_REG][WR_OFFS+CTRL_STRM_OFFS+:STRM_BITS];
assign host_req.data.req_2.mode         = slv_reg[CTRL_REG][WR_OFFS+CTRL_OPC_MODE];
assign host_req.data.req_2.rdma         = slv_reg[CTRL_REG][WR_OFFS+CTRL_OPC_RDMA];
assign host_req.data.req_2.remote       = slv_reg[CTRL_REG][WR_OFFS+CTRL_OPC_REMOTE];
assign host_req.data.req_2.pid          = slv_reg[CTRL_REG][WR_OFFS+CTRL_PID_OFFS+:PID_BITS];
assign host_req.data.req_2.vfid         = ID_REG; // RSRVD
assign host_req.data.req_2.dest         = slv_reg[CTRL_REG][WR_OFFS+CTRL_DEST_OFFS+:DEST_BITS];
assign host_req.data.req_2.last         = slv_reg[CTRL_REG][WR_OFFS+CTRL_LAST_OFFS];
assign host_req.data.req_2.actv         = slv_reg[CTRL_REG][WR_OFFS+CTRL_ACTV_OFFS];
assign host_req.data.req_2.host         = 1'b1; // RSRVD
assign host_req.data.req_2.vaddr        = slv_reg[CTRL_REG][WR_OFFS+CTRL_VADDR_OFFS+:VADDR_BITS]; 
assign host_req.data.req_2.len          = slv_reg[CTRL_REG][WR_OFFS+CTRL_LEN_OFFS+:LEN_BITS];
assign host_req.data.req_2.offs         = 0;
assign host_req.data.req_2.rsrvd        = 0;

assign host_req.valid = local_post || remote_post;

// Command queues
axis_data_fifo_req_256_used inst_cmd_queue (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(host_req.valid),
  .s_axis_tready(host_req.ready),
  .s_axis_tdata (host_req.data),
  .m_axis_tvalid(m_host_sq.valid),
  .m_axis_tready(m_host_sq.ready),
  .m_axis_tdata (m_host_sq.data),
  .axis_wr_data_count(local_queue_used)
);

// ---------------------------------------------------------------------------------------- 
// MEMORY
// ----------------------------------------------------------------------------------------
`ifdef EN_MEM

assign offload_req.valid = offload_post & slv_reg[OFFL_CTRL_REG][MEM_START];
assign offload_req.data.paddr_host = slv_reg[OFFL_CTRL_REG][MEM_HOST_OFFS+:PADDR_BITS];
assign offload_req.data.paddr_card = slv_reg[OFFL_CTRL_REG][MEM_CARD_OFFS+:PADDR_BITS];
assign offload_req.data.len = slv_reg[OFFL_CTRL_REG][MEM_LEN_OFFS+:LEN_BITS];
assign offload_req.data.last = slv_reg[OFFL_CTRL_REG][MEM_CTL];
assign offload_req.data.rsrvd = 0;

assign sync_req.valid = sync_post & slv_reg[SYNC_CTRL_REG][MEM_START];
assign sync_req.data.paddr_host = slv_reg[SYNC_CTRL_REG][MEM_HOST_OFFS+:PADDR_BITS];
assign sync_req.data.paddr_card = slv_reg[SYNC_CTRL_REG][MEM_CARD_OFFS+:PADDR_BITS];
assign sync_req.data.len = slv_reg[SYNC_CTRL_REG][MEM_LEN_OFFS+:LEN_BITS];
assign sync_req.data.last = slv_reg[SYNC_CTRL_REG][MEM_CTL];
assign sync_req.data.rsrvd = 0;

// Offload and sync queues
axis_data_fifo_req_128_used inst_offl_req_q (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(offload_req.valid),
  .s_axis_tready(offload_req.ready),
  .s_axis_tdata (offload_req.data),
  .m_axis_tvalid(m_dma_offload.valid),
  .m_axis_tready(m_dma_offload.ready),
  .m_axis_tdata (m_dma_offload.req),
  .axis_wr_data_count(offload_queue_used)
);

axis_data_fifo_req_128_used inst_sync_req_q (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(sync_req.valid),
  .s_axis_tready(sync_req.ready),
  .s_axis_tdata (sync_req.data),
  .m_axis_tvalid(m_dma_sync.valid),
  .m_axis_tready(m_dma_sync.ready),
  .m_axis_tdata (m_dma_sync.req),
  .axis_wr_data_count(sync_queue_used)
);

`endif

// ---------------------------------------------------------------------------------------- 
// RDMA
// ----------------------------------------------------------------------------------------
`ifdef EN_RDMA

// 
// CQ
//
queue_stream #(.QTYPE(ack_t), .QDEPTH(8)) inst_cmplt_rdma_q (
    .aclk(aclk), 
    .aresetn(aresetn), 
    .val_snk (s_rdma_done.valid),
    .rdy_snk (),
    .data_snk(s_rdma_done.data),
    .val_src (rdma_done.valid),
    .rdy_src (rdma_done.ready),
    .data_src(rdma_done.data)
);
assign s_rdma_done.ready = 1'b1;

assign rdma_done_rd.data = rdma_done.data;
assign rdma_done_rd.valid = is_opcode_rd_resp(rdma_done.data.opcode) ? rdma_done.valid : 1'b0;
assign rdma_done_wr.data = rdma_done.data;
assign rdma_done_wr.valid = is_opcode_rd_resp(rdma_done.data.opcode) ? 1'b0 : rdma_done.valid;
assign rdma_done.ready = is_opcode_rd_resp(rdma_done.data.opcode) ? rdma_done_rd.ready : rdma_done_wr.ready;

// RD
assign rdma_clear_rd = post && slv_reg[CTRL_REG][CTRL_CLR_STAT];
assign rdma_clear_addr_rd = slv_reg[CTRL_REG][CTRL_PID_OFFS+:PID_BITS];

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        rdma_rd_C <= 1'b0; 
    end
    else begin
        rdma_rd_C <= rdma_rd_C ? 1'b0 : (rdma_done_rd.valid ? 1'b1 : rdma_rd_C);
    end
end

assign rdma_done_rd.ready = (rdma_rd_C && rdma_done_rd.valid);

assign a_we_rdma_rd = (rdma_clear_rd || rdma_rd_C) ? ~0 : 0;
assign a_data_in_rdma_rd = rdma_clear_rd ? 0 : a_data_out_rdma_wr + 1;
assign a_addr_rdma_rd = rdma_clear_rd ? rdma_clear_addr_rd : rdma_done_rd.data.pid;
assign b_addr_rdma_rd = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_rdma_ack_rd (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_rdma_rd),
    .a_addr(a_addr_rdma_rd),
    .b_en(1'b1),
    .b_addr(b_addr_rdma_rd),
    .a_data_in(a_data_in_rdma_rd),
    .a_data_out(a_data_out_rdma_rd),
    .b_data_out(b_data_out_rdma_rd)
);

// WR
assign rdma_clear_wr = post && slv_reg[CTRL_REG][WR_OFFS+CTRL_CLR_STAT];
assign rdma_clear_addr_wr = slv_reg[CTRL_REG][WR_OFFS+CTRL_PID_OFFS+:PID_BITS];

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        rdma_wr_C <= 1'b0; 
    end
    else begin
        rdma_wr_C <= rdma_wr_C ? 1'b0 : (rdma_done_wr.valid ? 1'b1 : rdma_wr_C);
    end
end

assign rdma_done_wr.ready = (rdma_wr_C && rdma_done_wr.valid);

assign a_we_rdma_wr = (rdma_clear_wr || rdma_wr_C) ? ~0 : 0;
assign a_data_in_rdma_wr = rdma_clear_wr ? 0 : a_data_out_rdma_wr + 1;
assign a_addr_rdma_wr = rdma_clear_wr ? rdma_clear_addr_wr : rdma_done_wr.data.pid;
assign b_addr_rdma_wr = axi_araddr[ADDR_LSB+:PID_BITS];

ram_tp_nc #(
    .ADDR_BITS(PID_BITS),
    .DATA_BITS(32)
) inst_rdma_ack_wr (
    .clk(aclk),
    .a_en(1'b1),
    .a_we(a_we_rdma_wr),
    .a_addr(a_addr_rdma_wr),
    .b_en(1'b1),
    .b_addr(b_addr_rdma_wr),
    .a_data_in(a_data_in_rdma_wr),
    .a_data_out(a_data_out_rdma_wr),
    .b_data_out(b_data_out_rdma_wr)
);

// RDMA qp interface
assign m_rdma_qp_interface.data.new_state               = 0;
assign m_rdma_qp_interface.data.qp_num                  = slv_reg[RDMA_CTX_REG][0+:24]; // qpn
assign m_rdma_qp_interface.data.r_key                   = slv_reg[RDMA_CTX_REG][32+:32]; // r_key
assign m_rdma_qp_interface.data.local_psn               = slv_reg[RDMA_CTX_REG][64+:24];
assign m_rdma_qp_interface.data.remote_psn              = slv_reg[RDMA_CTX_REG][64+24+:24]; // psns
assign m_rdma_qp_interface.data.vaddr                   = slv_reg[RDMA_CTX_REG][128+:VADDR_BITS]; // vaddr

// RDMA connection interface
assign m_rdma_conn_interface.data.local_qpn             = slv_reg[RDMA_CONN_REG][0+:16];
assign m_rdma_conn_interface.data.remote_qpn            = slv_reg[RDMA_CONN_REG][16+:24];
assign m_rdma_conn_interface.data.remote_ip_address     = slv_reg[RDMA_CONN_REG][64+:128];
assign m_rdma_conn_interface.data.remote_udp_port       = slv_reg[RDMA_CONN_REG][40+:16];

`endif

// ---------------------------------------------------------------------------------------- 
// TCP/IP
// ----------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------- 
// Writeback
// ----------------------------------------------------------------------------------------

`ifdef EN_WB

assign wback[0].valid = rd_clear || rd_C;
assign wback[0].data.paddr = rd_clear ? (rd_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_LCL_RD_OFFS+:PADDR_BITS] : (meta_done_rd.data.pid << 2) + slv_reg[WBACK_REG][WBACK_LCL_RD_OFFS+:PADDR_BITS];
assign wback[0].data.value = rd_clear ? 0 : a_data_out_rd + 1'b1;
assign wback[0].data.rsrvd = 0;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[0]), .m_meta(wback_q[0]));

assign wback[1].valid = wr_clear || wr_C;
assign wback[1].data.paddr = wr_clear ? (wr_clear_addr << 2) + slv_reg[WBACK_REG][WBACK_LCL_WR_OFFS+:PADDR_BITS] : (meta_done_wr.data.pid << 2) + slv_reg[WBACK_REG][WBACK_LCL_WR_OFFS+:PADDR_BITS];
assign wback[1].data.value = wr_clear ? 0 : a_data_out_wr + 1'b1;
assign wback[1].data.rsrvd = 0;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[1]), .m_meta(wback_q[1]));

`ifdef EN_RDMA
assign wback[2].valid = rdma_clear_rd || rdma_rd_C;
assign wback[2].data.paddr = rdma_clear_rd ? (rdma_clear_addr_rd << 2) + slv_reg[WBACK_REG][WBACK_RMT_RD_OFFS+:PADDR_BITS] : (rdma_done_rd.data << 2) + slv_reg[WBACK_REG][WBACK_RMT_RD_OFFS+:PADDR_BITS];
assign wback[2].data.value = rdma_clear_rd ? 0 : a_data_out_rdma_rd + 1'b1;
assign wback[2].data.rsrvd = 0;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_rd (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[2]), .m_meta(wback_q[2]));

assign wback[3].valid = rdma_clear_wr || rdma_wr_C;
assign wback[3].data.paddr = rdma_clear_wr ? (rdma_clear_addr_wr << 2) + slv_reg[WBACK_REG][WBACK_RMT_WR_OFFS+:PADDR_BITS] : (rdma_done_wr.data << 2) + slv_reg[WBACK_REG][WBACK_RMT_WR_OFFS+:PADDR_BITS];
assign wback[3].data.value = rdma_clear_wr ? 0 : a_data_out_rdma_wr + 1'b1;
assign wback[3].data.rsrvd = 0;
queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback_rdma_wr (.aclk(aclk), .aresetn(aresetn), .s_meta(wback[3]), .m_meta(wback_q[3]));
`endif

// RR
meta_arbiter #(.N_ID(N_WBS), .N_ID_BITS(N_WBS_BITS), .DATA_BITS($bits(wback_t))) inst_wb_arb (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_meta(wback_q),
    .m_meta(wback_arb),
    .id_out()
);

queue_meta #(.QDEPTH(N_OUTSTANDING)) inst_meta_wback (.aclk(aclk), .aresetn(aresetn), .s_meta(wback_arb), .m_meta(m_wback));

`endif

// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

// I/O
assign s_axim_ctrl.awready = axi_awready;
assign s_axim_ctrl.wready = axi_wready;
assign s_axim_ctrl.bresp = axi_bresp;
assign s_axim_ctrl.bvalid = axi_bvalid;
assign s_axim_ctrl.arready = axi_arready;
assign s_axim_ctrl.rdata = axi_mux ? axi_rdata_bram : axi_rdata;
assign s_axim_ctrl.rresp = axi_rresp;
assign s_axim_ctrl.rlast = axi_rlast;
assign s_axim_ctrl.rvalid = axi_rvalid;
assign s_axim_ctrl.bid = s_axim_ctrl.awid;
assign s_axim_ctrl.rid = s_axim_ctrl.arid;
assign aw_wrap_size = (AVX_DATA_BITS/8 * (axi_awlen)); 
assign ar_wrap_size = (AVX_DATA_BITS/8 * (axi_arlen)); 
assign aw_wrap_en = ((axi_awaddr & aw_wrap_size) == aw_wrap_size)? 1'b1: 1'b0;
assign ar_wrap_en = ((axi_araddr & ar_wrap_size) == ar_wrap_size)? 1'b1: 1'b0;

// awready
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_awready <= 1'b0;
        axi_awv_awr_flag <= 1'b0;
    end 
    else
    begin    
        if (~axi_awready && s_axim_ctrl.awvalid && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
        begin
            // slave is ready to accept an address and
            // associated control signals
            axi_awready <= 1'b1;
            axi_awv_awr_flag  <= 1'b1; 
            // used for generation of bresp() and bvalid
        end
        else if (s_axim_ctrl.wlast && axi_wready)          
        // preparing to accept next address after current write burst tx completion
        begin
            axi_awv_awr_flag  <= 1'b0;
        end
        else        
        begin
            axi_awready <= 1'b0;
        end
    end 
end       

// awaddr
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_awaddr <= 0;
        axi_awlen_cntr <= 0;
        axi_awburst <= 0;
        axi_awlen <= 0;
    end 
    else
    begin    
        if (~axi_awready && s_axim_ctrl.awvalid && ~axi_awv_awr_flag)
        begin
            // address latching 
            axi_awaddr <= s_axim_ctrl.awaddr[AVX_ADDR_BITS-1:0];  
            axi_awburst <= s_axim_ctrl.awburst; 
            axi_awlen <= s_axim_ctrl.awlen;     
            // start address of transfer
            axi_awlen_cntr <= 0;
        end   
        else if((axi_awlen_cntr <= axi_awlen) && axi_wready && s_axim_ctrl.wvalid)        
        begin

            axi_awlen_cntr <= axi_awlen_cntr + 1;

            case (axi_awburst)
            2'b00: // fixed burst
            // The write address for all the beats in the transaction are fixed
                begin
                axi_awaddr <= axi_awaddr;          
                //for awsize = 4 bytes (010)
                end   
            2'b01: //incremental burst
            // The write address for all the beats in the transaction are increments by awsize
                begin
                axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1;
                axi_awaddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}};   
                end   
            2'b10: //Wrapping burst
            // The write address wraps when the address reaches wrap boundary 
                if (aw_wrap_en)
                begin
                    axi_awaddr <= (axi_awaddr - aw_wrap_size); 
                end
                else 
                begin
                    axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1;
                    axi_awaddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}}; 
                end                      
            default: //reserved (incremental burst for example)
                begin
                    axi_awaddr <= axi_awaddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1;
                end
            endcase              
        end
    end 
end       

// wready 
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_wready <= 1'b0;
    end 
    else
    begin    
        if ( ~axi_wready && s_axim_ctrl.wvalid && axi_awv_awr_flag)
        begin
            // slave can accept the write data
            axi_wready <= 1'b1;
        end
        //else if (~axi_awv_awr_flag)
        else if (s_axim_ctrl.wlast && axi_wready)
        begin
            axi_wready <= 1'b0;
        end
    end 
end       


// bvalid & bresp
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_bvalid <= 0;
        axi_bresp <= 2'b0;
    end 
    else
    begin    
        if (axi_awv_awr_flag && axi_wready && s_axim_ctrl.wvalid && ~axi_bvalid && s_axim_ctrl.wlast )
        begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b0; 
            // 'OKAY' response 
        end                   
        else
        begin
            if (s_axim_ctrl.bready && axi_bvalid) 
            //check if bready is asserted while bvalid is high) 
            //(there is a possibility that bready is always asserted high)   
            begin
                axi_bvalid <= 1'b0; 
            end  
        end
    end
    end   

// arready
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_arready <= 1'b0;
        axi_arv_arr_flag <= 1'b0;
    end 
    else
    begin    
        if (~axi_arready && s_axim_ctrl.arvalid && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
        begin
            axi_arready <= 1'b1;
            axi_arv_arr_flag <= 1'b1;
        end
        else if (axi_rvalid && s_axim_ctrl.rready && axi_arlen_cntr == axi_arlen)
        // preparing to accept next address after current read completion
        begin
            axi_arv_arr_flag  <= 1'b0;
        end
        else        
        begin
            axi_arready <= 1'b0;
        end
    end 
end       

// araddr
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_araddr <= 0;
        axi_arlen_cntr <= 0;
        axi_arburst <= 0;
        axi_arlen <= 0;
        axi_rlast <= 1'b0;
    end 
    else
    begin    
        if (~axi_arready && s_axim_ctrl.arvalid && ~axi_arv_arr_flag)
        begin
            // address latching 
            axi_araddr <= s_axim_ctrl.araddr[AVX_ADDR_BITS-1:0]; 
            axi_arburst <= s_axim_ctrl.arburst; 
            axi_arlen <= s_axim_ctrl.arlen;     
            // start address of transfer
            axi_arlen_cntr <= 0;
            axi_rlast <= 1'b0;
        end   
        else if((axi_arlen_cntr <= axi_arlen) && axi_rvalid && s_axim_ctrl.rready)        
        begin
            
            axi_arlen_cntr <= axi_arlen_cntr + 1;
            axi_rlast <= 1'b0;
        
            case (axi_arburst)
            2'b00: // fixed burst
                // The read address for all the beats in the transaction are fixed
                begin
                    axi_araddr       <= axi_araddr;        
                end   
            2'b01: //incremental burst
            // The read address for all the beats in the transaction are increments by awsize
                begin
                    axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1; 
                    axi_araddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}};   
                end   
            2'b10: //Wrapping burst
            // The read address wraps when the address reaches wrap boundary 
                if (ar_wrap_en) 
                begin
                    axi_araddr <= (axi_araddr - ar_wrap_size); 
                end
                else 
                begin
                axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] <= axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB] + 1; 
                axi_araddr[ADDR_LSB-1:0]  <= {ADDR_LSB{1'b0}};   
                end                      
            default: //reserved (incremental burst for example)
                begin
                axi_araddr <= axi_araddr[AVX_ADDR_BITS-1:ADDR_LSB]+1;
                end
            endcase              
        end
        else if((axi_arlen_cntr == axi_arlen) && ~axi_rlast && axi_arv_arr_flag )   
        begin
            axi_rlast <= 1'b1;
        end          
        else if (s_axim_ctrl.rready)   
        begin
            axi_rlast <= 1'b0;
        end          
    end 
end       

// arvalid
always @( posedge aclk )
begin
    if ( aresetn == 1'b0 )
    begin
        axi_rvalid <= 0;
        axi_rresp  <= 0;
    end 
    else
    begin    
        if (axi_arv_arr_flag && ~axi_rvalid)
        begin
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b0; 
            // 'OKAY' response
        end   
        else if (axi_rvalid && s_axim_ctrl.rready)
        begin
            axi_rvalid <= 1'b0;
        end            
    end
end    


//
// DEBUG
//

endmodule