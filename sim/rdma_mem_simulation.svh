

class rdma_mem_simulation;
    mailbox mail_rreq_recv[N_RDMA_AXI];
    mailbox mail_rreq_send[N_RDMA_AXI];
    mailbox mail_rrsp_recv[N_RDMA_AXI];
    mailbox mail_rrsp_send[N_RDMA_AXI];
    c_axisr rreq_recv[N_RDMA_AXI];
    c_axisr rreq_send[N_RDMA_AXI];
    c_axisr rrsp_recv[N_RDMA_AXI];
    c_axisr rrsp_send[N_RDMA_AXI];

    typedef logic[47:0] addr_t;
    typedef logic[8:0] data_t;
    typedef logic[63:0] keep_t;

    // Data in memory
    data_t mem_segments[$][];
    addr_t mem_vaddrs[$];
    addr_t mem_lengths[$];

    // Files to output transfers
    integer write_file;
    integer read_file;

    function new(
        mailbox mail_rdma_rreq_recv[N_RDMA_AXI],
        mailbox mail_rdma_rreq_send[N_RDMA_AXI],
        mailbox mail_rdma_rrsp_recv[N_RDMA_AXI],
        mailbox mail_rdma_rrsp_send[N_RDMA_AXI],
        c_axisr axis_rdma_rreq_recv[N_RDMA_AXI],
        c_axisr axis_rdma_rreq_send[N_RDMA_AXI],
        c_axisr axis_rdma_rrsp_recv[N_RDMA_AXI],
        c_axisr axis_rdma_rrsp_send[N_RDMA_AXI]
    );
        mail_rreq_recv = mail_rdma_rreq_recv;
        mail_rreq_send = mail_rdma_rreq_send;
        mail_rrsp_recv = mail_rdma_rrsp_recv;
        mail_rrsp_send = mail_rdma_rrsp_send;
        rreq_recv = axis_rdma_rreq_recv;
        rreq_send = axis_rdma_rreq_send;
        rrsp_recv = axis_rdma_rrsp_recv;
        rrsp_send = axis_rdma_rrsp_send;
    endfunction

    function set_data(string path_name,
        string file_name
    );
        addr_t vaddr;
        addr_t length;
        string full_file_name;
        data_t data[];
        int n_segments;
        $sscanf(file_name, "rdma-%x-%x.txt", vaddr, length);

        full_file_name = {
            path_name,
            file_name
        };

        data = new[length];
        $readmemh(full_file_name, data);
        mem_segments.push_back(data);
        mem_vaddrs.push_back(vaddr);
        mem_lengths.push_back(length);
        n_segments = $size(mem_segments) - 1;
        $display(
            "Loaded Segment '%s' at %x with length %x",
            file_name,
            mem_vaddrs[n_segments],
            mem_lengths[n_segments]
        );
    endfunction

    task reset(string path_name);
        $display("RDMA Memory Simulation: reset");
        write_file = $fopen({path_name, "rdma_mem_write_output.txt"}, "w");
        read_file = $fopen({path_name, "rdma_mem_read_output.txt"}, "w");
        for (int i = 0; i < N_RDMA_AXI; i++) begin
            rreq_send[i].reset_s();
            rrsp_send[i].reset_s();
            rreq_recv[i].reset_m();
            rrsp_recv[i].reset_m();
        end
        $display("RDMA Memory Simulation: reset complete");
    endtask

    // TODO: reimplement


    task run_rreq_send(input int strm);
        forever begin
            c_trs_req trs;
            c_trs_strm_data trs_data = new();
            addr_t base_addr;
            int length;
            int n_blocks;
            mail_rreq_send[strm].get(trs);
            $display("RDMA MEM SIMULATION: got rreq_send: len=%d", trs.data.len);

            // TODO: for now there is no start offset
            base_addr = trs.data.vaddr;
            length = trs.data.len;
            n_blocks = (length + 63) / 64;

            // TODO: implement delay for accepting writes
            for (int i = 0; i < n_blocks * 64; i += 64) begin // TODO: do properly
                rreq_send[strm].recv(trs_data.data, trs_data.keep, trs_data.last, trs_data.pid);
                $display(
                    "RDMA_RREQ_SEND received chunk: data=%x keep=%x last=%b pid=%d",
                    trs_data.data,
                    trs_data.keep,
                    trs_data.last,
                    trs_data.pid
                );
                // TODO: actually receive data and mutate the state of memory
                // TODO: write 'transfers' file
            end

            $display("RDMA MEM SIMULATION: completed mem_write");
        end
    endtask

    task run_rrsp_send(input int strm);
        forever begin
            c_trs_req trs;
            c_trs_strm_data trs_data = new();
            addr_t base_addr;
            int length;
            int n_blocks;
            mail_rrsp_send[strm].get(trs);
            $display("RDMA MEM SIMULATION: got rrsp_send[%d]: len=%d", strm, trs.data.len);

            // TODO: for now there is no start offset
            base_addr = trs.data.vaddr;
            length = trs.data.len;
            n_blocks = (length + 63) / 64;

            // TODO: implement delay for accepting writes
            for (int i = 0; i < n_blocks * 64; i += 64) begin // TODO: do properly
                rrsp_send[strm].recv(trs_data.data, trs_data.keep, trs_data.last, trs_data.pid);
                $display(
                    "RDMA_RRSP_SEND received chunk: data=%x keep=%x last=%b pid=%d",
                    trs_data.data,
                    trs_data.keep,
                    trs_data.last,
                    trs_data.pid
                );
                // TODO: actually receive data and mutate the state of memory
                // TODO: write 'transfers' file
            end

            $display("RDMA MEM SIMULATION: completed mem_write");
        end
    endtask

    // TODO: reimplement
    task run_rreq_recv(input int strm);
        forever begin
            c_trs_req trs;
            addr_t length;
            int n_blocks;
            addr_t base_addr;
            int segment_idx;
            data_t segment[];
            mail_rreq_recv[strm].get(trs);

            // delay this request a little after its issue time
            $display(
                "Delaying for: %t (req_time: %t, realtime: %t)",
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );
            // negatives will be considered as two's complement (I intend to finish the simulation in this decade)
            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);

            $display(
                "RDMA MEM SIMULATION: got mem_read[%d]: len=%d, vaddr=%x",
                strm,
                trs.data.len,
                trs.data.vaddr
            );

            // TODO: for now, there is no start offset and memory is read at the start index
            length = trs.data.len;
            n_blocks = (length + 63) / 64;
            base_addr = trs.data.vaddr;
            // TODO: for now, nothing else is relevant

            // NOTE: I assume that a transfer only intersects with a single segment
            segment_idx = 0;
            for (; segment_idx < $size(mem_vaddrs); segment_idx++) begin
                // check if transfer starts within this segment
                if (base_addr >= mem_vaddrs[segment_idx] &&
                        base_addr <= mem_vaddrs[segment_idx] + mem_lengths[segment_idx])
                    break;
                // check if transfer ends within this segment
                if (base_addr + length >= mem_vaddrs[segment_idx] &&
                        base_addr + length <= mem_vaddrs[segment_idx] + mem_lengths[segment_idx])
                    break;
            end
            segment = mem_segments[segment_idx];

            for (int i = 0; i < n_blocks * 64; i += 64) begin
                logic[511:0] data = 512'h00;
                keep_t keep = ~64'h00;
                addr_t offset;
                bit last = i + 64 == n_blocks * 64;

                // compute the keep offset
                if (last) keep >>= 64 - (length - i);

                // compute data offset
                offset = base_addr + i - mem_vaddrs[segment_idx];
                // TODO: recognize non allocated bytes
                for (int i = 0; i < 64; i++) begin
                    data[(i*8)+:8] ^= segment[offset + i];
                    // why strange data here
                    $display("Byte from segment: %x (offset: %x)", segment[offset + i], offset + i);
                end

                // transfer tdata, tkeep, tlast and the tpid for the transfer
                rreq_recv[strm].send(data, keep, last, trs.data.pid);
            end
        end
    endtask

    task run_rrsp_recv(input int strm);
        forever begin
            c_trs_req trs;
            addr_t length;
            int n_blocks;
            addr_t base_addr;
            int segment_idx;
            data_t segment[];
            mail_rrsp_recv[strm].get(trs);

            // delay this request a little after its issue time
            $display(
                "Delaying for: %t (req_time: %t, realtime: %t)",
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );
            // negatives will be considered as two's complement (I intend to finish the simulation in this decade)
            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);

            $display(
                "RDMA MEM SIMULATION: got mem_read[%d]: len=%d, vaddr=%x",
                strm,
                trs.data.len,
                trs.data.vaddr
            );

            // TODO: for now, there is no start offset and memory is read at the start index
            length = trs.data.len;
            n_blocks = (length + 63) / 64;
            base_addr = trs.data.vaddr;
            // TODO: for now, nothing else is relevant

            // NOTE: I assume that a transfer only intersects with a single segment
            segment_idx = 0;
            for (; segment_idx < $size(mem_vaddrs); segment_idx++) begin
                // check if transfer starts within this segment
                if (base_addr >= mem_vaddrs[segment_idx] &&
                        base_addr <= mem_vaddrs[segment_idx] + mem_lengths[segment_idx])
                    break;
                // check if transfer ends within this segment
                if (base_addr + length >= mem_vaddrs[segment_idx] &&
                        base_addr + length <= mem_vaddrs[segment_idx] + mem_lengths[segment_idx])
                    break;
            end

            $display(
                "Segment: index: %d, vaddr: %x, length: %x (actual: %x), n_segments: %d",
                segment_idx,
                mem_vaddrs[segment_idx],
                mem_lengths[segment_idx],
                $size(mem_segments[segment_idx]),
                $size(mem_segments)
            );
            $display(
                "%x %x %x %x",
                mem_segments[segment_idx][0],
                mem_segments[segment_idx][1],
                mem_segments[segment_idx][2],
                mem_segments[segment_idx][3]
            );
            segment = mem_segments[segment_idx];

            for (int i = 0; i < n_blocks * 64; i += 64) begin
                logic[511:0] data = 512'h00;
                keep_t keep = ~64'h00;
                addr_t offset;
                bit last = i + 64 == n_blocks * 64;

                // compute the keep offset
                if (last) keep >>= 64 - (length - i);

                // compute data offset
                offset = base_addr + i - mem_vaddrs[segment_idx];
                // TODO: recognize non allocated bytes
                for (int i = 0; i < 64; i++) begin
                    data[(i*8)+:8] ^= segment[offset + i];
                    // why strange data here
                    $display("Byte from segment: %x (offset: %x)", segment[offset + i], offset + i);
                end

                // transfer tdata, tkeep, tlast and the tpid for the transfer
                rrsp_recv[strm].send(data, keep, last, trs.data.pid);
            end
        end
    endtask
endclass;
