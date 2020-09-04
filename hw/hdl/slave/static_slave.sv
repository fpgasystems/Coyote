/**
 *  Static configuration slave
 */ 

import lynxTypes::*;

module static_slave (
  input  logic              aclk,
  input  logic              aresetn,
  
`ifdef EN_PR
  // XDMA descriptors
  xdmaIntf.m                pr_xdma_req,
`endif

`ifdef EN_FV
  // ARP
  metaIntf.m                arp_lookup_request,
  metaIntf.s                arp_lookup_reply,

  // IP
  metaIntf.m                set_ip_addr,
  metaIntf.m                set_board_number,

  // QP
  metaIntf.m                qp_interface,
  metaIntf.m                conn_interface,
`endif

  // Lowspeed control (only applicable to u250)
  output logic [2:0]        lowspeed_ctrl,

  // Control bus (HOST)
  AXI4L.s                   axi_ctrl
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
`ifdef EN_FV
localparam integer N_REGS = 29;
`else
  `ifdef EN_PR
localparam integer N_REGS = 14;
  `else
localparam integer N_REGS = 8;
  `endif
`endif
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer AXIL_ADDR_BITS = ADDR_LSB + ADDR_MSB;

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

// Registers
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] slv_reg;
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// -- Register map ----------------------------------------------------------------------- 
// CONFIG
// 0 (RW) : Probe
localparam integer PROBE_REG          = 0;
// 1 (RO) : Number of channels
localparam integer N_CHAN_REG         = 1;
// 2 (RO) : Number of regions
localparam integer N_REGIONS_REG      = 2;
// 3 (RO) : Control config
localparam integer CTRL_CNFG_REG      = 3;
// 4 (RO) : Memory config
localparam integer MEM_CNFG_REG       = 4;
// 5 (RO) : Partial reconfiguration config
localparam integer PR_CNFG_REG        = 5;
// 6 (RO) : FV config
localparam integer FV_CNFG_REG        = 6; 
// 7 (RW) : Control (only for u250)
localparam integer LOWSPEED_REG       = 7;
// PR
// 10 (W1S) : PR control
localparam integer PR_CTRL_REG        = 10;
  localparam integer PR_START  = 0;
  localparam integer PR_CTL    = 1;
  localparam integer PR_CLR    = 2;
// 11 (RO) : Status
localparam integer PR_STAT_REG        = 11;
  localparam integer PR_DONE   = 0;
  localparam integer PR_READY  = 1;
// 12 (RW) : Physical address
localparam integer PR_ADDR_REG        = 12;
// 13 (RW) : Length read
localparam integer PR_LEN_REG         = 13;
// FV
// 20 (RW) : IP address
localparam integer FV_IPADDR_REG    = 20;
// 21 (RW) : Board number 
localparam integer FV_BOARDNUM_REG  = 21;
// 22 (W1S) : ARP lookup
localparam integer FV_ARP_REG       = 22;
// 23 - 25 (RW) : Write QP context
localparam integer FV_CTX_REG_0     = 23;
localparam integer FV_CTX_REG_1     = 24;
localparam integer FV_CTX_REG_2     = 25;
// 26 - 28 (RW) : Write QP connection
localparam integer FV_CONN_REG_0    = 26;
localparam integer FV_CONN_REG_1    = 27;
localparam integer FV_CONN_REG_2    = 28;
//

