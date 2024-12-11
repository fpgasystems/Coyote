


class ctrl_simulation;

    c_axil drv;

    event done;

    function new(c_axil axi_drv);
        drv = axi_drv;
    endfunction

    task reset();
        drv.reset_m();
    endtask

    // TODO: adapt the driver to return values on read
    task run();
        // This is where control interactions are coded
        // write config register
        // enable write, local_only
        drv.write('hf8, 'h000000000000080a); // enable write, and 256 bytes transfer size

        drv.write('h18, 'h0000000000000a32);
        drv.write('h10, 'h000007fe00000000);
        drv.write('h08, 'h0000000000000040); // write descriptor length
        drv.write('h00, 'h000007ff00000bcc); // write descriptor base address

        #32
        forever begin
            logic [63:0] data;
            drv.read('hf8, data);
            if (data[63:56] == 8'd00) break;
        end

        // enable write and rdma
        drv.write('hf8, 'h0000000000000802); // enable write, and 256 bytes transfer size

        drv.write('h18, 'h0000000000000a32);
        drv.write('h10, 'h000007fe00000000);
        drv.write('h08, 'h0000000000000040); // write descriptor length
        drv.write('h00, 'h000007ff00000bcc); // write descriptor base address

        #32
        forever begin
            logic [63:0] data;
            drv.read('hf8, data);
            if (data[63:56] == 8'd00) break;
        end

        -> done; // no more control interactions
    endtask

endclass
