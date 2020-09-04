/**
 * Config slave AVX
 *
 * Configuration slave, datapath control and RD/WR request handling
 */

import lynxTypes::*;

module cnfg_slave_avx #(
    parameter integer         ID_REG = 0 
) (
    input  logic              aclk,
    input  logic              aresetn,

    // Control bus (HOST)
    AXI4.s                    axim_ctrl,

`ifdef EN_BPSS
    // Request user logic
    reqIntf.s                 rd_req_user,
    reqIntf.s                 wr_req_user,
`endif

`ifdef EN_FV
    // Request out rdma
    metaIntf.m                rdma_req,
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

// Constants
`ifdef EN_FV
    localparam integer N_REGS = 12;
`else
    localparam integer N_REGS = 7;
`endif
localparam integer ADDR_LSB = $clog2(AVX_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AVX_ADDR_BITS = ADDR_LSB + ADDR_MSB;

localparam integer CTRL_BYTES = 2;
localparam integer VADDR_BYTES = 6;
localparam integer LEN_BYTES = 4;

// Internal regs
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

// Slave registers
logic [N_REGS-1:0][AVX_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;

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
localparam integer CTRL_REG                                 = 0;
    localparam integer CTRL_START_RD        = 0;
    localparam integer CTRL_START_WR        = 1;
    localparam integer CTRL_SYNC_RD         = 2;
    localparam integer CTRL_SYNC_WR         = 3;
    localparam integer CTRL_STREAM_RD       = 4;
    localparam integer CTRL_STREAM_WR       = 5;
    localparam integer CTRL_CLR_STAT_RD     = 6;
    localparam integer CTRL_CLR_STAT_WR     = 7;
    localparam integer CTRL_CLR_IRQ_PENDING = 8;
    localparam integer CTRL_DEST_RD         = 9;
    localparam integer CTRL_DEST_WR         = 13;
    localparam integer CTRL_VADDR_RD_OFFS   = 64;
    localparam integer CTRL_VADDR_WR_OFFS   = 128;
    localparam integer CTRL_LEN_RD_OFFS     = 192;
    localparam integer CTRL_LEN_WR_OFFS     = 224;
// 1 (RO) : Page fault 
localparam integer PF_REG                                   = 1;
    localparam integer VADDR_MISS_OFFS      = 0;
    localparam integer LEN_MISS_OFFS        = 64;
// 2, 3 (W1S|W1C|R) : Datapath control set/clear
localparam integer CTRL_DP_REG_SET                          = 2;
localparam integer CTRL_DP_REG_CLR                          = 3;
    localparam integer CTRL_DP_DECOUPLE     = 0;
// 4 (RW) : Timer stop at completion counter
localparam integer TMR_STOP_REG                             = 4;
// 5 (RO) : Timers
localparam integer TMR_REG                                  = 5;
    localparam integer TMR_RD_OFFS              = 0;
    localparam integer TMR_WR_OFFS              = 64;
// 6 (RO) : Status
localparam integer STAT_REG                                 = 6;
    localparam integer STAT_CMD_USED_RD_OFFS    = 0;
    localparam integer STAT_CMD_USED_WR_OFFS    = 32;
    localparam integer STAT_DMA_RD_OFFS         = 64;
    localparam integer STAT_DMA_WR_OFFS         = 96;
    localparam integer STAT_SENT_RD_OFFS        = 128;
    localparam integer STAT_SENT_WR_OFFS        = 160;
    localparam integer STAT_PFAULTS_OFFS        = 192;
// FV
// 10 (W1S) : Post
localparam integer FV_POST_REG                            = 10;
// 11 (RO) : Status cmd used
localparam integer FV_STAT_CMD_USED_REG                   = 11;
//

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && axim_ctrl.wvalid;

always_ff @(posedge aclk, negedge aresetn) begin
    if ( aresetn == 1'b0 ) begin
        slv_reg[CTRL_REG][15:0] <= 0;
        slv_reg[CTRL_DP_REG_SET][31:0] <= 0;
        slv_reg[TMR_STOP_REG][31:0] <= 1;

`ifdef EN_FV
        rdma_post <= 1'b0;
`endif
    end
    else begin
        slv_reg[CTRL_REG][31:0] <= 0;
`ifdef EN_FV
        rdma_post <= 1'b0;
`endif
        
        // Page fault
        if(rd_cnfg.pf.miss || wr_cnfg.pf.miss) begin
            irq_pending <= 1'b1;
            slv_reg[PF_REG][VADDR_MISS_OFFS+:VADDR_BITS] <= rd_cnfg.pf.miss ? rd_cnfg.pf.vaddr : wr_cnfg.pf.vaddr; // miss virtual address
            slv_reg[PF_REG][LEN_MISS_OFFS+:LEN_BITS]  <= rd_cnfg.pf.miss ? rd_cnfg.pf.len   : wr_cnfg.pf.len;   // miss length
        end
        if(slv_reg[CTRL_REG][CTRL_CLR_IRQ_PENDING]) 
            irq_pending <= 1'b0;

        // Status counters
        slv_reg[STAT_REG][STAT_DMA_RD_OFFS+:32] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] ? 0 : slv_reg[STAT_REG][STAT_DMA_RD_OFFS+:32] + rd_cnfg.done_host + rd_cnfg.done_card + rd_cnfg.done_sync;
        slv_reg[STAT_REG][STAT_DMA_WR_OFFS+:32] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_WR] ? 0 : slv_reg[STAT_REG][STAT_DMA_WR_OFFS+:32] + wr_cnfg.done_host + wr_cnfg.done_card + wr_cnfg.done_sync;
        slv_reg[STAT_REG][STAT_SENT_RD_OFFS+:32] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] ? 0 : slv_reg[STAT_REG][STAT_SENT_RD_OFFS+:32] + rd_sent;
        slv_reg[STAT_REG][STAT_SENT_WR_OFFS+:32] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_WR] ? 0 : slv_reg[STAT_REG][STAT_SENT_WR_OFFS+:32] + wr_sent;
        slv_reg[STAT_REG][STAT_PFAULTS_OFFS+:32] <= (slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] || slv_reg[CTRL_REG][CTRL_CLR_STAT_WR]) ? 
            0 : slv_reg[STAT_REG][STAT_PFAULTS_OFFS+:32] + (rd_cnfg.pf.miss || wr_cnfg.pf.miss);

        // Timers
        slv_reg[TMR_REG][TMR_RD_OFFS+:64] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_RD] ? 
            0 : (slv_reg[STAT_REG][STAT_DMA_RD_OFFS+:32] >= slv_reg[TMR_STOP_REG][31:0]) ? slv_reg[TMR_REG][TMR_RD_OFFS+:64] : slv_reg[TMR_REG][TMR_RD_OFFS+:64] + 1;
        slv_reg[TMR_REG][TMR_WR_OFFS+:64] <= slv_reg[CTRL_REG][CTRL_CLR_STAT_WR] ? 
            0 : (slv_reg[STAT_REG][STAT_DMA_WR_OFFS+:32] >= slv_reg[TMR_STOP_REG][31:0]) ? slv_reg[TMR_REG][TMR_WR_OFFS+:64] : slv_reg[TMR_REG][TMR_WR_OFFS+:64] + 1;

        if(slv_reg_wren) begin
            case (axi_awaddr[ADDR_LSB+:ADDR_MSB]) 
                CTRL_REG: // Control
                    for (int i = 0; i < (AVX_DATA_BITS/8); i++) begin
                        if(axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_REG][(i*8)+:8] <= axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                CTRL_DP_REG_SET: // Control datapath set
                    for (int i = 0; i < CTRL_BYTES; i++) begin
                        if(axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] | axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                CTRL_DP_REG_CLR: // Control datapath clear
                    for (int i = 0; i < CTRL_BYTES; i++) begin
                        if(axim_ctrl.wstrb[i]) begin
                            slv_reg[CTRL_DP_REG_SET][(i*8)+:8] <= slv_reg[CTRL_DP_REG_SET][(i*8)+:8] & ~axim_ctrl.wdata[(i*8)+:8];
                        end
                    end
                TMR_STOP_REG: // Timer stop at
                    for (int i = 0; i < LEN_BYTES; i++) begin
                        if(axim_ctrl.wstrb[i]) begin
                            slv_reg[TMR_STOP_REG][(i*8)+:8] <= axim_ctrl.wdata[(i*8)+:8];
                        end
                    end

