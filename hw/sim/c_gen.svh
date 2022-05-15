import lynxTypes::*;

// AXIS Generator
class c_gen;
  
  // Send to driver (mailbox)
  mailbox gen2drv;

  // Completion
  event done;

  // Transactions generated
  int n_trs;

  // AXIS transactions
  rand c_trs trs;
  
  //
  // C-tor
  //
  function new(mailbox gen2drv, input integer n_trs);
    this.gen2drv = gen2drv;
    this.n_trs = n_trs;
  endfunction
  
  //
  // Run
  //
  task run();
    for(int i = 0; i < n_trs; i++) begin
      trs = new();
      if(!trs.randomize()) $fatal("ERR:  Generator randomization failed");
      trs.tlast = i == n_trs-1;
      trs.display("Gen");
      gen2drv.put(trs);
    end 
    -> done;
  endtask
  
endclass