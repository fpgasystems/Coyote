
// AXIS monitor
class c_mon;
  
  // Interface handle
  virtual AXI4SR axis;

  // Mailbox handle
  mailbox mon2scb;

  // Number of transactions
  int n_trs;

  // 
  // C-tor
  //
  function new(virtual AXI4SR axis, mailbox mon2scb);
    this.axis = axis;
    this.mon2scb = mon2scb;
  endfunction

  // Cycle start
  task cycle_start;
      #TT;
  endtask

  // Cycle wait
  task cycle_wait;
      @(posedge axis.aclk);
  endtask

  // Reset
  task reset_s;
      axis.tready <= 1'b0;
      $display("AXISR reset_s() completed.");
  endtask
  
  //
  // Run
  //
  task run;
    forever begin
        c_trs trs;
        trs = new();
        axis.tready <= #TA 1'b1;
        cycle_start();
        while(axis.tvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axis.tready <= #TA 1'b0;
        trs.tdata = axis.tdata;
        trs.tlast = axis.tlast;
        trs.tid = axis.tid;
        mon2scb.put(trs);
        trs.display("Mon");
        n_trs++;
    end
  endtask
  
endclass