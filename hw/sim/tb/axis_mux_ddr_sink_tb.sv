import lynxTypes::*;

module axis_mux_ddr_sink_tb;

    localparam CLK_PERIOD = 5ns;

    logic aclk = 1'b0;
    logic aresetn = 1'b1;

    logic done = 0;

    // Sink
    AXI4S #(.AXI4S_DATA_BITS(512)) axis_in_host (aclk);
    AXI4S #(.AXI4S_DATA_BITS(512)) axis_in_card (aclk);
    AXI4S #(.AXI4S_DATA_BITS(512)) axis_out (aclk);

    // Memory subsystem
    muxCardIntf mux_sink ();
    
    // Drivers
    axiSimTypes::AXI4Sdrv #(.AXIS_DATA_BITS(512)) axis_drv_host = new(axis_in_host, 1);
    axiSimTypes::AXI4Sdrv #(.AXIS_DATA_BITS(512)) axis_drv_card = new(axis_in_card, 2);
    axiSimTypes::AXI4Sdrv axis_drv_out = new(axis_out, 3);

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

    // DUTs
    axis_mux_ddr_sink inst_DUT_sink (
        .aclk(aclk),
        .aresetn(aresetn),
        .mux(mux_sink),
        .axis_in_host(axis_in_host),
        .axis_in_card(axis_in_card),
        .axis_out(axis_out)
    );

    logic mux_load_sink;
    logic mux_load_card_sink;
    logic [N_REGIONS_BITS-1:0] mux_load_id_sink;
    logic [LEN_BITS-1:0] mux_load_len_sink;

    // Memory subsystem queues
	queue #(
		.QTYPE(logic[1+N_REGIONS_BITS+LEN_BITS-1:0])
    ) inst_mux_que_sink (
		.aclk(aclk),
		.aresetn(aresetn),
		.val_snk(mux_load_sink),
		.rdy_snk(),
		.data_snk({mux_load_card_sink, mux_load_id_sink, mux_load_len_sink}),
		.val_src(mux_sink.valid),
		.rdy_src(mux_sink.ready),
		.data_src({mux_sink.card, mux_sink.id_in, mux_sink.len})
	);

    /* Sink */
    initial begin 
        mux_load_sink = 1'b0;
        mux_load_card_sink = 1'b0;
        mux_load_id_sink = 0;
        mux_load_len_sink = 0;
        #(2*CLK_PERIOD)
        mux_load_sink = 1'b1;
        mux_load_card_sink = 1'b1;
        mux_load_id_sink = 2;
        mux_load_len_sink = 28'h180;
        #(CLK_PERIOD)
        mux_load_id_sink = 1'b1;
        mux_load_card_sink = 1'b0;
        mux_load_len_sink = 28'h200;
        #(CLK_PERIOD)
        mux_load_sink = 1'b0;
    end
    
    /* Card */
    initial begin
        axis_drv_card.reset_m();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_card.send(44, 6);
    end

    /* Host */
    initial begin
        axis_drv_host.reset_m();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_host.send(33, 8);
    end

    /* Out */
    initial begin
        axis_drv_out.reset_s();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_out.recv(6);
        axis_drv_out.recv(8);
        done = 1;
    end

endmodule