`timescale 1ns / 1ps

import lynxTypes::*;
import simTypes::*;

`include "c_axis.svh"
`include "c_axil.svh"
`include "c_meta.svh"
`include "c_env.svh"

task delay(input integer n_clk_prds);
    #(n_clk_prds*CLK_PERIOD);
endtask

module tb_user;

    c_struct_t params = { 16 };

    logic aclk = 1'b1;
    logic aresetn = 1'b0;

    //clock generation
    always #(CLK_PERIOD/2) aclk = ~aclk;
    
    //reset Generation
    initial begin
        aresetn = 1'b0;
        #(RST_PERIOD) aresetn = 1'b1;
    end

    // Interfaces and drivers

    // AXI CSR
    AXI4L axi_ctrl (aclk);
    
    c_axil axi_ctrl_drv = new(axi_ctrl);
    
    // Notify
    metaIntf #(.STYPE(irq_not_t)) notify (aclk);
    
    c_meta #(.ST(irq_not_t)) notify_drv = new(notify);

    // Descriptors
    metaIntf #(.STYPE(req_t)) sq_rd (aclk);
    metaIntf #(.STYPE(req_t)) sq_wr (aclk);
    metaIntf #(.STYPE(ack_t)) cq_rd (aclk);
    metaIntf #(.STYPE(ack_t)) cq_wr (aclk);

    c_meta #(.ST(req_t)) sq_rd_drv = new(sq_rd);
    c_meta #(.ST(req_t)) sq_wr_drv = new(sq_wr);
    c_meta #(.ST(ack_t)) cq_rd_drv = new(cq_rd);
    c_meta #(.ST(ack_t)) cq_wr_drv = new(cq_wr);

`ifdef EN_RDMA
    metaIntf #(.STYPE(req_t)) rq_rd (aclk);

    c_meta #(.ST(req_t)) rq_rd_drv = new(rq_rd);
`endif
`ifdef EN_NET
    metaIntf #(.STYPE(req_t)) rq_wr (aclk);

    c_meta #(.ST(req_t)) rq_wr_drv = new(rq_wr);
