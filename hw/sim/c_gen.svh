import lynxTypes::*;
import simTypes::*;

// AXIS Generator
class c_gen;
  
  // Send to driver (mailbox)
  mailbox gen2drv;

  // Completion
  event done;

  // Params
  c_struct_t params;

  // AXIS transactions
  rand c_trs trs;
  
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
    for(int i = 0; i < rs_k; i++) begin
        for(int j = 0; j < stripe_size; j++) begin
          trs = new();
          if(!trs.randomize()) $fatal("ERR:  Generator randomization failed");
          trs.tlast = j == stripe_size-1;
          trs.display("Gen");
          gen2drv.put(trs);
        end
    end 
    -> done;
  endtask
  
endclass