import lynxTypes::*;

module axis_mux_ddr_src_wide_tb;

    localparam CLK_PERIOD = 5ns;

    logic aclk = 1'b0;
    logic aresetn = 1'b1;

    logic done_0 = 0;
    logic done_1 = 0;

    // src
    AXI4S #(.AXI4S_DATA_BITS(512)) axis_out_host (aclk);
    AXI4S #(.AXI4S_DATA_BITS(1024)) axis_out_card (aclk);
    AXI4S  #(.AXI4S_DATA_BITS(512)) axis_in [2] (aclk);

    // Memory subsystem
    muxCardIntf mux_src ();
    
    // Drivers
    axiSimTypes::AXI4Sdrv #(.AXIS_DATA_BITS(512)) axis_drv_host = new(axis_out_host, 1);
    axiSimTypes::AXI4Sdrv #(.AXIS_DATA_BITS(1024)) axis_drv_card = new(axis_out_card, 2);
    axiSimTypes::AXI4Sdrv axis_in_0 = new(axis_in[0], 3);
    axiSimTypes::AXI4Sdrv axis_in_1 = new(axis_in[1], 4);

    // Clock gen
    initial begin
        while (!done_0 || !done_1) begin
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
    axis_mux_ddr_src_wide inst_DUT_src (
        .aclk(aclk),
        .aresetn(aresetn),
        .mux(mux_src),
        .axis_in(axis_in),
        .axis_out_host(axis_out_host),
        .axis_out_card(axis_out_card)
    );

    logic mux_load_src;
    logic mux_load_card_src;
    logic [N_REGIONS_BITS-1:0] mux_load_id_src;
    logic [LEN_BITS-1:0] mux_load_len_src;

    // Memory subsystem queues
	queue #(
		.QTYPE(logic[1+N_REGIONS_BITS+LEN_BITS-1:0])
    ) inst_mux_que_src (
		.aclk(aclk),
		.aresetn(aresetn),
		.val_snk(mux_load_src),
		.rdy_snk(),
		.data_snk({mux_load_card_src, mux_load_id_src, mux_load_len_src}),
		.val_src(mux_src.valid),
		.rdy_src(mux_src.ready),
		.data_src({mux_src.card, mux_src.id_in, mux_src.len})
	);

    /* src */
    initial begin 
        mux_load_src = 1'b0;
        mux_load_card_src = 1'b0;
        mux_load_id_src = 0;
        mux_load_len_src = 0;
        #(2*CLK_PERIOD)
        mux_load_src = 1'b1;
        mux_load_card_src = 1'b1;
        mux_load_id_src = 2;
        mux_load_len_src = 28'h180;
        #(CLK_PERIOD)
        mux_load_id_src = 1'b1;
        mux_load_card_src = 1'b0;
        mux_load_len_src = 28'h200;
        #(CLK_PERIOD)
        mux_load_src = 1'b0;
    end
    
    /* Host */
    initial begin
        axis_drv_host.reset_s();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_host.recv(8);
        done_0 = 0;
    end

    /* Card */
    initial begin
        axis_drv_card.reset_s();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_card.recv(3);
        done_1 = 1;
    end

    /* Out 0 */
    initial begin
        axis_in_0.reset_m();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_in_0.send(33, 3);
        axis_in_0.send(100, 4);
    end

    /* Out 1 */
    initial begin
        axis_in_1.reset_s();
        #(4*CLK_PERIOD)
        @(posedge aclk);
        axis_in_1.send(44, 3);
        axis_in_1.send(200, 4);
    end

endmodule