`endif

    // Host
`ifdef EN_STRM
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_recv [N_STRM_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_send [N_STRM_AXI] (aclk);

    c_env axis_host_drv[N_STRM_AXI];
    
    for(genvar i = 0; i < N_STRM_AXI; i++) begin
        initial begin
            axis_host_drv[i] = new(axis_host_recv[i], axis_host_send[i], params, "HOST_STREAM");
        end
    end
`endif
`ifdef EN_MEM
    AXI4SR axis_card_recv [N_CARD_AXI] (aclk);
    AXI4SR axis_card_send [N_CARD_AXI] (aclk);

    c_env axis_card_drv [N_CARD_AXI];
    
    for(genvar i = 0; i < N_CARD_AXI; i++) begin
        initial begin
            axis_card_drv[i] = new(axis_card_recv[i], axis_card_send[i], params, "CARD_STREAM");
        end
    end
`endif
`ifdef EN_RDMA
    AXI4SR axis_rreq_recv [N_RDMA_AXI] (aclk);
    AXI4SR axis_rreq_send [N_RDMA_AXI] (aclk);
    AXI4SR axis_rrsp_recv [N_RDMA_AXI] (aclk);
    AXI4SR axis_rrsp_send [N_RDMA_AXI] (aclk);

    c_env axis_rreq_drv [N_RDMA_AXI];
    c_env axis_rrsp_drv [N_RDMA_AXI];
    
    for(genvar i = 0; i < N_RDMA_AXI; i++) begin
        initial begin
            axis_rreq_drv[i] = new(axis_rreq_recv[i], axis_rreq_send[i], params, "RREQ_STREAM");
            axis_rrsp_drv[i] = new(axis_rrsp_recv[i], axis_rrsp_send[i], params, "RRSP_STREAM");
        end
    end
`endif
`ifdef EN_TCP
    AXI4SR axis_tcp_recv [N_TCP_AXI] (aclk);
    AXI4SR axis_tcp_send [N_TCP_AXI] (aclk);

    c_env axis_tcp_drv [N_TCP_AXI];

    for(genvar i = 0; i < N_TCP_AXI; i++) begin
        initial begin
            axis_tcp_drv[i] = new(axis_tcp_recv[i], axis_tcp_send[i], params, "TCP_STREAM");
        end
    end
`endif

    //
    // DUT
    //
    design_user_logic_c0_0 inst_DUT (
        .axi_ctrl(axi_ctrl),
        .notify(notify),
        .sq_rd(sq_rd),
        .sq_wr(sq_wr),
        .cq_rd(cq_rd),
        .cq_wr(cq_wr),
    `ifdef EN_RDMA
        .rq_rd(rq_rd),
    `endif
    `ifdef EN_NET
        .rq_wr(rq_wr),
    `endif
    `ifdef EN_STRM
        .axis_host_recv(axis_host_recv),
        .axis_host_send(axis_host_send),
    `endif
    `ifdef EN_MEM
        .axis_card_recv(axis_card_recv),
        .axis_card_send(axis_card_send),
    `endif
    `ifdef EN_RDMA
        .axis_rreq_recv(axis_rreq_recv),
        .axis_rreq_send(axis_rreq_send),
        .axis_rrsp_recv(axis_rrsp_recv),
        .axis_rrsp_send(axis_rrsp_send),
    `endif
    `ifdef EN_TCP
        .axis_tcp_recv(axis_tcp_recv),
        .axis_tcp_send(axis_tcp_send),
    `endif
        .aclk(aclk),
        .aresetn(aresetn)
    );


    // Stream threads
    task env_threads();
        fork
    `ifdef EN_STRM
        for(int i = 0; i < N_STRM_AXI; i++) begin
            axis_host_drv[i].run();
        end
    `endif
    `ifdef EN_MEM
        for(int i = 0; i < N_CARD_AXI; i++) begin
            axis_card_drv[i].run();
        end
    `endif
    `ifdef EN_RDMA
        for(int i = 0; i < N_RDMA_AXI; i++) begin
            axis_rreq_drv[i].run();
            axis_rrsp_drv[i].run();
        end
    `endif
    `ifdef EN_TCP
        for(int i = 0; i < N_TCP_AXI; i++) begin
            axis_tcp_drv[i].run();
        end
    `endif
        join_any
    endtask
    
    // Stream completion
    task env_done();
    `ifdef EN_STRM
        for(int i = 0; i < N_STRM_AXI; i++) begin
            wait(axis_host_drv[i].done.triggered);
        end
    `endif
    `ifdef EN_MEM
        for(int i = 0; i < N_CARD_AXI; i++) begin
            wait(axis_card_drv[i].done.triggered);
        end
    `endif
    `ifdef EN_RDMA
        for(int i = 0; i < N_RDMA_AXI; i++) begin
            wait(axis_rreq_drv[i].done.triggered);
            wait(axis_rrsp_drv[i].done.triggered);
        end
    `endif
    `ifdef EN_TCP
        for(int i = 0; i < N_TCP_AXI; i++) begin
            wait(axis_tcp_drv[i].done.triggered);
        end
    `endif
    endtask
    
    // 
    initial begin
        env_threads();
        env_done();
        $display("All stream runs completed");
        $finish;
    end

    // AXIL control
    initial begin
        axi_ctrl_drv.reset_m();
    end
    
    // Notify
    initial begin
        notify_drv.reset_s();
    end
    
    // Descriptors
    initial begin
        sq_rd_drv.reset_s();
        sq_wr_drv.reset_s();
        cq_rd_drv.reset_m();
        cq_wr_drv.reset_m();
    `ifdef EN_RDMA
        rq_rd_drv.reset_m();
    `endif
    `ifdef EN_NET
        rq_wr_drv.reset_m();
    `endif
    end

    // Dump
    initial begin
        $dumpfile("dump.vcd"); $dumpvars;
    end

endmodule