/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

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
        input  logic [AXI_ADDR_BITS-1:0] addr,
        input  logic [AXIL_DATA_BITS-1:0] data,
        output logic [1:0] resp,
        input  logic is_dummy = 0
    );      
        // Request
        axi.cbm.awaddr  <= addr;
        axi.cbm.awvalid <= 1'b1;
        axi.cbm.wdata   <= data;
        if (!is_dummy) begin
            axi.cbm.wstrb <= ~0;
        end else begin
            axi.cbm.wstrb <= 0;
        end
        axi.cbm.wvalid  <= 1'b1;
        @(axi.cbm iff (axi.cbm.awready == 1'b1 && axi.cbm.wready == 1'b1));
        axi.cbm.awaddr  <= $urandom();
        axi.cbm.awvalid <= 1'b0;
        axi.cbm.wdata   <= $urandom();
        axi.cbm.wstrb   <= $urandom();
        axi.cbm.wvalid  <= 1'b0;

        // Response
        axi.cbm.bready <= 1'b1;
        @(axi.cbm iff (axi.cbm.bvalid == 1'b1));
        axi.cbm.bready <= 1'b0;

        `VERBOSE(("write() completed. Addr: %x, data: %0d", addr, data))
        resp = axi.cbm.bresp;
    endtask

    // Read
    task read (
        input  logic [AXI_ADDR_BITS-1:0]  addr,
		output logic [AXIL_DATA_BITS-1:0] data,
        output logic [1:0]                resp
    );
        // Request
        axi.cbm.araddr  <= addr;
        axi.cbm.arvalid <= 1'b1;
        @(axi.cbm iff (axi.cbm.arready == 1'b1));
        axi.cbm.araddr  <= $urandom();
        axi.cbm.arvalid <= 1'b0;

        // Response
        axi.cbm.rready <= 1'b1;
        @(axi.cbm iff (axi.cbm.rvalid == 1'b1));
        axi.cbm.rready <= 1'b0;

        `VERBOSE(("read() completed. Addr: %x, data: %0d", addr, axi.cbm.rdata))
		data = axi.cbm.rdata;
        resp = axi.cbm.rresp;
    endtask

endclass