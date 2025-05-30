`timescale 1ns / 1ps

import lynxTypes::*;

`include "c_axisr.svh"
`include "c_axil.svh"
`include "c_meta.svh"

`include "transactions.svh"
`include "ctrl_simulation.svh"
`include "notify_simulation.svh"
`include "mem_mock.svh"
`include "generator.svh"
`include "scoreboard.svh"
`include "rdma_driver_simulation.svh"

module tb_user;
    bit RANDOMIZATION_ENABLED = 1; // Simulation parameter that can be set with set_value -radix bin /tb_user/RANDOMIZATION_ENABLED 1

    logic aclk = 1'b1;
    logic aresetn = 1'b0;

    string path_name;
    string input_file_name;
    string output_file_name;

    // Clock generation
    always #(CLK_PERIOD/2) aclk = ~aclk;

    ////
    // Mailboxes
    ////

    mailbox #(trs_ctrl)  ctrl_mbx = new();
    mailbox #(c_trs_ack) ack_mbx = new();

    // Host memory streams
    mailbox #(c_trs_req) host_recv_mbx[N_STRM_AXI];
    mailbox #(c_trs_req) host_send_mbx[N_STRM_AXI];

    // Card memory streams
    mailbox #(c_trs_req) card_recv_mbx[N_CARD_AXI];
    mailbox #(c_trs_req) card_send_mbx[N_CARD_AXI];

    // RDMA streams
    mailbox #(c_trs_req) rdma_rrsp_recv_mbx[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_rrsp_send_mbx[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_rreq_recv_mbx[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_rreq_send_mbx[N_RDMA_AXI];

    ////
    // Interfaces and drivers
    ////

    // AXI CSR
    AXI4L axi_ctrl (aclk);
    c_axil axi_ctrl_drv = new(axi_ctrl);
    ctrl_simulation ctrl_sim;

    // Notify
    metaIntf #(.STYPE(irq_not_t)) notify(aclk);
    c_meta #(.ST(irq_not_t)) notify_drv = new(notify, RANDOMIZATION_ENABLED);
    notify_simulation notify_sim;

    // Descriptors
    metaIntf #(.STYPE(req_t)) sq_rd(aclk);
    metaIntf #(.STYPE(req_t)) sq_wr(aclk);
    metaIntf #(.STYPE(ack_t)) cq_rd(aclk);
    metaIntf #(.STYPE(ack_t)) cq_wr(aclk);
    metaIntf #(.STYPE(req_t)) rq_rd(aclk);
    metaIntf #(.STYPE(req_t)) rq_wr(aclk);

    c_meta #(.ST(req_t)) sq_rd_mon = new(sq_rd, RANDOMIZATION_ENABLED);
    c_meta #(.ST(req_t)) sq_wr_mon = new(sq_wr, RANDOMIZATION_ENABLED);
    c_meta #(.ST(ack_t)) cq_rd_drv = new(cq_rd, RANDOMIZATION_ENABLED);
    c_meta #(.ST(ack_t)) cq_wr_drv = new(cq_wr, RANDOMIZATION_ENABLED);
    c_meta #(.ST(req_t)) rq_rd_drv = new(rq_rd, RANDOMIZATION_ENABLED);
    c_meta #(.ST(req_t)) rq_wr_drv = new(rq_wr, RANDOMIZATION_ENABLED);

    // Generator reading from input.bin
    generator gen;

    // Scoreboard writing to output.bin
    scoreboard scb;

    // Host
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_recv[N_STRM_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_send[N_STRM_AXI] (aclk);

    c_axisr host_recv_drv[N_STRM_AXI];
    c_axisr host_send_drv[N_STRM_AXI];

    mem_mock #(N_STRM_AXI) host_mem_mock;

    // Card
`ifdef EN_MEM
    AXI4SR axis_card_recv[N_CARD_AXI] (aclk);
    AXI4SR axis_card_send[N_CARD_AXI] (aclk);

    c_axisr card_recv_drv[N_CARD_AXI];
    c_axisr card_send_drv[N_CARD_AXI];

    mem_mock #(N_CARD_AXI) card_mem_mock;
