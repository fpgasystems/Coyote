`ifndef AXI_ECI_RD_REQ_2VC_SV
`define AXI_ECI_RD_REQ_2VC_SV

import eci_cmd_defs::*;
import block_types::*;

module axi_eci_rd_req_2vc (
    input  logic 						                    aclk,
    input  logic 						                    aresetn,
    // AXI AR
    input  logic [ECI_ID_WIDTH-1:0] 	                    s_axi_arid,
    input  logic [ECI_ADDR_WIDTH-1:0]                       s_axi_araddr,
    input  logic [7:0]                                      s_axi_arlen,
    input  logic 						                    s_axi_arvalid,
    output logic 						                    s_axi_arready,
    //MIB VC interface - TO CPU
    output logic [ECI_WORD_WIDTH-1:0]                       mib_vc_data_o,
    output logic [4:0]                                      mib_vc_size_o,
    output logic 						                    mib_vc_valid_o,
    input  logic 						                    mib_vc_ready_i
);

    localparam ADDR_LSB = $clog2( ECI_CL_SIZE_BYTES );
   
    logic stall;

    // Internal regs
    logic [ECI_ID_WIDTH-1:0] arid_C;
    logic [ECI_ADDR_WIDTH-1:0] araddr_C;
    logic arvalid_C;

    logic [ECI_WORD_WIDTH-1:0] eci_load_cmd;
    logic [ECI_WORD_WIDTH-1:0] eci_data_C;
    logic [5:0] eci_size_C;
    logic eci_valid_C;

    // TMP
    logic [ECI_WORD_WIDTH-1:0]                       mib_vc_data_tmp;
    logic 						                     mib_vc_valid_tmp;
    logic 						                     mib_vc_ready_tmp;

    /*
    ila_rd_req inst_ila_rd_req (
        .clk(aclk),
        .probe0(s_axi_arid), // 5
        .probe1(s_axi_araddr), // 40
        .probe2(s_axi_arlen), // 8
        .probe3(s_axi_arvalid),
        .probe4(s_axi_arready),
        .probe5(mib_vc_data_o), // 64
        .probe6(mib_vc_size_o), // 5
        .probe7(mib_vc_valid_o),
        .probe8(mib_vc_ready_i),
        .probe9(stall),
        .probe10(arid_C), // 5
        .probe11(araddr_C), // 40
        .probe12(arvalid_C)
    );
    */
    // REG
    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            arid_C <= 'X;
            araddr_C <= 'X;
            arvalid_C <= 1'b0;

            eci_data_C <= 'X;
            eci_size_C <= 'X;
            eci_valid_C <= 1'b0;
        end
        else begin
            if(~stall) begin
                // S0
                arid_C <= s_axi_arid;
                araddr_C <= s_axi_araddr;
                arvalid_C <= s_axi_arvalid;

                // S1
                eci_data_C <= eci_load_cmd;
                eci_size_C <= 1;
                eci_valid_C <= arvalid_C;
            end
        end
    end

    // Combinatorial magic
    always_comb begin : GET_ECI_COMMAND
        // local
        automatic eci_word_t this_cmd;
        logic [ECI_ADDR_WIDTH-1:0] axi_araddr_aliased;

        axi_araddr_aliased = '0;
        axi_araddr_aliased = eci_alias_address(araddr_C);
        this_cmd = '0;
        this_cmd.rldt.opcode    = ECI_CMD_MREQ_RLDT;
        this_cmd.rldt.rreq_id   = arid_C;
        this_cmd.rldt.dmask	    = '1;
        this_cmd.rldt.ns        = 1'b1;   
        // 
        this_cmd.rldt.address[ECI_ADDR_WIDTH-1:ADDR_LSB] = axi_araddr_aliased[(ECI_ADDR_WIDTH-1)-ADDR_LSB:0];
        
        eci_load_cmd = this_cmd.eci_word;    
    end

    assign stall = ~mib_vc_ready_tmp;
    assign s_axi_arready = ~stall;

    // I/O
    assign mib_vc_data_tmp   = eci_data_C;
    assign mib_vc_size_o     = 1;
    assign mib_vc_valid_tmp  = eci_valid_C;

    axis_data_fifo_vc_64 inst_vc_fifo_rd (
      .s_axis_aresetn(aresetn),
      .s_axis_aclk(aclk),
      .s_axis_tvalid(mib_vc_valid_tmp),
      .s_axis_tready(mib_vc_ready_tmp),
      .s_axis_tdata(mib_vc_data_tmp), // 64
      .m_axis_tvalid(mib_vc_valid_o),
      .m_axis_tready(mib_vc_ready_i),
      .m_axis_tdata(mib_vc_data_o) // 64
   );
   
endmodule // axi_eci_rd_req
`endif
