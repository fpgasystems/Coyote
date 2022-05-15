import lynxTypes::*;

// AXIS Scoreboard
class c_scb;
   
  // Mailbox handle
  mailbox mon2scb;
  mailbox drv2scb;
  
  integer fail;

  // Number of transactions
  int n_trs;
  
  //
  // C-tor
  //
  function new(mailbox mon2scb, mailbox drv2scb);
    this.mon2scb = mon2scb;
    this.drv2scb = drv2scb;
  endfunction
  
  //
  // Run
  //
  task run;
    c_trs trs_mon;
    c_trs trs_drv;
    logic[31:0] sum;
    fail = 0;
    forever begin
      mon2scb.get(trs_mon);
      drv2scb.get(trs_drv);
      sum = 0;
      for(int i = 0; i < 16; i++) begin
        sum = sum + trs_drv.tdata[i*32+:32];
      end
      if(trs_mon.tdata[31:0] != sum) begin
        $display("ERR:  Incorrect result! Exp: %0d, Act: %0d", sum, trs_mon.tdata[31:0]);
        fail = 1;
      end
      else begin 
        $display("Results are correct.");
      end
      n_trs++;
    end
  endtask
  
endclass