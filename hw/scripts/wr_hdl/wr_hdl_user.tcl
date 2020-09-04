#########################################################################################
# User shell wrapper (Needed because of PR)
#########################################################################################
proc wr_hdl_user_wrapper {f_out c_reg} {
	upvar #0 cfg cnfg

	set template {}
	set entity {}
 	append entity "`timescale 1ns / 1ps\n"
	 append entity "\n"
	append entity "import lynxTypes::*;\n"
	append entity "\n"
 	append entity "/**\n"
 	append entity " * User logic wrapper\n"
 	append entity " * \n"
 	append entity " */\n"
	append entity "module design_user_wrapper_$c_reg #(\n"
	append entity ") (\n"
	append entity "    // AXI4 control\n"
	append entity "    input  logic\[AXI_ADDR_BITS-1:0]         axi_ctrl_araddr,\n"
	append entity "    input  logic\[2:0]                       axi_ctrl_arprot,\n"
	append entity "    output logic                            axi_ctrl_arready,\n"
	append entity "    input  logic                            axi_ctrl_arvalid,\n"
	append entity "    input  logic\[AXI_ADDR_BITS-1:0]         axi_ctrl_awaddr,\n"
	append entity "    input  logic\[2:0]                       axi_ctrl_awprot,\n"
	append entity "    output logic                            axi_ctrl_awready,\n"
	append entity "    input  logic                            axi_ctrl_awvalid, \n"
	append entity "    input  logic                            axi_ctrl_bready,\n"
	append entity "    output logic\[1:0]                       axi_ctrl_bresp,\n"
	append entity "    output logic                            axi_ctrl_bvalid,\n"
	append entity "    output logic\[AXI_ADDR_BITS-1:0]        axi_ctrl_rdata,\n"
	append entity "    input  logic                            axi_ctrl_rready,\n"
	append entity "    output logic\[1:0]                       axi_ctrl_rresp,\n"
	append entity "    output logic                            axi_ctrl_rvalid,\n"
	append entity "    input  logic\[AXIL_DATA_BITS-1:0]        axi_ctrl_wdata,\n"
	append entity "    output logic                            axi_ctrl_wready,\n"
	append entity "    input  logic\[(AXIL_DATA_BITS/8)-1:0]    axi_ctrl_wstrb,\n"
	append entity "    input  logic                            axi_ctrl_wvalid,\n"
	append entity "\n"
	if {$cnfg(en_bpss) eq 1} {
		append entity "    // Descriptor bypass\n"
		append entity "	   output logic 							rd_req_user_valid,\n"
		append entity "	   input  logic 							rd_req_user_ready,\n"
		append entity "	   output req_t 							rd_req_user_req,\n"
		append entity "	   output logic 							wr_req_user_valid,\n"
		append entity "	   input  logic 							wr_req_user_ready,\n"
		append entity "	   output req_t 							wr_req_user_req,\n"
		append entity "\n"
	}
	if {$cnfg(en_fv) eq 1} {
		if {$cnfg(en_fvv) eq 1} {
			append entity "    // RDMA Farview\n"
			append entity "	   input  logic 							fv_req_valid,\n"
			append entity "	   output logic 							fv_req_ready,\n"
			append entity "	   input  logic\[FV_REQ_BITS-1:0]			fv_req_data,\n"
			append entity "	   output logic 							fv_cmd_valid,\n"
			append entity "	   input  logic 							fv_cmd_ready,\n"
			append entity "	   output logic\[FV_REQ_BITS-1:0]			fv_cmd_data,\n"
			append entity "\n"
		}
		append entity "    // RDMA mem\n"
		append entity "	   input  logic 							rd_req_rdma_valid,\n"
		append entity "	   output logic 							rd_req_rdma_ready,\n"
		append entity "	   input  req_t 							rd_req_rdma_req,\n"
		append entity "	   input  logic 							wr_req_rdma_valid,\n"
		append entity "	   output logic 							wr_req_rdma_ready,\n"
		append entity "	   input  req_t 							wr_req_rdma_req,\n"
		append entity "\n"
		append entity "    // RDMA DATA\n"
		append entity "    output logic                            axis_rdma_src_tlast,\n"
		append entity "    input  logic                            axis_rdma_src_tready,\n"
		append entity "    output logic                            axis_rdma_src_tvalid,\n"
		append entity "    output logic\[AXI_DATA_BITS-1:0]		   axis_rdma_src_tdata,\n"
		append entity "    output logic\[AXI_DATA_BITS/8-1:0]	   axis_rdma_src_tkeep,\n"
		append entity "    input  logic                            axis_rdma_sink_tlast,\n"
		append entity "    output logic                            axis_rdma_sink_tready,\n"
		append entity "    input  logic                            axis_rdma_sink_tvalid,\n"
		append entity "    input  logic\[AXI_DATA_BITS-1:0]		   axis_rdma_sink_tdata,\n"
		append entity "    input  logic\[AXI_DATA_BITS/8-1:0]	   axis_rdma_sink_tkeep,\n"
		append entity "\n"
	}
    if {$cnfg(en_strm) eq 1} {
	    append entity "    // AXI4S HOST src\n"
        append entity "    output logic\[AXI_DATA_BITS-1:0]        axis_host_src_tdata,\n"
        append entity "    output logic\[AXI_DATA_BITS/8-1:0]      axis_host_src_tkeep,\n"
        append entity "    output logic                            axis_host_src_tlast,\n"
		append entity "    output logic\[3:0]                      axis_host_src_tdest,\n"
        append entity "    input  logic                            axis_host_src_tready,\n"
        append entity "    output logic                            axis_host_src_tvalid,\n"
        append entity "\n"
        append entity "    // AXI4S HOST sink\n"
        append entity "    input  logic\[AXI_DATA_BITS-1:0]        axis_host_sink_tdata,\n"
		append entity "    input  logic\[AXI_DATA_BITS/8-1:0]      axis_host_sink_tkeep,\n"
        append entity "    input  logic                            axis_host_sink_tlast,\n"
		append entity "    input  logic\[3:0]                      axis_host_sink_tdest,\n"
        append entity "    output logic                            axis_host_sink_tready,\n"
        append entity "    input  logic                            axis_host_sink_tvalid,\n"
        append entity "\n"
    }
    if {$cnfg(en_ddr) eq 1} {
        append entity "    // AXI4S CARD src\n"
		append entity "    output logic\[N_DDR_CHAN*AXI_DATA_BITS-1:0]        axis_card_src_tdata,\n"
		append entity "    output logic\[N_DDR_CHAN*AXI_DATA_BITS/8-1:0]      axis_card_src_tkeep,\n"
        append entity "    output logic                            axis_card_src_tlast,\n"
		append entity "    output logic\[3:0]                      axis_card_src_tdest,\n"
        append entity "    input  logic                            axis_card_src_tready,\n"
        append entity "    output logic                            axis_card_src_tvalid,\n"
        append entity "\n"
        append entity "    // AXI4S CARD sink\n"
		append entity "    input  logic\[N_DDR_CHAN*AXI_DATA_BITS-1:0]        axis_card_sink_tdata,\n"
		append entity "    input  logic\[N_DDR_CHAN*AXI_DATA_BITS/8-1:0]      axis_card_sink_tkeep,\n"
        append entity "    input  logic                            axis_card_sink_tlast,\n"
		append entity "    input  logic\[3:0]                      axis_card_sink_tdest,\n"
        append entity "    output logic                            axis_card_sink_tready,\n"
        append entity "    input  logic                            axis_card_sink_tvalid,\n"
        append entity "\n"
    }
    append entity "    // Clock and reset\n"
	append entity "    input  logic                            aclk,\n"
	append entity "    input  logic\[0:0]                       aresetn\n"
	append entity ");\n"
	append entity "\n"
	append entity "// Control\n"
	append entity "AXI4L axi_ctrl_user();\n"
	append entity "\n"
	append entity "assign axi_ctrl_user.araddr                   = axi_ctrl_araddr;\n"
	append entity "assign axi_ctrl_user.arprot                   = axi_ctrl_arprot;\n"
	append entity "assign axi_ctrl_user.arvalid                  = axi_ctrl_arvalid;\n"
	append entity "assign axi_ctrl_user.awaddr                   = axi_ctrl_awaddr;\n"
	append entity "assign axi_ctrl_user.awprot                   = axi_ctrl_awprot;\n"
	append entity "assign axi_ctrl_user.awvalid                  = axi_ctrl_awvalid;\n"
	append entity "assign axi_ctrl_user.bready                   = axi_ctrl_bready;\n"
	append entity "assign axi_ctrl_user.rready                   = axi_ctrl_rready;\n"
	append entity "assign axi_ctrl_user.wdata                    = axi_ctrl_wdata;\n"
	append entity "assign axi_ctrl_user.wstrb                    = axi_ctrl_wstrb;\n"
	append entity "assign axi_ctrl_user.wvalid                   = axi_ctrl_wvalid;\n"
	append entity "\n"
	append entity "assign axi_ctrl_arready                     = axi_ctrl_user.arready;\n"
	append entity "assign axi_ctrl_awready                     = axi_ctrl_user.awready;\n"
	append entity "assign axi_ctrl_bresp                       = axi_ctrl_user.bresp;\n"
	append entity "assign axi_ctrl_bvalid                      = axi_ctrl_user.bvalid;\n"
	append entity "assign axi_ctrl_rdata                       = axi_ctrl_user.rdata;\n"
	append entity "assign axi_ctrl_rresp                       = axi_ctrl_user.rresp;\n"
	append entity "assign axi_ctrl_rvalid                      = axi_ctrl_user.rvalid;\n"
	append entity "assign axi_ctrl_wready                      = axi_ctrl_user.wready;\n"
	append entity "\n"
	if {$cnfg(en_bpss) eq 1} {
		append entity "// Descriptor bypass\n"
		append entity "reqIntf rd_req_user();\n"
		append entity "reqIntf wr_req_user();\n"
		append entity "\n"
		append entity "assign rd_req_user_valid = rd_req_user.valid;\n"
		append entity "assign rd_req_user.ready = rd_req_user_ready;\n"
		append entity "assign rd_req_user_req = rd_req_user.req;\n"
		append entity "assign wr_req_user_valid = wr_req_user.valid;\n"
		append entity "assign wr_req_user.ready = wr_req_user_ready;\n"
		append entity "assign wr_req_user_req = wr_req_user.req;\n"
		append entity "\n"
	}
	if {$cnfg(en_fv) eq 1} {
		if {$cnfg(en_fvv) eq 1} {
			append entity "// RDMA Farview\n"
			append entity "metaIntf #(.DATA_BITS(FV_REQ_BITS)) fv_req();\n"
			append entity "metaIntf #(.DATA_BITS(FV_REQ_BITS)) fv_cmd();\n"
			append entity "\n"
			append entity "assign fv_req.valid = fv_req_valid;\n"
			append entity "assign fv_req_ready = fv_req.ready;\n"
			append entity "assign fv_req.data = fv_req_data;\n"
			append entity "assign fv_cmd_valid = fv_cmd.valid;\n"
			append entity "assign fv_cmd.ready = fv_cmd_ready;\n"
			append entity "assign fv_cmd_data = fv_cmd.data;\n"
			append entity "\n"
		}
		append entity "// RDMA commands\n"
		append entity "reqIntf rd_req_rdma();\n"
		append entity "reqIntf wr_req_rdma();\n"
		append entity "\n"
		append entity "assign rd_req_rdma.valid = rd_req_rdma_valid;\n"
		append entity "assign rd_req_rdma_ready = rd_req_rdma.ready;\n"
		append entity "assign rd_req_rdma.req = rd_req_rdma_req;\n"
		append entity "assign wr_req_rdma.valid = wr_req_rdma_valid;\n"
		append entity "assign wr_req_rdma_ready = wr_req_rdma.ready;\n"
		append entity "assign wr_req_rdma.req = wr_req_rdma_req;\n"
		append entity "\n"
		append entity "// AXIS RDMA source\n"
		append entity "AXI4S axis_rdma_src();\n"
		append entity "\n"
		append entity "assign axis_rdma_src_tdata             = axis_rdma_src.tdata;\n"
		append entity "assign axis_rdma_src_tkeep             = axis_rdma_src.tkeep;\n"
		append entity "assign axis_rdma_src_tlast             = axis_rdma_src.tlast;\n"
		append entity "assign axis_rdma_src_tvalid            = axis_rdma_src.tvalid;\n"
		append entity "\n"
		append entity "assign axis_rdma_src.tready            = axis_rdma_src_tready;\n"
		append entity "\n"
		append entity "// AXIS RDMA sink\n"
		append entity "AXI4S axis_rdma_sink();\n"
		append entity "\n"
		append entity "assign axis_rdma_sink.tdata             = axis_rdma_sink_tdata;\n"
		append entity "assign axis_rdma_sink.tkeep             = axis_rdma_sink_tkeep;\n"
		append entity "assign axis_rdma_sink.tlast             = axis_rdma_sink_tlast;\n"
		append entity "assign axis_rdma_sink.tvalid            = axis_rdma_sink_tvalid;\n"
		append entity "\n"
		append entity "assign axis_rdma_sink_tready            = axis_rdma_sink.tready;\n"
		append entity "\n"
	}
    if {$cnfg(en_strm) eq 1} {
        append entity "// AXIS host source\n"
        append entity "AXI4SR axis_host_src();\n"
        append entity "\n"
        append entity "assign axis_host_src_tdata                  = axis_host_src.tdata;\n"
        append entity "assign axis_host_src_tkeep                  = axis_host_src.tkeep;\n"
        append entity "assign axis_host_src_tlast                  = axis_host_src.tlast;\n"
		append entity "assign axis_host_src_tdest                  = axis_host_src.tdest;\n"
        append entity "assign axis_host_src_tvalid                 = axis_host_src.tvalid;\n"
        append entity "\n"
        append entity "assign axis_host_src.tready                 = axis_host_src_tready;\n"
        append entity "\n"
        append entity "// AXIS host sink\n"
        append entity "AXI4SR axis_host_sink();\n"
        append entity "\n"
        append entity "assign axis_host_sink.tdata                 = axis_host_sink_tdata;\n"
        append entity "assign axis_host_sink.tkeep                 = axis_host_sink_tkeep;\n"
        append entity "assign axis_host_sink.tlast                 = axis_host_sink_tlast;\n"
		append entity "assign axis_host_sink.tdest                 = axis_host_sink_tdest;\n"
        append entity "assign axis_host_sink.tvalid                = axis_host_sink_tvalid;\n"
        append entity "\n"
        append entity "assign axis_host_sink_tready                = axis_host_sink.tready;\n"
        append entity "\n"
    }
    if {$cnfg(en_ddr) eq 1} {
        append entity "// AXIS card source\n"
        append entity "AXI4SR #(.AXI4S_DATA_BITS(N_DDR_CHAN*AXI_DATA_BITS)) axis_card_src();\n"
        append entity "\n"
        append entity "assign axis_card_src_tdata                  = axis_card_src.tdata;\n"
        append entity "assign axis_card_src_tkeep                  = axis_card_src.tkeep;\n"
        append entity "assign axis_card_src_tlast                  = axis_card_src.tlast;\n"
		append entity "assign axis_card_src_tdest                  = axis_card_src.tdest;\n"
        append entity "assign axis_card_src_tvalid                 = axis_card_src.tvalid;\n"
        append entity "\n"
        append entity "assign axis_card_src.tready                 = axis_card_src_tready;\n"
        append entity "\n"
        append entity "// AXIS card sink\n"
        append entity "AXI4SR #(.AXI4S_DATA_BITS(N_DDR_CHAN*AXI_DATA_BITS)) axis_card_sink();\n"
        append entity "\n"
	    append entity "assign axis_card_sink.tdata                 = axis_card_sink_tdata;\n"
        append entity "assign axis_card_sink.tkeep                 = axis_card_sink_tkeep;\n"
        append entity "assign axis_card_sink.tlast                 = axis_card_sink_tlast;\n"
		append entity "assign axis_card_sink.tdest                 = axis_card_sink_tdest;\n"
        append entity "assign axis_card_sink.tvalid                = axis_card_sink_tvalid;\n"
        append entity "\n"
        append entity "assign axis_card_sink_tready                = axis_card_sink.tready;\n"
        append entity "\n"
    }
	append entity "// USER LOGIC\n"
	append entity "design_user_logic_$c_reg inst_user_$c_reg (\n"
	append entity "  .axi_ctrl(axi_ctrl_user),\n"
	if {$cnfg(en_bpss) eq 1} {
		append entity "  .rd_req_user(rd_req_user),\n"
		append entity "  .wr_req_user(wr_req_user),\n"
	}
	if {$cnfg(en_fv) eq 1} {
		if {$cnfg(en_fvv) eq 1} {
			append entity "  .fv_src(fv_cmd),\n"
			append entity "  .fv_sink(fv_req),\n"
		}
		append entity "  .rd_req_rdma(rd_req_rdma),\n"
		append entity "  .wr_req_rdma(wr_req_rdma),\n"
		append entity "  .axis_rdma_src(axis_rdma_src),\n"
		append entity "  .axis_rdma_sink(axis_rdma_sink),\n"
	}
    if {$cnfg(en_strm) eq 1} {
        append entity "  .axis_host_src(axis_host_src),\n"
        append entity "  .axis_host_sink(axis_host_sink),\n"
    }
    if {$cnfg(en_ddr) eq 1} {
        append entity "  .axis_card_src(axis_card_src),\n"
        append entity "  .axis_card_sink(axis_card_sink),\n"
    }
    append entity "  .aclk(aclk),\n"
	append entity "  .aresetn(aresetn)\n"
	append entity ");\n"
	append entity "\n"
	append entity "\n"
	append entity "endmodule\n"
	append entity "\n"
	lappend template $entity
	set vho_file [open $f_out w]
	foreach line $template {
	    puts $vho_file $line
	}
	close $vho_file
}

