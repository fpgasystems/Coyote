`ifndef AXI_INTF_SV_
`define AXI_INTF_SV_

import lynxTypes::*;

// ----------------------------------------------------------------------------
// AXI4
// ----------------------------------------------------------------------------
interface AXI4 #(
	parameter AXI4_ADDR_BITS = AXI_ADDR_BITS,
	parameter AXI4_DATA_BITS = AXI_DATA_BITS
) (
	input  logic aclk
);

localparam AXI4_STRB_BITS = AXI4_DATA_BITS / 8;

typedef logic [AXI4_ADDR_BITS-1:0] addr_t;
typedef logic [AXI4_DATA_BITS-1:0] data_t;
typedef logic [AXI4_STRB_BITS-1:0] strb_t;

// AR channel
addr_t 			araddr;
logic[1:0]		arburst;
logic[3:0]		arcache;
logic[0:0]      arid;
logic[7:0]		arlen;
logic[0:0]		arlock;
logic[2:0]		arprot;
logic[3:0]		arqos;
logic[3:0]		arregion;
logic[2:0]		arsize;
logic			arready;
logic			arvalid;

// AW channel
addr_t 			awaddr;
logic[1:0]		awburst;
logic[3:0]		awcache;
logic[0:0]      awid;
logic[7:0]		awlen;
logic[0:0]		awlock;
logic[2:0]		awprot;
logic[3:0]		awqos;
logic[3:0]		awregion;
logic[2:0]		awsize;
logic			awready;
logic			awvalid;
 
// R channel
data_t 			rdata;
logic[0:0]      rid;
logic			rlast;
logic[1:0]		rresp;
logic 			rready;
logic			rvalid;

// W channel
data_t 			wdata;
logic			wlast;
strb_t 			wstrb;
logic			wready;
logic			wvalid;

// B channel
logic[0:0]      bid;
logic[1:0]		bresp;
logic			bready;
logic			bvalid;

// Tie off unused master signals
task tie_off_m ();
	araddr    = 0;
    arburst   = 2'b01;
    arcache   = 4'b0;
    arid      = 0;
    arlen     = 8'b0;	
    arlock    = 1'b0;	
    arprot    = 3'b0;	
    arqos     = 4'b0;	
    arregion  = 4'b0;	
    arsize    = 3'b0;	
    arvalid   = 1'b0;	
    awaddr    = 0;	
    awburst   = 2'b01;
    awcache   = 4'b0;	
    awid      = 0;
    awlen     = 8'b0;	
    awlock    = 1'b0;	
    awprot    = 3'b0;	
    awqos     = 4'b0;	
    awregion  = 4'b0;	
    awsize    = 3'b0;	
    awvalid   = 1'b0;
    bready    = 1'b0;    
    rready    = 1'b0;	
    wdata     = 0;	
    wlast     = 1'b0;
    wstrb     = 0;	
    wvalid    = 1'b0;	
endtask

// Tie off unused slave signals
task tie_off_s ();
	arready  = 1'b0;     
    awready  = 1'b0;
    bresp    = 2'b0;
    bvalid   = 1'b0;
    bid      = 0;	
    rdata    = 0;
    rid      = 0;
    rlast    = 1'b0;
    rresp    = 2'b0;
    rvalid   = 1'b0;
    wready   = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	// AR
	input awready,
	output awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awregion, awsize, awvalid, awid,
	// AW
	input arready,
	output araddr, arburst, arcache, arlen, arlock, arprot, arqos, arregion, arsize, arvalid, arid,
	// R
	input rlast, rresp, rdata, rvalid, rid,
	output rready,
	// W
	input wready,
	output wdata, wlast, wstrb, wvalid,
	// B
	input bresp, bvalid, bid,
	output bready
);

// Slave
modport s (
	import tie_off_s,
	// AR
	input awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awregion, awsize, awvalid, awid,
	output awready,
	// AW
	input araddr, arburst, arcache, arlen, arlock, arprot, arqos, arregion, arsize, arvalid, arid,
	output arready,
	// R
	input rready,
	output rlast, rresp, rdata, rvalid, rid,
	// W
	input wdata, wlast, wstrb, wvalid,
	output wready,
	// B
	input bready,
	output bresp, bvalid, bid
);

endinterface

// ----------------------------------------------------------------------------
// AXI4 lite
// ----------------------------------------------------------------------------
interface AXI4L #(
	parameter AXI4L_ADDR_BITS = AXI_ADDR_BITS,
	parameter AXI4L_DATA_BITS = AXIL_DATA_BITS
) (
	input  logic aclk
);

localparam AXI4L_STRB_BITS = AXI4L_DATA_BITS / 8;

