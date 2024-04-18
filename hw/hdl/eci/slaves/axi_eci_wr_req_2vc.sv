
`ifndef AXI_ECI_WR_REQ_2VC_SV
`define AXI_ECI_WR_REQ_2VC_SV

import eci_cmd_defs::*;
import block_types::*;

module axi_eci_wr_req_2vc (
   input  logic 					                           aclk,
   input  logic 					                           aresetn,

   // Write Address AW channel 
   input  logic [ECI_ID_WIDTH-1:0] 	                     s_axi_awid,
   input  logic [ECI_ADDR_WIDTH-1:0]                     s_axi_awaddr,
   input  logic [7:0]                                    s_axi_awlen,
   input  logic 					                           s_axi_awvalid,
   output logic 					                           s_axi_awready,

   // Write data W channe
   input  logic [ECI_CL_WIDTH-1:0] 	                     s_axi_wdata,
   input  logic [(ECI_CL_WIDTH/8)-1:0]                   s_axi_wstrb,
   input  logic 					                           s_axi_wlast,
   input  logic 					                           s_axi_wvalid,
   output logic 					                           s_axi_wready,

   // Write data to VC
   output logic [17-1:0][ECI_WORD_WIDTH-1:0]             vc_pkt_o,
   output logic [4:0] 	                                 vc_pkt_size_o,
   output logic 					                           vc_pkt_valid_o,
   input  logic 					                           vc_pkt_ready_i
);

   // Internal regs
   logic [17-1:0][ECI_WORD_WIDTH-1:0] eci_data_C;
   logic [4:0] eci_size_C;
   logic eci_valid_C;

   // Internal
   logic [ECI_WORD_WIDTH-1:0] eci_req;
   logic stall;
    
   // Fifo AW
   logic [ECI_ID_WIDTH+ECI_ADDR_WIDTH-1:0] s_axi_awdata;
   assign s_axi_awdata = {s_axi_awid, s_axi_awaddr};

   logic axi_awvalid;
   logic axi_awready;
   logic [ECI_ID_WIDTH-1:0] axi_awid;
   logic [ECI_ADDR_WIDTH-1:0] axi_awaddr;
   logic [ECI_ID_WIDTH+ECI_ADDR_WIDTH-1:0] axi_awdata;
   assign axi_awid = axi_awdata[ECI_ADDR_WIDTH+:ECI_ID_WIDTH];
   assign axi_awaddr = axi_awdata[0+:ECI_ADDR_WIDTH];

   // TMP
   logic [17-1:0][ECI_WORD_WIDTH-1:0]      vc_pkt_tmp;
   logic 					               vc_pkt_valid_tmp;
   logic 					               vc_pkt_ready_tmp;

   axis_data_fifo_wr_req_aw inst_wr_req_aw_fifo (
      .s_axis_aresetn(aresetn),
      .s_axis_aclk(aclk),
      .s_axis_tvalid(s_axi_awvalid),
      .s_axis_tready(s_axi_awready),
      .s_axis_tdata(s_axi_awdata),
      .m_axis_tvalid(axi_awvalid),
      .m_axis_tready(axi_awready),
      .m_axis_tdata(axi_awdata)
   );

   // Fifo W
   logic [ECI_CL_WIDTH-1:0] axi_wdata;
   logic [ECI_CL_WIDTH/8-1:0] axi_wstrb;
   logic axi_wvalid;
   logic axi_wready;
   logic axi_wlast;
    /*
   ila_wr_req inst_ila_wr_req (
        .clk(aclk),
        .probe0(s_axi_awid), // 5
        .probe1(s_axi_awaddr), // 40
        .probe2(s_axi_awlen), // 8
        .probe3(s_axi_awvalid),
        .probe4(s_axi_awready),
        .probe5(vc_pkt_o[0]), // 64
        .probe6(vc_pkt_size_o), // 5
        .probe7(vc_pkt_valid_o),
        .probe8(vc_pkt_ready_i),
        .probe9(stall),
        .probe10(s_axi_wdata[63:0]), // 64
        .probe11(s_axi_wvalid), 
        .probe12(s_axi_wready)
    );
    */
   axis_data_fifo_wr_req_w inst_wr_req_w_fifo (
      .s_axis_aresetn(aresetn),
      .s_axis_aclk(aclk),
      .s_axis_tvalid(s_axi_wvalid),
      .s_axis_tready(s_axi_wready),
      .s_axis_tdata(s_axi_wdata),
      .s_axis_tstrb(s_axi_wstrb),
      .s_axis_tlast(s_axi_wlast),
      .m_axis_tvalid(axi_wvalid),
      .m_axis_tready(axi_wready),
      .m_axis_tdata(axi_wdata),
      .m_axis_tstrb(axi_wstrb),
      .m_axis_tlast(axi_wlast)
   );

   // Create RSTT header
   assign eci_req = create_wr_hdr(
      .addr  (axi_awaddr),
      .id    (axi_awid),
      .wstrb (axi_wstrb)
   );

   // -- REG
   always_ff @( posedge aclk ) begin : blockName
      if(~aresetn) begin
         eci_data_C <= 'X;
         eci_size_C <= 'X;
         eci_valid_C <= 1'b0;
      end
      else begin
         if(~stall) begin
            // S1
            eci_data_C[0] <= eci_req;
            eci_data_C[1+:16] <= axi_wdata;
            eci_size_C <= 17; //get_size_from_strb(.strb(axi_wstrb));
            eci_valid_C <= axi_awvalid & axi_wvalid;
         end
      end
   end

   assign stall = ~vc_pkt_ready_tmp;
   assign axi_awready = (~stall) && (axi_awvalid & axi_wvalid);
   assign axi_wready = (~stall) && (axi_awvalid & axi_wvalid);

   assign vc_pkt_tmp = eci_data_C;
   assign vc_pkt_size_o = 17;
   assign vc_pkt_valid_tmp = eci_valid_C;

   axis_data_fifo_vc_1088 inst_vc_fifo_wr (
      .s_axis_aresetn(aresetn),
      .s_axis_aclk(aclk),
      .s_axis_tvalid(vc_pkt_valid_tmp),
      .s_axis_tready(vc_pkt_ready_tmp),
      .s_axis_tdata(vc_pkt_tmp), // 1088
      .m_axis_tvalid(vc_pkt_valid_o),
      .m_axis_tready(vc_pkt_ready_i),
      .m_axis_tdata(vc_pkt_o) // 1088
   );

   //------Functions and Tasks below------//

   // Function to create write request header from address
   // and write strobe 
   function automatic [ECI_WORD_WIDTH-1:0] create_wr_hdr (
      input logic [ECI_ADDR_WIDTH-1:0] addr,
      input logic [ECI_ID_WIDTH-1:0] id,
      input logic [(ECI_CL_WIDTH/8)-1:0] wstrb
   );
      eci_word_t this_cmd;
      eci_address_t addr_aliased;
      logic [3:0] this_dmask;
      
      addr_aliased = eci_alias_address(addr);

      this_dmask    = '0;
      this_dmask[3] = |wstrb[127:96];
      this_dmask[2] = |wstrb[95:64];
      this_dmask[1] = |wstrb[63:32];
      this_dmask[0] = |wstrb[31:0];
      
      this_cmd = '0;
      this_cmd.rstt.opcode   = ECI_CMD_MREQ_RSTT;
      this_cmd.rstt.rreq_id  = id;
      this_cmd.rstt.dmask    = this_dmask;
      this_cmd.rstt.ns       = 1'b1; // Non secure
      // Cache line address is PhyAddr[ECI_ADDR_WIDTH-1:ECI_CL_ADDR_LSB]
      // Extract cache line address from PhyAddr, alias it and add it back
      // to get the address that needs to be put in the header  
      this_cmd.rstt.address[ECI_ADDR_WIDTH-1:ECI_CL_ADDR_LSB] = addr_aliased[(ECI_ADDR_WIDTH-1)-ECI_CL_ADDR_LSB:0];
      
      return(this_cmd.eci_word);
   endfunction : create_wr_hdr


   // Get ECI packet (header+data) size based on the strobe
   // Header - 1 ECI WORD
   // Data - 4 sub cache lines,(scl) each scl is 4 ECI words each
   //        ie 128 bytes of data maximum 
   // Write strobe - 1 valid bit for each of the 128 bytes in Data
   //
   // write granularity is at sub cache line level and
   // the number of valid sub cache lines dictate the size
   // of data to be written 
   function automatic [ECI_PACKET_SIZE_WIDTH-1:0] get_size_from_strb (
      input logic [(ECI_CL_WIDTH/8)-1:0] strb
   );
      logic [ECI_PACKET_SIZE_WIDTH-1:0]  size;

      // indicates validity of the 4 sub cache lines 
      logic [3:0] 			 scl_valid;

      scl_valid[0] = |(strb[31:0]);
      scl_valid[1] = |(strb[63:32]);
      scl_valid[2] = |(strb[95:64]);
      scl_valid[3] = |(strb[127:96]);

      if(scl_valid[3])
	      size = ECI_PACKET_SIZE;        // Header + 16 words (4 scl) 
      else if(scl_valid[2])
	      size = (ECI_PACKET_SIZE - 4);  // Header + 12 words (3 scl) 
      else if(scl_valid[1])
	      size = (ECI_PACKET_SIZE - 8);  // Header + 8 words (2 scl) 
      else if(scl_valid[0])
	      size = (ECI_PACKET_SIZE - 12); // Header + 4 words (1 scl) 
      else
	      size = (ECI_PACKET_SIZE - 12); // size cannot be 0, should have atleast 1 scl 
      return(size);
      
   endfunction //get_size_from_strb

endmodule // axi_eci_wr_req
`endif
