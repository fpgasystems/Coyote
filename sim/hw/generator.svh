import "DPI-C" function int open_pipe_for_non_blocking_reads (input string path);
import "DPI-C" function shortint try_read_byte_from_file (input int fd);
import "DPI-C" function void close_file (input int fd);

`include "log.svh"

/* 
* The generator class has three primary functions in the simulation environment:
* 1. It takes work queue entries from sq_rd and sq_wr and parses them into a mailbox message for the correct driver process
* 2. It reads the input files passed from tb_user and generates matching work queue entries in rq_rd and rq_wr, simulating incoming RDMA requests, or it generates a prompt to the host driver to send data via AXI4 streams in case the simulation needs data from the host without accompanying work queue entries.
* 3. It generates cq_rd and cq_wr transactions according to the feedback of the driver classes
*/

class generator;
    // For these structs the order is the other way around than it is in software while writing the binary file
    typedef struct packed {
        longint size;
        longint vaddr;
    } vaddr_size_t;

    typedef struct packed {
        byte do_polling;
        longint count;
        byte opcode;
    } check_completed_t;

    enum {
        CSR,         // cThread.get- and setCSR
        USER_MAP,    // cThread.userMap
        MEM_WRITE,   // Memory writes mem[i] = ...
        INVOKE,      // cThread.invoke
        SLEEP,       // Sleep for a certain duration before processing the next command
        CHECK_COMPLETED, // Poll until a certain number of operations is completed
        CLEAR_COMPLETED, // cThread.clearCompleted
        USER_UNMAP,  // cThread.userUnmap
        RQ_RD, RQ_WR // TODO: Add support for RDMA
    } op_type_t;
    int op_type_size[] = {
        trs_ctrl::BYTES, 
        $bits(vaddr_size_t) / 8, 
        $bits(vaddr_size_t) / 8, 
        c_trs_req::BYTES, 
        $bits(longint) / 8, 
        $bits(check_completed_t) / 8,
        0,
        $bits(longint) / 8
    };

    mailbox #(trs_ctrl)  ctrl_mbx;
    mailbox #(c_trs_ack) acks_mbx;
    mailbox #(c_trs_req) host_strm_rd_mbx[N_STRM_AXI];
    mailbox #(c_trs_req) host_strm_wr_mbx[N_STRM_AXI];
    mailbox #(c_trs_req) card_strm_rd_mbx[N_CARD_AXI];
    mailbox #(c_trs_req) card_strm_wr_mbx[N_CARD_AXI];
    mailbox #(c_trs_req) rdma_strm_rreq_recv[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_strm_rreq_send[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_strm_rrsp_recv[N_RDMA_AXI];
    mailbox #(c_trs_req) rdma_strm_rrsp_send[N_RDMA_AXI];

    event csr_polling_done;

    event ack;
    longint completed_reads = 0;
    longint completed_writes = 0;

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

    string file_name;
    event done;

    function new(
        mailbox #(trs_ctrl) ctrl_mbx,
        mailbox #(c_trs_ack) acks_mbx,
        mailbox #(c_trs_req) host_strm_rd_mbx[N_STRM_AXI],
        mailbox #(c_trs_req) host_strm_wr_mbx[N_STRM_AXI],
        mailbox #(c_trs_req) card_strm_rd_mbx[N_CARD_AXI],
        mailbox #(c_trs_req) card_strm_wr_mbx[N_CARD_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rreq_recv[N_RDMA_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rreq_send[N_RDMA_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rrsp_recv[N_RDMA_AXI],
        mailbox #(c_trs_req) mail_rdma_strm_rrsp_send[N_RDMA_AXI],
        input event csr_polling_done,
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
        input string input_file_name,
        scoreboard scb
    );
        this.ctrl_mbx = ctrl_mbx;
        this.acks_mbx = acks_mbx;
        this.host_strm_rd_mbx = host_strm_rd_mbx;
        this.host_strm_wr_mbx = host_strm_wr_mbx;
        this.card_strm_rd_mbx = card_strm_rd_mbx;
        this.card_strm_wr_mbx = card_strm_wr_mbx;
        this.rdma_strm_rreq_recv = mail_rdma_strm_rreq_recv;
        this.rdma_strm_rreq_send = mail_rdma_strm_rreq_send;
        this.rdma_strm_rrsp_recv = mail_rdma_strm_rrsp_recv;
        this.rdma_strm_rrsp_send = mail_rdma_strm_rrsp_send;

        this.csr_polling_done = csr_polling_done;

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

        this.file_name = input_file_name;

        this.scb = scb;
    endfunction

    task forward_rd_req(c_trs_req trs); // Transfer request to the correct driver
        if (trs.data.strm == STRM_CARD) begin
            card_strm_rd_mbx[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_HOST) begin
            host_strm_rd_mbx[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_TCP) begin
            `ASSERT(0, ("TCP Interface Simulation is not yet supported!"))
        end else if (trs.data.strm == STRM_RDMA) begin
            rdma_strm_rreq_recv[trs.data.dest].put(trs);
        end
            `DEBUG(("run_sq_rd_recv, addr: %x, length: %d, opcode: %d, pid: %d, strm: %d, dest %d, mode: %d, rdma: %d, remote: %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.dest, trs.data.mode, trs.data.rdma, trs.data.remote))
    endtask

    task forward_wr_req(c_trs_req trs); // Transfer request to the correct driver
        if (trs.data.strm == STRM_CARD) begin
            card_strm_wr_mbx[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_HOST) begin
            host_strm_wr_mbx[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_TCP) begin
            `ASSERT(0, ("TCP Interface Simulation is not yet supported!"))
        end else if (trs.data.strm == STRM_RDMA) begin
            rdma_strm_rreq_send[trs.data.dest].put(trs);
        end
            `DEBUG(("run_sq_wr_recv, addr: %x, length: %d, opcode: %d, pid: %d, strm: %d, dest %d, mode: %d, rdma: %d, remote: %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.dest, trs.data.mode, trs.data.rdma, trs.data.remote))
    endtask

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

    task run_sq_rd_recv();
        forever begin
            c_trs_req trs = new();
            sq_rd_mon.recv(trs.data);
        `ifdef EN_INTERACTIVE
            if (trs.data.strm == STRM_HOST) begin
                scb.writeHostRead(trs.data.vaddr, trs.data.len);
                host_sync_vaddr = trs.data.vaddr;
                `DEBUG(("Waiting for host read sync..."))
                @(host_sync_done);
            end
        `endif
            forward_rd_req(trs);
        end
    endtask

    task run_sq_wr_recv();
        forever begin
            c_trs_req trs = new();
            sq_wr_mon.recv(trs.data);
            forward_wr_req(trs);
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

    task read_next_byte(input int fd, output shortint result);
        // While the file does not have any new content, yield
        // the simulation for one clock cycle and then retry.
        // Note: We cannot use $fgetc here since this blocks
        // the WHOLE simulator (not just the calling thread...)
        result = try_read_byte_from_file(fd);
        while (result == -2) begin
            #(CLK_PERIOD);
            result = try_read_byte_from_file(fd);
        end

        if (result == -3) begin
            `FATAL(("Unknown error occured while trying to read input file"))
        end
    endtask

    task run_gen();
        logic[511:0] data;
        int fd;
        // The op byte is short int instead of byte to allow
        // differentiation between error values (-1, -2, -3)
        // and actual values!
        shortint op_type;

        fd = open_pipe_for_non_blocking_reads(file_name);
        if (fd == -1) begin
            `DEBUG(("File %s could not be opened: %0d", file_name, fd))
            -> done;
            return;
        end else begin
            `DEBUG(("Gen: successfully opened file at %s", file_name))
        end

        // Loop while the file has not reached its end
        read_next_byte(fd, op_type);
        while (op_type != -1) begin
            for (int i = 0; i < op_type_size[op_type]; i++) begin
                byte next_byte;
                read_next_byte(fd, next_byte);
                data[i * 8+:8] = next_byte[7:0];
            end

            case(op_type)
                CSR: begin
                    trs_ctrl trs = new();
                    trs.initialize(data);
                    ctrl_mbx.put(trs);
                    if (trs.do_polling) begin
                        `DEBUG(("Polling until CSR register at address %h has value %0d...", trs.addr, trs.data))
                        @(csr_polling_done);
                        `DEBUG(("Polling CSR completed"))
                    end else begin
                        `VERBOSE(("CSR %0d to address %h with value %0d", trs.is_write, trs.addr, trs.data))
                    end
                end
                USER_MAP: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    host_mem_mock.malloc(trs.vaddr, trs.size);
                `ifdef EN_MEM
                    card_mem_mock.malloc(trs.vaddr, trs.size);
                `endif
                    `DEBUG(("Mapped vaddr %0d, size %0d", trs.vaddr, trs.size))
                end
                MEM_WRITE: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    for (int i = 0; i < trs.size; i++) begin
                        byte next_byte;
                        read_next_byte(fd, next_byte);
                        host_mem_mock.write_data(trs.vaddr + i, next_byte);
                    end
                    if (host_sync_vaddr == trs.vaddr) begin
                        host_sync_vaddr = -1;
                        `DEBUG(("Host sync done"))
                        -> host_sync_done;
                    end
                    `DEBUG(("Wrote %0d Bytes to address %h", trs.size, trs.vaddr))
                end
                INVOKE: begin
                    c_trs_req trs = new();
                    trs.initialize(data);

                    if (trs.data.opcode == LOCAL_WRITE) begin
                        forward_wr_req(trs);
                    end else if (trs.data.opcode == LOCAL_READ) begin
                        forward_rd_req(trs);
                    end else if (trs.data.opcode == LOCAL_TRANSFER) begin
                        forward_wr_req(trs);
                        forward_rd_req(trs);
                    end else begin
                        `DEBUG(("CoyoteOper %h not supported!", trs.data.opcode))
                        -> done;
                    end
                end
                SLEEP: begin
                    realtime duration;
                    longint cycles = data[$bits(cycles) - 1:0];
                    duration = cycles * CLK_PERIOD;
                    `DEBUG(("Sleep for %0d cycles...", cycles))
                    #(duration);
                end
                CHECK_COMPLETED: begin
                    check_completed_t check_completed;
                    int check_reads = 0;
                    int check_writes = 0;
                    int result;
                    check_completed = data[$bits(check_completed_t) - 1:0];

                    if (check_completed.opcode == LOCAL_WRITE) begin
                        check_writes = check_completed.count;
                    end else if (check_completed.opcode == LOCAL_READ) begin
                        check_reads = check_completed.count;
                    end else if (check_completed.opcode == LOCAL_TRANSFER) begin
                        check_writes = check_completed.count;
                        check_reads = check_completed.count;
                    end else begin
                        `DEBUG(("CoyoteOper %h not supported!", check_completed.opcode))
                        -> done;
                    end

                    if (check_completed.do_polling) begin
                        `DEBUG(("Checking until %0d read(s) and %0d write(s) are completed...", check_reads, check_writes))
                        while (completed_reads < check_reads || completed_writes < check_writes) begin
                            @(ack);
                        end
                        `DEBUG(("Polling checks completed"))
                    end

                    result = (check_completed.opcode == LOCAL_READ) ? completed_reads : completed_writes; // LOCAL_TRANSFER returns LOCAL_WRITES
                    scb.writeCheckCompleted(result);
                    `VERBOSE(("Written check completed result %0d", result))
                end
                CLEAR_COMPLETED: begin
                    completed_reads = 0;
                    completed_writes = 0;
                    `DEBUG(("Clear completed"))
                end
                USER_UNMAP: begin
                    longint vaddr = data[$bits(vaddr) - 1:0];
                    host_mem_mock.free(vaddr);
                `ifdef EN_MEM
                    card_mem_mock.free(vaddr);
                `endif
                    `DEBUG(("Unmapped vaddr %0d", vaddr))
                end
                default: begin
                    `FATAL(("Op type %0d unknown", op_type))
                end
            endcase
            read_next_byte(fd, op_type);
        end
        
        `DEBUG(("Input file was closed!"))
        close_file(fd);
        -> done;
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
                `DEBUG(("Ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid))
                cq_rd.send(data);
            end else begin
                `DEBUG(("Ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid))
                cq_wr.send(data);
            end

            if (trs.last) begin
                if (trs.rd) begin
                    completed_reads++;
                end else begin
                    completed_writes++;
                end
                -> ack;
            end
        end
    endtask

endclass
