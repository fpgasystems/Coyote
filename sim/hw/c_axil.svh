class c_axil;
    // Interface handle
    virtual AXI4L axi;

    // Constructor
    function new(virtual AXI4L axi);
        this.axi = axi;
    endfunction

    // Reset
    task reset_m;
        axi.cbm.araddr <= 0;
        axi.cbm.arprot <= 0;
        axi.cbm.arqos <= 0;
        axi.cbm.arregion <= 0;
        axi.cbm.arvalid <= 0;
        axi.cbm.awaddr <= 0;
        axi.cbm.awprot <= 0;
        axi.cbm.awqos <= 0;
        axi.cbm.awregion <= 0;
        axi.cbm.awvalid <= 0;
        axi.cbm.bready <= 0;
        axi.cbm.rready <= 0;
        axi.cbm.wdata <= 0;
        axi.cbm.wstrb <= 0;
        axi.cbm.wvalid <= 0;
        `DEBUG(("reset_m() completed."))
    endtask

    task reset_s;
        axi.cbs.arready <= 0;
        axi.cbs.awready <= 0;
        axi.cbs.bresp <= 0;
        axi.cbs.bvalid <= 0;
        axi.cbs.rdata <= 0;
        axi.cbs.rresp <= 0;
        axi.cbs.rvalid <= 0;
        axi.cbs.wready <= 0;
        `DEBUG(("reset_s() completed."))
    endtask

    // Write
    task write (
        input logic [AXI_ADDR_BITS-1:0] addr,
        input logic [AXIL_DATA_BITS-1:0] data
    );      
        // Request
        axi.cbm.awaddr  <= addr;
        axi.cbm.awvalid <= 1'b1;
        axi.cbm.wdata   <= data;
        axi.cbm.wstrb   <= ~0;
        axi.cbm.wvalid  <= 1'b1;
        @(axi.cbm);
        while(axi.cbm.awready != 1'b1 && axi.cbm.wready != 1'b1) begin @(axi.cbm); end
        axi.cbm.awaddr  <= 0;
        axi.cbm.awvalid <= 1'b0;
        axi.cbm.wdata   <= 0;
        axi.cbm.wstrb   <= 0;
        axi.cbm.wvalid  <= 1'b0;

        // Response
        axi.cbm.bready <= 1'b1;
        @(axi.cbm);
        while(axi.cbm.bvalid != 1) begin @(axi.cbm); end
        axi.cbm.bready <= 1'b0;

        `VERBOSE(("write() completed. Addr: %x, data: %0d", addr, data))
    endtask

    // Read
    task read (
        input  logic [AXI_ADDR_BITS-1:0]  addr,
		output logic [AXIL_DATA_BITS-1:0] data
    );
        // Request
        axi.cbm.araddr  <= addr;
        axi.cbm.arvalid <= 1'b1;
        @(axi.cbm);
        while(axi.cbm.arready != 1'b1) begin @(axi.cbm); end
        axi.cbm.araddr  <= 0;
        axi.cbm.arvalid <= 1'b0;

        // Response
        axi.cbm.rready <= 1'b1;
        @(axi.cbm);
        while(axi.cbm.rvalid != 1) begin @(axi.cbm); end
        axi.cbm.rready <= 1'b0;

        `VERBOSE(("read() completed. Addr: %x, data: %0d", addr, axi.cbm.rdata))
		data = axi.cbm.rdata;
    endtask

endclass