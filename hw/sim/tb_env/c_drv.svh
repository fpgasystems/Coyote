
// AXIS driver
class c_drv;
  
  // Interface handle
  virtual AXI4SR axis;
  
  // Mailbox handle
  mailbox gen2drv;
  mailbox drv2scb;

  // Number of transactions
  int n_trs;

  // 
  // C-tor
  //
  function new(virtual AXI4SR axis, mailbox gen2drv, mailbox drv2scb);
    this.axis = axis;
    this.gen2drv = gen2drv;
    this.drv2scb = drv2scb;
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
  task reset_m;
      axis.tvalid <= 1'b0;
      axis.tdata <= 0;
      axis.tkeep <= 0;
      axis.tlast <= 1'b0;
      axis.tid  <= 0;
      $display("AXISR reset_m() completed.");
  endtask
  
  //
  // Run
  //
  task run;
    forever begin
      c_trs trs;
      gen2drv.get(trs);
      drv2scb.put(trs);
      axis.tdata  <= #TA trs.tdata;   
      axis.tkeep  <= #TA ~0;
      axis.tlast  <= #TA trs.tlast;
      axis.tid    <= #TA trs.tid;
      axis.tvalid <= #TA 1'b1;
      cycle_start();
      while(axis.tready != 1'b1) begin cycle_wait(); cycle_start(); end
      cycle_wait();
      axis.tdata  <= #TA 0;
      axis.tkeep  <= #TA 0;
      axis.tlast  <= #TA 1'b0;
      axis.tid    <= #TA 0;
      axis.tvalid <= #TA 1'b0;
      trs.display("Drv");
      n_trs++;
    end
  endtask
  
endclass