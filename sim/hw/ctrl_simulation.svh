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

`include "log.svh"
`include "scoreboard.svh"

/* 
* This class reads input from a text file and either generates a write to the axi_ctrl stream, or it reads data from the axi_ctrl stream until certain bits match before execution continues
*/

class ctrl_simulation;
    mailbox #(trs_ctrl) mbx;
    c_axil drv;
    scoreboard scb;

    event polling_done;

    function new(mailbox #(trs_ctrl) ctrl_mbx, c_axil axi_drv, scoreboard scb);
        this.mbx = ctrl_mbx;
        this.drv = axi_drv;
        this.scb = scb;
    endfunction

    task initialize();
        drv.reset_m();
    endtask

    task run();
        trs_ctrl trs;
        logic [AXIL_DATA_BITS-1:0] read_data;

        forever begin
            // We need this as non-blocking with @(...), otherwise timing might be off if we do a 
            // busy wait and we would need to wait an additional cycle every time
            int success = mbx.try_get(trs);
            while (!success) begin
                @(drv.axi.cbm);
                success = mbx.try_get(trs);
            end

            if (trs.is_write) begin // Write a control register
                drv.write(trs.addr, trs.data);
                `DEBUG(("Write register: %x, data: %0d", trs.addr, trs.data))

            `ifdef EN_RANDOMIZATION // Dummy writes which happen in real hardware because of the AVX512 writing of registers
                for (int i = 0; i < 7; i++) begin drv.write(trs.addr + i, $urandom(), 1); end
            `endif
            end else begin // Read from a control register
                drv.read(trs.addr, read_data);
                if (trs.do_polling) begin
                    while (read_data != trs.data) begin
                        drv.read(trs.addr, read_data);
                    end
                    -> polling_done;
                end
                scb.writeCTRL(read_data);
                `DEBUG(("Read register: %x, data: %0d", trs.addr, read_data))
            end
        end
    endtask
endclass
