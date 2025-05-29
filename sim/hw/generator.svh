/* 
* The generator class has three primary functions in the simulation environment:
* 1. It takes work queue entries from sq_rd and sq_wr and parses them into a mailbox message for the correct driver process
* 2. It reads the input files passed from tb_user and generates matching work queue entries in rq_rd and rq_wr, simulating incoming RDMA requests, or it generates a prompt to the host driver to send data via AXI4 streams in case the simulation needs data from the host without accompanying work queue entries.
* 3. It generates cq_rd and cq_wr transactions according to the feedback of the driver classes
*/

// For these structs the order is the other way around than it is in software while writing the binary file
typedef struct packed {
    longint size;
    longint vaddr;
} vaddr_size_t;

typedef struct packed {
    byte last;
    longint len;
    longint vaddr;
    byte dest;
    byte strm;
    byte opcode;
} sock_req_t;

typedef struct packed {
    longint count;
    byte opcode;
} check_completed_t;

class generator;
    enum {
        CSR,         // cThread.get- and setCSR
        GET_MEM,     // cThread.getMem
        MEM_WRITE,   // Memory writes mem[i] = ...
        INVOKE,      // cThread.invoke
        SLEEP,       // Sleep for a certain duration before processing the next command
        CHECK_COMPLETED, // Poll until a certain number of operations is completed
        RQ_RD, RQ_WR // TODO: Add support for RDMA
    } sock_type_t;
    int sock_type_size[] = {
        $bits(ctrl_op_t) / 8, 
        $bits(vaddr_size_t) / 8, 
        $bits(vaddr_size_t) / 8, 
        $bits(sock_req_t) / 8, 
        $bits(longint) / 8, 
        $bits(check_completed_t) / 8
    };

    mailbox ctrl_mbx;
    mailbox acks_mbx;
    mailbox host_mem_rd[N_STRM_AXI];
    mailbox host_mem_wr[N_STRM_AXI];
    mailbox card_mem_rd[N_CARD_AXI];
    mailbox card_mem_wr[N_CARD_AXI];
    mailbox rdma_strm_rreq_recv[N_RDMA_AXI];
    mailbox rdma_strm_rreq_send[N_RDMA_AXI];
    mailbox rdma_strm_rrsp_recv[N_RDMA_AXI];
    mailbox rdma_strm_rrsp_send[N_RDMA_AXI];

    event csr_polling_done;

    event ack;
    longint completed_reads = 0;
    longint completed_writes = 0;

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

    string sock_name;
    event done;

    function new(
        mailbox ctrl_mbx,
        mailbox acks_mbx,
        mailbox host_mem_strm_rd[N_STRM_AXI],
        mailbox host_mem_strm_wr[N_STRM_AXI],
        mailbox card_mem_strm_rd[N_CARD_AXI],
        mailbox card_mem_strm_wr[N_CARD_AXI],
        mailbox mail_rdma_strm_rreq_recv[N_RDMA_AXI],
        mailbox mail_rdma_strm_rreq_send[N_RDMA_AXI],
        mailbox mail_rdma_strm_rrsp_recv[N_RDMA_AXI],
        mailbox mail_rdma_strm_rrsp_send[N_RDMA_AXI],
        event csr_polling_done,
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
        string input_sock_name
    );
        this.ctrl_mbx = ctrl_mbx;
        this.acks_mbx = acks_mbx;
        this.csr_polling_done = csr_polling_done;
        host_mem_rd = host_mem_strm_rd;
        host_mem_wr = host_mem_strm_wr;
        card_mem_rd = card_mem_strm_rd;
        card_mem_wr = card_mem_strm_wr;
        rdma_strm_rreq_recv = mail_rdma_strm_rreq_recv;
        rdma_strm_rreq_send = mail_rdma_strm_rreq_send;
        rdma_strm_rrsp_recv = mail_rdma_strm_rrsp_recv;
        rdma_strm_rrsp_send = mail_rdma_strm_rrsp_send;

        this.host_mem_mock = host_mem_mock;
    `ifdef EN_MEM
        this.card_mem_mock = card_mem_mock;
    `endif

        this.sq_rd_mon = sq_rd_mon;
        this.sq_wr_mon = sq_wr_mon;
        cq_rd = cq_rd_drv;
        cq_wr = cq_wr_drv;
        rq_rd = rq_rd_drv;
        rq_wr = rq_wr_drv;

        sock_name = input_sock_name;
    endfunction

    task forward_rd_req(c_trs_req trs); // Transfer request to the correct driver
        if (trs.data.strm == STRM_CARD) begin
            card_mem_rd[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_HOST) begin
            host_mem_rd[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_TCP) begin
            $display("Gen: TCP Interface Simulation is not yet supported!");
        end else if (trs.data.strm == STRM_RDMA) begin
            rdma_strm_rreq_recv[trs.data.dest].put(trs);
        end

        $display("Gen: run_sq_rd_recv, addr: %x, length: %d, opcode: %d, pid: %d, strm: %d, mode: %d, rdma: %d, remote: %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.mode, trs.data.rdma, trs.data.remote);
    endtask

    task forward_wr_req(c_trs_req trs); // Transfer request to the correct driver
        if (trs.data.strm == STRM_CARD) begin
            card_mem_wr[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_HOST) begin
            host_mem_wr[trs.data.dest].put(trs);
        end else if (trs.data.strm == STRM_TCP) begin
            $display("Gen: TCP Interface Simulation is not yet supported!");
        end else if (trs.data.strm == STRM_RDMA) begin
            rdma_strm_rreq_send[trs.data.dest].put(trs);
        end
        $display("Gen: run_sq_wr_recv, addr: %x, length: %d, opcode: %d, pid: %d, strm: %d, mode: %d, rdma: %d, remote: %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.mode, trs.data.rdma, trs.data.remote);
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

    task run_gen();
        logic[511:0] data;
        int fd;
        byte sock_type;

        fd = $fopen(sock_name, "rb");

        if (!fd) begin
            $display("Gen: File %s could not be opened: %0d", sock_name, fd);
            -> done;
            return;
        end

        sock_type = $fgetc(fd);
        while (sock_type != -1) begin
            for (int i = 0; i < sock_type_size[sock_type]; i++) begin
                byte next_byte = $fgetc(fd);
                data[i * 8+:8] = next_byte[7:0];
            end

            case(sock_type)
                CSR: begin
                    ctrl_op_t trs = data[$bits(ctrl_op_t) - 1:0];
                    ctrl_mbx.put(trs);
                    if (trs.do_polling) begin
                        $display("Gen: Polling until CSR register at address %h has value %0d...", trs.addr, trs.data);
                        @(csr_polling_done);
                        $display("Gen: Polling complete");
                    end
                end
                GET_MEM: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    host_mem_mock.malloc(trs.vaddr, trs.size);
                `ifdef EN_MEM
                    card_mem_mock.malloc(trs.vaddr, trs.size);
                `endif
                end
                MEM_WRITE: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    for (int i = 0; i < trs.size; i++) begin
                        byte next_byte = $fgetc(fd);
                        host_mem_mock.write_data(trs.vaddr + i, next_byte);
                    end
                    $display("Gen: Wrote %0d Bytes to address %h", trs.size, trs.vaddr);
                end
                INVOKE: begin
                    c_trs_req trs = new();
                    sock_req_t sock_req;
                    sock_req = data[$bits(sock_req_t) - 1:0];

                    trs.data.opcode = sock_req.opcode;
                    trs.data.strm   = sock_req.strm;
                    trs.data.dest   = sock_req.dest;
                    trs.data.vaddr  = sock_req.vaddr;
                    trs.data.len    = sock_req.len;
                    trs.data.last   = sock_req.last;

                    if (trs.data.opcode == LOCAL_WRITE) begin
                        forward_wr_req(trs);
                    end else if (trs.data.opcode == LOCAL_READ) begin
                        forward_rd_req(trs);
                    end else if (trs.data.opcode == LOCAL_TRANSFER) begin
                        forward_wr_req(trs);
                        forward_rd_req(trs);
                    end else begin
                        $display("Gen: CoyoteOper %h not supported!", trs.data.opcode);
                    end
                end
                SLEEP: begin
                    realtime duration;
                    longint cycles = data[$bits(cycles) - 1:0];
                    duration = cycles * CLK_PERIOD;
                    $display("Gen: Sleep for %0d cycles...", cycles);
                    #(duration);
                end
                CHECK_COMPLETED: begin
                    check_completed_t check_completed;
                    int check_reads = 0;
                    int check_writes = 0;
                    check_completed = data[$bits(check_completed_t) - 1:0];

                    if (check_completed.opcode == LOCAL_WRITE) begin
                        check_writes = check_completed.count;
                    end else if (check_completed.opcode == LOCAL_READ) begin
                        check_reads = check_completed.count;
                    end else if (check_completed.opcode == LOCAL_TRANSFER) begin
                        check_writes = check_completed.count;
                        check_reads = check_completed.count;
                    end else begin
                        $display("Gen: CoyoteOper %h not supported!", check_completed.opcode);
                    end

                    $display("Gen: Checking until %0d read(s) and %0d write(s) are completed...", check_reads, check_writes);
                    while (completed_reads < check_reads || completed_writes < check_writes) begin
                        @(ack);
                    end
                    $display("Gen: Checks completed");
                end
                default:;
            endcase

            sock_type = $fgetc(fd);
        end
        
        $fclose(fd);
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
                $display("Gen: Ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid);
                cq_rd.send(data);
            end else begin
                $display("Gen: Ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid);
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
