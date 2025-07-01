import sim_pkg::*;

`include "log.svh"

/**
 * This class wraps the send and recv drivers of a host or card stream.
 * It also has a reference to the respective memory mock.
 * It waits for read and write requests on the respective request mailboxes and uses the corresponding driver to read or write the data from/to the stream.
 * After a request finishes, it sends an acknowledgement through the acks_mbx mailbox.
 */
class stream_simulation;
    localparam REQ_DELAY = 50ns;
    localparam AXI_DATA_BYTES = AXI_DATA_BITS / 8;

    typedef logic[AXI_DATA_BYTES - 1:0] keep_t;

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
        bit[AXI_DATA_BYTES - 1:0] recv_keep;
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

            // We need this as non-blocking with @(...), otherwise timing might be off if we do a busy wait and we would need to wait an additional cycle
            int success = sq_wr_mbx.try_get(trs);
            while (!success) begin
                @(send_drv.axis.cbs);
                success = sq_wr_mbx.try_get(trs);
            end

            // Delay this request a little after its issue time
            if (trs.req_time + REQ_DELAY - $realtime > 0) begin
                `DEBUG(("%s[%0d]: Delaying send for: %0t (req_time: %0t, realtime: %0t)", name, dest, trs.req_time + REQ_DELAY - $realtime, trs.req_time, $realtime))
            end
 
            while (trs.req_time + REQ_DELAY - $realtime > 0)
                @(recv_drv.axis.cbs);
            
            `DEBUG(("%s[%0d]: Got send: vaddr=%x, len=%0d", name, dest, trs.data.vaddr, trs.data.len))

            base_addr = trs.data.vaddr;
            length = trs.data.len;
            n_blocks = (length + AXI_DATA_BYTES - 1) / AXI_DATA_BYTES;

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
                `VERBOSE(("%s[%0d]: Received data from send", name, dest))
                    
                offset = base_addr + (current_block * AXI_DATA_BYTES) - mem.segs[segment_idx].vaddr;

                keep_bits = 0;
                for (int current_byte = 0; current_byte < AXI_DATA_BYTES; current_byte++) begin
                    // Mask keep signal
                    if (recv_keep[current_byte]) begin
                        mem.segs[segment_idx].data[offset + current_byte] = recv_data[(current_byte * 8)+:8];
                        keep_bits++;
                    end
                end

                if (current_block < n_blocks - 1) begin
                    `ASSERT(keep_bits == AXI_DATA_BYTES, ("%s[%0d]: Stream keep %b is not normalized.", name, dest, recv_keep))
                end else begin // Last block
                    int remaining_length = length - (n_blocks - 1) * AXI_DATA_BYTES;
                    `ASSERT(keep_bits == remaining_length, ("%s[%0d]: Last data beat size %0d does not match remaining request size %0d.", name, dest, keep_bits, remaining_length))
                    if (trs.data.last && !recv_last) missing_last = 1;
                end

                if (name == "HOST") begin
                    scb.writeHostMem(base_addr + (current_block * AXI_DATA_BYTES), recv_data, recv_keep);
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
            
            // We need this as non-blocking with @(...), otherwise timing might be off if we do a busy wait and we would need to wait an additional cycle
            int success = sq_rd_mbx.try_get(trs);
            while (!success) begin
                @(recv_drv.axis.cbm);
                success = sq_rd_mbx.try_get(trs);
            end

            // Delay this request a little after its issue time
            if (trs.req_time + REQ_DELAY - $realtime > 0) begin
                `DEBUG(("%s[%0d]: Delaying recv for: %0t (req_time: %0t, realtime: %0t)", name, dest, trs.req_time + REQ_DELAY - $realtime, trs.req_time, $realtime))
            end
            
            while (trs.req_time + REQ_DELAY - $realtime > 0)
                @(recv_drv.axis.cbm);

            `DEBUG(("%s[%0d]: Got recv: vaddr=%x, len=%0d", name, dest, trs.data.vaddr, trs.data.len))

            length = trs.data.len;
            n_blocks = (length + AXI_DATA_BYTES - 1) / AXI_DATA_BYTES;
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
                logic[AXI_DATA_BITS - 1:0] data = 0;
                keep_t keep = -1;
                vaddr_t offset;
                bit last = current_block + 1 == n_blocks;

                // Compute the keep offset
                if (last) keep >>= AXI_DATA_BYTES - (length - (current_block * AXI_DATA_BYTES));

                // Compute data offset
                offset = base_addr + (current_block * AXI_DATA_BYTES) - mem.segs[segment_idx].vaddr;

                // Ugly conversion because we use MSB data, but memory is read in LSB fashion
                for (int current_byte = 0; current_byte < AXI_DATA_BYTES; current_byte++) begin
                    data[AXI_DATA_BITS - 1 - ((AXI_DATA_BYTES - 1 - current_byte) * 8)-:8] = segment[offset + current_byte];
                end

                `VERBOSE(("%s[%0d]: Sending data to recv", name, dest))
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