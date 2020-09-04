import lynxTypes::*;

module tb_cdma_unaglined;

    localparam CLK_PERIOD = 5ns;

    logic aclk = 1'b0;
    logic aresetn = 1'b1;

    logic done = 0;

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
        #(2*CLK_PERIOD) aresetn = 1;
    end

    // Signals
    dmaIntf rdCDMA (aclk);
    dmaIntf wrCDMA (aclk);

    AXI4 axi_ddr_in (aclk);
    AXI4S axis_ddr_in (aclk);
    AXI4S axis_ddr_out (aclk);

    // Drivers
    lynxSimTypes::DMAdrv dma_drv_rd = new(rdCDMA, 0);
    lynxSimTypes::DMAdrv dma_drv_wr = new(wrCDMA, 1);

    axiSimTypes::AXI4drv axi_drv_ddr_in = new(axi_ddr_in, 2);
    axiSimTypes::AXI4Sdrv axis_drv_ddr_in = new(axis_ddr_in, 3);
    axiSimTypes::AXI4Sdrv axis_drv_ddr_out = new(axis_ddr_out, 4);

    // DUT
    cdma_unaglined inst_DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .rdCDMA(rdCDMA),
        .wrCDMA(wrCDMA),
        .axi_ddr_in(axi_ddr_in),
        .axis_ddr_in(axis_ddr_in),
        .axis_ddr_out(axis_ddr_out)
    );

    // DRIVER -------------------------------------------------------------------------------

    // DMA drive
    initial begin
        dma_drv_rd.reset_m();
        #(10*CLK_PERIOD)
        @(posedge aclk);
        dma_drv_rd.send_dma(8, 68, 1'b1);
    end

    initial begin
        dma_drv_wr.reset_m();
        #(10*CLK_PERIOD)
        @(posedge aclk);
    end

    // AXI sink
    initial begin
        axi_drv_ddr_in.reset_s();
        #(50*CLK_PERIOD)
        @(posedge aclk);
        axi_drv_ddr_in.read_ar();
        #(20*CLK_PERIOD)
        @(posedge aclk);
        for(int i = 0; i < 10; i++) begin
            axi_drv_ddr_in.write_r($urandom_range(0, 1000), 0);
        end
    end

    // AXIS 
    initial begin
        axis_drv_ddr_in.reset_m();
    end

    initial begin
        axis_drv_ddr_out.reset_s();
        #(70*CLK_PERIOD)
        @(posedge aclk);
        axis_drv_ddr_out.recv(10);
    end

endmodule