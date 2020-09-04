/**
 *  TLB bram
 *
 * Implementation of the TLB in the on-chip memory.
 * @param:
 *   - TLB_ORDER :  TLB size (power of 2)
 *   - PG_BITS :    Initial addressing bit
 *   - N_ASSOC :    Set associativity
 */

import lynxTypes::*;

module tlb_slave #(
  parameter integer TLB_ORDER = 10,
  parameter integer PG_BITS = 12,
  parameter integer N_ASSOC = 4
) (
  input  logic              aclk,
  input  logic              aresetn,
  
  AXI4L.s                   axi_ctrl,

  tlbIntf.s                 TLB
);

// -- Decl ----------------------------------------------------------
// ------------------------------------------------------------------

// Constants
localparam integer N_BRAM_BITS = $clog2(N_ASSOC);
localparam integer ADDR_LSB = (AXIL_DATA_BITS/32) + 1;
localparam integer ADDR_MSB = TLB_ORDER;
localparam integer AXIL_ADDR_BITS = N_BRAM_BITS + ADDR_MSB + ADDR_LSB;

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

// Internal signals
logic slv_reg_rden;
logic slv_reg_wren;
logic aw_en;

// -- Def -----------------------------------------------------------
// ------------------------------------------------------------------

// Write active
assign slv_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

// Read active
assign slv_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

// Page table
logic [ADDR_MSB-1:0] ram_addr;
logic [N_ASSOC-1:0] [(AXIL_DATA_BITS/8)-1:0] ram_wr_en;
logic [N_ASSOC-1:0] [AXIL_DATA_BITS-1:0] ram_rd_data;

always_comb begin
  ram_wr_en = 0;
  axi_rdata = ram_rd_data[0];


  if(slv_reg_wren) begin
      ram_addr = axi_awaddr[ADDR_LSB+ADDR_MSB-1:ADDR_LSB];
      if(N_ASSOC > 1) begin
        for (int i = 0; i < N_ASSOC; i++) begin
            if(i == axi_awaddr[AXIL_ADDR_BITS-1:ADDR_MSB+ADDR_LSB]) begin
              ram_wr_en[i] = axi_ctrl.wstrb;
            end
        end  
      end
      else begin 
        ram_wr_en[0][(AXIL_DATA_BITS/8)-1:0] = axi_ctrl.wstrb;
      end
  end
  else begin
    ram_addr = axi_araddr[ADDR_LSB+ADDR_MSB-1:ADDR_LSB];
    if(N_ASSOC > 1) begin
      for (int i = 0; i < N_ASSOC; i++) begin
        if(i == axi_araddr[AXIL_ADDR_BITS-1:ADDR_MSB+ADDR_LSB]) begin
          axi_rdata = ram_rd_data[i];
        end
      end
    end 
    else begin
      axi_rdata = ram_rd_data[0][AXIL_DATA_BITS-1:0];
    end
  end
end

// TLB
for (genvar i = 0; i < N_ASSOC; i++) begin
  // BRAM instantiation
  ram_tp_nc #(
      .ADDR_BITS(TLB_ORDER),
      .DATA_BITS(TLB_DATA_BITS)
  ) inst_pt (
      .clk       (aclk),
      .a_we      (ram_wr_en[i]),
      .a_addr    (ram_addr),
      .b_addr    (TLB.addr[PG_BITS+TLB_ORDER-1:PG_BITS]),
      .a_data_in (axi_ctrl.wdata),
      .a_data_out(ram_rd_data[i]),
      .b_data_out(TLB.data[i])
    );
end

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

endmodule // tlb_slave