`endif

    // RDMA
`ifdef EN_RDMA
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rreq_recv[N_RDMA_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rreq_send[N_RDMA_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rrsp_recv[N_RDMA_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rrsp_send[N_RDMA_AXI] (aclk);

    c_axisr rdma_rreq_recv_drv[N_RDMA_AXI];
    c_axisr rdma_rreq_send_drv[N_RDMA_AXI];
    c_axisr rdma_rrsp_recv_drv[N_RDMA_AXI];
    c_axisr rdma_rrsp_send_drv[N_RDMA_AXI];

    rdma_driver_simulation rdma_drv_sim;
`endif

`ifdef EN_TCP //TODO: TCP Simulation
    AXI4SR axis_tcp_recv [N_TCP_AXI] (aclk);
    AXI4SR axis_tcp_send [N_TCP_AXI] (aclk);
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

    task static env_threads();
        fork
            ctrl_sim.run();
            notify_sim.run();

            gen.run_sq_rd_recv();
            gen.run_sq_wr_recv();
            gen.run_gen();
            gen.run_ack();

            host_mem_mock.run();
        `ifdef EN_MEM
            card_mem_mock.run();
        `endif
        `ifdef EN_RDMA
            rdma_drv_sim.run_rreq_send(0);
            rdma_drv_sim.run_rreq_recv(0);
            rdma_drv_sim.run_rrsp_send(0);
            rdma_drv_sim.run_rrsp_recv(0);
        `endif
        join_none
    endtask


    task static env_done();
        fork
            wait(gen.done.triggered);
        join
    endtask

    initial begin
        // Reset generation
        aresetn = 1'b0;

        // Simulation files
        $dumpfile("dump.vcd"); $dumpvars;

        path_name = {BUILD_DIR, "/sim/"};

        input_file_name = {path_name, "input.bin"};
        output_file_name = {path_name, "output.bin"};

        // Scoreboard
        scb = new(output_file_name);

        // CTRL & Notify
        ctrl_sim = new(ctrl_mbx, axi_ctrl_drv, scb);
        notify_sim = new(notify_drv, scb);

        // Host memory
    `ifdef EN_STRM
        for (int i = 0; i < N_STRM_AXI; i++) begin
            host_recv_mbx[i] = new();
            host_send_mbx[i] = new();
            host_recv_drv[i] = new(axis_host_recv[0], RANDOMIZATION_ENABLED);
            host_send_drv[i] = new(axis_host_send[0], RANDOMIZATION_ENABLED);
        end
        
        host_mem_mock = new(
            "HOST",
            ack_mbx,
            host_recv_mbx,
            host_send_mbx,
            host_send_drv,
            host_recv_drv,
            scb
        );
    `endif

        // Card memory
    `ifdef EN_MEM
        for (int i = 0; i < N_CARD_AXI; i++) begin
            card_recv_mbx[i] = new();
            card_send_mbx[i] = new();
            card_send_drv[i] = new(axis_card_send[0], RANDOMIZATION_ENABLED);
            card_recv_drv[i] = new(axis_card_recv[0], RANDOMIZATION_ENABLED);
        end

        card_mem_mock = new(
            "CARD",
            ack_mbx,
            card_recv_mbx,
            card_send_mbx,
            card_send_drv,
            card_recv_drv,
            scb
        );
    `endif

        // RDMA
    `ifdef EN_RDMA
        rdma_rreq_recv_mbx[0] = new();
        rdma_rreq_send_mbx[0] = new();
        rdma_rrsp_recv_mbx[0] = new();
        rdma_rrsp_send_mbx[0] = new();

        rdma_rreq_recv_drv[0] = new(axis_rreq_recv[0]);
        rdma_rreq_send_drv[0] = new(axis_rreq_send[0]);
        rdma_rrsp_recv_drv[0] = new(axis_rrsp_recv[0]);
        rdma_rrsp_send_drv[0] = new(axis_rrsp_send[0]);

        rdma_drv_sim = new(
            ack_mbx,
            rdma_rreq_recv_mbx,
            rdma_rreq_send_mbx,
            rdma_rrsp_recv_mbx,
            rdma_rrsp_send_mbx,
            rdma_rreq_recv_drv,
            rdma_rreq_send_drv,
            rdma_rrsp_recv_drv,
            rdma_rrsp_send_drv
        );
    `endif

        // Generator
        gen = new(
            ctrl_mbx,
            ack_mbx,
            host_recv_mbx,
            host_send_mbx,
            card_recv_mbx,
            card_send_mbx,
            rdma_rreq_recv_mbx,
            rdma_rreq_send_mbx,
            rdma_rrsp_recv_mbx,
            rdma_rrsp_send_mbx,
            ctrl_sim.polling_done,
            host_mem_mock,
        `ifdef EN_MEM
            card_mem_mock,
        `endif
            sq_rd_mon,
            sq_wr_mon,
            cq_rd_drv,
            cq_wr_drv,
            rq_rd_drv,
            rq_wr_drv,
            input_file_name
        );

        // Reset of interfaces
        gen.initialize();

        ctrl_sim.initialize();
        notify_sim.initialize();
        host_mem_mock.initialize();
    `ifdef EN_MEM
        card_mem_mock.initialize();
    `endif
    `ifdef EN_RDMA
        rdma_drv_sim.initialize(path_name);
    `endif
        
        #(RST_PERIOD) aresetn = 1'b1;

        env_threads();
        env_done();

        for(int i = 0; i < 10; i++) begin
            #(CLK_PERIOD);
        end
        $display("Testbench finished!");

        // Close file descriptors
        scb.close();
    `ifdef EN_RDMA
        rdma_drv_sim.print_data();
    `endif

        $finish;
    end
endmodule
