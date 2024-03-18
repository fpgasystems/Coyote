class c_meta #(
    parameter type ST = logic[63:0]
);

    // Interface handle;
    virtual metaIntf #(.STYPE(ST)) meta;

    // Constructor
    function new(virtual metaIntf #(.STYPE(ST)) meta);
        this.meta = meta;
    endfunction

    // Cycle start
    task cycle_start;
        #TT;
    endtask

    // Cycle wait
    task cycle_wait;
        @(posedge meta.aclk);
    endtask
    
    task cycle_n_wait(input integer n_cyc);
        for(int i = 0; i < n_cyc; i++) cycle_wait();
    endtask

    // Reset
    task reset_m;
        meta.valid <= 1'b0;
        meta.data <= 0;
        $display("META reset_m() completed.");
    endtask

    task reset_s;
        meta.ready <= 1'b0;
        $display("META reset_s() completed.");
    endtask

    //
    // Drive
    //
    task send (
        input logic [$bits(ST)-1:0] data
    );
        meta.data   <= #TA data;
        meta.valid  <= #TA 1'b1;
        cycle_start();
        while(meta.ready != 1'b1) begin cycle_wait(); cycle_start(); end
        cycle_wait();
        meta.valid  <= #TA 1'b0;
        $display("META send() completed. Data: %x", meta.data);
    endtask

    // 
    // Receive
    //
    task recv ();
        meta.ready <= #TA 1'b1;
        cycle_start();
        while(meta.valid != 1'b1) begin cycle_wait(); cycle_start(); end 
        cycle_wait();  
        meta.ready <= #TA 1'b0;
        $display("META recv() completed. Data: %x", meta.data);
    endtask

endclass