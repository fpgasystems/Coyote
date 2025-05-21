
// AXIS
class c_axisr;
  
    // Interface handle
    virtual AXI4SR axis;

    // 
    // C-tor
    //
    function new(virtual AXI4SR axis);
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
        axis.tid <= 0;
        $display("AXISR reset_m() completed.");
    endtask

    task reset_s;
        axis.tready <= 1'b0;
        $display("AXISR reset_s() completed.");
    endtask
    
    //
    // Send
    //
    task send (
        input  logic [AXI_DATA_BITS-1:0] tdata,
        input  logic [AXI_DATA_BITS/8-1:0] tkeep,
        input  logic tlast,
        input  logic [AXI_ID_BITS-1:0] tid
    );
        axis.tdata  <= #TA tdata;   
        axis.tkeep  <= #TA tkeep;
        axis.tlast  <= #TA tlast;
        axis.tid    <= #TA tid;
        axis.tvalid <= #TA 1'b1;
        cycle_start();
        while(axis.tready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axis.tdata  <= #TA 0;
        axis.tkeep  <= #TA 0;
        axis.tlast  <= #TA 1'b0;
        axis.tid    <= #TA 0;
        axis.tvalid <= #TA 1'b0;
        $display("AXIS send() completed. Data: %x, keep: %x, last: %x", tdata, tkeep, tlast);
    endtask

    //
    // Recv
    //
    task recv (
        output  logic [AXI_DATA_BITS-1:0] tdata,
        output  logic [AXI_DATA_BITS/8-1:0] tkeep,
        output  logic tlast,
        output  logic [AXI_ID_BITS-1:0] tid
    );
        // Request
        axis.tready  <= #TA 1'b1;
        cycle_start();
        while(axis.tvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        tdata = axis.tdata;
        tkeep = axis.tkeep;
        tlast = axis.tlast;
        tid = axis.tid;
        cycle_wait();
        axis.tready <= #TA 1'b0;
        $display("AXIS recv() completed. Data: %x, keep: %x, last: %x, id: %x", axis.tdata, axis.tkeep, axis.tlast, axis.tid);
    endtask
  
endclass