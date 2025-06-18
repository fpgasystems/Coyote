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

    function void writeCTRL(input bit[AXIL_DATA_BITS-1:0] data);
        writeByte(GET_CSR);
        writeLong(data);
        $fflush(fd);
        `VERBOSE(("Write CTRL, %0d", data))
    endfunction

    function void writeHostMem(vaddr_t vaddr, input bit[AXI_DATA_BITS - 1:0] data, input bit[AXI_DATA_BITS / 8 - 1:0] keep);
        int len = $countones(keep);
        writeByte(HOST_WRITE);
        writeLong(vaddr);
        writeLong(len);
        for (int i = 0; i < len; i++) begin
            writeByte(data[i * 8+:8]);
        end
        $fflush(fd);
        `VERBOSE(("Write host mem, vaddr %0d, len %0d, %0b", vaddr, len, keep))
    endfunction

    function void writeNotify(irq_not_t interrupt);
        writeByte(IRQ);
        writeByte(interrupt.pid);
        writeInt(interrupt.value);
        $fflush(fd);
        `DEBUG(("Notify, PID: %0d, value: %0d", interrupt.pid, interrupt.value))
    endfunction

    function void writeCheckCompleted(input int data);
        writeByte(CHECK_COMPLETED);
        writeInt(data);
        $fflush(fd);
        `VERBOSE(("Write check completed, %0d", data))
    endfunction

    function void writeHostRead(vaddr_t vaddr, input vaddr_t len);
        writeByte(HOST_READ);
        writeLong(vaddr);
        writeLong(len);
        $fflush(fd);
        `DEBUG(("Write host read, vaddr: %0d, len: %0d", vaddr, len))
    endfunction
endclass

`endif