`ifdef EN_FV
                FV_POST_REG: // Post
                    for (int i = 0; i < AVX_DATA_BITS/8; i++) begin
                        if(axim_ctrl.wstrb[i]) begin
                            slv_reg[FV_POST_REG][(i*8)+:8] <= axim_ctrl.wdata[(i*8)+:8];
                            rdma_post <= 1'b1;
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

always_ff @(posedge aclk, negedge aresetn) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 0;
  end
  else begin
    axi_rdata <= 0;
    if(slv_reg_rden) begin
      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        PF_REG: // Page fault
            axi_rdata[0+:96] <= slv_reg[PF_REG];
        CTRL_DP_REG_SET: // Datapath
            axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        CTRL_DP_REG_CLR: // Datapath
            axi_rdata[15:0] <= slv_reg[CTRL_DP_REG_SET][15:0];
        TMR_STOP_REG: // Timer stop at
            axi_rdata[31:0] <= slv_reg[TMR_STOP_REG][31:0];
        TMR_REG: // Timers
            axi_rdata[127:0] <= slv_reg[TMR_REG];
        STAT_REG: begin // Status
            axi_rdata[63:0] <= {wr_queue_used, rd_queue_used};
            axi_rdata[223:64] <= slv_reg[STAT_REG][223:64];            
        end

`ifdef EN_FV
        FV_POST_REG:
            axi_rdata <= slv_reg[FV_POST_REG];
        FV_STAT_CMD_USED_REG: 
            axi_rdata[31:0] <= rdma_queue_used;
