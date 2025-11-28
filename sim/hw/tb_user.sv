/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`timescale 1ns / 1ps

import lynxTypes::*;

`include "log.svh"

`include "c_axisr.svh"
`include "c_axil.svh"
`include "c_meta.svh"

`include "transactions.svh"
`include "ctrl_simulation.svh"
`include "notify_simulation.svh"
`include "mem_mock.svh"
`include "generator.svh"
`include "scoreboard.svh"
`include "memory_simulation.svh"

module tb_user;
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
    AXI4L axi_ctrl(.*);
    c_axil axi_ctrl_drv = new(axi_ctrl);
    ctrl_simulation ctrl_sim;

    // Notify
    metaIntf #(.STYPE(irq_not_t)) notify(.*);
    c_meta #(.ST(irq_not_t)) notify_drv = new(notify);
    notify_simulation notify_sim;

    // Descriptors
    metaIntf #(.STYPE(req_t)) sq_rd(.*);
    metaIntf #(.STYPE(req_t)) sq_wr(.*);
    metaIntf #(.STYPE(ack_t)) cq_rd(.*);
    metaIntf #(.STYPE(ack_t)) cq_wr(.*);
    metaIntf #(.STYPE(req_t)) rq_rd(.*);
    metaIntf #(.STYPE(req_t)) rq_wr(.*);

    c_meta #(.ST(req_t)) sq_rd_mon = new(sq_rd);
    c_meta #(.ST(req_t)) sq_wr_mon = new(sq_wr);
    c_meta #(.ST(ack_t)) cq_rd_drv = new(cq_rd);
    c_meta #(.ST(ack_t)) cq_wr_drv = new(cq_wr);
    c_meta #(.ST(req_t)) rq_rd_drv = new(rq_rd);
    c_meta #(.ST(req_t)) rq_wr_drv = new(rq_wr);

    // Generator reading from input.bin
    generator gen;

    // Scoreboard writing to output.bin
    scoreboard scb;

    // Host
    // This stuff still has to exist even if streams are not enabled for offload and sync purposes
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_recv[N_STRM_AXI](.*);
    AXI4SR #(.AXI4S_DATA_BITS(AXI_DATA_BITS)) axis_host_send[N_STRM_AXI](.*);

    c_axisr host_recv_drv[N_STRM_AXI];
    c_axisr host_send_drv[N_STRM_AXI];

    mem_mock #(N_STRM_AXI) host_mem_mock; 

    // Card
`ifdef EN_MEM
    AXI4SR axis_card_recv[N_CARD_AXI](.*);
    AXI4SR axis_card_send[N_CARD_AXI](.*);

    c_axisr card_recv_drv[N_CARD_AXI];
    c_axisr card_send_drv[N_CARD_AXI];

    mem_mock #(N_CARD_AXI) card_mem_mock;
`endif

    // RDMA
`ifdef EN_RDMA
    AXI4SR axis_rreq_recv[N_RDMA_AXI](.*);
    AXI4SR axis_rreq_send[N_RDMA_AXI](.*);
    AXI4SR axis_rrsp_recv[N_RDMA_AXI](.*);
    AXI4SR axis_rrsp_send[N_RDMA_AXI](.*);

    c_axisr rdma_rreq_recv_drv[N_RDMA_AXI];
    c_axisr rdma_rreq_send_drv[N_RDMA_AXI];
    c_axisr rdma_rrsp_recv_drv[N_RDMA_AXI];
    c_axisr rdma_rrsp_send_drv[N_RDMA_AXI];

    mem_mock #(N_RDMA_AXI) rdma_mem_mock;
`endif

    memory_simulation mem_sim;

