class c_meta #(
    parameter type ST = logic[63:0]
);
    localparam SEND_RAND_THRESHOLD = 5;
    localparam RECV_RAND_THRESHOLD = 10;
    bit RANDOMIZATION_ENABLED;

    // Interface handle;
    virtual metaIntf #(.STYPE(ST)) meta;

    // Constructor
    function new(virtual metaIntf #(.STYPE(ST)) meta, input bit RANDOMIZATION_ENABLED);
        this.RANDOMIZATION_ENABLED = RANDOMIZATION_ENABLED;
        this.meta = meta;
    endfunction

    // Reset
    task reset_m;
        meta.cbm.valid <= 1'b0;
        meta.cbm.data  <= 0;
        $display("META reset_m() completed.");
    endtask

    task reset_s;
        meta.cbs.ready <= 1'b0;
        $display("META reset_s() completed.");
    endtask

    //
    // Drive
    //
    task send (
        input logic [$bits(ST)-1:0] data
    );
        while (RANDOMIZATION_ENABLED && $urandom_range(0, 99) < SEND_RAND_THRESHOLD) begin @(meta.cbm); end

        meta.cbm.data  <= data;
        meta.cbm.valid <= 1'b1;
        @(meta.cbm);
        while(meta.cbm.ready != 1'b1) begin @(meta.cbm); end
        meta.cbm.valid <= 1'b0;

        $display("META send() completed. Data: %x", data);
    endtask

    //
    // Receive
    //
    task recv (
        output logic [$bits(ST)-1:0] data
    ); 
        while (RANDOMIZATION_ENABLED && $urandom_range(0, 99) < SEND_RAND_THRESHOLD) begin @(meta.cbs); end

        meta.cbs.ready <= 1'b1;
        @(meta.cbs);
        while(meta.cbs.valid != 1'b1) begin @(meta.cbs); end
        meta.cbs.ready <= 1'b0;

        $display("META recv() completed. Data: %x", meta.cbs.data);
        data = meta.cbs.data;
    endtask

endclass