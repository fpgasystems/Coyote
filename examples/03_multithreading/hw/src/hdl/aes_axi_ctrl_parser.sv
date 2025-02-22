import lynxTypes::*;

/**
 * aes_axi_ctrl_parser
 * @brief Reads from the AXI Lite stream containing the encryption keys
 * 
 * @param[in] aclk Clock signal
 * @param[in] aresetn Active low reset signal
 
 * @param[in/out] axi_ctrl AXI Lite Control signal, from/to the host via PCIe and XDMA

 * @param[out] key Encryption key
 * @param[out] key_valid Asserted high when key is complete, so aes_top can start the key inflation process

 * @param[out] iv Initialization vector (IV) used to start the encryption process
 * @param[out] iv_dest IV destination stream in vfpga_top.svh; when asserthed high, implies the i-th cThread can start the encryption on the axis_host_recv[i]
 * @param[out] iv_valid Asserted high when the IV is complete, i.e. both the 64-bit registers are set
 */
module aes_axi_ctrl_parser (
  input  logic          aclk,
  input  logic          aresetn,
  
  AXI4L.s               axi_ctrl,

  output logic [127:0]  key,
  output logic          key_valid,

  output logic [127:0]  iv,
  output logic [5:0]    iv_dest,
  output logic          iv_valid
);

/////////////////////////////////////
//          CONSTANTS             //
///////////////////////////////////
localparam integer N_REGS = 5;
localparam integer ADDR_MSB = $clog2(N_REGS);
localparam integer ADDR_LSB = $clog2(AXIL_DATA_BITS/8);
localparam integer AXI_ADDR_BITS = ADDR_LSB + ADDR_MSB;

/////////////////////////////////////
//          REGISTERS             //
///////////////////////////////////
// Internal AXI registers
logic [AXI_ADDR_BITS-1:0] axi_awaddr;
logic axi_awready;
logic [AXI_ADDR_BITS-1:0] axi_araddr;
logic axi_arready;
logic [1:0] axi_bresp;
logic axi_bvalid;
logic axi_wready;
logic [AXIL_DATA_BITS-1:0] axi_rdata;
logic [1:0] axi_rresp;
logic axi_rvalid;
logic aw_en;

// Registers for holding the values read from/to be written to the AXI Lite interface
// These are synchronous but the outputs are combinatorial
logic [N_REGS-1:0][AXIL_DATA_BITS-1:0] ctrl_reg;
logic ctrl_reg_wren, ctrl_reg_rden;

/////////////////////////////////////
//         REGISTER MAP           //
///////////////////////////////////
// 0 (WR)   : Low 64 bits of AES key
localparam integer KEY_LOW_REG = 0;

// 1 (WR)   : High 64 bits of AES key
localparam integer KEY_HIGH_REG = 1;

// 2 (WR)   : Low 64 bits of initialization vector (IV)
localparam integer IV_LOW_REG = 2;

// 3 (WR)   : High 64 bits of initialization vector (IV)
localparam integer IV_HIGH_REG = 3;

// 4 (WR)   : IV destination stream (and stream i corresponds to the i-th Coyote thread)
localparam integer IV_DEST_REG = 4;

/////////////////////////////////////
//         WRITE PROCESS          //
///////////////////////////////////
// Data coming in from host to the vFPGA vie PCIe and XDMA
assign ctrl_reg_wren = axi_wready && axi_ctrl.wvalid && axi_awready && axi_ctrl.awvalid;

always_ff @(posedge aclk) begin
  if (aresetn == 1'b0) begin
    ctrl_reg <= 0;
    key_valid <= 1'b0;
    iv_valid <= 1'b0;
  end
  else begin
    key_valid <= 1'b0;
    iv_valid <= 1'b0;

    if(ctrl_reg_wren) begin
      case (axi_awaddr[ADDR_LSB+:ADDR_MSB])
        KEY_LOW_REG:     
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              ctrl_reg[KEY_LOW_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        KEY_HIGH_REG:   
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              ctrl_reg[KEY_HIGH_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];

              // key_valid is asserted high when the top 64 bits are set
              // The assumption is that first the lower 64 bits are set, and then the top 64 bits
              // This is not the safest programming, but it will suffice for this example
              // It's possible to add one more register, corresponding to the valid signal, that can also be written from the software
              key_valid <= 1'b1;
            end
          end
        IV_LOW_REG:   
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              ctrl_reg[IV_LOW_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        IV_HIGH_REG:   
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              ctrl_reg[IV_HIGH_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
            end
          end
        IV_DEST_REG:     
          for (int i = 0; i < (AXIL_DATA_BITS/8); i++) begin
            if(axi_ctrl.wstrb[i]) begin
              ctrl_reg[IV_DEST_REG][(i*8)+:8] <= axi_ctrl.wdata[(i*8)+:8];
              iv_valid <= 1'b1;
            end
          end
        default: ;
      endcase
    end
  end
end

/////////////////////////////////////
//         READ PROCESS           //
///////////////////////////////////
// Data going to the host from the vFPGA via XDMA and PCIe
assign ctrl_reg_rden = axi_arready & axi_ctrl.arvalid & ~axi_rvalid;

always_ff @(posedge aclk) begin
  if(aresetn == 1'b0) begin
    axi_rdata <= 0;
  end
  else begin
    axi_rdata <= 0;
    if(ctrl_reg_rden) begin
      case (axi_araddr[ADDR_LSB+:ADDR_MSB])
        KEY_LOW_REG:   
          axi_rdata <= key[63:0];
        KEY_HIGH_REG:  
          axi_rdata <= key[127:64];
        IV_LOW_REG:   
          axi_rdata <= iv[63:0];
        IV_HIGH_REG:  
          axi_rdata <= iv[127:64];
        default: ;
      endcase
    end
  end
end

/////////////////////////////////////
//       OUTPUT ASSIGNMENT        //
///////////////////////////////////
assign key[63:0]    = ctrl_reg[KEY_LOW_REG];
assign key[127:64]  = ctrl_reg[KEY_HIGH_REG];

assign iv[63:0]     = ctrl_reg[IV_LOW_REG];
assign iv[127:64]   = ctrl_reg[IV_HIGH_REG];
assign iv_dest      = ctrl_reg[IV_DEST_REG][5:0];

/////////////////////////////////////
//     STANDARD AXI CONTROL       //
///////////////////////////////////
// NOT TO BE EDITED

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
always_ff @(posedge aclk) begin
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
always_ff @(posedge aclk) begin
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
always_ff @(posedge aclk) begin
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
always_ff @(posedge aclk) begin
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

// rvalid and rresp
always_ff @(posedge aclk) begin
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