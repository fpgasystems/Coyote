`timescale 1ns / 1ps

`ifndef MEMORY_SIMULATION_SVH
`define MEMORY_SIMULATION_SVH

`include "log.svh"

/**
 * The memory_simulation class has two primary functions in the simulation environment:
 * 1. It takes work queue entries from sq_rd and sq_wr and passes them as mailbox messages to the correct driver process
 * 2. It generates cq_rd and cq_wr transactions according to the feedback of the driver classes
 */
class memory_simulation;
    mailbox #(c_trs_ack) acks_mbx;
    mailbox #(c_trs_req) host_strm_rd_mbx[N_STRM_AXI];
    mailbox #(c_trs_req) host_strm_wr_mbx[N_STRM_AXI];
    mailbox #(c_trs_req) card_strm_rd_mbx[N_CARD_AXI];
    mailbox #(c_trs_req) card_strm_wr_mbx[N_CARD_AXI];

    mailbox #(c_trs_req) rdma_strm_rreq_recv[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_strm_rreq_send[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_strm_rrsp_recv[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_strm_rrsp_send[N_RDMA_AXI];

    event ack;
    longint completed_counters[LOCAL_SYNC + 1];

    vaddr_t host_sync_vaddr = -1;
    event host_sync_done;

    mem_mock #(N_STRM_AXI) host_mem_mock;
`ifdef EN_MEM
    mem_mock #(N_CARD_AXI) card_mem_mock;
`endif

    c_meta #(.ST(req_t)) sq_rd_mon;
    c_meta #(.ST(req_t)) sq_wr_mon;
    c_meta #(.ST(ack_t)) cq_rd;
    c_meta #(.ST(ack_t)) cq_wr;
    c_meta #(.ST(req_t)) rq_rd;
    c_meta #(.ST(req_t)) rq_wr;

    scoreboard scb;

    function new(
        mailbox #(c_trs_ack) acks_mbx,
        mailbox #(c_trs_req) host_strm_rd_mbx[N_STRM_AXI],
        mailbox #(c_trs_req) host_strm_wr_mbx[N_STRM_AXI],
        mailbox #(c_trs_req) card_strm_rd_mbx[N_CARD_AXI],
        mailbox #(c_trs_req) card_strm_wr_mbx[N_CARD_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rreq_recv[N_RDMA_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rreq_send[N_RDMA_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rrsp_recv[N_RDMA_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rrsp_send[N_RDMA_AXI],
        mem_mock #(N_STRM_AXI) host_mem_mock,
    `ifdef EN_MEM
        mem_mock #(N_CARD_AXI) card_mem_mock,
    `endif
        c_meta #(.ST(req_t)) sq_rd_mon,
        c_meta #(.ST(req_t)) sq_wr_mon,
        c_meta #(.ST(ack_t)) cq_rd_drv,
        c_meta #(.ST(ack_t)) cq_wr_drv,
        c_meta #(.ST(req_t)) rq_rd_drv,
        c_meta #(.ST(req_t)) rq_wr_drv,
        scoreboard scb
    );
        this.acks_mbx = acks_mbx;
        this.host_strm_rd_mbx = host_strm_rd_mbx;
        this.host_strm_wr_mbx = host_strm_wr_mbx;
        this.card_strm_rd_mbx = card_strm_rd_mbx;
        this.card_strm_wr_mbx = card_strm_wr_mbx;

        this.rdma_strm_rreq_recv = mail_rdma_strm_rreq_recv;
        this.rdma_strm_rreq_send = mail_rdma_strm_rreq_send;
        this.rdma_strm_rrsp_recv = mail_rdma_strm_rrsp_recv;
        this.rdma_strm_rrsp_send = mail_rdma_strm_rrsp_send;

        this.host_mem_mock = host_mem_mock;
    `ifdef EN_MEM
        this.card_mem_mock = card_mem_mock;
    `endif

        this.sq_rd_mon = sq_rd_mon;
        this.sq_wr_mon = sq_wr_mon;
        this.cq_rd = cq_rd_drv;
        this.cq_wr = cq_wr_drv;
        this.rq_rd = rq_rd_drv;
        this.rq_wr = rq_wr_drv;

        this.scb = scb;
    endfunction

    function void write(vaddr_t vaddr, ref byte data[]);
        mem_seg_t mem_seg = host_mem_mock.get_mem_seg(vaddr);
        vaddr_t offset = vaddr - mem_seg.vaddr;
        for (int i = 0; i < $size(data); i++) begin
            mem_seg.data[i + offset] = data[i];
        end
        if (host_sync_vaddr == vaddr) begin
            host_sync_vaddr = -1;
            `DEBUG(("Host sync done"))
            -> host_sync_done;
        end
    endfunction

    function void copy(mem_seg_t src_mem_seg, mem_seg_t dst_mem_seg, vaddr_t vaddr, vaddr_t len);
        vaddr_t offset = vaddr - src_mem_seg.vaddr;
        for (int i = offset; i < offset + len; i++) begin
            dst_mem_seg.data[i] = src_mem_seg.data[i];
        end
    endfunction

`ifdef EN_MEM
    function bit is_pagefault(vaddr_t vaddr);
        return card_mem_mock.get_mem_seg(vaddr).marker == 0;
    endfunction

    function void invokeOffload(vaddr_t vaddr, vaddr_t len);
        mem_seg_t mem_seg = card_mem_mock.get_mem_seg(vaddr);
        copy(host_mem_mock.get_mem_seg(vaddr), mem_seg, vaddr, len);
        mem_seg.marker = 1;
        completed_counters[LOCAL_OFFLOAD]++;
    endfunction

    task invokeSync(vaddr_t vaddr, vaddr_t len);
        mem_seg_t mem_seg = card_mem_mock.get_mem_seg(vaddr);
        vaddr_t offset = vaddr - mem_seg.vaddr;

        copy(mem_seg, host_mem_mock.get_mem_seg(vaddr), vaddr, len);

        scb.writeHostMemHeader(vaddr, len);
        for (int i = offset; i < offset + len; i++) begin
            scb.writeByte(mem_seg.data[i]);
        end
        scb.flush();

        mem_seg.marker = 0;
        completed_counters[LOCAL_SYNC]++;
    endtask
