

class requester_simulation;

    mailbox acks;
    mailbox host_mem_rd[N_STRM_AXI];
    mailbox host_mem_wr[N_STRM_AXI];
    mailbox rdma_rreq_rd[N_RDMA_AXI];
    mailbox rdma_rreq_wr[N_RDMA_AXI];
    mailbox rdma_rrsp_rd[N_RDMA_AXI];
    mailbox rdma_rrsp_wr[N_RDMA_AXI];

    c_meta #(.ST(req_t)) sq_rd;
    c_meta #(.ST(req_t)) sq_wr;
    c_meta #(.ST(ack_t)) cq_rd;
    c_meta #(.ST(ack_t)) cq_wr;
    c_meta #(.ST(req_t)) rq_rd;
    c_meta #(.ST(req_t)) rq_wr;

    function new(
        mailbox mail_ack,
        mailbox host_mem_strm_rd[N_STRM_AXI],
        mailbox host_mem_strm_wr[N_STRM_AXI],
        mailbox rdma_strm_rreq_rd[N_RDMA_AXI],
        mailbox rdma_strm_rreq_wr[N_RDMA_AXI],
        mailbox rdma_strm_rrsp_rd[N_RDMA_AXI],
        mailbox rdma_strm_rrsp_wr[N_RDMA_AXI],
        // TODO: add additional mailboxes
        c_meta #(.ST(req_t)) sq_rd_drv,
        c_meta #(.ST(req_t)) sq_wr_drv,
        c_meta #(.ST(ack_t)) cq_rd_drv,
        c_meta #(.ST(ack_t)) cq_wr_drv,
        c_meta #(.ST(req_t)) rq_rd_drv,
        c_meta #(.ST(req_t)) rq_wr_drv
    );
        acks = mail_ack;
        host_mem_rd = host_mem_strm_rd;
        host_mem_wr = host_mem_strm_wr;
        rdma_rreq_rd = rdma_strm_rreq_rd;
        rdma_rreq_wr = rdma_strm_rreq_wr;
        rdma_rrsp_rd = rdma_strm_rrsp_rd;
        rdma_rrsp_wr = rdma_strm_rrsp_wr;

        sq_rd = sq_rd_drv;
        sq_wr = sq_wr_drv;
        cq_rd = cq_rd_drv;
        cq_wr = cq_wr_drv;
        rq_rd = rq_rd_drv;
        rq_wr = rq_wr_drv;
    endfunction

    task reset();
        sq_rd.reset_s();
        sq_wr.reset_s();
        cq_rd.reset_m();
        cq_wr.reset_m();
        rq_rd.reset_m();
        rq_wr.reset_m();
    endtask

    task run_sq_rd_recv();
        forever begin
            c_trs_req trs = new();
            c_trs_ack ack_trs;
            sq_rd.recv(trs.data);
            trs.req_time = $realtime;

            // initiate the transfer
            if (trs.data.strm == 3) begin
                // TODO: implement
            end
            else if (trs.data.strm == 1) begin
                host_mem_rd[trs.data.dest].put(trs);
            end

            $display("run_sq_rd_recv: %x %d %d %d %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.dest);

            // acknowledge transfer
            // TODO: figure out when exactly this should happen
            ack_trs = new(1, trs.data.opcode, trs.data.strm, trs.data.remote, 1 /* TODO: what is this? */, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("Sending ack: opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks.put(ack_trs);

        end
    endtask

    task run_sq_wr_recv();
        forever begin
            c_trs_req trs = new();
            c_trs_ack ack_trs;
            sq_wr.recv(trs.data);
            trs.req_time = $realtime;

            // initiate the transfer
            if (trs.data.strm == 3) begin
                // TODO: implement
                rdma_rreq_wr[trs.data.dest].put(trs);
            end
            else if (trs.data.strm == 1) begin
                host_mem_wr[trs.data.dest].put(trs);
            end

            $display("run_sq_wr_recv: %x %d %d %d %d %d %d %d", trs.data.vaddr, trs.data.len, trs.data.opcode, trs.data.pid, trs.data.strm, trs.data.mode, trs.data.rdma, trs.data.remote);

            // acknowledge transfer
            // TODO: figure out when exactly this should happen
            ack_trs = new(0, trs.data.opcode, trs.data.strm, trs.data.remote, 1 /* TODO: what is this? */, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("Sending ack: opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks.put(ack_trs);

        end
    endtask

    task run_req();
        fork
            run_sq_rd_recv();
            run_sq_wr_recv();
        join_any
    endtask

    task run_ack();
        forever begin
            c_trs_ack trs = new(0, 0, 0, 0, 0, 0, 0, 0);
            ack_t data;

            acks.get(trs);

            data.opcode = trs.opcode;
            data.strm = trs.strm;
            data.remote = trs.remote;
            data.host = trs.host;
            data.dest = trs.dest;
            data.pid = trs.pid;
            data.vfid = trs.vfid;
            data.rsrvd = 0;

            $display("Ack: opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", data.opcode, data.strm, data.remote, data.host, data.dest, data.pid, data.vfid);

            if (trs.rd) begin
                cq_rd.send(data);
            end
            else begin
                cq_wr.send(data);
            end
        end
    endtask

endclass