// ---------------------------------------------------------------------------------------- 
// Write process 
// ----------------------------------------------------------------------------------------
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk, negedge aresetn) begin
  if ( aresetn == 1'b0 ) begin
    slv_reg[LOWSPEED_REG][2:0] <= ~0;
  
`ifdef EN_PR
    slv_reg[PR_CTRL_REG][15:0] <= 0;
    slv_reg[PR_STAT_REG][15:0] <= 0;
`endif

`ifdef EN_FV
    set_ip_addr.valid <= 1'b0;
    set_board_number.valid <= 1'b0;
    arp_lookup_request.valid <= 1'b0;
    arp_lookup_reply.ready <= 1'b1;

    qp_interface.valid <= 1'b0;
    conn_interface.valid <= 1'b0;
`endif 
  end
  else begin
`ifdef EN_PR
    slv_reg[PR_CTRL_REG] <= 0;
    slv_reg[PR_STAT_REG][PR_STAT_DONE] <= slv_reg[PR_CTRL_REG][PR_CTRL_CLR] ? 1'b0 : pr_req.done ? 1'b1 : slv_reg[PR_STAT_REG][PR_STAT_DONE];
`endif

`ifdef EN_FV
    arp_lookup_request.valid <= arp_lookup_request.ready ? 1'b0 : arp_lookup_request.valid;
    arp_lookup_reply.ready <= 1'b1;

    qp_interface.valid <= qp_interface.ready ? 1'b0 : qp_interface.valid;
    conn_interface.valid <= conn_interface.ready ? 1'b0 : conn_interface.valid;
`endif

    if(slv_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        PROBE_REG: // Probe
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[PROBE_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
         
        LOWSPEED_REG: // Lowspeed control
          for (int i = 0; i < 1; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[LOWSPEED_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end

`ifdef EN_PR  
        PR_CTRL_REG: // PR control
          for (int i = 0; i < 2; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[PR_CTRL_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_ADDR_REG: // PR address
          for (int i = 0; i < AXIL_DATA_BITS/8; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[PR_ADDR_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        PR_LEN_REG: // PR length
          for (int i = 0; i < 4; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              slv_reg[PR_LEN_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
`endif

`ifdef EN_FV
        FV_IPADDR_REG: // IP address
          for (int i = 0; i < 4; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              set_ip_addr.data[(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
              set_ip_addr.valid <= 1'b1;
            end
          end
        FV_BOARDNUM_REG: // Board number
          for (int i = 0; i < 1; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              set_board_number.data[3:0] <= axi_ctrl.wdata[3:0];
              set_board_number.valid <= 1'b1;
            end
          end
        FV_ARP_REG: // ARP lookup
          for (int i = 0; i < 4; i++) begin
            if(axi_ctrl.wstrb[i]) begin
              arp_lookup_request.data[(i*8)+:8] <= axi_ctrl.wdata[(24-i*8)+:8];
              arp_lookup_request.valid <= 1'b1;
            end
          end
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
              qp_interface.valid <= 1'b1;
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
              conn_interface.valid <= 1'b1;
            end
          end
`endif

        default : ;
      endcase
    end
  end
end    

// ---------------------------------------------------------------------------------------- 
// Read process 
// ----------------------------------------------------------------------------------------
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk, negedge aresetn) begin
  if( aresetn == 1'b0 ) begin
    axi_rdata <= 0;
  end
  else begin
    axi_rdata <= 0;
    if(slv_reg_rden) begin
      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        PROBE_REG:
          axi_rdata <= slv_reg[PROBE_REG];
        N_CHAN_REG: // Number of channels
          axi_rdata <= N_CHAN;
        N_REGIONS_REG: // Number of regions
          axi_rdata <= N_REGIONS;
        CTRL_CNFG_REG: begin // Control config
          axi_rdata[0] <= AVX_FLOW;
          axi_rdata[1] <= BPSS_FLOW;
        end
        MEM_CNFG_REG: begin // Memory config
          axi_rdata[0] <= DDR_FLOW;
          axi_rdata[5:1] <= N_DDR_CHAN;
        end
        PR_CNFG_REG: // PR config
          axi_rdata <= PR_FLOW;
        FV_CNFG_REG: begin // FV config
          axi_rdata[0] <= FV_FLOW;
          axi_rdata[1] <= FV_VERBS;
        end
        LOWSPEED_REG:
          axi_rdata[2:0] <= slv_reg[LOWSPEED_REG][2:0];
        
`ifdef EN_PR
        PR_STAT_REG:
          axi_rdata[1:0] <= {pr_req.ready, slv_reg[PR_STAT_REG][PR_DONE]};
        PR_ADDR_REG:
          axi_rdata <= slv_reg[PR_ADDR_REG];
        PR_LEN_REG:
          axi_rdata[31:0] <= slv_reg[PR_LEN_REG][31:0];
`endif

`ifdef EN_FV
        FV_CTX_REG_0: // Context
          axi_rdata <= slv_reg[FV_CTX_REG_0];
        FV_CTX_REG_1: // Context
          axi_rdata <= slv_reg[FV_CTX_REG_1];
        FV_CTX_REG_2: // Context final
          axi_rdata <= slv_reg[FV_CTX_REG_2];
        FV_CONN_REG_0: // Connection
          axi_rdata <= slv_reg[FV_CONN_REG_0];
        FV_CONN_REG_1: // Connection
          axi_rdata <= slv_reg[FV_CONN_REG_1];
        FV_CONN_REG_2: // Connection final
          axi_rdata <= slv_reg[FV_CONN_REG_2];
`endif

        default: ;
      endcase
    end
  end 
end

// ---------------------------------------------------------------------------------------- 
// Output
// ----------------------------------------------------------------------------------------
assign lowspeed_ctrl = slv_reg[LOWSPEED_REG][2:0];

`ifdef EN_PR

dmaIntf pr_req ();
dmaIntf xdma_req ();

always_comb begin
  // PR request
  pr_req.valid = slv_reg[PR_CTRL_REG][PR_START];
  pr_req.req.ctl = slv_reg[PR_CTRL_REG][PR_CTL];
  pr_req.req.paddr = slv_reg[PR_ADDR_REG];
  pr_req.req.len = slv_reg[PR_LEN_REG];
  // Done signal
  pr_req.done = xdma_req.done;
end

queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(4)
) inst_que (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(pr_req.valid),
  .rdy_snk(pr_req.ready),
  .data_snk(pr_req.req),
  .val_src(xdma_req.valid),
  .rdy_src(xdma_req.ready),
  .data_src(xdma_req.req)
);

// XDMA
assign pr_xdma_req.h2c_ctl           = {{11{1'b0}}, xdma_req.req.ctl, {2{1'b0}}, {2{xdma_req.req.ctl}}};
assign pr_xdma_req.h2c_addr          = xdma_req.req.paddr;
assign pr_xdma_req.h2c_len           = xdma_req.req.len;
assign pr_xdma_req.h2c_valid         = xdma_req.valid;

assign pr_xdma_req.c2h_ctl           = 0;
assign pr_xdma_req.c2h_addr          = 0;
assign pr_xdma_req.c2h_len           = 0;
assign pr_xdma_req.c2h_valid         = 0;

assign xdma_req.ready                 = pr_xdma_req.h2c_ready;;
assign xdma_req.done                  = pr_xdma_req.h2c_status[1];

`endif

`ifdef EN_FV

// FV qp interface
assign qp_interface.data[54:0] = slv_reg[FV_CTX_REG_0][54:0]; // remote psn, local qpn, local region, qp state 
assign qp_interface.data[94:55] = slv_reg[FV_CTX_REG_1][39:0]; // remote key, local psn
assign qp_interface.data[142:95] = slv_reg[FV_CTX_REG_2][47:0]; // vaddr
assign qp_interface.data[143:143] = 0;

// FV qp connection interface
assign conn_interface.data[39:0] = slv_reg[FV_CONN_REG_0][39:0]; // remote qpn, local qpn (24?)
assign conn_interface.data[103:40] = slv_reg[FV_CONN_REG_1][63:0]; // gid
assign conn_interface.data[167:104] = slv_reg[FV_CONN_REG_2][63:0]; // gid
assign conn_interface.data[183:168] = slv_reg[FV_CONN_REG_0][55:40]; // port

`endif

// ---------------------------------------------------------------------------------------- 
// AXI
// ----------------------------------------------------------------------------------------

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

endmodule // cnfg_slave