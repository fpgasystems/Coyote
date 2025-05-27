`timescale 1ns / 1ps

import lynxTypes::*;

`include "c_axisr.svh"
`include "c_axil.svh"
`include "c_meta.svh"
`include "c_trs.svh"

`include "ctrl_simulation.svh"
`include "notify_simulation.svh"
`include "mem_mock.svh"
`include "generator.svh"
`include "scoreboard.svh"
`include "rdma_driver_simulation.svh"

task static delay(input integer n_clk_prds);
    #(n_clk_prds*CLK_PERIOD);
endtask

// From a full path get the prefix to just the Coyote root directory, used to pass filenames of mem_segments
function string get_path_from_file(string fullpath_filename);
    int i;
    int str_index;
    string ret;
    
    ret = "";

    for (i = fullpath_filename.len()-4; i>0; i=i-1) begin
        if (fullpath_filename.substr(i, i+3) == "/sim") begin
            str_index=i;
            break;
        end
    end
    
    ret=fullpath_filename.substr(0,str_index);  
    return ret;
endfunction

module tb_user;
    logic aclk = 1'b1;
    logic aresetn = 1'b0;

    string path_name;
    string input_sock_name;
    string output_sock_name;

    // Clock generation
    always #(CLK_PERIOD/2) aclk = ~aclk;

    ////
    // Mailboxes
    ////

    mailbox ctrl_mbx = new();
    mailbox mail_ack = new();

    // Host memory streams
    mailbox host_drv_strm_rd[N_STRM_AXI];
    mailbox host_drv_strm_wr[N_STRM_AXI];

    // RDMA streams
    mailbox rdma_rrsp_recv_mbx[N_RDMA_AXI];
    mailbox rdma_rrsp_send_mbx[N_RDMA_AXI];
    mailbox rdma_rreq_recv_mbx[N_RDMA_AXI];
    mailbox rdma_rreq_send_mbx[N_RDMA_AXI];

    // Card memory streams
    mailbox card_drv_strm_rd[N_CARD_AXI];
    mailbox card_drv_strm_wr[N_CARD_AXI];

    // TODO: TCP streams

    ////
    // Interfaces and drivers
    ////

    // AXI CSR
    AXI4L axi_ctrl (aclk);
    c_axil axi_ctrl_drv = new(axi_ctrl);
    ctrl_simulation ctrl_sim;

    // Notify
    metaIntf #(.STYPE(irq_not_t)) notify(aclk);
    c_meta #(.ST(irq_not_t)) notify_drv = new(notify);
    notify_simulation notify_sim;

    // Descriptors
    metaIntf #(.STYPE(req_t)) sq_rd(aclk);
    metaIntf #(.STYPE(req_t)) sq_wr(aclk);
    metaIntf #(.STYPE(ack_t)) cq_rd(aclk);
    metaIntf #(.STYPE(ack_t)) cq_wr(aclk);
    metaIntf #(.STYPE(req_t)) rq_rd(aclk);
    metaIntf #(.STYPE(req_t)) rq_wr(aclk);

    c_meta #(.ST(req_t)) sq_rd_mon = new(sq_rd);
    c_meta #(.ST(req_t)) sq_wr_mon = new(sq_wr);
    c_meta #(.ST(ack_t)) cq_rd_drv = new(cq_rd);
    c_meta #(.ST(ack_t)) cq_wr_drv = new(cq_wr);
    c_meta #(.ST(req_t)) rq_rd_drv = new(rq_rd);
    c_meta #(.ST(req_t)) rq_wr_drv = new(rq_wr);

    // Generator based on input.sock
    generator gen;

    // Scoreboard writing to output.sock
    scoreboard scb;

    // Host
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_recv[N_STRM_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_send[N_STRM_AXI] (aclk);

    c_axisr axis_host_recv_drv[N_STRM_AXI];
    c_axisr axis_host_send_drv[N_STRM_AXI];

    mem_mock #(N_STRM_AXI) host_mem_mock;

    // Card
`ifdef EN_MEM
    AXI4SR axis_card_recv[N_CARD_AXI] (aclk);
    AXI4SR axis_card_send[N_CARD_AXI] (aclk);

    c_axisr axis_card_recv_drv[N_CARD_AXI];
    c_axisr axis_card_send_drv[N_CARD_AXI];

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

`ifdef EN_TCP //TODO: TCP sim
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
        `ifdef EN_TCP
            //TCP interface is not yet implemented
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

        path_name = get_path_from_file(`__FILE__);
        path_name = {path_name, "build_sim/sim/"}; // TODO: Change this

        input_sock_name = {path_name, "input.sock"};
        output_sock_name = {path_name, "output.sock"};

        // Scoreboard
        scb = new(output_sock_name);

        // CTRL & Notify
        ctrl_sim = new(ctrl_mbx, axi_ctrl_drv, scb);
        notify_sim = new(notify_drv, scb);

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
            mail_ack,
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

        // TCP
    `ifdef EN_TCP
        //TCP interface is not yet implemented
    `endif

        // Card memory
    `ifdef EN_MEM
        card_drv_strm_rd[0] = new();
        card_drv_strm_wr[0] = new();
        axis_card_send_drv[0] = new(axis_card_send[0]);
        axis_card_recv_drv[0] = new(axis_card_recv[0]);

        card_mem_mock = new(
            "CARD",
            mail_ack,
            card_drv_strm_rd,
            card_drv_strm_wr,
            axis_card_send_drv,
            axis_card_recv_drv,
            scb
        );
    `endif

        // Host memory
    `ifdef EN_STRM
        host_drv_strm_rd[0] = new();
        host_drv_strm_wr[0] = new();
        axis_host_recv_drv[0] = new(axis_host_recv[0]);
        axis_host_send_drv[0] = new(axis_host_send[0]);

        if(N_STRM_AXI > 1) begin
            host_drv_strm_rd[1] = new();
            host_drv_strm_wr[1] = new();
            axis_host_recv_drv[1] = new(axis_host_recv[1]);
            axis_host_send_drv[1] = new(axis_host_send[1]);
        end
        if(N_STRM_AXI > 2) begin
            host_drv_strm_rd[2] = new();
            host_drv_strm_wr[2] = new();
            axis_host_recv_drv[2] = new(axis_host_recv[2]);
            axis_host_send_drv[2] = new(axis_host_send[2]);
        end
        if(N_STRM_AXI > 3) begin
            host_drv_strm_rd[3] = new();
            host_drv_strm_wr[3] = new();
            axis_host_recv_drv[3] = new(axis_host_recv[3]);
            axis_host_send_drv[3] = new(axis_host_send[3]);
        end
        
        host_mem_mock = new(
            "HOST",
            mail_ack,
            host_drv_strm_rd,
            host_drv_strm_wr,
            axis_host_send_drv,
            axis_host_recv_drv,
            scb
        );
    `endif

        // Generator
        gen = new(
            ctrl_mbx,
            mail_ack,
            host_drv_strm_rd,
            host_drv_strm_wr,
            card_drv_strm_rd,
            card_drv_strm_wr,
            rdma_rreq_recv_mbx,
            rdma_rreq_send_mbx,
            rdma_rrsp_recv_mbx,
            rdma_rrsp_send_mbx,
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
            input_sock_name
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

        #500;
        $display("All stream runs completed");

        // Print mem content and close file descriptors
        scb.close();
    `ifdef EN_RDMA
        rdma_drv_sim.print_data();
    `endif

        $finish;
    end
endmodule
