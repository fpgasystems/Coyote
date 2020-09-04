import lynxTypes::*;

module tb_user;

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
        #CLK_PERIOD aresetn = 1;
    end

    // Interfaces
    AXI4L axi_ctrl (aclk);
    AXI4S axis_host_src (aclk);
    AXI4S axis_host_sink (aclk);
    AXI4S axis_rdma_src (aclk);
    AXI4S axis_rdma_sink (aclk);
    reqIntf rd_req_user (aclk);
    reqIntf wr_req_user (aclk);
    reqIntf rd_req_rdma (aclk);
    reqIntf wr_req_rdma (aclk);
    metaIntf #(.DATA_BITS(256)) fv_sink (aclk);
    metaIntf #(.DATA_BITS(256)) fv_src (aclk);
    
    // Drivers
    axiSimTypes::AXI4Ldrv axi_drv_ctrl = new(axi_ctrl, 0);
    axiSimTypes::AXI4Sdrv axis_drv_host_src = new(axis_host_src, 1);
    axiSimTypes::AXI4Sdrv axis_drv_host_sink = new(axis_host_sink, 2);
    axiSimTypes::AXI4Sdrv axis_drv_rdma_src = new(axis_rdma_src, 3);
    axiSimTypes::AXI4Sdrv axis_drv_rdma_sink = new(axis_rdma_sink, 4);
    lynxSimTypes::REQdrv req_drv_rd_user = new(rd_req_user, 5);
    lynxSimTypes::REQdrv req_drv_wr_user = new(wr_req_user, 6);
    lynxSimTypes::REQdrv req_drv_rd_rdma = new(rd_req_rdma, 7);
    lynxSimTypes::REQdrv req_drv_wr_rdma = new(wr_req_rdma, 8);
    lynxSimTypes::METAdrv #(.DB(256)) meta_drv_fv_sink = new(fv_sink, 9);
    lynxSimTypes::METAdrv #(.DB(256)) meta_drv_fv_src = new(fv_src, 10);

    // DUT
    design_user_logic_0 inst_DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .axi_ctrl(axi_ctrl),
        .fv_sink(fv_sink),
        .fv_src(fv_src),
        .rd_req_user(rd_req_user),
        .wr_req_user(wr_req_user),
        .rd_req_rdma(rd_req_rdma),
        .wr_req_rdma(wr_req_rdma),
        .axis_host_sink(axis_host_sink),
        .axis_host_src(axis_host_src),
        .axis_rdma_sink(axis_rdma_sink),
        .axis_rdma_src(axis_rdma_src)
    );

    // DRIVER -------------------------------------------------------------------------------
    
    // Control
    initial begin
        axi_drv_ctrl.reset_m();
    end
    
    // USER requests
    initial begin
        req_drv_rd_user.reset_s();
    end
    
    initial begin
        req_drv_wr_user.reset_s();
    end
    
    // RDMA requests
    initial begin
        req_drv_rd_rdma.reset_m();
    end
    
    initial begin
        req_drv_wr_rdma.reset_m();
    end
    
    // FARVIEW requests
    initial begin
        meta_drv_fv_sink.reset_m();
    end
    
    initial begin
        meta_drv_fv_src.reset_s();
    end
    
    // HOST data
    initial begin
        axis_drv_host_sink.reset_m();
    end
    
    initial begin
        axis_drv_host_src.reset_s();
    end
    
    // RDMA data
    initial begin
        axis_drv_rdma_sink.reset_m();
    end
    
    initial begin
        axis_drv_rdma_src.reset_s();
    end
    

endmodule