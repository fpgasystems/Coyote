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

class c_meta #(
    parameter type ST = logic[63:0]
);
    localparam SEND_RAND_THRESHOLD = 5;
    localparam RECV_RAND_THRESHOLD = 10;

    // Interface handle;
    virtual metaIntf #(.STYPE(ST)) meta;

    // Constructor
    function new(virtual metaIntf #(.STYPE(ST)) meta);
        this.meta = meta;
    endfunction

    // Reset
    task reset_m;
        meta.cbm.valid <= 1'b0;
        meta.cbm.data  <= 0;
        `DEBUG(("reset_m() completed."))
    endtask

    task reset_s;
        meta.cbs.ready <= 1'b0;
        `DEBUG(("reset_s() completed."))
    endtask

    //
    // Drive
    //
    task send (
        input logic [$bits(ST)-1:0] data
    );
    `ifdef EN_RANDOMIZATION
        while ($urandom_range(0, 99) < SEND_RAND_THRESHOLD) begin @(meta.cbm); end
    `endif

        meta.cbm.data  <= data;
        meta.cbm.valid <= 1'b1;
        @(meta.cbm iff (meta.cbm.ready == 1'b1));
        meta.cbm.data  <= $urandom();
        meta.cbm.valid <= 1'b0;

        `DEBUG(("send() completed. Data: %x", data))
    endtask

    //
    // Receive
    //
    task recv (
        output logic [$bits(ST)-1:0] data
    );
    `ifdef EN_RANDOMIZATION
        while ($urandom_range(0, 99) < RECV_RAND_THRESHOLD) begin @(meta.cbs); end
    `endif

        meta.cbs.ready <= 1'b1;
        @(meta.cbs iff (meta.cbs.valid == 1'b1));
        meta.cbs.ready <= 1'b0;

        `DEBUG(("recv() completed. Data: %x", meta.cbs.data))
        data = meta.cbs.data;
    endtask

endclass
