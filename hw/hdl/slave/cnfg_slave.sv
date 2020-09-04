/**
 *  Config Slave
 *
 * Configuration slave, datapath control and RD/WR request handling
 */ 

import lynxTypes::*;

module cnfg_slave #(
  parameter integer         ID_REG = 0 
)(
  input  logic              aclk,
  input  logic              aresetn,
  
  // Control bus (HOST)
  AXI4L.s                   axi_ctrl,

`ifdef EN_BPSS
  // Request in user logic
  reqIntf.s                 rd_req_user,
  reqIntf.s                 wr_req_user,
`endif

`ifdef EN_FV
  // Request out rdma
  metaIntf.m                fv_req,
`endif
   
  // Request out
  reqIntf.m                 rd_req,
  reqIntf.m                 wr_req,

  // Config intf
  cnfgIntf.m                rd_cnfg,
  cnfgIntf.m                wr_cnfg,

  // Control
  output logic              decouple,
  output logic              pf_irq
);

// -- Decl -------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// Constants
`ifdef EN_FV
localparam integer N_REGS = 25;
`else
localparam integer N_REGS = 19;
`endif
localparam integer ADDR_LSB = (AXIL_DATA_BITS/32) + 1;
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;

localparam integer CTRL_BYTES = 2;
localparam integer VADDR_BYTES = 6;
localparam integer LEN_BYTES = 4;

// Internal registers
logic [AXIL_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXIL_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;

// Slave Registers
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// Internal signals
logic irq_pending;
logic rd_sent;
logic wr_sent;

logic [31:0] rd_queue_used;
logic [31:0] wr_queue_used;

`ifdef EN_FV
logic [31:0] rdma_queue_used;
logic rdma_post;
`endif

// -- Def --------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// 0 (W1S|W1C) : Control 
localparam integer CTRL_REG                               = 0;
      localparam integer CTRL_START_RD        = 0;
      localparam integer CTRL_START_WR        = 1;
      localparam integer CTRL_SYNC_RD         = 2;
      localparam integer CTRL_SYNC_WR         = 3;
      localparam integer CTRL_STREAM_RD       = 4;
      localparam integer CTRL_STREAM_WR       = 5;
      localparam integer CTRL_CLR_STAT_RD     = 6;
      localparam integer CTRL_CLR_STAT_WR     = 7;
      localparam integer CTRL_CLR_IRQ_PENDING = 8;
      localparam integer CTRL_SEND_FV_REQ   = 9;
      localparam integer CTRL_SEND_QP_CTX     = 10;
      localparam integer CTRL_SEND_QP_CONN    = 11;
// 1 (RW) : Virtual address read
localparam integer VADDR_RD_REG                           = 1;
// 2 (RW) : Length read
localparam integer LEN_RD_REG                             = 2;
// 3 (RW) : Virtual address write
localparam integer VADDR_WR_REG                           = 3;
// 4 (RW) : Length write
localparam integer LEN_WR_REG                             = 4;
// 5 (RO) : Virtual address miss
localparam integer VADDR_MISS_REG                         = 5;
// 6 (RO) : Length miss
localparam integer LEN_MISS_REG                           = 6;
// 7,8 (W1S|W1C|R) : Datapath control set/clear
localparam integer CTRL_DP_REG_SET                        = 7;
localparam integer CTRL_DP_REG_CLR                        = 8;
      localparam integer CTRL_DP_DECOUPLE     = 0;
// 9 (RW) : Timer stop at completion counter
localparam integer TMR_STOP_REG                           = 9;
// 10, 11 (RO) : Timers
localparam integer TMR_RD_REG                             = 10;
localparam integer TMR_WR_REG                             = 11;
// 12 (RO) : Status 
localparam integer STAT_CMD_USED_RD_REG                   = 12;
localparam integer STAT_CMD_USED_WR_REG                   = 13;
// 13, 14 (RO) : Number of completed transfers
localparam integer STAT_DMA_RD_REG                        = 14;
localparam integer STAT_DMA_WR_REG                        = 15;
// 15, 16 (RO) : Number of sent requests
localparam integer STAT_SENT_RD_REG                       = 16;
localparam integer STAT_SENT_WR_REG                       = 17;
// 17 (RO) : Number of page faults
localparam integer STAT_PFAULTS_REG                       = 18;
// FV
// 20, 21, 22 (RW) : FV post
localparam integer FV_POST_REG_0                        = 20;
localparam integer FV_POST_REG_1                        = 21;
localparam integer FV_POST_REG_2                        = 22;
localparam integer FV_POST_REG_3                        = 23;
// 23 (RO) : FV cmd check used
localparam integer FV_STAT_CMD_USED_REG                 = 24;
//

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg[CTRL_REG][15:0] <= 0;
    slv_reg[CTRL_DP_REG_SET][15:0] <= 0;
    slv_reg[TMR_STOP_REG][31:0] <= 1;

    irq_pending <= 1'b0; 

`ifdef EN_FV
    rdma_post <= 1'b0;
