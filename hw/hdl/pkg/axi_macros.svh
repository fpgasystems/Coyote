`ifndef AXI_ASSIGN_SVH_
`define AXI_ASSIGN_SVH_

`define AXIS_ASSIGN(s, m)              	\
	assign m.tdata      = s.tdata;     	\
	assign m.tkeep      = s.tkeep;     	\
	assign m.tlast      = s.tlast;     	\
	assign m.tvalid     = s.tvalid;    	\
	assign s.tready     = m.tready;

`define AXISR_ASSIGN(s, m)              \
	assign m.tdata      = s.tdata;     	\
	assign m.tkeep      = s.tkeep;     	\
	assign m.tlast      = s.tlast;     	\
	assign m.tvalid     = s.tvalid;    	\
	assign s.tready     = m.tready;		\
	assign m.tdest		= s.tdest;

`define AXIL_ASSIGN(s, m)              	\
	assign m.araddr 	= s.araddr;		\
	assign m.arprot 	= s.arprot; 	\
	assign m.arvalid 	= s.arvalid;	\
	assign m.awaddr		= s.awaddr;		\
	assign m.awprot		= s.awprot;		\
	assign m.awvalid	= s.awvalid;	\
	assign m.bready 	= s.bready;		\
	assign m.rready 	= s.rready; 	\
	assign m.wdata		= s.wdata;		\
	assign m.wstrb		= s.wstrb;		\
	assign m.wvalid 	= s.wvalid;		\
	assign s.arready 	= m.arready;	\
	assign s.awready	= m.awready; 	\
	assign s.bresp		= m.bresp;		\
	assign s.bvalid 	= m.bvalid;		\
	assign s.rdata		= m.rdata;		\
	assign s.rresp		= m.rresp;		\
	assign s.rvalid		= m.rvalid;		\
	assign s.wready 	= m.wready;
	
`endif