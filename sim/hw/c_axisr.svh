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

`timescale 1ns / 1ps

// AXIS
class c_axisr;
    localparam SEND_RAND_THRESHOLD = 5;
    localparam RECV_RAND_THRESHOLD = 10;

    // Interface handle
    virtual AXI4SR axis;
    int index;

    // 
    // C-tor
    // Index is a optional parameter that can be supplied when this class is
    // used on host/card streams. It describes the index of the coyote stream
    // c_axisr is used on. Setting the parameter changes the debug messages produced
    // by this class. In the instance of host/card streams this is needed for
    // the Python unit test performance tests to work properly.
    // Those tests parse the c_axisr debug messages and need to associate the parsed
    // recv()/send() timing with a coyote stream index.
    //
    function new(virtual AXI4SR axis, int index = -1);
        this.axis = axis;
        this.index = index;
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
        @(axis.cbm iff (axis.cbm.tready == 1'b1));
        axis.cbm.tdata  <= $urandom();
        axis.cbm.tkeep  <= $urandom();
        axis.cbm.tlast  <= $urandom();
        axis.cbm.tid    <= $urandom();
        axis.cbm.tvalid <= 1'b0;

        if (index == -1) begin
          `VERBOSE(("send() completed. Data: %x, keep: %x, last: %x", tdata, tkeep, tlast))
        end else begin
          // Caution: Changing this log format will break the python performance tests.
          //          Please adjust the regex in ../unit-test/fpga_performance_test_case.py
          `VERBOSE(("[%0d] send() completed. Data: %x, keep: %x, last: %x", index, tdata, tkeep, tlast))
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
        @(axis.cbs iff (axis.cbs.tvalid == 1'b1));
        axis.cbs.tready <= 1'b0;

        if (index == -1) begin
          `VERBOSE(("recv() completed. Data: %x, keep: %x, last: %x, id: %x", axis.cbs.tdata, axis.cbs.tkeep, axis.cbs.tlast, axis.cbs.tid))
        end else begin
          // Caution: Changing this log format will break the python performance tests.
          //          Please adjust the regex in ../unit-test/fpga_performance_test_case.py
          `VERBOSE(("[%0d] recv() completed. Data: %x, keep: %x, last: %x, id: %x", index, axis.cbs.tdata, axis.cbs.tkeep, axis.cbs.tlast, axis.cbs.tid))
        end
      
        tdata = axis.cbs.tdata;
        tkeep = axis.cbs.tkeep;
        tlast = axis.cbs.tlast;
        tid   = axis.cbs.tid;
    endtask
  
endclass