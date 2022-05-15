`ifndef AXI_ECI_WR_RESP_2VC_SV
`define AXI_ECI_WR_RESP_2VC_SV

import eci_cmd_defs::*;
import block_types::*;

module axi_eci_wr_resp_2vc (
  input logic 					                                aclk,
  input logic 					                                aresetn,
  // Write response B channel
  output logic [ECI_ID_WIDTH-1:0] 	                    s_axi_bid,
  output logic [1:0] 					                          s_axi_bresp,
  output logic 					                                s_axi_bvalid,
  input  logic 					                                s_axi_bready,
  // Write response from VC
  input logic [ECI_WORD_WIDTH-1:0]                      vc_pkt_i,
  input logic [4:0]                                     vc_pkt_size_i,
  input logic 					                                vc_pkt_valid_i,
  output logic 					                                vc_pkt_ready_o
);

  logic [(ECI_ID_WIDTH + 2)-1:0] id_concat_status;
  assign id_concat_status = get_id_status_from_resp(vc_pkt_i);
    /*
  ila_wr_resp inst_ila_wr_resp (
      .clk(aclk),
      .probe0(s_axi_bid), // 5
      .probe1(s_axi_bresp), // 2
      .probe2(s_axi_bvalid),
      .probe3(s_axi_bready),
      .probe4(vc_pkt_i[63:0]), // 64
      .probe5(vc_pkt_size_i), // 5
      .probe6(vc_pkt_valid_i),
      .probe7(vc_pkt_ready_o)
  );
    */
  // Send it
  assign s_axi_bvalid = vc_pkt_valid_i;
  assign vc_pkt_ready_o = s_axi_bready;
  assign s_axi_bid = id_concat_status[(ECI_ID_WIDTH + 2)-1:2];
  assign s_axi_bresp = id_concat_status[1:0];

  // Extract info
  function automatic [(ECI_ID_WIDTH + 2) - 1 : 0] get_id_status_from_resp
    (
    input logic [ECI_WORD_WIDTH-1:0] resp
    );
    // contains both ID and status
    logic [(ECI_ID_WIDTH + 2)-1:0]   id_concat_status;
    eci_word_t mresp;
    mresp = resp;

    id_concat_status[(ECI_ID_WIDTH + 2)-1:2] = mresp.pemd.rreq_id;
    // OKAY - 00
    // NOT OKAY - 01
    id_concat_status[1:0] = (mresp.pemd.opcode == ECI_CMD_MRSP_PEMD) ? 2'b00 : 2'b01;

    return(id_concat_status);
  endfunction

endmodule 
`endif
