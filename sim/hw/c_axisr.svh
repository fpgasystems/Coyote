
// AXIS
class c_axisr;
    localparam SEND_RAND_THRESHOLD = 5;
    localparam RECV_RAND_THRESHOLD = 10;

    // Interface handle
    virtual AXI4SR axis;
    int stream;

    // 
    // C-tor
    //
    function new(virtual AXI4SR axis, int stream = -1);
        this.axis = axis;
        this.stream = stream;
    endfunction
    
    // Reset
    task reset_m;
        axis.cbm.tvalid <= 1'b0;
        axis.cbm.tdata  <= 0;
        axis.cbm.tkeep  <= 0;
        axis.cbm.tlast  <= 1'b0;
        axis.cbm.tid    <= 0;
        `DEBUG(("reset_m() completed."))
    endtask

    task reset_s;
        axis.cbs.tready <= 1'b0;
        `DEBUG(("reset_s() completed."))
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
    `ifdef EN_RANDOMIZATION
        while ($urandom_range(0, 99) < SEND_RAND_THRESHOLD) begin @(axis.cbm); end
    `endif

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

        if (stream == -1) begin
          `VERBOSE(("send() completed. Data: %x, keep: %x, last: %x", tdata, tkeep, tlast))
        end else begin
          `VERBOSE(("[%0d] send() completed. Data: %x, keep: %x, last: %x", stream, tdata, tkeep, tlast))
        end
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
    `ifdef EN_RANDOMIZATION
        while ($urandom_range(0, 99) < RECV_RAND_THRESHOLD) begin @(axis.cbs); end
    `endif

        axis.cbs.tready <= 1'b1;
        @(axis.cbs);
        while(axis.cbs.tvalid != 1'b1) begin @(axis.cbs); end
        axis.cbs.tready <= 1'b0;

        if (stream == -1) begin
          `VERBOSE(("recv() completed. Data: %x, keep: %x, last: %x, id: %x", axis.cbs.tdata, axis.cbs.tkeep, axis.cbs.tlast, axis.cbs.tid))
        end else begin
          `VERBOSE(("[%0d] recv() completed. Data: %x, keep: %x, last: %x, id: %x", stream, axis.cbs.tdata, axis.cbs.tkeep, axis.cbs.tlast, axis.cbs.tid))
        end
      
        tdata = axis.cbs.tdata;
        tkeep = axis.cbs.tkeep;
        tlast = axis.cbs.tlast;
        tid   = axis.cbs.tid;
    endtask
  
endclass