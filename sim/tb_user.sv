`timescale 1ns / 1ps

import lynxTypes::*;
import simTypes::*;

`include "c_axis.svh"
`include "c_axisr.svh"
`include "c_axil.svh"
`include "c_meta.svh"
`include "c_env.svh"
`include "c_ctrl.svh"

`include "ctrl_simulation.svh"
`include "notify_simulation.svh"
`include "requester_simulation.svh"
`include "host_mem_simulation.svh"
`include "rdma_mem_simulation.svh"

task static delay(input integer n_clk_prds);
    #(n_clk_prds*CLK_PERIOD);
endtask

// From a full path get the prefix to just the Coyote root directory, used to pass filenames of mem_segments
function string get_path_from_file(string fullpath_filename);
    int i;
    int str_index;
    string ret="";

    for (i = fullpath_filename.len()-4; i>0; i=i-1) begin
        if (fullpath_filename.substr(i, i+9) == "/build_sim") begin
            str_index=i;
            break;
        end
    end
    
    ret=fullpath_filename.substr(0,str_index);    
    return ret;
endfunction

module tb_user;

    c_struct_t params = { 16 };

    logic aclk = 1'b1;
    logic aresetn = 1'b0;

    string path_name;

    //clock generation
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // mailboxes
    // acks
    mailbox mail_ack = new();

    // host memory streams
    mailbox host_mem_strm_rd[N_STRM_AXI];
    mailbox host_mem_strm_wr[N_STRM_AXI];
    // RDMA streams
    mailbox mail_rdma_strm_rrsp_recv[N_RDMA_AXI];
    mailbox mail_rdma_strm_rrsp_send[N_RDMA_AXI];
    mailbox mail_rdma_strm_rreq_recv[N_RDMA_AXI];
    mailbox mail_rdma_strm_rreq_send[N_RDMA_AXI];
    // card memory streams
    mailbox card_mem_strm_rd[N_CARD_AXI];
    mailbox card_mem_strm_wr[N_CARD_AXI];
    // TODO: TCP streams

    // Interfaces and drivers

    // AXI CSR
    AXI4L axi_ctrl (aclk);

    c_axil axi_ctrl_drv = new(axi_ctrl);
    ctrl_simulation ctrl_sim = new(axi_ctrl_drv);

    // Notify
    metaIntf #(.STYPE(irq_not_t)) notify (aclk);

    c_meta #(.ST(irq_not_t)) notify_drv = new(notify);
    notify_simulation notify_sim = new(notify_drv);

    // Descriptors
    // all of these are necessary
    metaIntf #(.STYPE(req_t)) sq_rd (aclk);
    metaIntf #(.STYPE(req_t)) sq_wr (aclk);
    metaIntf #(.STYPE(ack_t)) cq_rd (aclk);
    metaIntf #(.STYPE(ack_t)) cq_wr (aclk);
    metaIntf #(.STYPE(req_t)) rq_rd (aclk);
    metaIntf #(.STYPE(req_t)) rq_wr (aclk);

    c_meta #(.ST(req_t)) sq_rd_drv = new(sq_rd);
    c_meta #(.ST(req_t)) sq_wr_drv = new(sq_wr);
    c_meta #(.ST(ack_t)) cq_rd_drv = new(cq_rd);
    c_meta #(.ST(ack_t)) cq_wr_drv = new(cq_wr);
    c_meta #(.ST(req_t)) rq_rd_drv = new(rq_rd);
    c_meta #(.ST(req_t)) rq_wr_drv = new(rq_wr);

    // instantiate the requester interface simulaion
    requester_simulation req_sim;

    // Host
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_recv [N_STRM_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_send [N_STRM_AXI] (aclk);

    // replace c_env with my own solution
    c_axisr axis_host_recv_drv[N_STRM_AXI];
    c_axisr axis_host_send_drv[N_STRM_AXI];
    host_mem_simulation host_mem_sim;


`ifdef EN_MEM
    AXI4SR axis_card_recv [N_CARD_AXI] (aclk);
    AXI4SR axis_card_send [N_CARD_AXI] (aclk);

    c_axisr axis_card_recv_drv [N_CARD_AXI];
    c_axisr axis_card_send_drv [N_CARD_AXI];
    card_mem_simulation card_mem_sim;
`endif
`ifdef EN_RDMA
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rreq_recv [N_RDMA_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rreq_send [N_RDMA_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rrsp_recv [N_RDMA_AXI] (aclk);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_rrsp_send [N_RDMA_AXI] (aclk);

    // replace c_env with my own solution
    //c_env axis_rreq_drv [N_RDMA_AXI];
    //c_env axis_rrsp_drv [N_RDMA_AXI];

    c_axisr axis_rdma_rreq_recv_drv[N_RDMA_AXI];
    c_axisr axis_rdma_rreq_send_drv[N_RDMA_AXI];
    c_axisr axis_rdma_rrsp_recv_drv[N_RDMA_AXI];
    c_axisr axis_rdma_rrsp_send_drv[N_RDMA_AXI];
    rdma_mem_simulation rdma_mem_sim;
`endif
`ifdef EN_TCP
    AXI4SR axis_tcp_recv [N_TCP_AXI] (aclk);
    AXI4SR axis_tcp_send [N_TCP_AXI] (aclk);

    c_env axis_tcp_drv [N_TCP_AXI];
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
    task static env_threads();
        #(RST_PERIOD); // first delay the execution until the reset is done
        fork
        ctrl_sim.run();
        notify_sim.run();
        req_sim.run_req();
        req_sim.run_ack();
        host_mem_sim.run_send(0);
        host_mem_sim.run_recv(0);
        host_mem_sim.run_send(1);
        host_mem_sim.run_recv(1);
        //host_mem_sim.run_send(2);
        //host_mem_sim.run_recv(2);
        //host_mem_sim.run_send(3);
        //host_mem_sim.run_recv(3);

    `ifdef EN_MEM
        card_mem_sim.run_send[0];
        card_mem_sim.run_recv[0];
    `endif
    `ifdef EN_RDMA
        //for(int i = 0; i < N_RDMA_AXI; i++) begin
        //    axis_rreq_drv[i].run();
        //    axis_rrsp_drv[i].run();
        //end
        rdma_mem_sim.run_rreq_send(0);
        rdma_mem_sim.run_rreq_recv(0);
        rdma_mem_sim.run_rrsp_send(0);
        rdma_mem_sim.run_rrsp_recv(0);
    `endif
    `ifdef EN_TCP
        for(int i = 0; i < N_TCP_AXI; i++) begin
            axis_tcp_drv[i].run();
        end
    `endif
        join_any
    endtask

    // Stream completion
    task static env_done();
        wait(ctrl_sim.done.triggered);

    `ifdef EN_MEM
        /*for(int i = 0; i < N_CARD_AXI; i++) begin
            wait(axis_card_drv[i].done.triggered);
        end*/
    `endif
    `ifdef EN_RDMA
        //for(int i = 0; i < N_RDMA_AXI; i++) begin
        //    wait(axis_rreq_drv[i].done.triggered);
        //    wait(axis_rrsp_drv[i].done.triggered);
        //end
    `endif
    `ifdef EN_TCP
        for(int i = 0; i < N_TCP_AXI; i++) begin
            wait(axis_tcp_drv[i].done.triggered);
        end
    `endif
    endtask

    generate
    initial begin
        //reset Generation
        aresetn = 1'b0;

        // Dump
        $dumpfile("dump.vcd"); $dumpvars;

        // RDMA
    `ifdef EN_RDMA
        //for(genvar i = 0; i < N_RDMA_AXI; i++) begin
        //    axis_rreq_drv[i] = new(axis_rreq_recv[i], axis_rreq_send[i], params, "RREQ_STREAM");
        //    axis_rrsp_drv[i] = new(axis_rrsp_recv[i], axis_rrsp_send[i], params, "RRSP_STREAM");
        //end

        mail_rdma_strm_rreq_recv[0] = new();
        mail_rdma_strm_rreq_send[0] = new();
        mail_rdma_strm_rrsp_recv[0] = new();
        mail_rdma_strm_rrsp_send[0] = new();

        axis_rdma_rreq_recv_drv[0] = new(axis_rreq_recv[0]);
        axis_rdma_rreq_send_drv[0] = new(axis_rreq_send[0]);
        axis_rdma_rrsp_recv_drv[0] = new(axis_rrsp_recv[0]);
        axis_rdma_rrsp_send_drv[0] = new(axis_rrsp_send[0]);

        rdma_mem_sim = new(
            mail_rdma_strm_rreq_recv,
            mail_rdma_strm_rreq_send,
            mail_rdma_strm_rrsp_recv,
            mail_rdma_strm_rrsp_send,
            axis_rdma_rreq_recv_drv,
            axis_rdma_rreq_send_drv,
            axis_rdma_rrsp_recv_drv,
            axis_rdma_rrsp_send_drv
        );

    `endif

        // TCP
    `ifdef EN_TCP
        axis_tcp_drv[0] = new(axis_tcp_recv[0], axis_tcp_send[0], params, "TCP_STREAM");
    `endif

        // Card Memory
    `ifdef EN_MEM
        card_mem_strm_rd[0] = new();
        card_mem_strm_wr[0] = new();
        axis_card_recv_drv[0] = new(axis_card_recv[0]);
        axis_card_recv_send[0] = new(axis_card_send[0]);

        card_mem_sim = new(
            card_mem_strm_rd,
            card_mem_strm_wr,
            axis_card_send_drv[0],
            axis_card_recv_drv[0]);
    `endif

        // Host memory
    `ifdef EN_STRM
        // TODO: is this somehow possible with a loop?
        host_mem_strm_rd[0] = new();
        host_mem_strm_wr[0] = new();
        host_mem_strm_rd[1] = new();
        host_mem_strm_wr[1] = new();
        //host_mem_strm_rd[2] = new();
        //host_mem_strm_wr[2] = new();
        //host_mem_strm_rd[3] = new();
        //host_mem_strm_wr[3] = new();
        axis_host_recv_drv[0] = new(axis_host_recv[0]);
        axis_host_send_drv[0] = new(axis_host_send[0]);
        axis_host_recv_drv[1] = new(axis_host_recv[1]);
        axis_host_send_drv[1] = new(axis_host_send[1]);
        //axis_host_recv_drv[2] = new(axis_host_recv[2]);
        //axis_host_send_drv[2] = new(axis_host_send[2]);
        //axis_host_recv_drv[3] = new(axis_host_recv[3]);
        //axis_host_send_drv[3] = new(axis_host_send[3]);

        host_mem_sim = new(
            host_mem_strm_rd,
            host_mem_strm_wr,
            axis_host_send_drv,
            axis_host_recv_drv
        );

        // load the entire memory image of the example process
        // NOTE: this list can be autogenerated with the scripts/generate_set_data.sh script!
        //host_mem_sim.set_data("seg-7f3c1b9ac000-1000.txt");
        //host_mem_sim.set_data("seg-55c372b52000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1ba09000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c09dfc000-200000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9f4000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1ba16000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b7d5000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1bafd000-1000.txt");
        //host_mem_sim.set_data("seg-7f3bfc000000-21000.txt");
        //host_mem_sim.set_data("seg-7f3c1bd78000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1bb5d000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9c9000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9d4000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1bff8000-140f000.txt");
        //host_mem_sim.set_data("seg-7ffe91bdc000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1bd7a000-d000.txt");
        //host_mem_sim.set_data("seg-7f3c1bb59000-4000.txt");
        //host_mem_sim.set_data("seg-7f3c195fe000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c1bafe000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1b7f7000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c0a7fe000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c1baa7000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1baa8000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c14000000-21000.txt");
        //host_mem_sim.set_data("seg-7f3c1bda5000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b8dd000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c04000000-21000.txt"); // main heap data
        //host_mem_sim.set_data("seg-7f3c18000000-600000.txt");
        //host_mem_sim.set_data("seg-7f3c1bfcd000-3000.txt");
        //host_mem_sim.set_data("seg-ffffffffff600000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1bd87000-3000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9ae000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1bfd0000-3000.txt");
        //host_mem_sim.set_data("seg-7f3c1baa6000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c09000000-400000.txt");
        //host_mem_sim.set_data("seg-7f3c1bd74000-4000.txt");
        //host_mem_sim.set_data("seg-7f3c1bda6000-1000.txt");
        //host_mem_sim.set_data("seg-55c372b41000-7000.txt");
        //host_mem_sim.set_data("seg-7f3c1ae00000-800000.txt");
        //host_mem_sim.set_data("seg-7ffe91bd8000-4000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9ad000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1bafc000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c0afff000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c206a5000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1b8de000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1a600000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c09ffd000-800000.txt");
        //host_mem_sim.set_data("seg-7ffe91b3b000-22000.txt");
        //host_mem_sim.set_data("seg-7f3c1bb00000-8000.txt");
        //host_mem_sim.set_data("seg-7f3c2037d000-b1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9d5000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c00000000-21000.txt");
        //host_mem_sim.set_data("seg-7f3c1bda7000-9a000.txt");
        //host_mem_sim.set_data("seg-7f3c19000000-400000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9c8000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9d6000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c206dd000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1b7c6000-f000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9ca000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c0b800000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c19dff000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c10000000-21000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9f6000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1ba17000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1b7f8000-e000.txt");
        //host_mem_sim.set_data("seg-7f3c1ba08000-1000.txt");
        //host_mem_sim.set_data("seg-55c372b53000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1ba07000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c18800000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9f5000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c1bb5e000-28000.txt");
        //host_mem_sim.set_data("seg-7f3c0c000000-21000.txt");
        //host_mem_sim.set_data("seg-7f3c1b8df000-a000.txt");
        //host_mem_sim.set_data("seg-7f3c2032d000-50000.txt");
        //host_mem_sim.set_data("seg-7f3c1b7f6000-1000.txt");
        //host_mem_sim.set_data("seg-7f3c206df000-2000.txt");
        //host_mem_sim.set_data("seg-7f3c1b9cc000-2000.txt");
        //host_mem_sim.set_data("seg-55c3732d2000-42000.txt");
        //host_mem_sim.set_data("seg-7f3c2042e000-277000.txt");
        //host_mem_sim.set_data("seg-7f3c1bfc2000-b000.txt");
        //host_mem_sim.set_data("seg-7f3c095fc000-800000.txt");
        //host_mem_sim.set_data("seg-7f3c1ba15000-1000.txt");

        //host_mem_sim.set_data("seg-7ff00000000-ef0.txt"); // longer descriptor test (b00, b0, 7ff00000e00)
        //host_mem_sim.set_data("seg-7ff00000000-140.txt"); // short non divisible descriptor test (40, 20, 7ff000000e0)
        //host_mem_sim.set_data("seg-7ff00000000-2c8.txt"); // longer non divisible descriptor test (100, 30, 7ff00000258)
        //host_mem_sim.set_data("seg-7ff00000000-2d4.txt"); // longer non divisible descriptor test (10c, 30, 7ff00000264) with trailing data
        //host_mem_sim.set_data("seg-7ff00000000-2e0.txt"); // short simple test (200, 20, 7ff00000280)
        
        path_name = get_path_from_file(`__FILE__);
        host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-7f3bfc000000-21000.txt"); // longer data for testing the request splitter (418c, 40, 7ff000042e4)
        host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-7ff00000000-c4c.txt"); // longer data for testing the request splitter (418c, 40, 7ff000042e4)
        host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-7fe00000000-21000.txt");
        rdma_mem_sim.set_data({path_name, "memory_segments/"}, "rdma-0000-20000.txt"); // simply testing the RDMA interface
        rdma_mem_sim.set_data({path_name, "memory_segments/"}, "rdma-7fe00000000-21000.txt");
        

        //host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-000000-10.txt");
        //host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-000018-10.txt");
        //host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-000008-10.txt");
        //host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-000010-10.txt");
        //host_mem_sim.set_data({path_name, "memory_segments/"}, "seg-000008-20.txt");

    `endif

        // requester interface
        req_sim = new(
            mail_ack,
            host_mem_strm_rd,
            host_mem_strm_wr,
            card_mem_strm_rd,
            card_mem_strm_wr,
            mail_rdma_strm_rreq_recv,
            mail_rdma_strm_rreq_send,
            mail_rdma_strm_rrsp_recv,
            mail_rdma_strm_rrsp_send,
            sq_rd_drv,
            sq_wr_drv,
            cq_rd_drv,
            cq_wr_drv,
            rq_rd_drv,
            rq_wr_drv
        );

        // reset of interfaces
        ctrl_sim.reset();       // AXIL control
        notify_sim.reset(path_name);     // Notify
        req_sim.reset();        // Descriptors
        card_mem_sim.reset(path_name);
        host_mem_sim.reset(path_name);   // Host Memory Streams
        rdma_mem_sim.reset(path_name);   // RDMA Memory Streams

        #(RST_PERIOD) aresetn = 1'b1;

        env_threads();
        env_done();
        $display("All stream runs completed");
        host_mem_sim.print_data();
        rdma_mem_sim.print_data();
        
        #50
        $finish;
    end
    endgenerate

endmodule
