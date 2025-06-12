import sim_pkg::*;

`include "log.svh"

class mem_t; // We need this as a wrapper because you cannot pass queues [$] by reference
    mem_seg_t segs[$];
endclass

class stream_simulation;
    localparam REQ_DELAY = 50ns;

    typedef logic[63:0] keep_t;

    int dest;
    string name;

    mailbox #(c_trs_ack) acks_mbx;
    mailbox #(c_trs_req) sq_rd_mbx;
    mailbox #(c_trs_req) sq_wr_mbx;

    c_axisr send_drv;
    c_axisr recv_drv;

    mem_t mem;
    scoreboard scb;

    function new (
        input int dest, 
        input string name, 
        mailbox #(c_trs_ack) acks_mbx,
        mailbox #(c_trs_req) sq_rd_mbx, 
        mailbox #(c_trs_req) sq_wr_mbx, 
        c_axisr send_drv, 
        c_axisr recv_drv, 
        mem_t mem, 
        scoreboard scb
    );
        this.dest = dest;
        this.name = name;

        this.acks_mbx = acks_mbx;
        this.sq_rd_mbx = sq_rd_mbx;
        this.sq_wr_mbx = sq_wr_mbx;

        this.send_drv = send_drv;
        this.recv_drv = recv_drv;

        this.mem = mem;
        this.scb = scb;
    endfunction

    task run_write_queue();
        bit[AXI_DATA_BITS - 1:0] recv_data;
        bit[AXI_DATA_BITS / 8 - 1:0] recv_keep;
        bit recv_last;
        bit[5:0] recv_tid;

        forever begin
            c_trs_req trs;
            c_trs_ack ack_trs;
            vaddr_t base_addr;
            int length;
            int n_blocks;
            int offset;
            int segment_idx;
            int keep_bits;
            bit missing_last;

            sq_wr_mbx.get(trs);

            // Delay this request a little after its issue time
            `DEBUG((
                "%s[%0d]: Delaying send for: %0t (req_time: %0t, realtime: %0t)",
                name,
                dest,
                trs.req_time + REQ_DELAY - $realtime,
                trs.req_time,
                $realtime
            ))

            @(recv_drv.axis.cbs); // We need this, otherwise timing might be off if we do not wait in the loop below
            while (trs.req_time + REQ_DELAY - $realtime > 0)
                @(recv_drv.axis.cbs);
            
            `DEBUG(("%s[%0d]: Got send: vaddr=%x, len=%0d", name, dest, trs.data.vaddr, trs.data.len))

            base_addr = trs.data.vaddr;
            length = trs.data.len;
            n_blocks = (length + 63) / 64;

            // Get the right mem_segment
            segment_idx = -1;
            for(int i = 0; i < $size(mem.segs); i++) begin
                if (mem.segs[i].vaddr <= base_addr && (mem.segs[i].vaddr + mem.segs[i].size) >= (base_addr + length)) begin
                    segment_idx = i;
                end
            end

            `ASSERT(segment_idx > -1, ("%s[%0d]: No segment found to write data to in memory.", name, dest))
         
            // Go through every 64 byte block
            missing_last = 0;
            for (int current_block = 0; current_block < n_blocks; current_block++) begin
                send_drv.recv(recv_data, recv_keep, recv_last, recv_tid);
                `VERBOSE(("%s[%0d]: Received data from send: %x", name, dest, data))
                    
                offset = base_addr + (current_block * 64) - mem.segs[segment_idx].vaddr;

                keep_bits = 0;
                for (int current_byte = 0; current_byte < 64; current_byte++) begin
                    // Mask keep signal
                    if (recv_keep[current_byte]) begin
                        mem.segs[segment_idx].data[offset + current_byte] = recv_data[(current_byte * 8)+:8];
                        keep_bits++;
                    end
                end

                if (current_block < n_blocks - 1) begin
                    `ASSERT(keep_bits == 64, ("%s[%0d]: Stream keep %b is not normalized.", name, dest, recv_keep))
                end else begin // Last block
                    int remaining_length = length - (n_blocks - 1) * 64;
                    `ASSERT(keep_bits == remaining_length, ("%s[%0d]: Last data beat size %0d does not match remaining request size %0d.", name, dest, keep_bits, remaining_length))
                    if (trs.data.last && !recv_last) missing_last = 1;
                end

                if (name == "HOST") begin
                    scb.writeHostMem(base_addr + (current_block * 64), recv_data, recv_keep);
                end
            end

            if (missing_last) begin // Check for one more data beat that is just the last signal
                send_drv.recv(recv_data, recv_keep, recv_last, recv_tid);
                `ASSERT(!recv_keep && recv_last, ("%s[%0d]: Stream that has to be terminated by last but is not.", name, dest))
            end

            ack_trs = new();
            ack_trs.initialize(0, trs);
            `DEBUG(("%s[%0d]: Sending send ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d, last=%d", name, dest, ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid, ack_trs.last))
            acks_mbx.put(ack_trs);
            `DEBUG(("%s[%0d]: Completed send.", name, dest))
        end
    endtask

    task run_read_queue();
        forever begin
            c_trs_req trs;
            c_trs_ack ack_trs;
            vaddr_t length;
            int n_blocks;
            vaddr_t base_addr;
            int segment_idx;
            byte segment[];
            
            sq_rd_mbx.get(trs);

            // Delay this request a little after its issue time
            `DEBUG((
                "%s[%0d]: Delaying recv for: %0t (req_time: %0t, realtime: %0t)",
                name,
                dest,
                trs.req_time + REQ_DELAY - $realtime,
                trs.req_time,
                $realtime
            ))
            
            @(recv_drv.axis.cbm); // We need this, otherwise timing might be off if we do not wait in the loop below
            while (trs.req_time + REQ_DELAY - $realtime > 0)
                @(recv_drv.axis.cbm);

            `DEBUG(("%s[%0d]: Got recv: vaddr=%x, len=%0d", name, dest, trs.data.vaddr, trs.data.len))

            length = trs.data.len;
            n_blocks = (length + 63) / 64;
            base_addr = trs.data.vaddr;

            // Get the right mem_segment
            segment_idx = -1;
            for(int i = 0; i < $size(mem.segs); i++) begin
                if (mem.segs[i].vaddr <= base_addr && (mem.segs[i].vaddr + mem.segs[i].size) >= (base_addr + length)) begin
                    segment_idx = i;
                end
            end

            `ASSERT(segment_idx > -1, ("%s[%0d]: No segment found to read data from in memory.", name, dest))

            segment = mem.segs[segment_idx].data;

            for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                logic[511:0] data = 512'h00;
                keep_t keep = ~64'h00;
                vaddr_t offset;
                bit last = current_block + 1 == n_blocks;

                // Compute the keep offset
                if (last) keep >>= 64 - (length - (current_block * 64));

                // Compute data offset
                offset = base_addr + (current_block * 64) - mem.segs[segment_idx].vaddr;

                // Ugly conversion because we use MSB data, but memory is read in LSB fashion
                for (int current_byte = 0; current_byte < 64; current_byte++) begin
                    data[511 - ((63 - current_byte) * 8)-:8] = segment[offset + current_byte];
                end

                `VERBOSE(("%s[%0d]: Sending data to recv: %x", name, dest, data))
                recv_drv.send(data, keep, trs.data.last ? last : 0, trs.data.pid);
            end

            ack_trs = new();
            ack_trs.initialize(1, trs);
            `DEBUG(("%s[%0d]: Sending recv ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d, last=%d", name, dest, ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid, ack_trs.last))
            acks_mbx.put(ack_trs);
            `DEBUG(("%s[%0d]: Completed recv.", name, dest))
        end
    endtask
endclass