`endif
        
        default: ;
      endcase
    end
  end 
end

// ---------------------------------------------------------------------------------------- 
// Output
// ----------------------------------------------------------------------------------------
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
assign rd_req_cnfg.req.vaddr = slv_reg[CTRL_REG][CTRL_VADDR_RD_OFFS+:VADDR_BITS];
assign rd_req_cnfg.req.len = slv_reg[CTRL_REG][CTRL_LEN_RD_OFFS+:LEN_BITS];
assign rd_req_cnfg.req.sync = slv_reg[CTRL_REG][CTRL_SYNC_RD];
assign rd_req_cnfg.req.ctl = 1'b1;
assign rd_req_cnfg.req.stream = slv_reg[CTRL_REG][CTRL_STREAM_RD];
assign rd_req_cnfg.req.dest = slv_reg[CTRL_REG][CTRL_DEST_RD+:4];
assign rd_req_cnfg.req.rsrvd = 0;
assign rd_req_cnfg.valid = slv_reg[CTRL_REG][CTRL_START_RD];

assign wr_req_cnfg.req.vaddr = slv_reg[CTRL_REG][CTRL_VADDR_WR_OFFS+:VADDR_BITS];
assign wr_req_cnfg.req.len = slv_reg[CTRL_REG][CTRL_LEN_WR_OFFS+:LEN_BITS];
assign wr_req_cnfg.req.sync = slv_reg[CTRL_REG][CTRL_SYNC_WR];
assign wr_req_cnfg.req.ctl = 1'b1;
assign wr_req_cnfg.req.stream = slv_reg[CTRL_REG][CTRL_STREAM_WR];
assign wr_req_cnfg.req.dest = slv_reg[CTRL_REG][CTRL_DEST_WR+:4];
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

`ifdef EN_BPSS

reqIntf rd_req_user_q ();
reqIntf wr_req_user_q ();

// Command queues (user logic)
axis_data_fifo_req_96_used inst_cmd_queue_rd_user (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(rd_req_user.valid),
  .s_axis_tready(rd_req_user.ready),
  .s_axis_tdata(rd_req_user.req),
  .m_axis_tvalid(rd_req_user_q.valid),
  .m_axis_tready(rd_req_user_q.ready),
  .m_axis_tdata(rd_req_user_q.req),
  .axis_wr_data_count()
);

axis_data_fifo_req_96_used inst_cmd_queue_wr_user (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(wr_req_user.valid),
  .s_axis_tready(wr_req_user.ready),
  .s_axis_tdata(wr_req_user.req),
  .m_axis_tvalid(wr_req_user_q.valid),
  .m_axis_tready(wr_req_user_q.ready),
  .m_axis_tdata(wr_req_user_q.req),
  .axis_wr_data_count()
);

axis_interconnect_cnfg_req_arbiter inst_rd_interconnect_user (
  .ACLK(aclk),
  .ARESETN(aresetn),

  .S00_AXIS_ACLK(aclk),
  .S00_AXIS_ARESETN(aresetn),
  .S00_AXIS_TVALID(rd_req_host.valid),
  .S00_AXIS_TREADY(rd_req_host.ready),
  .S00_AXIS_TDATA(rd_req_host.req),

  .S01_AXIS_ACLK(aclk),
  .S01_AXIS_ARESETN(aresetn),
  .S01_AXIS_TVALID(rd_req_user_q.valid),
  .S01_AXIS_TREADY(rd_req_user_q.ready),
  .S01_AXIS_TDATA(rd_req_user_q.req),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(rd_req.valid),
  .M00_AXIS_TREADY(rd_req.ready),
  .M00_AXIS_TDATA(rd_req.req),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0)
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
  .S01_AXIS_TVALID(wr_req_user_q.valid),
  .S01_AXIS_TREADY(wr_req_user_q.ready),
  .S01_AXIS_TDATA(wr_req_user_q.req),

  .M00_AXIS_ACLK(aclk),
  .M00_AXIS_ARESETN(aresetn),
  .M00_AXIS_TVALID(wr_req.valid),
  .M00_AXIS_TREADY(wr_req.ready),
  .M00_AXIS_TDATA(wr_req.req),

  .S00_ARB_REQ_SUPPRESS(0),
  .S01_ARB_REQ_SUPPRESS(0)
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