`endif

    function int checkCompleted(int opcode);
        return completed_counters[opcode];
    endfunction

    function void clearCompleted();
        for (int i = 0; i < $size(completed_counters); i++) begin
            completed_counters[i] = 0;
        end
    endfunction

    function void userMap(vaddr_t vaddr, vaddr_t size);
        host_mem_mock.malloc(vaddr, size);
    `ifdef EN_MEM
        card_mem_mock.malloc(vaddr, size);
    `endif
    endfunction

    function void userUnmap(vaddr_t vaddr);
        host_mem_mock.free(vaddr);
    `ifdef EN_MEM
        card_mem_mock.free(vaddr);
    `endif
    endfunction

    task initialize();
        sq_rd_mon.reset_s();
        sq_wr_mon.reset_s();
        cq_rd.reset_m();
        cq_wr.reset_m();
        rq_rd.reset_m();
        rq_wr.reset_m();
        rq_rd.reset_s();
        rq_wr.reset_s();
    endtask

    task invokeRead(c_trs_req trs); // Transfer request to the correct driver
        if (trs.data.strm == STRM_HOST) begin
            host_strm_rd_mbx[trs.data.dest].put(trs);
    `ifdef EN_MEM
        end else if (trs.data.strm == STRM_CARD) begin
            if (is_pagefault(trs.data.vaddr)) begin
                // If card memory data is accessed from the vFPGA side for the first time, pagefault and get the data from the host memory
                mem_seg_t card_mem_seg = card_mem_mock.get_mem_seg(trs.data.vaddr);
                `DEBUG(("Page fault for vaddr %x", trs.data.vaddr))
                copy(host_mem_mock.get_mem_seg(trs.data.vaddr), card_mem_seg, card_mem_seg.vaddr, card_mem_seg.size);
                card_mem_seg.marker = 1; // Mark memory segment as loaded
            end
            card_strm_rd_mbx[trs.data.dest].put(trs);
    `endif
        end else begin
            `FATAL(("Stream type %0d is not supported by hardware configuration!", trs.data.strm))
        end
        `DEBUG(("run_sq_rd_recv, addr: %x, length: %d, opcode: %d, pid: %d, strm: %d, dest %d, mode: %d, rdma: %d, remote: %d, last: %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.dest, trs.data.mode, trs.data.rdma, trs.data.remote, trs.data.last))
    endtask

    task invokeWrite(c_trs_req trs); // Transfer request to the correct driver
        if (trs.data.strm == STRM_HOST) begin
            host_strm_wr_mbx[trs.data.dest].put(trs);
    `ifdef EN_MEM
        end else if (trs.data.strm == STRM_CARD) begin
            mem_seg_t card_mem_seg = card_mem_mock.get_mem_seg(trs.data.vaddr);
            card_mem_seg.marker = 1; // Mark memory segment as loaded
            card_strm_wr_mbx[trs.data.dest].put(trs);
    `endif
        end else begin
            `FATAL(("Stream type %0d is not supported by hardware configuration!", trs.data.strm))
        end
        `DEBUG(("run_sq_wr_recv, addr: %x, length: %d, opcode: %d, pid: %d, strm: %d, dest %d, mode: %d, rdma: %d, remote: %d, last: %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.dest, trs.data.mode, trs.data.rdma, trs.data.remote, trs.data.last))
    endtask

    task run_sq_rd_recv();
        forever begin
            c_trs_req trs = new();
            sq_rd_mon.recv(trs.data);
        `ifdef EN_INTERACTIVE
            // If we are in interactive mode, request the data that we will read from the host.
            // We do this in the run_sq_rd_recv task because we only need this for reads from the vFPGA side.
            // For reads triggered by the host, the host code has to handle this to not create a feedback loop.
            if (trs.data.strm == STRM_HOST) begin
                scb.writeHostRead(trs.data.vaddr, trs.data.len);
                host_sync_vaddr = trs.data.vaddr;
                `DEBUG(("Waiting for host read sync..."))
                @(host_sync_done);
                @(sq_rd_mon.meta.cbs);
        `ifdef EN_MEM
            end else if (trs.data.strm == STRM_CARD && is_pagefault(trs.data.vaddr)) begin
                // Because the simulation does not know about pages, only about memory segments, we get the whole memory segment on a pagefault
                mem_seg_t mem_seg = card_mem_mock.get_mem_seg(trs.data.vaddr);
                scb.writeHostRead(mem_seg.vaddr, mem_seg.size);
                host_sync_vaddr = mem_seg.vaddr;
                `DEBUG(("Waiting for host read sync..."))
                @(host_sync_done);
                @(sq_rd_mon.meta.cbs);
        `endif
            end
        `endif
            trs.req_time = $realtime;
            invokeRead(trs);
        end
    endtask

    task run_sq_wr_recv();
        forever begin
            c_trs_req trs = new();
            sq_wr_mon.recv(trs.data);
            trs.req_time = $realtime;
            invokeWrite(trs);
        end
    endtask

    task run_ack();
        forever begin
            c_trs_ack trs = new();
            ack_t data;

            acks_mbx.get(trs);

            data.opcode = trs.opcode;
            data.strm = trs.strm;
            data.remote = trs.remote;
            data.host = trs.host;
            data.dest = trs.dest;
            data.pid = trs.pid;
            data.vfid = trs.vfid;
            data.rsrvd = 0;

            if (trs.rd) begin
                `DEBUG(("Ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d, last=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid, trs.last))
                cq_rd.send(data);
            end else begin
                `DEBUG(("Ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d, last=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid, trs.last))
                cq_wr.send(data);
            end

            if (trs.last) begin
                if (trs.rd) begin
                    completed_counters[LOCAL_READ]++;
                end else begin
                    completed_counters[LOCAL_WRITE]++;
                    completed_counters[LOCAL_TRANSFER]++; // LOCAL_TRANSFER returns LOCAL_WRITES
                end
                -> ack;
            end
        end
    endtask

    /*task run_rq_rd_write(string path_name, string file_name);
        req_t rq_trs;
        c_trs_req mailbox_trs;
        int delay;
        string full_file_name;
        int FILE;
        string line;

        //open file descriptor
        full_file_name = {path_name, file_name};
        FILE = $fopen(full_file_name, "r");

        //read a single line, create rq_trs and mailbox_trs and initiate transfers after waiting for the specified delay
        while($fgets(line, FILE)) begin
            rq_trs = 0;
            $sscanf(line, "%x %h %h", delay, rq_trs.len, rq_trs.vaddr);

            rq_trs.opcode = 5'h10; //RDMA opcode for read_only
            rq_trs.host = 1'b1;
            rq_trs.actv = 1'b1;
            rq_trs.last = 1'b1;
            rq_trs.rdma = 1'b1;
            rq_trs.mode = 1'b1;

            mailbox_trs = new();
            mailbox_trs.data = rq_trs;

            #delay;

            rq_rd.send(rq_trs);
            mailbox_trs.req_time = $realtime;
            rdma_strm_rrsp_send[0].put(mailbox_trs);
        end

        //wait for mailbox to clear
        while(rdma_strm_rrsp_send[0].num() != 0) begin
            #100;
        end

        $display("RQ_RD DONE");
    endtask

    task run_rq_wr_write(string path_name, string file_name);
        //read input file -> delay -> write to rq_wr
        //delay, length, vaddr
        req_t rq_trs;
        c_trs_req mailbox_trs;
        int delay;
        string full_file_name;
        int FILE;
        string line;

        //open file descriptor
        full_file_name = {path_name, file_name};
        FILE = $fopen(full_file_name, "r");

        //read a single line, create rq_trs and mailbox_trs and initiate transfers after waiting for the specified delay
        while($fgets(line, FILE)) begin
            rq_trs = 0;
            $sscanf(line, "%x %h %h", delay, rq_trs.len, rq_trs.vaddr);

            rq_trs.opcode = 5'h0a; //RDMA opcode for read_only
            rq_trs.host = 1'b1;
            rq_trs.actv = 1'b1;
            rq_trs.last = 1'b1;
            rq_trs.rdma = 1'b1;
            rq_trs.mode = 1'b1;

            mailbox_trs = new();
            mailbox_trs.data = rq_trs;

            #delay;

            rq_wr.send(rq_trs);
            mailbox_trs.req_time = $realtime;
            rdma_strm_rrsp_recv[0].put(mailbox_trs);
        end

        //wait for mailbox to clear
        while(rdma_strm_rrsp_recv[0].num() != 0) begin
            #100;
        end

        $display("RQ_WR DONE");
    endtask*/
endclass

`endif