#########################################################################################
# User logic shell
#########################################################################################
proc wr_hdl_user {f_out c_reg} {	
	upvar #0 cfg cnfg

	set template {}
	set entity {}
	append entity "`timescale 1ns / 1ps\n"
	append entity "\n"
	append entity "`include \"axi_macros.svh\"\n"
	append entity "`include \"lynx_macros.svh\"\n"
	append entity "\n"
	append entity "import lynxTypes::*;\n"
	append entity "\n"
	append entity "/**\n"
	append entity " * User logic\n"
	append entity " * \n"
	append entity " */\n"
	append entity "module design_user_logic_$c_reg (\n"
	append entity "    // AXI4L CONTROL\n"
	append entity "    // Slave control. Utilize this interface for any kind of CSR implementation.\n"
	append entity "    AXI4L.s                     axi_ctrl,\n"
	append entity "\n"
	if {$cnfg(en_bpss) eq 1} {
		append entity "    // DESCRIPTOR BYPASS\n"
		append entity "    // vaddr[48] - virt. address, len[28] - length, ctl[1] - final, stream[1], sync[1] - explicit move\n"
		append entity "    // Explicit transfer requests from user logic.\n"
		append entity "    reqIntf.m			        rd_req_user,\n"
		append entity "    reqIntf.m			        wr_req_user,\n"
		append entity "\n"
	}
	if {$cnfg(en_fv) eq 1} {
		append entity "    // RDMA\n"
		append entity "    // vaddr[48] - virtual address, len[28] - length, ctl[1] - final transfer, sync[1] - host synchronization\n"
		append entity "    // Read and write descriptors arriving from the network stack.\n"
		append entity "    reqIntf.s			        rd_req_rdma,\n"
		append entity "    reqIntf.s 			        wr_req_rdma,\n"
		append entity "\n"
		if {$cnfg(en_fvv) eq 1} {
			append entity "    // FARVIEW\n"
			append entity "    // Remote one-sided RPC calls and response commands \[256]-req, \[256]-cmd. bits.\n"
			append entity "    metaIntf.m 			        fv_src,\n"
			append entity "    metaIntf.s			        fv_sink,\n"
			append entity "\n"
		}
		append entity "    // AXI4S RDMA DATA\n"
		append entity "    // Network data.\n"
		append entity "    AXI4S.m                     axis_rdma_src,\n"
		append entity "    AXI4S.s                     axis_rdma_sink,\n"
		append entity "\n"
	}
    if {$cnfg(en_strm) eq 1} {
        append entity "    // AXI4S host\n"
        append entity "    // Host streams.\n"
        append entity "    AXI4SR.m                    axis_host_src,\n"
        append entity "    AXI4SR.s                    axis_host_sink,\n"
    }
	if {$cnfg(en_ddr) eq 1} {
        append entity "    // AXI4S host\n"
        append entity "    // Card streams.\n"
        append entity "    AXI4SR.m                    axis_card_src,\n"
        append entity "    AXI4SR.s                    axis_card_sink,\n"
    }
    append entity "\n"
    append entity "    // Clock and reset\n"
	append entity "    input  wire                 aclk,\n"
	append entity "    input  wire\[0:0]            aresetn\n"
	append entity ");\n"
	append entity "\n"
	append entity "/* -- Tie-off unused interfaces and signals ----------------------------- */\n"
	append entity "always_comb axi_ctrl.tie_off_s();\n"
	if {$cnfg(en_bpss) eq 1} {
		append entity "always_comb rd_req_user.tie_off_m();\n"
		append entity "always_comb wr_req_user.tie_off_m();\n"
	}
	if {$cnfg(en_fv) eq 1} {	
		append entity "always_comb rd_req_rdma.tie_off_s();\n"
		append entity "always_comb wr_req_rdma.tie_off_s();\n"
		if {$cnfg(en_fvv) eq 1} {
			append entity "always_comb fv_src.tie_off_m();\n"
			append entity "always_comb fv_sink.tie_off_s();\n"
		}
		append entity "always_comb axis_rdma_src.tie_off_m();\n"
		append entity "always_comb axis_rdma_sink.tie_off_s();\n"
	}
    if {$cnfg(en_strm) eq 1} {
        append entity "always_comb axis_host_src.tie_off_m();\n"
        append entity "always_comb axis_host_sink.tie_off_s();\n"
    }
    if {$cnfg(en_ddr) eq 1} {
        append entity "always_comb axis_card_src.tie_off_m();\n"
        append entity "always_comb axis_card_sink.tie_off_s();\n"
    }
	append entity "\n"
	append entity "/* -- USER LOGIC -------------------------------------------------------- */\n"
	append entity "\n"
	append entity "\n"
	append entity "\n"
	append entity "endmodule\n"
	lappend template $entity
	set vho_file [open $f_out w]
	foreach line $template {
	    puts $vho_file $line
	}
	close $vho_file
}