`ifdef EN_TCP //TODO: TCP Simulation
    AXI4SR axis_tcp_recv[N_TCP_AXI](.*);
    AXI4SR axis_tcp_send[N_TCP_AXI](.*);
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

            mem_sim.run_sq_rd_recv();
            mem_sim.run_sq_wr_recv();
            mem_sim.run_ack();

            gen.run_gen();

        `ifdef EN_STRM
            host_mem_mock.run();
        `endif
        `ifdef EN_MEM
            card_mem_mock.run();
        `endif
        `ifdef EN_RDMA
            rdma_mem_mock.run();
        `endif
        join_none
    endtask


    task static env_done();
        fork
            wait(gen.done.triggered);
        join
    endtask

    for (genvar i = 0; i < N_STRM_AXI; i++) begin
        initial begin
            host_recv_mbx[i] = new();
            host_send_mbx[i] = new();

            host_recv_drv[i] = new(axis_host_recv[i], i);
            host_send_drv[i] = new(axis_host_send[i], i);
        end
    end

`ifdef EN_MEM
    for (genvar i = 0; i < N_CARD_AXI; i++) begin
        initial begin
            card_recv_mbx[i] = new();
            card_send_mbx[i] = new();

            card_send_drv[i] = new(axis_card_send[i], i);
            card_recv_drv[i] = new(axis_card_recv[i], i);
        end
    end
`endif

`ifdef EN_RDMA
    for (genvar i = 0; i < N_RDMA_AXI; i++) begin
        initial begin
            rdma_rreq_recv_mbx[i] = new();
            rdma_rreq_send_mbx[i] = new();
            rdma_rrsp_recv_mbx[i] = new();
            rdma_rrsp_send_mbx[i] = new();

            rdma_rreq_recv_drv[i] = new(axis_rreq_recv[i], i);
            rdma_rreq_send_drv[i] = new(axis_rreq_send[i], i);
            rdma_rrsp_recv_drv[i] = new(axis_rrsp_recv[i], i);
            rdma_rrsp_send_drv[i] = new(axis_rrsp_send[i], i);
        end
    end
`endif

    initial begin
        // Reset generation
        aresetn = 1'b0;

    `ifdef EN_VAR_DUMP
        $dumpfile("dump.vcd"); $dumpvars;
    `endif

        path_name = {BUILD_DIR, "/sim/"};

        input_file_name = {path_name, "input.bin"};
        output_file_name = {path_name, "output.bin"};

        // Scoreboard
        scb = new(output_file_name);

        // CTRL & Notify
        ctrl_sim = new(ctrl_mbx, axi_ctrl_drv, scb);
        notify_sim = new(notify_drv, scb);

        // Host memory
        host_mem_mock = new(
            "HOST",
            ack_mbx,
            host_recv_mbx,
            host_send_mbx,
            host_send_drv,
            host_recv_drv,
            scb
        );

        // Card memory
    `ifdef EN_MEM
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
        rdma_mem_mock = new(
            "RDMA",
            ack_mbx,
            rdma_rreq_recv_mbx, // queue to send read requests
            rdma_rreq_send_mbx, // queue to send write requests
            rdma_rreq_send_drv, // data input for write
            rdma_rreq_recv_drv, // data output for read
            scb
        );
    `endif

        mem_sim = new(
            ack_mbx,
            host_recv_mbx,
            host_send_mbx,
            card_recv_mbx,
            card_send_mbx,
            rdma_rreq_recv_mbx,
            rdma_rreq_send_mbx,
            rdma_rrsp_recv_mbx,
            rdma_rrsp_send_mbx,
            host_mem_mock,
        `ifdef EN_MEM
            card_mem_mock,
        `endif
        `ifdef EN_RDMA
            rdma_mem_mock,
        `endif
            sq_rd_mon,
            sq_wr_mon,
            cq_rd_drv,
            cq_wr_drv,
            rq_rd_drv,
            rq_wr_drv,
            scb
        );

        // Generator
        gen = new(
            ctrl_mbx,
            ctrl_sim.polling_done,
            input_file_name,
            mem_sim,
            scb
        );

        // Reset of interfaces
        mem_sim.initialize();

        ctrl_sim.initialize();
        notify_sim.initialize();
        host_mem_mock.initialize();
    `ifdef EN_MEM
        card_mem_mock.initialize();
    `endif
    `ifdef EN_RDMA
        rdma_mem_mock.initialize();
    `endif
        
        #(RST_PERIOD) aresetn = 1'b1;

        env_threads();
        env_done();

        for(int i = 0; i < 10; i++) begin
            #(CLK_PERIOD);
        end
        `DEBUG(("Testbench finished!"))

        // Close file descriptors
        scb.close();

        $finish;
    end
endmodule
