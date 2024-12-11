import lynxTypes::*;
import simTypes::*;

// AXIS Scoreboard
class c_scb;
   
  // Mailbox handle
  mailbox mon2scb;
  mailbox drv2scb;

  // Params
  c_struct_t params;

  // Completion
  event done;
  
  // Fail flag
  integer fail;

  
  //
  // C-tor
  //
  function new(mailbox mon2scb, mailbox drv2scb, input c_struct_t params);
    this.mon2scb = mon2scb;
    this.drv2scb = drv2scb;
    this.params = params;
  endfunction
  
  //
  // Run
  // --------------------------------------------------------------------------
  // This is the function to edit if any custom stimulus is needed. 
  // By default it will generate random stimulus n_trs times.
  // --------------------------------------------------------------------------
  //

  task run;
    c_trs trs_mon;
    c_trs trs_drv;
    fail = 0;
    
    for(int i = 0; i < params.n_trs; i++) begin
      mon2scb.get(trs_mon);
      drv2scb.get(trs_drv);
    end
    -> done;
  endtask
  
endclass