// RDMA requests
metaIntf #(.DATA_BITS(FV_REQ_BITS)) rdma_req_cnfg();

// Assign
assign rdma_req_cnfg.data[4:0] = slv_reg[FV_POST_REG][0+:5]; // opcode
assign rdma_req_cnfg.data[28:5] = slv_reg[FV_POST_REG][5+:24]; // local qpn
assign rdma_req_cnfg.data[32:29] = ID_REG; // local region
assign rdma_req_cnfg.data[33] = 1'b1; // host
assign rdma_req_cnfg.data[34] = 1'b0; // mode
assign rdma_req_cnfg.data[63:35] = 0; // reserved
assign rdma_req_cnfg.data[255:64] = slv_reg[FV_POST_REG][64+:192]; // params, length, remote vaddr, local vaddr
assign rdma_req_cnfg.valid = rdma_post;

// Parser
network_req_parser #(.ID_REG(ID_REG), .HOST(1)) inst_parser (.aclk(aclk), .aresetn(aresetn), .req_in(rdma_req_cnfg), .req_out(rdma_req), .used(rdma_queue_used));

`endif

// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

// I/O
assign axim_ctrl.awready = axi_awready;
assign axim_ctrl.wready = axi_wready;
assign axim_ctrl.bresp = axi_bresp;
assign axim_ctrl.bvalid = axi_bvalid;
assign axim_ctrl.arready	= axi_arready;
assign axim_ctrl.rdata = axi_rdata;
assign axim_ctrl.rresp = axi_rresp;
assign axim_ctrl.rlast = axi_rlast;
assign axim_ctrl.rvalid = axi_rvalid;
assign axim_ctrl.bid = axim_ctrl.awid;
assign axim_ctrl.rid = axim_ctrl.arid;
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
        if (~axi_awready && axim_ctrl.awvalid && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
        begin
            // slave is ready to accept an address and
            // associated control signals
            axi_awready <= 1'b1;
            axi_awv_awr_flag  <= 1'b1; 
            // used for generation of bresp() and bvalid
        end
        else if (axim_ctrl.wlast && axi_wready)          
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
        if (~axi_awready && axim_ctrl.awvalid && ~axi_awv_awr_flag)
        begin
            // address latching 
            axi_awaddr <= axim_ctrl.awaddr[AVX_ADDR_BITS-1:0];  
            axi_awburst <= axim_ctrl.awburst; 
            axi_awlen <= axim_ctrl.awlen;     
            // start address of transfer
            axi_awlen_cntr <= 0;
        end   
        else if((axi_awlen_cntr <= axi_awlen) && axi_wready && axim_ctrl.wvalid)        
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
        if ( ~axi_wready && axim_ctrl.wvalid && axi_awv_awr_flag)
        begin
            // slave can accept the write data
            axi_wready <= 1'b1;
        end
        //else if (~axi_awv_awr_flag)
        else if (axim_ctrl.wlast && axi_wready)
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
        if (axi_awv_awr_flag && axi_wready && axim_ctrl.wvalid && ~axi_bvalid && axim_ctrl.wlast )
        begin
            axi_bvalid <= 1'b1;
            axi_bresp  <= 2'b0; 
            // 'OKAY' response 
        end                   
        else
        begin
            if (axim_ctrl.bready && axi_bvalid) 
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
        if (~axi_arready && axim_ctrl.arvalid && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
        begin
            axi_arready <= 1'b1;
            axi_arv_arr_flag <= 1'b1;
        end
        else if (axi_rvalid && axim_ctrl.rready && axi_arlen_cntr == axi_arlen)
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
        if (~axi_arready && axim_ctrl.arvalid && ~axi_arv_arr_flag)
        begin
            // address latching 
            axi_araddr <= axim_ctrl.araddr[AVX_ADDR_BITS-1:0]; 
            axi_arburst <= axim_ctrl.arburst; 
            axi_arlen <= axim_ctrl.arlen;     
            // start address of transfer
            axi_arlen_cntr <= 0;
            axi_rlast <= 1'b0;
        end   
        else if((axi_arlen_cntr <= axi_arlen) && axi_rvalid && axim_ctrl.rready)        
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
        else if (axim_ctrl.rready)   
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
        else if (axi_rvalid && axim_ctrl.rready)
        begin
            axi_rvalid <= 1'b0;
        end            
    end
end    

endmodule