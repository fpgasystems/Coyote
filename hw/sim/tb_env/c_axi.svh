import lynxTypes::*;
import simTypes::*;

class c_axi #(
    parameter AXI4_DATA_BITS = 512,
    parameter AXI4_ADDR_BITS = 64,
    parameter AXI4_ID_BITS = 6
);

    // Interface handle
    virtual AXI4 #(.AXI4_DATA_BITS(AXI4_DATA_BITS), .AXI4_ADDR_BITS(AXI4_ADDR_BITS), .AXI4_ID_BITS(AXI4_ID_BITS)) axi;

    // Constructor
    function new(virtual AXI4 #(.AXI4_DATA_BITS(AXI4_DATA_BITS), .AXI4_ADDR_BITS(AXI4_ADDR_BITS), .AXI4_ID_BITS(AXI4_ID_BITS)) axi);
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
        $display("AXI4 reset_m() completed.");
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
        $display("AXI4 reset_s() completed.");
    endtask

    // Write AW
    task write_aw (
        input logic [AXI4_ADDR_BITS-1:0] addr,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [AXI4_ID_BITS-1:0] id
    );
        axi.awaddr      <= #TA addr;
        axi.awburst     <= #TA 2'b01;
        axi.awcache     <= #TA 0;
        axi.awid        <= #TA id;
        axi.awlen       <= #TA len;
        axi.awlock      <= #TA 0;
        axi.awprot      <= #TA 0;
        axi.awqos       <= #TA 0;
        axi.awregion    <= #TA 0;
        axi.awsize      <= #TA size;
        axi.awvalid     <= #TA 1'b1;
        cycle_start();
        while(axi.awready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.awaddr      <= #TA 0;
        axi.awburst     <= #TA 0;
        axi.awcache     <= #TA 0;
        axi.awid        <= #TA 0;
        axi.awlen       <= #TA 0;
        axi.awlock      <= #TA 0;
        axi.awprot      <= #TA 0;
        axi.awqos       <= #TA 0;
        axi.awregion    <= #TA 0;
        axi.awsize      <= #TA 0;
        axi.awvalid     <= #TA 1'b0;
        $display("AXI4 write_aw() completed. Addr: %x, len: %d, size: %d, id: %d", addr, len, size, id);
    endtask

    // Write AR
    task write_ar (
        input logic [AXI4_ADDR_BITS-1:0] addr,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [AXI4_ID_BITS-1:0] id
    );
        axi.araddr      <= #TA addr;
        axi.arburst     <= #TA 2'b01;
        axi.arcache     <= #TA 0;
        axi.arid        <= #TA id;
        axi.arlen       <= #TA len;
        axi.arlock      <= #TA 0;
        axi.arprot      <= #TA 0;
        axi.arqos       <= #TA 0;
        axi.arregion    <= #TA 0;
        axi.arsize      <= #TA size;
        axi.arvalid     <= #TA 1'b1;
        cycle_start();
        while(axi.arready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.araddr      <= #TA 0;
        axi.arburst     <= #TA 0;
        axi.arcache     <= #TA 0;
        axi.arid        <= #TA 0;
        axi.arlen       <= #TA 0;
        axi.arlock      <= #TA 0;
        axi.arprot      <= #TA 0;
        axi.arqos       <= #TA 0;
        axi.arregion    <= #TA 0;
        axi.arsize      <= #TA 0;
        axi.arvalid     <= #TA 1'b0;
        $display("AXI4 write_ar() completed. Addr: %x, len: %d, size: %d, id: %d", addr, len, size, id);
    endtask

    // Write W
    task write_w (
        input logic [AXI4_DATA_BITS-1:0] wdata,
        input logic [AXI4_DATA_BITS/8-1:0] wstrb,
        input logic wlast
    );
        axi.wdata   <= #TA wdata;
        axi.wlast   <= #TA wlast;
        axi.wstrb   <= #TA wstrb;
        axi.wvalid  <= #TA 1'b1;
        cycle_start();
        while(axi.wready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.wdata   <= #TA 0;
        axi.wlast   <= #TA 0;
        axi.wstrb   <= #TA 0;
        axi.wvalid  <= #TA 1'b0;
        $display("AXI4 write_w() completed. Data: %x, strb: %d, last: %d", wdata, wstrb, wlast);
    endtask

    // Write r
    task write_r (
        input logic [AXI4_DATA_BITS-1:0] rdata,
        input logic rlast,
        input logic [4:0] rid
    );
        axi.rid     <= #TA rid;
        axi.rresp   <= #TA 0;
        axi.rdata   <= #TA rdata;
        axi.rlast   <= #TA rlast;
        axi.rvalid  <= #TA 1'b1;
        cycle_start();
        while(axi.rready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.rid     <= #TA 0;
        axi.rresp   <= #TA 0;
        axi.rdata   <= #TA 0;
        axi.rlast   <= #TA 0;
        axi.rvalid  <= #TA 1'b0;
        $display("AXI4 write_r() completed. Data: %x, last: %d, rid: %d", rdata, rlast, rid);
    endtask

    // Write B
    task write_b (
        input logic [4:0] bid
    );
        axi.bid     <= #TA bid;
        axi.bresp   <= #TA 0;
        axi.bvalid  <= #TA 1'b1;
        cycle_start();
        while(axi.bready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.bid     <= #TA 0;
        axi.bresp   <= #TA 0;
        axi.bvalid  <= #TA 1'b0;
        $display("AXI4 write_b() completed. Bid: %d", bid);
    endtask

    // Read AW
    task read_aw ();
        axi.awready <= #TA 1'b1;
        cycle_start();
        while(axi.awvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.awready = #TA 1'b0;
        $display("AXI4 read_aw() completed. Addr: %x, len: %d, size: %d, id: %d", axi.awaddr, axi.awlen, axi.awsize, axi.awid);
    endtask

    // Read AR
    task read_ar ();
        axi.arready <= #TA 1'b1;
        cycle_start();
        while(axi.arvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.arready <= #TA 1'b0;
        $display("AXI4 read_ar() completed. Addr: %x, len: %d, size: %d, id: %s", axi.araddr, axi.arlen, axi.awsize, axi.awid);
    endtask

    // Read W
    task read_w ();
        axi.wready <= #TA 1'b1;
        cycle_start();
        while(axi.wvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        $display("W - data: %x, wstrb: %x, wlast: %x", axi.wdata, axi.wstrb, axi.wlast);
        cycle_wait();
        axi.wready <= #TA 1'b0;
        $display("AXI4 read_w() completed. Data: %x, strb: %d, last: %d", axi.wdata, axi.wstrb, axi.wlast);
    endtask

    // Read R
    task read_r ();
        axi.rready <= #TA 1'b1;
        cycle_start();
        while(axi.rvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        $display("R - data: %x, rlast: %x", axi.rdata, axi.rlast);
        cycle_wait();
        axi.rready <= #TA 1'b0;
        $display("AXI4 read_r() completed. Data: %x, last: %d, id: %s", axi.rdata, axi.wlast, axi.rid);
    endtask

    // Read B
    task read_b ();
        axi.bready <= #TA 1'b1;
        cycle_start();
        while(axi.bvalid != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        axi.bready <= #TA 1'b0;
        $display("AXI4 read_b() completed. Bid: %s", axi.bid);
    endtask

endclass;