`endif
  end
  else begin
    slv_reg[CTRL_REG] <= 0; // Control

`ifdef EN_FV
    rdma_post <= 1'b0;
`endif

    // Page fault
    if(rd_cnfg.pf.miss || wr_cnfg.pf.miss) begin
      irq_pending <= 1'b1;
      slv_reg[VADDR_MISS_REG] <= rd_cnfg.pf.miss ? rd_cnfg.pf.vaddr : wr_cnfg.pf.vaddr; // miss virtual address
      slv_reg[LEN_MISS_REG]   <= rd_cnfg.pf.miss ? rd_cnfg.pf.len   : wr_cnfg.pf.len;   // miss length
    end
    if(slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING]) 
      irq_pending <= 1'b0;

    // Status counters
    slv_reg[STAT_DMA_RD_REG][31:0] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] ? 0 : slv_reg[STAT_DMA_RD_REG][31:0] + rd_cnfg.done_host + rd_cnfg.done_card + rd_cnfg.done_sync;
    slv_reg[STAT_DMA_WR_REG][31:0] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_WR] ? 0 : slv_reg[STAT_DMA_WR_REG][31:0] + wr_cnfg.done_host + wr_cnfg.done_card + wr_cnfg.done_sync;
    slv_reg[STAT_SENT_RD_REG][31:0] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] ? 0 : slv_reg[STAT_SENT_RD_REG][31:0] + rd_sent;
    slv_reg[STAT_SENT_WR_REG][31:0] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_WR] ? 0 : slv_reg[STAT_SENT_WR_REG][31:0] + wr_sent;
    slv_reg[STAT_PFAULTS_REG][31:0] <= (slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] || slv_reg[CTRL_REG][CTRL_CLR_STAT_WR]) ? 0 : slv_reg[STAT_PFAULTS_REG] + (rd_cnfg.pf.miss || wr_cnfg.pf.miss);

    // Timers
    slv_reg[TMR_RD_REG] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] ? 0 : (slv_reg[STAT_DMA_RD_REG][31:0] >= slv_reg[TMR_STOP_REG][31:0]) ? slv_reg[TMR_RD_REG] : slv_reg[TMR_RD_REG] + 1;
    slv_reg[TMR_WR_REG] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_WR] ? 0 : (slv_reg[STAT_DMA_WR_REG][31:0] >= slv_reg[TMR_STOP_REG][31:0]) ? slv_reg[TMR_WR_REG] : slv_reg[TMR_WR_REG] + 1;

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        CTRL_REG: // Control
          for (int i = 0; i < CTRL_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        VADDR_RD_REG: // Virtual address read
          for (int i = 0; i < VADDR_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[VADDR_RD_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        LEN_RD_REG: // Length read
          for (int i = 0; i < LEN_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[LEN_RD_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        VADDR_WR_REG: // Virtual address write
          for (int i = 0; i < VADDR_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[VADDR_WR_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        LEN_WR_REG: // Length write
          for (int i = 0; i < LEN_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[LEN_WR_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CTRL_DP_REG_SET: // Datapath control set
          for (int i = 0; i < CTRL_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] | axi_ctrl.wdata[(i*8)+:8];
            end
          end
        CTRL_DP_REG_CLR: // Datapath control clear
          for (int i = 0; i < CTRL_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] & ~axi_ctrl.wdata[(i*8)+:8];
            end
          end
        TMR_STOP_REG: // Timer stop at
          for (int i = 0; i < LEN_BYTES; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[TMR_STOP_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end

`ifdef EN_FV
        FV_CTX_REG_0: // Context
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_CTX_REG_0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_CTX_REG_1: // Context
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_CTX_REG_1][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_CTX_REG_2: // Context final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_CTX_REG_2][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_CONN_REG_0: // Connection
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_CONN_REG_0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_CONN_REG_1: // Connection
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_CONN_REG_1][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_CONN_REG_2: // Connection final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_CONN_REG_2][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_POST_REG_0: // Post
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_POST_REG_0][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_POST_REG_1: // Post
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_POST_REG_1][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_POST_REG_2: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_POST_REG_2][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        FV_POST_REG_3: // Post final
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[FV_POST_REG_3][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
              rdma_post <= 1'b1;
            end
          end
`endif

        default : ;
      endcase
    end
  end
end    

/* ---------------------------------------------------------------------------------------- */
/* -- Read process ------------------------------------------------------------------------ */
/* ---------------------------------------------------------------------------------------- */
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk, negedge aresetn) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 0;
  end
  else begin
    axi_rdata <= 0;
    if(slv_reg_rden) begin
      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        VADDR_RD_REG: // Virtual address read
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[VADDR_RD_REG][VADDR_BITS-1:0];
        LEN_RD_REG: // Length read
          axi_rdata[LEN_BITS-1:0] <= slv_reg[LEN_RD_REG][LEN_BITS-1:0];
        VADDR_WR_REG: // Virtual address write
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[VADDR_WR_REG][VADDR_BITS-1:0];
        LEN_WR_REG: // Length write
          axi_rdata[LEN_BITS-1:0] <= slv_reg[LEN_WR_REG][LEN_BITS-1:0];
        VADDR_MISS_REG: // Virtual address miss
          axi_rdata[VADDR_BITS-1:0] <= slv_reg[VADDR_MISS_REG][VADDR_BITS-1:0];
        LEN_MISS_REG: // Length miss
          axi_rdata[LEN_BITS-1:0] <= slv_reg[LEN_MISS_REG][LEN_BITS-1:0];
        CTRL_DP_REG_SET: // Datapath
          axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        CTRL_DP_REG_CLR: // Datapath
          axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        TMR_STOP_REG: // Timer stop at
          axi_rdata[31:0] <= slv_reg[TMR_STOP_REG][31:0];
        TMR_RD_REG: // Timer read
          axi_rdata <= slv_reg[TMR_RD_REG];
        TMR_WR_REG: // Timer write
          axi_rdata <= slv_reg[TMR_WR_REG];
        STAT_CMD_USED_RD_REG: // Status queues used read
          axi_rdata[31:0] <= rd_queue_used;
        STAT_CMD_USED_WR_REG: // Status queues used write
          axi_rdata[31:0] <= wr_queue_used;
        STAT_DMA_RD_REG: // Status dma read
          axi_rdata[31:0] <= slv_reg[STAT_DMA_RD_REG][31:0];
        STAT_DMA_WR_REG: // Status dma write
          axi_rdata[31:0] <= slv_reg[STAT_DMA_WR_REG][31:0];
        STAT_SENT_RD_REG: // Status sent read
          axi_rdata[31:0] <= slv_reg[STAT_SENT_RD_REG][31:0];
        STAT_SENT_WR_REG: // Status sent write
          axi_rdata[31:0] <= slv_reg[STAT_SENT_WR_REG][31:0];
        STAT_PFAULTS_REG: // Status page faults
          axi_rdata[31:0] <= slv_reg[STAT_PFAULTS_REG][31:0];

`ifdef EN_FV
        FV_POST_REG_0: // Post
          axi_rdata <= slv_reg[FV_POST_REG_0];
        FV_POST_REG_1: // Post
          axi_rdata <= slv_reg[FV_POST_REG_1];
        FV_POST_REG_2: // Post final
          axi_rdata <= slv_reg[FV_POST_REG_2];
        FV_STAT_CMD_USED_REG: // Status queue used
          axi_rdata[31:0] <= rdma_queue_used;
`endif

        default: ;
      endcase
    end
  end 
end

/* ---------------------------------------------------------------------------------------- */
/* -- Output ------------------------------------------------------------------------------ */
/* ---------------------------------------------------------------------------------------- */
assign rd_sent = rd_req.valid & rd_req.ready;
assign wr_sent = wr_req.valid & wr_req.ready;

always_comb begin
  // Page fault handling
  rd_cnfg.restart = slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING];
  wr_cnfg.restart = slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING];
  pf_irq = irq_pending;

  // Decoupling
  decouple = slv_reg[CTRL_DP_REG_SET][CTRL_DP_DECOUPLE];
end

reqIntf rd_req_cnfg();
reqIntf wr_req_cnfg();
reqIntf rd_req_host();
reqIntf wr_req_host();

// Assign 
assign rd_req_cnfg.req.vaddr = slv_reg[VADDR_RD_REG][VADDR_BITS-1:0];
assign rd_req_cnfg.req.len = slv_reg[LEN_RD_REG][LEN_BITS-1:0];
assign rd_req_cnfg.req.sync = slv_reg[CTRL_REG][CTRL_SYNC_RD];
assign rd_req_cnfg.req.ctl = 1'b1;
assign rd_req_cnfg.req.rsrvd = 0;
assign rd_req_cnfg.valid = slv_reg[CTRL_REG][CTRL_START_RD];

assign wr_req_cnfg.req.vaddr = slv_reg[VADDR_WR_REG][VADDR_BITS-1:0];
assign wr_req_cnfg.req.len = slv_reg[LEN_WR_REG][LEN_BITS-1:0];
assign wr_req_cnfg.req.sync = slv_reg[CTRL_REG][CTRL_SYNC_WR];
assign wr_req_cnfg.req.ctl = 1'b1;
assign wr_req_cnfg.req.rsrvd = 0;
assign wr_req_cnfg.valid = slv_reg[CTRL_REG][CTRL_START_WR];

// Command queues
axis_data_fifo_req_96_used inst_cmd_queue_rd (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(rd_req_cnfg.valid),
  .s_axis_tready(rd_req_cnfg.ready),
  .s_axis_tdata(rd_req_cnfg.req),
  .m_axis_tvalid(rd_req_host.valid),
  .m_axis_tready(rd_req_host.ready),
  .m_axis_tdata(rd_req_host.req),
  .axis_wr_data_count(rd_queue_used)
);

axis_data_fifo_req_96_used inst_cmd_queue_wr (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(wr_req_cnfg.valid),
  .s_axis_tready(wr_req_cnfg.ready),
  .s_axis_tdata(wr_req_cnfg.req),
  .m_axis_tvalid(wr_req_host.valid),
  .m_axis_tready(wr_req_host.ready),
  .m_axis_tdata(wr_req_host.req),
  .axis_wr_data_count(wr_queue_used)
);

`ifdef EN_USER_BYPASS

reqIntf rd_req_ul_q ();
reqIntf wr_req_ul_q ();

// Command queues (user logic)
axis_data_fifo_req_96_used inst_cmd_queue_rd_ul (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(rd_req_ul.valid),
  .s_axis_tready(rd_req_ul.ready),
  .s_axis_tdata(rd_req_ul.req),
  .m_axis_tvalid(rd_req_ul_q.valid),
  .m_axis_tready(rd_req_ul_q.ready),
  .m_axis_tdata(rd_req_ul_q.data),
  .axis_wr_data_count()
);

axis_data_fifo_req_96_used inst_cmd_queue_wr_ul (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(wr_req_ul.valid),
  .s_axis_tready(wr_req_ul.ready),
  .s_axis_tdata(wr_req_ul.req),
  .m_axis_tvalid(wr_req_ul_q.valid),
  .m_axis_tready(wr_req_ul_q.ready),
  .m_axis_tdata(wr_req_ul_q.data),
  .axis_wr_data_count()
);

axis_interconnect_cnfg_req_arbiter inst_rd_interconnect (
  .ACLK(aclk),
  .ARESETN(aresetn),

  .S00_AXIS_ACLK(aclk),
  .S00_AXIS_ARESETN(aresetn),
  .S00_AXIS_TVALID(rd_req_host.valid),
  .S00_AXIS_TREADY(rd_req_host.ready),
  .S00_AXIS_TDATA(rd_req_host.req),

  .S01_AXIS_ACLK(aclk),
  .S01_AXIS_ARESETN(aresetn),
  .S01_AXIS_TVALID(rd_req_ul_q.valid),
  .S01_AXIS_TREADY(rd_req_ul_q.ready),
  .S01_AXIS_TDATA(rd_req_ul_q.req),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(rd_req.valid),
  .M00_AXIS_TREADY(rd_req.ready),
  .M00_AXIS_TDATA(rd_req.req),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0),
  .S00_DECODE_ERR(),
  .S01_DECODE_ERR()
);

axis_interconnect_cnfg_req_arbiter inst_wr_interconnect (
  .ACLK(aclk),
  .ARESETN(aresetn),

  .S00_AXIS_ACLK(aclk),
  .S00_AXIS_ARESETN(aresetn),
  .S00_AXIS_TVALID(wr_req_host.valid),
  .S00_AXIS_TREADY(wr_req_host.ready),
  .S00_AXIS_TDATA(wr_req_host.req),

  .S01_AXIS_ACLK(aclk),
  .S01_AXIS_ARESETN(aresetn),
  .S01_AXIS_TVALID(wr_req_ul_q.valid),
  .S01_AXIS_TREADY(wr_req_ul_q.ready),
  .S01_AXIS_TDATA(wr_req_ul_q.req),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(wr_req.valid),
  .M00_AXIS_TREADY(wr_req.ready),
  .M00_AXIS_TDATA(wr_req.req),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0),
  .S00_DECODE_ERR(),
  .S01_DECODE_ERR()
);

