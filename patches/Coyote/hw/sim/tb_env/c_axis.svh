
// AXIS
class c_axis;
  
    // Interface handle
    virtual AXI4S axis;

    // 
    // C-tor
    //
    function new(virtual AXI4S axis);
        this.axis = axis;
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
        $display("AXIS reset_m() completed.");
    endtask

    task reset_s;
        axis.tready <= 1'b0;
        $display("AXIS reset_s() completed.");
    endtask
    
    //
    // Send
    //
    task send (
        input  logic [AXI_DATA_BITS-1:0] tdata,
        input  logic [AXI_DATA_BITS/8-1:0] tkeep,
        input  logic tlast
    );
        axis.tdata  <= #TA tdata;   
        axis.tkeep  <= #TA tkeep;
        axis.tlast  <= #TA tlast;
        axis.tvalid <= #TA 1'b1;
        cycle_start();
        while(axis.tready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axis.tdata  <= #TA 0;
        axis.tkeep  <= #TA 0;
        axis.tlast  <= #TA 1'b0;
        axis.tvalid <= #TA 1'b0;
        $display("AXIS send() completed. Data: %x, keep: %x, last: %x", tdata, tkeep, tlast);
    endtask

    //
    // Recv
    //
    task recv ();
        // Request
        axis.tready  <= #TA 1'b1;
        cycle_start();
        while(axis.tready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axis.tready <= #TA 1'b0;
        $display("AXIS recv() completed. Data: %x, keep: %x, last: %x", axis.tdata, axis.tkeep, axis.tlast);
    endtask
  
endclass