typedef logic [AXI4L_ADDR_BITS-1:0] addr_t;
typedef logic [AXI4L_DATA_BITS-1:0] data_t;
typedef logic [AXI4L_STRB_BITS-1:0] strb_t;

// AR channel
addr_t 			araddr;
logic[2:0]		arprot;
logic[3:0]		arqos;
logic[3:0]		arregion;
logic			arready;
logic			arvalid;

// AW channel
addr_t 			awaddr;
logic[2:0]		awprot;
logic[3:0]		awqos;
logic[3:0]		awregion;
logic			awready;
logic			awvalid;
 
// R channel
data_t 			rdata;
logic[1:0]		rresp;
logic 			rready;
logic			rvalid;

// W channel
data_t 			wdata;
strb_t 			wstrb;
logic			wready;
logic			wvalid;

// B channel
logic[1:0]		bresp;
logic			bready;
logic			bvalid;

// Tie off unused master signals
task tie_off_m ();
	araddr    = 0;
    arprot    = 3'b0;	
    arqos     = 4'b0;	
    arregion  = 4'b0;	
    arvalid   = 1'b0;	
    awaddr    = 0;	
    awprot    = 3'b0;	
    awqos     = 4'b0;	
    awregion  = 4'b0;		
    awvalid   = 1'b0;	
    bready    = 1'b0;	
    rready    = 1'b0;	
    wdata     = 0;	
    wstrb     = 0;	
    wvalid    = 1'b0;	
endtask

// Tie off unused slave signals
task tie_off_s ();
	arready  = 1'b0;     
    awready  = 1'b0;
    bresp    = 2'b0;
    bvalid   = 1'b0;
    rdata    = 0;
    rresp    = 2'b0;
    rvalid   = 1'b0;
    wready   = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	// AR
	input awready,
	output awaddr, awprot, awqos, awregion, awvalid,
	// AW
	input arready,
	output araddr, arprot, arqos, arregion, arvalid,
	// R
	input rresp, rdata, rvalid,
	output rready,
	// W
	input wready,
	output wdata, wstrb, wvalid,
	// B
	input bresp, bvalid,
	output bready
);

// Slave
modport s (
	import tie_off_s,
	// AR
	input awaddr, awprot, awqos, awregion, awvalid,
	output awready,
	// AW
	input araddr, arprot, arqos, arregion, arvalid,
	output arready,
	// R
	input rready,
	output rresp, rdata, rvalid,
	// W
	input wdata, wstrb, wvalid,
	output wready,
	// B
	input bready,
	output bresp, bvalid
);

endinterface

// ----------------------------------------------------------------------------
// AXI4 stream 
// ----------------------------------------------------------------------------
interface AXI4S #(
	parameter AXI4S_DATA_BITS = AXI_DATA_BITS
) (
    input  logic aclk
);

localparam AXI4S_KEEP_BITS = AXI4S_DATA_BITS / 8;

typedef logic [AXI4S_DATA_BITS-1:0] data_t;
typedef logic [AXI4S_KEEP_BITS-1:0] keep_t;

data_t          tdata;
keep_t  		tkeep;
logic           tlast;
logic           tready;
logic           tvalid;

// Tie off unused master signals
task tie_off_m ();
    tdata      = 0;
    tkeep      = 0;
    tlast     = 1'b0;
    tvalid     = 1'b0;
endtask

// Tie off unused slave signals
task tie_off_s ();
    tready     = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	input tready,
	output tdata, tkeep, tlast, tvalid
);

// Slave
modport s (
    import tie_off_s,
    input tdata, tkeep, tlast, tvalid,
    output tready
);

endinterface


// ----------------------------------------------------------------------------
// AXI4 stream routed
// ----------------------------------------------------------------------------
interface AXI4SR #(
	parameter AXI4S_DATA_BITS = AXI_DATA_BITS
) (
    input  logic aclk
);

localparam AXI4S_KEEP_BITS = AXI4S_DATA_BITS / 8;

typedef logic [AXI4S_DATA_BITS-1:0] data_t;
typedef logic [AXI4S_KEEP_BITS-1:0] keep_t;
typedef logic [3:0] dest_t;	
 
data_t          tdata;
keep_t  		tkeep;
dest_t 			tdest;
logic           tlast;
logic           tready;
logic           tvalid;

// Tie off unused master signals
task tie_off_m ();
    tdata      = 0;
    tkeep      = 0;
    tlast      = 1'b0;
	tdest 	   = 0;
    tvalid     = 1'b0;
endtask

// Tie off unused slave signals
task tie_off_s ();
    tready     = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	input tready,
	output tdata, tkeep, tlast, tvalid, tdest
);

// Slave
modport s (
    import tie_off_s,
    input tdata, tkeep, tlast, tvalid, tdest,
    output tready
);

endinterface

`endif