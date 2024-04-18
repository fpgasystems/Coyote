class c_axil;

    // Interface handle
    virtual AXI4L axi;

    // Constructor
    function new(virtual AXI4L axi);
        this.axi = axi;
    endfunction

    // Cycle start
    task cycle_start;
        #TT;
    endtask

    // Cycle wait
    task cycle_wait;
        @(posedge axi.aclk);
    endtask

    // Reset
    task reset_m;
        axi.araddr <= 0;
        axi.arprot <= 0;
        axi.arqos <= 0;
        axi.arregion <= 0;
        axi.arvalid <= 0;
        axi.awaddr <= 0;
        axi.awprot <= 0;
        axi.awqos <= 0;
        axi.awregion <= 0;
        axi.awvalid <= 0;
        axi.bready <= 0;
        axi.rready <= 0;
        axi.wdata <= 0;
        axi.wstrb <= 0;
        axi.wvalid <= 0;
        $display("AXIL reset_m() completed.");
    endtask

    task reset_s;
        axi.arready <= 0;
        axi.awready <= 0;
        axi.bresp <= 0;
        axi.bvalid <= 0;
        axi.rdata <= 0;
        axi.rresp <= 0;
        axi.rvalid <= 0;
        axi.wready <= 0;
        $display("AXIL reset_s() completed.");
    endtask

    // Write
    task write (
        input logic [AXI_ADDR_BITS-1:0] addr,
        input logic [AXIL_DATA_BITS-1:0] data
    );      
        // Request
        axi.awaddr  <= #TA addr;
        axi.awvalid <= #TA 1'b1;
        axi.wdata   <= #TA data;
        axi.wstrb   <= #TA ~0;
        axi.wvalid  <= #TA 1'b1;
        cycle_start();
        while(axi.awready != 1'b1 && axi.wready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.awaddr  <= #TA 0;
        axi.awvalid <= #TA 1'b0;
        axi.wdata   <= #TA 0;
        axi.wstrb   <= #TA 0;
        axi.wvalid  <= #TA 1'b0;
        // Response
        axi.bready  <= #TA 1'b1;
        cycle_start();
        while(axi.bvalid != 1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.bready  <= #TA 1'b0;
        $display("AXIL write() completed. Data: %x, addr: %x", data, addr);
    endtask

    // Read
    task read (
        input logic [AXI_ADDR_BITS-1:0] addr
    );
        // Request
        axi.araddr  <= #TA addr;
        axi.arvalid <= #TA 1'b1;
        cycle_start();
        while(axi.arready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.araddr  <= #TA 0;
        axi.arvalid <= #TA 1'b0;
        // Response
        axi.rready  <= #TA 1'b1;
        cycle_start();
        while(axi.rvalid != 1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.rready  <= #TA 1'b0;
        $display("AXIL read() completed. Data: %x, addr: %x", axi.rdata, addr);
    endtask

endclass