`ifndef SCOREBOARD_SVH
`define SCOREBOARD_SVH

import sim_pkg::*;

class scoreboard;
    enum bit[7:0] {
        GET_CSR,    // Result of cThread.getCSR()
        HOST_WRITE, // Host write through axis_host_send
        IRQ         // Interrupt through notify interface
    } sock_type_t;

    int fd;

    function new(
        string output_sock_name
    );
        this.fd = $fopen(output_sock_name, "wb");
        if (!fd) begin
            $display("File %s could not be opened: %0d", output_sock_name, fd);
        end
    endfunction

    function close();
        $fclose(fd);
    endfunction

    function writeByte(byte data);
        $fwrite(fd, "%c", data);
    endfunction

    function writeInt(int data);
        for (int i = 0; i < 4; i++) begin
            writeByte(data[i * 8+:8]);
        end
    endfunction

    function writeLong(longint data);
        for (int i = 0; i < 8; i++) begin
            writeByte(data[i * 8+:8]);
        end
    endfunction

    function writeCTRL(bit[AXIL_DATA_BITS-1:0] data);
        writeByte(GET_CSR);
        writeLong(data);
        $display("SCB: Write CTRL, %0d", data);
    endfunction

    function writeHostMem(vaddr_t vaddr, bit[AXI_DATA_BITS - 1:0] data, bit[AXI_DATA_BITS / 8 - 1:0] keep);
        vaddr_t len = $countones(keep);
        writeByte(HOST_WRITE);
        writeLong(vaddr);
        writeLong(len);
        for (int i = 0; i < len; i++) begin
            writeByte(data[i * 8+:8]);
        end
        $display("Test");
    endfunction

    function writeNotify(irq_not_t interrupt);
        writeByte(IRQ);
        writeByte(interrupt.pid);
        writeInt(interrupt.value);
        $display("SCB: Notify, PID: %0d, value: %0d", interrupt.pid, interrupt.value);
    endfunction
endclass

`endif
