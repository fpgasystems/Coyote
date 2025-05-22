/* 
  This class reads input from a text file and either generates a write to the axi_ctrl stream, or it reads data from the axi_ctrl stream until certain bits match before execution continues
*/

typedef struct packed {
    byte    is_write;
    longint addr;
    longint data;
    int     read_start_bit;
    int     read_end_bit;
} ctrl_op_t;

class ctrl_simulation;
    mailbox mbx;
    c_axil  drv;

    int transfer_file;

    function new(mailbox ctrl_mbx, c_axil axi_drv);
        this.mbx = ctrl_mbx;
        this.drv = axi_drv;
    endfunction

    task initialize(string path_name);
        $display("Ctrl simulation: Initialize");
        drv.reset_m();
        transfer_file = $fopen({path_name, "ctrl_transfer_output.txt"}, "w");
        $display("Ctrl simulation: Initialization complete");
    endtask

    task run();
        ctrl_op_t trs;
        logic [AXIL_DATA_BITS-1:0] read_data_mask;
        logic [AXIL_DATA_BITS-1:0] read_data;

        forever begin
            mbx.get(trs);

            if (trs.is_write) begin // Write a control register
                drv.write(trs.addr, trs.data);
                $fdisplay(transfer_file, "%t: CTRL write, register: %h, data: %h", $realtime, trs.addr, trs.data);
            end else begin // Read from control register until a certain value matches
                read_data_mask = 'hffffffffffffffff;
                for(int i = 63; i > trs.read_start_bit; i--) begin
                    read_data_mask[i] = 1'b0;
                end
                for(int i = 0; i < trs.read_end_bit; i++) begin
                    read_data_mask[i] = 1'b0;
                end
                trs.data = trs.data & read_data_mask;

                forever begin
                    drv.read(trs.addr, read_data);
                    read_data = read_data & read_data_mask;
                    if (read_data == trs.data) begin
                        $fdisplay(transfer_file, "%t: CTRL read successful, register: %h, data: %h, expected: %h", $realtime, trs.addr, read_data, trs.data);
                        break;
                    end
                    $fdisplay(transfer_file, "%t: CTRL read unsuccessful, register: %h, data: %h, expected: %h", $realtime, trs.addr, read_data, trs.data);
                end
            end
        end
    endtask
endclass