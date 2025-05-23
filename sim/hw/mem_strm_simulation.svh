import sim_pkg::*;

class mem_t; // We need this as a wrapper because you cannot pass queues [$] by reference
    mem_seg_t segs[$];
endclass

class mem_strm_simulation;
    typedef logic[63:0] keep_t;

    int strm;
    string name;

    mailbox acks_mbx;
    mailbox sq_rd_mbx;
    mailbox sq_wr_mbx;

    c_axisr send_drv;
    c_axisr recv_drv;

    mem_t mem;

    function new (int strm, string name, mailbox acks_mbx, mailbox sq_rd_mbx, mailbox sq_wr_mbx, c_axisr send_drv, c_axisr recv_drv, mem_t mem);
        this.strm = strm;
        this.name = name;

        this.acks_mbx = acks_mbx;
        this.sq_rd_mbx = sq_rd_mbx;
        this.sq_wr_mbx = sq_wr_mbx;

        this.send_drv = send_drv;
        this.recv_drv = recv_drv;

        this.mem = mem;
    endfunction

    task run_write_queue();
        bit[511:0] recv_data;
        bit[63:0] recv_keep;
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
            sq_wr_mbx.get(trs);

            // Delay this request a little after its issue time
            $display(
                "%s mock: Delaying send for: %0t (req_time: %0t, realtime: %0t)",
                name,
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );

            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);
            
            $display("%s mock: Got send[%0d]: vaddr=%x, len=%0d", name, strm, trs.data.vaddr, trs.data.len);

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

            if(segment_idx == -1) begin
                $display("%s mock: No segment found to write data to in memory.", name);
            end else begin            
                // Go through every 64 byte block
                for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                    send_drv.recv(recv_data, recv_keep, recv_last, recv_tid);
                        
                    offset = base_addr + (current_block * 64) - mem.segs[segment_idx].vaddr;

                    for(int current_byte = 0; current_byte < 64; current_byte++)begin

                        // Mask keep signal
                        if(recv_keep[current_byte]) begin
                            mem.segs[segment_idx].data[offset + current_byte] = recv_data[(current_byte * 8)+:8];
                        end
                    end

                    // Write transfer file
                    // $fdisplay(transfer_file, "%t: %s_SEND: %d, %h, %h, %h, %b", $realtime, name, strm, base_addr + (current_block * 64), recv_data[0+:512], recv_keep, recv_last);
                    // $display("%s mock: Send block %h at address %d, keep: %h, last: %b", name, recv_data[0+:512], base_addr + (current_block * 64), recv_keep, recv_last);
                end
            end
            ack_trs = new(0, trs.data.opcode, trs.data.strm, trs.data.remote, trs.data.host, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("%s mock: Sending ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", name, ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks_mbx.put(ack_trs);
            $display("%s mock: Completed send.", name);
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
            $display(
                "%s mock: Delaying recv for: %0t (req_time: %0t, realtime: %0t)",
                name,
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );
            
            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);

            $display("%s mock: Got recv[%0d]: vaddr=%x, len=%0d", name, strm, trs.data.vaddr, trs.data.len);

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

            if(segment_idx == -1) begin
                $display("%s mock: No segment found to get data from in memory.", name);
            end else begin
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
                        data[511-((63-current_byte)*8) -:8] = segment[offset + current_byte];
                    end

                    // Write transfer file
                    // $fdisplay(transfer_file, "%t: %s_RECV: %d, %h, %x, %x, %d", $realtime, name, strm, base_addr + (current_block * 64), data, keep, last);
                    // $display("%s mock: Receiving data recv [%0d]: %x", name, strm, data);
                    recv_drv.send(data, keep, last, trs.data.pid);
                end
            end

            ack_trs = new(1, trs.data.opcode, trs.data.strm, trs.data.remote, trs.data.host, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("%s mock: Sending ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", name, ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks_mbx.put(ack_trs);
            $display("%s mock: Completed recv.", name);
        end
    endtask
endclass