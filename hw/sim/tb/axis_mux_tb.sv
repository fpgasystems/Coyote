import lynxTypes::*;

module axis_mux_tb;

    localparam CLK_PERIOD = 5ns;

    logic aclk = 1'b0;
    logic aresetn = 1'b1;

    logic done_sink = 0;
    logic done_src = 0;

    // Sink
    AXI4S axis_sink_in [N_REGIONS] (aclk);
    AXI4S axis_sink_out (aclk);
    
    // Source
    AXI4S axis_src_in (aclk);
    AXI4S axis_src_out [N_REGIONS] (aclk);

    // Decoupler
    AXI4S axis_dcplr [N_REGIONS] (aclk);
    
    logic [N_REGIONS-1:0] decouple = 0;

    // Memory subsystem
    muxIntf mux_sink ();
    muxIntf mux_src ();
    
    // Drivers
    axiSimTypes::AXI4Sdrv axis_drv_sink_out = new(axis_sink_out, 1);
    axiSimTypes::AXI4Sdrv axis_drv_src_in = new(axis_src_in, 2);

    // Clock gen
    initial begin
        while (!done_sink || !done_src) begin
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
    axis_mux_sink inst_DUT_sink (
        .aclk(aclk),
        .aresetn(aresetn),
        .mux(mux_sink),
        .axis_in(axis_sink_in),
        .axis_out(axis_sink_out)
    );
    
    axis_mux_src inst_DUT_src (
        .aclk(aclk),
        .aresetn(aresetn),
        .mux(mux_src),
        .axis_in(axis_src_in),
        .axis_out(axis_src_out)
    );

    axis_decoupler inst_DUT_dcplr_sink (
        .aclk(aclk),
        .aresetn(aresetn),
        .decouple(decouple),
        .axis_in(axis_dcplr),
        .axis_out(axis_sink_in)
    );

    axis_decoupler inst_DUT_dcplr_src (
        .aclk(aclk),
        .aresetn(aresetn),
        .decouple(decouple),
        .axis_in(axis_src_out),
        .axis_out(axis_dcplr)
    );

    logic mux_load_sink, mux_load_src;
    logic [N_REGIONS_BITS-1:0] mux_load_id_sink, mux_load_id_src;
    logic [LEN_BITS-1:0] mux_load_len_sink, mux_load_len_src;

    // Memory subsystem queues
	queue #(
		.QTYPE(logic[N_REGIONS_BITS+LEN_BITS-1:0])
    ) inst_mux_que_sink (
		.aclk(aclk),
		.aresetn(aresetn),
		.val_snk(mux_load_sink),
		.rdy_snk(),
		.data_snk({mux_load_id_sink, mux_load_len_sink}),
		.val_src(mux_sink.valid),
		.rdy_src(mux_sink.ready),
		.data_src({mux_sink.id_in, mux_sink.len})
	);

    queue #(
		.QTYPE(logic[N_REGIONS_BITS+LEN_BITS-1:0])
    ) inst_mux_que_src (
		.aclk(aclk),
		.aresetn(aresetn),
		.val_snk(mux_load_src),
		.rdy_snk(),
		.data_snk({mux_load_id_src, mux_load_len_src}),
		.val_src(mux_src.valid),
		.rdy_src(mux_src.ready),
		.data_src({mux_src.id_in, mux_src.len})
	);


    /* Sink */
    initial begin 
        mux_load_sink = 1'b0;
        mux_load_id_sink = 0;
        mux_load_len_sink = 0;
        #(2*CLK_PERIOD)
        mux_load_sink = 1'b1;
        mux_load_id_sink = 2;
        mux_load_len_sink = 28'h180;
        #(CLK_PERIOD)
        mux_load_id_sink = 1;
        mux_load_len_sink = 28'h1C0;
        #(CLK_PERIOD)
        mux_load_id_sink = 0;
        mux_load_len_sink = 28'hC0;
        #(CLK_PERIOD)
        mux_load_sink = 1'b0;
    end
    
    initial begin
        axis_drv_sink_out.reset_s();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_sink_out.recv(6);
        axis_drv_sink_out.recv(7);
        axis_drv_sink_out.recv(3);
        done_sink = 1;
    end
    
    /* Source */
    initial begin 
        mux_load_src = 1'b0;
        mux_load_id_src = 0;
        mux_load_len_src = 0;
        #(2*CLK_PERIOD)
        mux_load_src = 1'b1;
        mux_load_id_src = 2;
        mux_load_len_src = 28'h180;
        #(CLK_PERIOD)
        mux_load_id_src = 1;
        mux_load_len_src = 28'h1C0;
        #(CLK_PERIOD)
        mux_load_id_src = 0;
        mux_load_len_src = 28'hC0;
        #(CLK_PERIOD)
        mux_load_src = 1'b0;
    end
    
    initial begin
        axis_drv_src_in.reset_m();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_src_in.send(0, 64'hffffffffffffffff, 6);
        axis_drv_src_in.send(0, 64'hffffffffffffffff, 7);
        axis_drv_src_in.send(0, 64'hffffffffffffffff, 3);
        done_src = 1;
    end


endmodule