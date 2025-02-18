/* This class reads input from a text file and either generates a write to the axi_ctrl stream,
    or it reads data from the axi_ctrl stream until certain bits match before execution continues
*/
    


class ctrl_simulation;

    c_axil drv;
    string path_name;
    string file_name;

    event done;

    function new(c_axil axi_drv, string input_path_name, string ctrl_file_name);
        drv = axi_drv;
        path_name = input_path_name;
        file_name = ctrl_file_name;
    endfunction

    task initialize();
        $display("Ctrl Simulation: initialize");
        drv.reset_m();
        $display("Ctrl Simulation: initialization complete");
    endtask

    task run();
        logic iswrite;
        logic [AXI_ADDR_BITS-1:0] addr;
        logic [AXIL_DATA_BITS-1:0] data;
        logic [AXIL_DATA_BITS-1:0] read_data_mask;
        int read_start_bit;
        int read_end_bit;
        logic [AXIL_DATA_BITS-1:0] read_data;


        string full_file_name;
        string line;
        int FILE;

        full_file_name = {path_name, file_name};
        FILE = $fopen(full_file_name, "r");

        while($fgets(line, FILE)) begin
            $sscanf(line, "%x %h %h %d %d", iswrite, addr, data, read_start_bit, read_end_bit);

            //write a control register
            if(iswrite) begin
                drv.write(addr, data);
                $display("Writing Control Register: %h with data: %h at time: %X", addr, data, $realtime);
            end else if (!iswrite) begin

                //read from control register until a certain value matches
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
                    if (read_data == data) break;
                end
            end
        end

        $display("CTRL Done");
        -> done;
    endtask
endclass