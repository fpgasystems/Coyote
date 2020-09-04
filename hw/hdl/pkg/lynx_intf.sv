`ifndef LYNX_INTF_SV_
`define LYNX_INTF_SV_

import lynxTypes::*;

// ----------------------------------------------------------------------------
// Config
// ----------------------------------------------------------------------------
interface tlbIntf #(
	parameter N_ASSOC = 4
);

typedef logic [VADDR_BITS-1:0] addr_t;
typedef logic [N_ASSOC-1:0][TLB_DATA_BITS-1:0] data_t;

addr_t 			addr;
data_t 			data;

// Slave
modport s (
	input addr,
	output data
);

// Master
modport m (
	output addr,
	input data
);

endinterface

// ----------------------------------------------------------------------------
// Config interface
// ----------------------------------------------------------------------------
interface cnfgIntf ();	

logic 			done_host;
logic 			done_card;
logic 			done_sync;
logic 			restart;
pf_t 			pf;

// Slave
modport s (
	output done_host,
	output done_card,
	output done_sync,
	input  restart,
	output pf
);

// Master
modport m (
	input  done_host,
	input  done_card,
	input  done_sync,
	output restart,
	input  pf
);

endinterface

// ----------------------------------------------------------------------------
// DMA interface
// ----------------------------------------------------------------------------
interface dmaIntf (
	input  logic aclk
);

dma_req_t   	req;
logic 			valid;
logic 			ready;

logic 			done;

// Tie off unused slave signals
task tie_off_s ();
	ready = 1'b0;
	done = 1'b0;
endtask

// Tie off unused master signals
task tie_off_m ();
	req = 0;
	valid = 1'b0;
endtask

// Slave
modport s (
	import tie_off_s,
	input  req,
	input  valid,
	output ready,
	output done
);

// Master
modport m (
	import tie_off_m,
	output req,
	output valid,
	input  ready,
	input  done
);

endinterface

// ----------------------------------------------------------------------------
// DMA ISR interface
// ----------------------------------------------------------------------------
interface dmaIsrIntf ();

dma_isr_req_t 	req;
logic 			valid;
logic 			ready;

logic 			done;
logic 			isr_return;

// Tie off unused slave signals
task tie_off_s ();
	ready = 1'b0;
	done = 1'b0;
	isr_return = 1'b0;
endtask

// Tie off unused master signals
task tie_off_m ();
	req = 0;
	valid = 1'b0;
endtask

// Slave
modport s (
    import tie_off_s,
	input  req,
	input  valid,
	output ready,
	output done,
	output isr_return
);

// Master
modport m (
    import tie_off_m,
	output req,
	output valid,
	input  ready,
	input  done,
	input  isr_return
);

endinterface

// ----------------------------------------------------------------------------
// Request interface 
// ----------------------------------------------------------------------------
interface reqIntf(
	input  logic aclk
);

req_t 						req;
logic 						valid;
logic 						ready;

// Tie off unused 
task tie_off_s ();
	ready = 1'b0;
endtask

task tie_off_m ();
	req = 0;
	valid = 1'b0;
endtask

// Slave 
modport s (
    import tie_off_s,
	input  req,
	input  valid,
	output ready
);

// Master
modport m (
    import tie_off_m,
	output req,
	output valid,
	input  ready
);

endinterface

// ---------------------------------------------------------------------------- 
// Farview Request interface 
// ---------------------------------------------------------------------------- 
interface rdmaIntf(
	input  logic aclk
);

rdma_req_t 					req;
logic 						valid;
logic 						ready;

// Tie off unused 
task tie_off_s ();
	ready = 1'b0;
endtask

task tie_off_m ();
	req = 0;
	valid = 1'b0;
endtask

// Slave 
modport s (
	import tie_off_s,
	input  req,
	input  valid,
	output ready
);

// Master
modport m (
	import tie_off_m,
	output req,
	output valid,
	input  ready
);

endinterface

// ----------------------------------------------------------------------------
// Meta interface 
// ----------------------------------------------------------------------------
interface metaIntf #(
	parameter DATA_BITS = 96
) (
	input  logic aclk
);

logic valid;
logic ready;
logic [DATA_BITS-1:0] data;

// Tie off unused 
task tie_off_s ();
	ready = 1'b0;
endtask

task tie_off_m ();
	data = 0;
	valid = 1'b0;
endtask

// Slave
modport s (
	import tie_off_s,
	input  valid,
	output ready,
	input  data
);

// Master
modport m (
	import tie_off_m,
	output valid,
	input  ready,
	output data
);

endinterface

// ---------------------------------------------------------------------------- 
// Mux user interface 
// ---------------------------------------------------------------------------- 
interface muxUserIntf #(
	parameter integer N_ID_BITS = N_REGIONS_BITS,
	parameter integer ARB_DATA_BITS = AXI_DATA_BITS
);

localparam integer BEAT_LOG_BITS = $clog2(ARB_DATA_BITS/8);

logic [N_ID_BITS-1:0]			    id;
logic [LEN_BITS-BEAT_LOG_BITS-1:0]	len;

logic 							   ready;
logic 							   valid;

// Tie off unused 
task tie_off_s ();
	id = 0;
	len = 0;
	ready = 1'b0;
endtask

task tie_off_m ();
	valid = 1'b0;
endtask

// Slave
modport s (
    import tie_off_s,
	output id,
	output len,
	output ready,
	input  valid
);

// Master
modport m (
    import tie_off_m,
	input  id,
	input  len,
	input  ready,
	output valid
);

endinterface

// ---------------------------------------------------------------------------- 
// XDMA bypass
// ---------------------------------------------------------------------------- 
interface xdmaIntf ();

logic [63:0] h2c_addr;
logic [27:0] h2c_len;
logic [15:0] h2c_ctl;
logic h2c_valid;
logic h2c_ready;

logic [63:0] c2h_addr;
logic [27:0] c2h_len;
logic [15:0] c2h_ctl;
logic c2h_valid;
logic c2h_ready;

logic [7:0] h2c_status;
logic [7:0] c2h_status;

// Slave
modport s (
	input h2c_addr,
	input h2c_len,
	input h2c_ctl,
	input h2c_valid,
	output h2c_ready,
	input c2h_addr,
	input c2h_len,
	input c2h_ctl,
	input c2h_valid,
	output c2h_ready,
	output h2c_status,
	output c2h_status
);

// Master
modport m (
	output h2c_addr,
	output h2c_len,
	output h2c_ctl,
	output h2c_valid,
	input h2c_ready,
	output c2h_addr,
	output c2h_len,
	output c2h_ctl,
	output c2h_valid,
	input c2h_ready,
	input h2c_status,
	input c2h_status
);


endinterface


`endif
