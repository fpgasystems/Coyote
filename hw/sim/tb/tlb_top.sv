import lynxTypes::*;
import lynxSimTypes::*;
import axiSimTypes::*;

module tlb_top_tb;

    // ----------------------------------------------------------------
    // -- Clock and reset
    // ----------------------------------------------------------------
    logic done = 0;
    
    localparam CLK_PERIOD = 5ns;

    logic aclk = 1'b0;
    logic aresetn = 1'b1;

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

    // ----------------------------------------------------------------
    // -- DUT
    // ----------------------------------------------------------------

    // Control
    AXI4L axi_ctrl_lTlb [N_REGIONS] (aclk);
    AXI4L axi_ctrl_sTlb [N_REGIONS] (aclk);
    AXI4L axi_ctrl_cnfg [N_REGIONS] (aclk);
    
    // Requests
    reqIntf rd_req_user [N_REGIONS] (aclk);
    reqIntf wr_req_user [N_REGIONS] (aclk);

    // DMAs
    dmaIntf rdXDMA_host (aclk);
    dmaIntf wrXDMA_host (aclk);
    
    // Drivers
    axiSimTypes::AXI4Ldrv axil_drv_lTlb = new(axi_ctrl_lTlb[0], 0);
    axiSimTypes::AXI4Ldrv axil_drv_sTlb = new(axi_ctrl_sTlb[0], 1);
    axiSimTypes::AXI4Ldrv axil_drv_cnfg = new(axi_ctrl_cnfg[0], 2);
    
    lynxSimTypes::REQdrv req_drv_rd = new(rd_req_user[0], 3);
    lynxSimTypes::REQdrv req_drv_wr = new(wr_req_user[0], 4);
    
    lynxSimTypes::DMAdrv dma_drv_rd_xdma_host = new(rdXDMA_host, 5);
    lynxSimTypes::DMAdrv dma_drv_wr_xdma_host = new(wrXDMA_host, 6);

    logic [N_REGIONS-1:0] rxfer_host;
    logic [N_REGIONS-1:0] wxfer_host;

    // DUT
    tlb_top inst_DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .axi_ctrl_lTlb(axi_ctrl_lTlb),
        .axi_ctrl_sTlb(axi_ctrl_sTlb),
        .axi_ctrl_cnfg(axi_ctrl_cnfg),
        .rd_req_user(rd_req_user),
        .wr_req_user(wr_req_user),
        .rdXDMA_host(rdXDMA_host),
        .wrXDMA_host(wrXDMA_host),
        .rxfer_host(rxfer_host),
        .wxfer_host(wxfer_host),
        .decouple(),
        .pf_irq()
    );

    // ----------------------------------------------------------------
    // -- Sim
    // ----------------------------------------------------------------
    
    // TLB entries
    initial begin
        axil_drv_sTlb.reset_m();
        #(80*CLK_PERIOD)
        @(posedge aclk);
        // Write to stlb host
        axil_drv_sTlb.write(64'h10, 64'h8000_0000_4000_0056);
        #(2*CLK_PERIOD);
        // Write to stlb card
        axil_drv_sTlb.write(64'h2010, 64'hC000_0000_4000_0010);
    end
    
    initial begin
        axil_drv_lTlb.reset_m();
    end
    
    // Config
    initial begin
        axil_drv_cnfg.reset_m();
        #(5*CLK_PERIOD)
        @(posedge aclk);
        // Change DP
        axil_drv_cnfg.write(64'h50, 64'h2);
        #(90*CLK_PERIOD);
        axil_drv_cnfg.write(64'h00, 64'h4);
    end
    
    // User requests RD
    initial begin
        // Hit small read
        req_drv_rd.reset_m();
        #(20*CLK_PERIOD)
        @(posedge aclk);
        req_drv_rd.send(64'h200, 64'h1002010, 1'b0, 1'b1, 1'b1);
        // Hit small read sync
        //#(10*CLK_PERIOD)
        //@(posedge aclk);
        //req_drv_rd.send(64'h200, 64'h1002010, 1'b1);
    end
    
    // User requests wR
    initial begin
        req_drv_wr.reset_m();
        // Hit small sync write
        //#(50*CLK_PERIOD)
        //@(posedge aclk);
        //req_drv_wr.send(64'h200, 64'h1002010, 1'b1);
    end
    
    // DMAs HOST
    initial begin
        dma_drv_rd_xdma_host.reset_s();  
        #(50*CLK_PERIOD)
        @(posedge aclk);
        dma_drv_rd_xdma_host.recv_dma();
        #(70*CLK_PERIOD);
        @(posedge aclk);
        dma_drv_rd_xdma_host.send_done(); 
    end
    
    initial begin
        dma_drv_wr_xdma_host.reset_s(); 
        /*
        #(50*CLK_PERIOD)
        @(posedge aclk);
        dma_drv_wr_xdma_sync.recv_dma();
        #(100*CLK_PERIOD);
        @(posedge aclk);
        dma_drv_wr_xdma_sync.send_done(); 
        */
    end

endmodule