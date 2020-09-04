package axiSimTypes;

    import lynxTypes::*;

    //
    // AXI4 Stream driver
    //
    class AXI4Sdrv;

        // Interface handle
        virtual AXI4S axis;
        
        // ID
        integer id;

        // Constructor
        function new(virtual AXI4S axis, input integer id);
            this.axis = axis;
            this.id = id;
        endfunction

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
        endtask

        task reset_s;
            axis.tready <= 1'b0;
        endtask

        // Drive
        task send_data_incr (
            input logic [AXI_DATA_BITS-1:0] tdata,
            input integer n_tr
        );
            for(int i = 0; i < 8; i++) begin
                axis.tdata[i*64+:64] <= tdata+i;
            end       
            axis.tkeep <= ~0;
            axis.tlast <= 1'b0;
            axis.tvalid <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                if(i == n_tr-1) axis.tlast <= 1'b1;
                cycle_wait();
                while(axis.tready != 1'b1) begin cycle_wait(); end
                for(int j = 0; j < 8; j++) begin
                    axis.tdata[j*64+:64] <= axis.tdata[j*64+:64] + 8;
                end
            end
            axis.tdata <= 0;
            axis.tkeep <= 0;
            axis.tlast <= 1'b0;
            axis.tvalid <= 1'b0;
            //cycle_wait();
        endtask
        
        task send_data (
            input logic [AXI_DATA_BITS-1:0] tdata,
            input integer n_tr
        );
            axis.tdata <= tdata;   
            axis.tkeep <= ~0;
            axis.tlast <= 1'b0;
            axis.tvalid <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                if(i == n_tr-1) axis.tlast <= 1'b1;
                cycle_wait();
                while(axis.tready != 1'b1) begin cycle_wait(); end
            end
            axis.tdata <= 0;
            axis.tkeep <= 0;
            axis.tlast <= 1'b0;
            axis.tvalid <= 1'b0;
            //cycle_wait();
        endtask

        task recv (
            input integer n_tr
        );
            axis.tready <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                cycle_wait();
                while(axis.tvalid != 1'b1) begin cycle_wait(); end
            end
            axis.tready <= 1'b0;
            //cycle_wait();
        endtask

    endclass;

    //
    // AXI4 Lite driver
    //
    class AXI4Ldrv;

        // Interface handle
        virtual AXI4L axi;
        
        // ID
        integer id;

        // Constructor
        function new(virtual AXI4L axi, input integer id);
            this.axi = axi;
            this.id = id;
        endfunction

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
        endtask

        // Write
        task write (
            input logic [AXI_ADDR_BITS-1:0] addr,
            input logic [AXIL_DATA_BITS-1:0] data
        );      
            // Request
            axi.awaddr <= addr;
            axi.awvalid <= 1'b1;
            axi.wdata <= data;
            axi.wstrb <= ~0;
            axi.wvalid <= 1'b1;
            cycle_wait();
            while(axi.awready != 1'b1 && axi.wready != 1'b1) begin cycle_wait(); end
            axi.awaddr <= 0;
            axi.awvalid <= 1'b0;
            axi.wdata <= 0;
            axi.wstrb <= 0;
            axi.wvalid <= 1'b0;
            // Response
            axi.bready <= 1'b1;
            cycle_wait();
            while(axi.bvalid != 1) begin cycle_wait(); end
            axi.bready <= 1'b0;
            $display("AXIL: Data %x written at addr %x, id %d", data, addr, id);
        endtask

        // Read
        task read (
            input logic [AXI_ADDR_BITS-1:0] addr
        );
            // Request
            axi.araddr <= addr;
            axi.arvalid <= 1'b1;
            cycle_wait();
            while(axi.arready != 1'b1) begin cycle_wait(); end
            axi.araddr <= 0;
            axi.arvalid <= 1'b0;
            // Response
            axi.rready <= 1'b1;
            cycle_wait();
            while(axi.rvalid != 1) begin cycle_wait(); end
            axi.rready <= 1'b0;
            $display("AXIL: Data %x read at addr %x, id %d", axi.rdata, addr, id);
        endtask

    endclass;

    //
    // AXI4 driver
    //
    class AXI4drv;

        // Interface handle
        virtual AXI4 axi;
        
        // ID
        integer id;

        // Constructor
        function new(virtual AXI4 axi, input integer id);
            this.axi = axi;
            this.id = id;
        endfunction

        // Cycle wait
        task cycle_wait;
            @(posedge axi.aclk);
        endtask

        // Reset
        task reset_m;
            axi.araddr <= 0;
            axi.arburst <= 0;
            axi.arcache <= 0;
            axi.arid <= 0;
            axi.arlen <= 0;
            axi.arlock <= 0;
            axi.arprot <= 0;
            axi.arqos <= 0;
            axi.arregion <= 0;
            axi.arsize <= 0;
            axi.arvalid <= 0;
            axi.awaddr <= 0;
            axi.awburst <= 0;
            axi.awcache <= 0;
            axi.awid <= 0;
            axi.awlen <= 0;
            axi.awlock <= 0;
            axi.awprot <= 0;
            axi.awqos <= 0;
            axi.awregion <= 0;
            axi.awsize <= 0;
            axi.awvalid <= 0;
            axi.wdata <= 0;
            axi.wlast <= 0;
            axi.wstrb <= 0;
            axi.wvalid <= 0;
            axi.rready <= 0;
            axi.bready <= 0;
        endtask

        task reset_s;
            axi.arready <= 0;
            axi.awready <= 0;
            axi.bresp <= 0;
            axi.bvalid <= 0;
            axi.bid <= 0;
            axi.rdata <= 0;
            axi.rid <= 0;
            axi.rresp <= 0;
            axi.rlast <= 0;
            axi.rvalid <= 0;
            axi.wready <= 0;
        endtask

        // Write AW
        task write_aw (
            input logic [AXI_ADDR_BITS-1:0] addr,
            input logic [LEN_BITS-1:0] len,
            input logic [2:0] size
        );
            axi.awaddr <= addr;
            axi.awburst <= 2'b01;
            axi.awcache <= 0;
            axi.awid <= 0;
            axi.awlen <= len;
            axi.awlock <= 0;
            axi.awprot <= 0;
            axi.awqos <= 0;
            axi.awregion <= 0;
            axi.awsize <= size;
            axi.awvalid <= 1'b1;
            cycle_wait();
            while(axi.awready != 1'b1) begin cycle_wait(); end
            axi.awaddr <= 0;
            axi.awburst <= 0;
            axi.awcache <= 0;
            axi.awid <= 0;
            axi.awlen <= 0;
            axi.awlock <= 0;
            axi.awprot <= 0;
            axi.awqos <= 0;
            axi.awregion <= 0;
            axi.awsize <= 0;
            axi.awvalid <= 1'b0;
        endtask

        // Write AR
        task write_ar (
            input logic [AXI_ADDR_BITS-1:0] addr,
            input logic [LEN_BITS-1:0] len,
            input logic [2:0] size
        );
            axi.araddr <= addr;
            axi.arburst <= 2'b01;
            axi.arcache <= 0;
            axi.arid <= 0;
            axi.arlen <= len;
            axi.arlock <= 0;
            axi.arprot <= 0;
            axi.arqos <= 0;
            axi.arregion <= 0;
            axi.arsize <= size;
            axi.arvalid <= 1'b1;
            cycle_wait();
            while(axi.arready != 1'b1) begin cycle_wait(); end
            axi.araddr <= 0;
            axi.arburst <= 0;
            axi.arcache <= 0;
            axi.arid <= 0;
            axi.arlen <= 0;
            axi.arlock <= 0;
            axi.arprot <= 0;
            axi.arqos <= 0;
            axi.arregion <= 0;
            axi.arsize <= 0;
            axi.arvalid <= 1'b0;
        endtask

        // Write W
        task write_w (
            input logic [AXI_DATA_BITS-1:0] wdata,
            input logic [AXI_DATA_BITS/8-1:0] wstrb,
            input logic wlast
        );
            axi.wdata <= wdata;
            axi.wlast <= wlast;
            axi.wstrb <= wstrb;
            axi.wvalid <= 1'b1;
            cycle_wait();
            while(axi.wready != 1'b1) begin cycle_wait(); end
            axi.wdata <= 0;
            axi.wlast <= 0;
            axi.wstrb <= 0;
            axi.wvalid <= 1'b0;
        endtask

        // Write r
        task write_r (
            input logic [AXI_DATA_BITS-1:0] rdata,
            input logic rlast
        );
            axi.rid <= 0;
            axi.rresp <= 0;
            axi.rdata <= rdata;
            axi.rlast <= rlast;
            axi.rvalid <= 1'b1;
            cycle_wait();
            while(axi.rready != 1'b1) begin cycle_wait(); end
            axi.rid <= 0;
            axi.rresp <= 0;
            axi.rdata <= 0;
            axi.rlast <= 0;
            axi.rvalid <= 1'b0;
        endtask

        // Write B
        task write_b ();
            axi.bid <= 0;
            axi.bresp <= 0;
            axi.bvalid <= 1'b1;
            cycle_wait();
            while(axi.bready != 1'b1) begin cycle_wait(); end
            axi.bid <= 0;
            axi.bresp <= 0;
            axi.bvalid <= 1'b0;
        endtask

        // Read AW
        task read_aw (
            output logic [AXI_ADDR_BITS-1:0] addr,
            output logic [LEN_BITS-1:0] len
        );
            axi.awready <= 1'b1;
            cycle_wait();
            while(axi.awvalid != 1'b1) begin cycle_wait(); end
            addr = axi.awaddr;
            len = axi.awlen;
            cycle_wait();
            axi.awready = 1'b0;
        endtask

        // Read AR
        task read_ar ();
            axi.arready <= 1'b1;
            cycle_wait();
            while(axi.arvalid != 1'b1) begin cycle_wait(); end
            $display("AR - addr: %x, len: %x", axi.araddr, axi.arlen);
            cycle_wait();
            axi.arready = 1'b0;
        endtask

        // Read W
        task read_w (
            output logic [AXI_DATA_BITS-1:0] wdata,
            output logic [AXI_DATA_BITS/8-1:0] wstrb,
            output logic wlast
        );
            axi.wready <= 1'b1;
            cycle_wait();
            while(axi.wvalid != 1'b1) begin cycle_wait(); end
            wdata = axi.wdata;
            wstrb = axi.wstrb;
            wlast = axi.wlast;
            cycle_wait();
            axi.wready <= 1'b0;
        endtask

        // Read R
        task read_r (
            output logic [AXI_DATA_BITS-1:0] rdata,
            output logic rlast
        );
            axi.rready <= 1'b1;
            cycle_wait();
            while(axi.rvalid != 1'b1) begin cycle_wait(); end
            rdata = axi.rdata;
            rlast = axi.rlast;
            cycle_wait();
            axi.rready <= 1'b0;
        endtask

        // Read B
        task read_b ();
            axi.bready <= 1'b1;
            cycle_wait();
            while(axi.bvalid != 1'b1) begin cycle_wait(); end
            cycle_wait();
            axi.bready <= 1'b0;
        endtask

    endclass;



endpackage