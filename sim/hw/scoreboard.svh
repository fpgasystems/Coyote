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

`ifndef SCOREBOARD_SVH
`define SCOREBOARD_SVH

import sim_pkg::*;

`include "log.svh"

class scoreboard;
    enum bit[7:0] {
        GET_CSR,         // Result of cThread.getCSR()
        HOST_WRITE,      // Host write through axis_host_send
        IRQ,             // Interrupt through notify interface
        CHECK_COMPLETED, // Result of cThread.checkCompleted()
        HOST_READ         // Host read through sq_rd
    } op_type_t;

    int fd;

    semaphore lock = new(1);

    function new(input string output_file_name);
        this.fd = $fopen(output_file_name, "wb");
        if (!fd) begin
            `DEBUG(("File %s could not be opened: %0d", output_file_name, fd))
        end else begin
            `DEBUG(("Scoreboard successfully opened file at %s", output_file_name))
        end
    endfunction

    function void close();
        $fclose(fd);
    endfunction

    // Note: When adding new functionality, please make sure to call
    // fflush once, after the whole message has been written.
    // Otherwise, there might be unexpected behavior in the Python/C++
    // clients since they may way forever to get their output.
    function void writeByte(input byte data);
        $fwrite(fd, "%c", data);
    endfunction

    function void writeInt(input int data);
        for (int i = 0; i < 4; i++) begin
            writeByte(data[i * 8+:8]);
        end
    endfunction

    function void writeLong(input longint data);
        for (int i = 0; i < 8; i++) begin
            writeByte(data[i * 8+:8]);
        end
    endfunction

    task writeOpCode(input byte opcode);
        lock.get(1);
        writeByte(opcode);
    endtask

    task flush();
        $fflush(fd);
        lock.put(1);
    endtask

    task writeCTRL(input bit[AXIL_DATA_BITS-1:0] data);
        writeOpCode(GET_CSR);
        writeLong(data);
        flush();
        `VERBOSE(("Write CTRL, %0d", data))
    endtask

    task writeHostMemHeader(vaddr_t vaddr, vaddr_t len);
        writeOpCode(HOST_WRITE);
        writeLong(vaddr);
        writeLong(len);
    endtask

    task writeHostMem(vaddr_t vaddr, input bit[AXI_DATA_BITS - 1:0] data, input bit[AXI_DATA_BITS / 8 - 1:0] keep);
        int len = $countones(keep);
        writeHostMemHeader(vaddr, len);
        for (int i = 0; i < len; i++) begin
            writeByte(data[i * 8+:8]);
        end
        flush();
        `VERBOSE(("Write host mem, vaddr %0d, len %0d, %0b", vaddr, len, keep))
    endtask

    task writeNotify(irq_not_t interrupt);
        writeOpCode(IRQ);
        writeByte(interrupt.pid);
        writeInt(interrupt.value);
        flush();
        `DEBUG(("Notify, PID: %0d, value: %0d", interrupt.pid, interrupt.value))
    endtask

    task writeCheckCompleted(input int data);
        writeOpCode(CHECK_COMPLETED);
        writeInt(data);
        flush();
        `VERBOSE(("Write check completed, %0d", data))
    endtask

    task writeHostRead(vaddr_t vaddr, input vaddr_t len);
        writeOpCode(HOST_READ);
        writeLong(vaddr);
        writeLong(len);
        flush();
        `DEBUG(("Write host read, vaddr: %0d, len: %0d", vaddr, len))
    endtask
endclass

`endif
