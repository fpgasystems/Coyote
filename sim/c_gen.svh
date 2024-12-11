import lynxTypes::*;
import simTypes::*;

// AXIS Generator
class c_gen;
  
  // Send to driver (mailbox)
  mailbox gen2drv;

  // Params
  c_struct_t params;

  // Completion
  event done;

  
  //
  // C-tor
  //
  function new(mailbox gen2drv, input c_struct_t params);
    this.gen2drv = gen2drv;
    this.params = params;
  endfunction
  
  //
  // Run
  // --------------------------------------------------------------------------
  // This is the function to edit if any custom stimulus is needed. 
  // By default it will generate random stimulus n_trs times.
  // --------------------------------------------------------------------------
  //
  
  task run();
    c_trs trs = new();
	
	
    -> done;
  endtask

endclass


// AXI4L ctrl generator
class c_gen_ctrl;
  
  // Send to driver (mailbox)
  mailbox gen2ctrl;

  // Params
  c_struct_t params;

  // Completion
  event done;
  
  //
  // C-tor
  //
  function new(mailbox gen2ctrl, input c_struct_t params);
    this.gen2ctrl = gen2ctrl;
    this.params = params;
  endfunction
  
  //
  // Run
  // --------------------------------------------------------------------------
  // This is the function to edit if any custom stimulus is needed. 
  // By default it will generate random stimulus n_trs times.
  // --------------------------------------------------------------------------
  //
  
  task run();
	c_trs_ctrl trs_ctrl_r =	new();
	c_trs_ctrl trs_ctrl_w_0 = new();
	c_trs_ctrl trs_ctrl_w_1 = new();
	c_trs_ctrl trs_ctrl_w_2 = new();
	c_trs_ctrl trs_ctrl_w_3 = new();

	// delay for a bit
	delay(4);
	
	// write src address to 0x010000
	trs_ctrl_w_0.addr = 64'h8;
	trs_ctrl_w_0.data = 64'h10000;
	trs_ctrl_w_0.read = 0;
	trs_ctrl_w_0.done_signal = 0;
	gen2ctrl.put(trs_ctrl_w_0);
	
	
	// write dst address to 0x020000
	trs_ctrl_w_1.addr = 64'h10;
	trs_ctrl_w_1.data = 64'h20000;
	trs_ctrl_w_1.read = 0;
	trs_ctrl_w_1.done_signal = 0;
	gen2ctrl.put(trs_ctrl_w_1);
	
	
	// write transfer length to 1024
	trs_ctrl_w_2.addr = 64'h18;
	trs_ctrl_w_2.data = 64'd1024;
	trs_ctrl_w_2.read = 0;
	trs_ctrl_w_2.done_signal = 0;
	gen2ctrl.put(trs_ctrl_w_2);
	
	
	// start the transfer
	trs_ctrl_w_3.addr = 64'h0;
	trs_ctrl_w_3.data = 64'hffffffffffffffff;
	trs_ctrl_w_3.read = 0;
	trs_ctrl_w_3.done_signal = 0;
	gen2ctrl.put(trs_ctrl_w_3);
	
	// read the src address
	trs_ctrl_r.addr = 64'h8;
	trs_ctrl_r.data = 64'd0;
	trs_ctrl_r.read = 1;
	trs_ctrl_r.done_signal = 0;
	gen2ctrl.put(trs_ctrl_r);
	
    -> done;
  endtask

endclass
