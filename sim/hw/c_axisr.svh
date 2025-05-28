
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
    
    // Reset
    task reset_m;
        axis.cbm.tvalid <= 1'b0;
        axis.cbm.tdata  <= 0;
        axis.cbm.tkeep  <= 0;
        axis.cbm.tlast  <= 1'b0;
        axis.cbm.tid    <= 0;
        $display("AXISR reset_m() completed.");
    endtask

    task reset_s;
        axis.cbs.tready <= 1'b0;
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
        axis.cbm.tdata  <= tdata;   
        axis.cbm.tkeep  <= tkeep;
        axis.cbm.tlast  <= tlast;
        axis.cbm.tid    <= tid;
        axis.cbm.tvalid <= 1'b1;
        @(axis.cbm);
        while(axis.cbm.tready != 1'b1) begin @(axis.cbm); end
        axis.cbm.tdata  <= 0;
        axis.cbm.tkeep  <= 0;
        axis.cbm.tlast  <= 1'b0;
        axis.cbm.tid    <= 0;
        axis.cbm.tvalid <= 1'b0;

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
        axis.cbs.tready <= 1'b1;
        @(axis.cbs);
        while(axis.cbs.tvalid != 1'b1) begin @(axis.cbs); end
        axis.cbs.tready <= 1'b0;

        $display("AXIS recv() completed. Data: %x, keep: %x, last: %x, id: %x", axis.cbs.tdata, axis.cbs.tkeep, axis.cbs.tlast, axis.cbs.tid);
        tdata = axis.cbs.tdata;
        tkeep = axis.cbs.tkeep;
        tlast = axis.cbs.tlast;
        tid   = axis.cbs.tid;
    endtask
  
endclass