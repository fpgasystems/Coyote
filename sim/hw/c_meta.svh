class c_meta #(
    parameter type ST = logic[63:0]
);
    localparam SEND_RAND_THRESHOLD = 5;
    localparam RECV_RAND_THRESHOLD = 10;

    // Interface handle;
    virtual metaIntf #(.STYPE(ST)) meta;

    // Constructor
    function new(virtual metaIntf #(.STYPE(ST)) meta);
        this.meta = meta;
    endfunction

    // Reset
    task reset_m;
        meta.cbm.valid <= 1'b0;
        meta.cbm.data  <= 0;
        `DEBUG(("reset_m() completed."))
    endtask

    task reset_s;
        meta.cbs.ready <= 1'b0;
        `DEBUG(("reset_s() completed."))
    endtask

    //
    // Drive
    //
    task send (
        input logic [$bits(ST)-1:0] data
    );
    `ifdef EN_RANDOMIZATION
        while ($urandom_range(0, 99) < SEND_RAND_THRESHOLD) begin @(meta.cbm); end
    `endif

        meta.cbm.data  <= data;
        meta.cbm.valid <= 1'b1;
        @(meta.cbm iff (meta.cbm.ready == 1'b1));
        meta.cbm.valid <= 1'b0;

        `DEBUG(("send() completed. Data: %x", data))
    endtask

    //
    // Receive
    //
    task recv (
        output logic [$bits(ST)-1:0] data
    );
    `ifdef EN_RANDOMIZATION
        while ($urandom_range(0, 99) < SEND_RAND_THRESHOLD) begin @(meta.cbs); end
    `endif

        meta.cbs.ready <= 1'b1;
        @(meta.cbs iff (meta.cbs.valid == 1'b1));
        meta.cbs.ready <= 1'b0;

        `DEBUG(("recv() completed. Data: %x", meta.cbs.data))
        data = meta.cbs.data;
    endtask

endclass