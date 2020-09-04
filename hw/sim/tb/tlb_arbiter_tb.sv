import lynxTypes::*;

module tlb_arbiter_tb;

    localparam CLK_PERIOD = 5ns;

    logic aclk = 1'b0;
    logic aresetn = 1'b1;

    logic done = 0;

    // Requests
    reqIntf req_in [N_REGIONS] (aclk);
    reqIntf req_out (aclk);
    
    logic [N_REGIONS_BITS-1:0] id;
    
    // Drivers
    lynxSimTypes::REQdrv req_drv_in_0 = new(req_in[0], 0);
    lynxSimTypes::REQdrv req_drv_in_1 = new(req_in[1], 1);
    lynxSimTypes::REQdrv req_drv_in_2 = new(req_in[2], 2);
    lynxSimTypes::REQdrv req_drv_out = new(req_out, 3);

    // Clock gen
    initial begin
        while (!done) begin
            aclk <= 1;
            #(CLK_PERIOD/2);
            aclk <= 0;
            #(CLK_PERIOD/2);
        end
    end

    // Reset gen
    initial begin
        aresetn = 0;
        #CLK_PERIOD aresetn = 1;
    end

    // DUT
    tlb_arbiter inst_DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .req_snk(req_in),
        .req_src(req_out),
        .id(id)
    );

    /* Init */
    initial begin
        req_drv_in_0.reset_src_s();
        #(5*CLK_PERIOD)
        @(posedge aclk);
        req_drv_in_0.send(512, 64'hffff);
    end
    
    initial begin
        req_drv_in_1.reset_src_s();
        #(8*CLK_PERIOD)
        @(posedge aclk);
        req_drv_in_1.send(256, 64'heeee); 
    end
    
    initial begin
        req_drv_in_2.reset_src_s();
        #(5*CLK_PERIOD)
        @(posedge aclk);
        req_drv_in_2.send(1024, 64'hdddd);
    end
    
    initial begin
        req_drv_out.reset_src_m();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        req_drv_out.recv();
        req_drv_out.recv();
        req_drv_out.recv();
        done = 1;
    end

endmodule