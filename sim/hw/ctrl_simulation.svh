/* 
  This class reads input from a text file and either generates a write to the axi_ctrl stream, or it reads data from the axi_ctrl stream until certain bits match before execution continues
*/

typedef struct packed {
    byte    is_write;
    longint addr;
    longint data;
    byte    read_data_mask;
    int     read_start_bit;
    int     read_end_bit;
} ctrl_op;

class ctrl_simulation;
    c_axil drv;
    string input_path_name;
    string input_file_name;

    int transfer_file;

    event done;

    function new(c_axil axi_drv, string input_path,string input_file);
        drv = axi_drv;
        input_path_name = input_path;
        input_file_name = input_file;
    endfunction

    task initialize(string path_name);
        $display("Ctrl simulation: Initialize");
        drv.reset_m();
        transfer_file = $fopen({path_name, "ctrl_transfer_output.txt"}, "w");
        $display("Ctrl simulation: Initialization complete");
    endtask

    task run();
        logic is_write;
        logic [AXI_ADDR_BITS-1:0] addr;
        logic [AXIL_DATA_BITS-1:0] data;
        logic [AXIL_DATA_BITS-1:0] read_data_mask;
        int read_start_bit;
        int read_end_bit;
        logic [AXIL_DATA_BITS-1:0] read_data;


        string full_file_name;
        string line;
        int FILE;

        full_file_name = {input_path_name, input_file_name};
        FILE = $fopen(full_file_name, "r");

        while($fgets(line, FILE)) begin
            $sscanf(line, "%x %h %h %d %d", is_write, addr, data, read_start_bit, read_end_bit);

            // Write a control register
            if(is_write) begin
                drv.write(addr, data);
                $fdisplay(transfer_file, "%t: CTRL write, register: %h, data: %h", $realtime, addr, data);
            end else if (!is_write) begin

                // Read from control register until a certain value matches
                read_data_mask = 'hffffffffffffffff;
                for(int i = 63; i > read_start_bit; i--) begin
                    read_data_mask[i] = 1'b0;
                end
                for(int i = 0; i < read_end_bit; i++) begin
                    read_data_mask[i] = 1'b0;
                end
                data = data & read_data_mask;

                forever begin
                    drv.read(addr, read_data);
                    read_data = read_data & read_data_mask;
                    if (read_data == data) begin
                        $fdisplay(transfer_file, "%t: CTRL read successful, register: %h, data: %h, expected: %h", $realtime, addr, read_data, data);
                        break;
                    end
                    $fdisplay(transfer_file, "%t: CTRL read unsuccessful, register: %h, data: %h, expected: %h", $realtime, addr, read_data, data);
                end
            end
        end

        $display("CTRL done");
        $fclose(transfer_file);
        -> done;
    endtask
endclass