/* 
  This class reads input from a text file and either generates a write to the axi_ctrl stream, or it reads data from the axi_ctrl stream until certain bits match before execution continues
*/

`include "scoreboard.svh"

typedef struct packed {
    longint data;
    longint addr;
    byte    is_write;
} ctrl_op_t;

class ctrl_simulation;
    mailbox    mbx;
    c_axil     drv;
    scoreboard scb;

    function new(mailbox ctrl_mbx, c_axil axi_drv, scoreboard scb);
        this.mbx = ctrl_mbx;
        this.drv = axi_drv;
        this.scb = scb;
    endfunction

    task initialize();
        drv.reset_m();
    endtask

    task run();
        ctrl_op_t trs;
        logic [AXIL_DATA_BITS-1:0] read_data;

        forever begin
            mbx.get(trs);

            if (trs.is_write) begin // Write a control register
                drv.write(trs.addr, trs.data);
                $display("%t: CTRL write, register: %h, data: %h", $realtime, trs.addr, trs.data);
            end else begin // Read from a control register
                drv.read(trs.addr, read_data);
                scb.writeCTRL(read_data);
                $display("%t: CTRL read, register: %h, data: %h", $realtime, trs.addr, read_data);
            end
        end
    endtask
endclass