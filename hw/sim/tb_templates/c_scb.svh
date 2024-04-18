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

  // Stream type
  integer strm_type;
  
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
  // This is the function to edit if any custom stimulus is provided. 
  // By default it will not perform any checks and will only consume drv and mon interfaces.
  // --------------------------------------------------------------------------
  //

  task run;
    c_trs trs_mon;
    c_trs trs_drv;
    fail = 0;
    
    for(int i = 0; i < params.n_trs; i++) begin
      drv2scb.get(trs_drv);
      mon2scb.get(trs_mon);
    end
    -> done;
  endtask
  
endclass