`else

assign rd_req.req = rd_req_host.req;
assign rd_req.valid = rd_req_host.valid;
assign rd_req_host.ready = rd_req.ready;

assign wr_req.req = wr_req_host.req;
assign wr_req.valid = wr_req_host.valid;
assign wr_req_host.ready = wr_req.ready;

`endif

`ifdef EN_FV

assign local_qpn = slv_reg[FV_QPN_REG][23:0];

// FV requests
metaIntf #(.DATA_BITS(RPC_CMD_BITS)) rdma_req_cnfg();

// Assign
assign rdma_req_cnfg.data[4:0] = slv_reg[FV_POST_REG_0][4:0]; // opcode
assign rdma_req_cnfg.data[28:5] = slv_reg[FV_QPN_REG][23:0]; // local qpn
assign rdma_req_cnfg.data[32:29] = ID_REG; // local region
assign rdma_req_cnfg.data[33] = 1'b1; // host
assign rdma_req_cnfg.data[63:34] = 0; // reserved
assign rdma_req_cnfg.data[127:64] = slv_reg[FV_POST_REG_1]; // remote vaddr[15:0], local vaddr
assign rdma_req_cnfg.data[191:128] = slv_reg[FV_POST_REG_2]; // length, remote vaddr[47:16]
assign rdma_req_cnfg.data[255:192] = slv_reg[FV_POST_REG_3]; // params
assign rdma_req_cnfg.valid = rdma_post;

// Parser
network_req_parser #(.ID_REG(ID_REG), .HOST(1)) inst_parser (.aclk(aclk), .aresetn(aresetn), .req_in(rdma_req_cnfg), .req_out(rdma_req), .used(rdma_queue_used));

`endif

/* ---------------------------------------------------------------------------------------- */
/* -- AXI --------------------------------------------------------------------------------- */
/* ---------------------------------------------------------------------------------------- */

// I/O
assign axi_ctrl.awready = axi_awready;
assign axi_ctrl.arready = axi_arready;
assign axi_ctrl.bresp = axi_bresp;
assign axi_ctrl.bvalid = axi_bvalid;
assign axi_ctrl.wready = axi_wready;
assign axi_ctrl.rdata = axi_rdata;
assign axi_ctrl.rresp = axi_rresp;
assign axi_ctrl.rvalid = axi_rvalid;

// awready and awaddr
always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 )
    begin
      axi_awready <= 1'b0;
      axi_awaddr <= 0;
      aw_en <= 1'b1;
    end 
  else
    begin    
      if (~axi_awready && axi_ctrl.awvalid && axi_ctrl.wvalid && aw_en)
        begin
          axi_awready <= 1'b1;
          aw_en <= 1'b0;
          axi_awaddr <= axi_ctrl.awaddr;
        end
      else if (axi_ctrl.bready && axi_bvalid)
        begin
          aw_en <= 1'b1;
          axi_awready <= 1'b0;
        end
      else           
        begin
          axi_awready <= 1'b0;
        end
    end 
end  

// arready and araddr
always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 )
    begin
      axi_arready <= 1'b0;
      axi_araddr  <= 0;
    end 
  else
    begin    
      if (~axi_arready && axi_ctrl.arvalid)
        begin
          axi_arready <= 1'b1;
          axi_araddr  <= axi_ctrl.araddr;
        end
      else
        begin
          axi_arready <= 1'b0;
        end
    end 
end    

// bvalid and bresp
always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 )
    begin
      axi_bvalid  <= 0;
      axi_bresp   <= 2'b0;
    end 
  else
    begin    
      if (axi_awready && axi_ctrl.awvalid && ~axi_bvalid && axi_wready && axi_ctrl.wvalid)
        begin
          axi_bvalid <= 1'b1;
          axi_bresp  <= 2'b0;
        end                   
      else
        begin
          if (axi_ctrl.bready && axi_bvalid) 
            begin
              axi_bvalid <= 1'b0; 
            end  
        end
    end
end

// wready
always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 )
    begin
      axi_wready <= 1'b0;
    end 
  else
    begin    
      if (~axi_wready && axi_ctrl.wvalid && axi_ctrl.awvalid && aw_en )
        begin
          axi_wready <= 1'b1;
        end
      else
        begin
          axi_wready <= 1'b0;
        end
    end 
end  

// rvalid and rresp (1Del?)
always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 )
    begin
      axi_rvalid <= 0;
      axi_rresp  <= 0;
    end 
  else
    begin    
      if (axi_arready && axi_ctrl.arvalid && ~axi_rvalid)
        begin
          axi_rvalid <= 1'b1;
          axi_rresp  <= 2'b0;
        end   
      else if (axi_rvalid && axi_ctrl.rready)
        begin
          axi_rvalid <= 1'b0;
        end                
    end
end    

endmodule
