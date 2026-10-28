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

import sim_pkg::*;

`include "log.svh"
`include "sim_params.svh"

/**
 * This class wraps the send and recv drivers of a host or card stream.
 * It also has a reference to the respective memory mock.
 * It waits for read and write requests on the respective mailboxes.
 * After a request finishes, it sends an acknowledgement.
 */
class stream_simulation;
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
    mock_params params;
    sim_rng rd_rng;
    sim_rng wr_rng;

    function new (
        input int dest, 
        input string name, 
        mailbox #(c_trs_ack) acks_mbx,
        mailbox #(c_trs_req) sq_rd_mbx, 
        mailbox #(c_trs_req) sq_wr_mbx, 
        c_axisr send_drv, 
        c_axisr recv_drv, 
        mem_t mem, 
        scoreboard scb,
        mock_params params
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
        this.params = params;

        this.rd_rng = new(params.seed, name, dest, 0);
        this.wr_rng = new(params.seed, name, dest, 1);
    endfunction

    // Extra wait of one request, uniform in [0, jitter]
    function realtime jitter_delay(sim_rng rng);
        if (params.jitter == 0) return 0;
        return rng.uniform() * params.jitter;
    endfunction

    // One draw at the first beat of every MTU (with mtu 0 at the first beat of the transfer); 1 is a loss
    function bit mtu_lost(sim_rng rng, int block);
        if (params.drop == 0) return 0;
        if (params.mtu == 0 ? block != 0 : (block * AXI_DATA_BYTES) % params.mtu != 0) return 0;
        return rng.uniform() < params.drop;
    endfunction

    function int mtu_index(int block);
        return (params.mtu == 0) ? 0 : block * AXI_DATA_BYTES / params.mtu;
    endfunction

    // One clock of the direction: wr is data into the mock (send_drv), else data out of it (recv_drv)
    task clock(bit wr);
        if (wr) @(send_drv.axis.cbs);
        else @(recv_drv.axis.cbm);
    endtask

    task wait_until(bit wr, realtime t);
        while ($realtime < t) clock(wr);
    endtask

    // Before one beat: a lost MTU is resent, so the stream stalls for the retransmission time and
    // then carries the same data.
    task throttle(bit wr, int block, vaddr_t vaddr, ref int n_drops);
        sim_rng rng = wr ? wr_rng : rd_rng;
        token_bucket bucket = wr ? params.wr : params.rd;
        if (mtu_lost(rng, block)) begin
            n_drops++;
            `DEBUG(("%s[%0d]: dropped MTU %0d of %s at vaddr %x, resend after %0.0f ns", name, dest, mtu_index(block),
                wr ? string'("send") : string'("recv"), vaddr, params.retransmit / 1ns))
            wait_until(wr, $realtime + params.retransmit);
        end
        while (!bucket.take()) clock(wr);
    endtask

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
            mem_seg_t segment;
            int keep_bits;
            int n_last;
            int n_drops;
            bit missing_last;
            realtime ready_at;

            // We need this as non-blocking with @(...), otherwise timing might be off if we do a busy wait and we would need to wait an additional cycle
            int success = sq_wr_mbx.try_get(trs);
            while (!success) begin
                @(send_drv.axis.cbs);
                success = sq_wr_mbx.try_get(trs);
            end

            // Delay this request a little after its issue time
            ready_at = trs.req_time + params.latency + jitter_delay(wr_rng);
            if (ready_at > $realtime) begin
                `DEBUG(("%s[%0d]: Delaying send for: %0t (req_time: %0t, realtime: %0t)", name, dest, ready_at - $realtime, trs.req_time, $realtime))
            end
            wait_until(1, ready_at);

            `DEBUG(("%s[%0d]: Got send: vaddr=%x, len=%0d", name, dest, trs.data.vaddr, trs.data.len))

            base_addr = trs.data.vaddr;
            length = trs.data.len;
            n_blocks = (length + AXI_DATA_BYTES - 1) / AXI_DATA_BYTES;

            `ASSERT(mem.is_mapped(base_addr, length), ("%s[%0d]: No segment found to write data to in memory.", name, dest))
            segment = null;

            missing_last = 0;
            n_last = 0;
            n_drops = 0;
            for (int current_block = 0; current_block < n_blocks; current_block++) begin
                throttle(1, current_block, trs.data.vaddr, n_drops);
                send_drv.recv(recv_data, recv_keep, recv_last, recv_tid);
                `VERBOSE(("%s[%0d]: Received data from send", name, dest))
                if (recv_last) n_last++;
                    
                keep_bits = 0;
                for (int current_byte = 0; current_byte < AXI_DATA_BYTES; current_byte++) begin
                    // Mask keep signal
                    if (recv_keep[current_byte]) begin
                        // The request may span multiple segments, so we look up the segment whenever we leave the current one
                        vaddr_t addr = base_addr + (current_block * AXI_DATA_BYTES) + current_byte;
                        if (segment == null || addr < segment.vaddr || addr >= segment.vaddr + segment.size) begin
                            segment = mem.find_seg(addr);
                            `ASSERT(segment != null, ("%s[%0d]: No segment found to write data to in memory at vaddr %x.", name, dest, addr))
                        end
                        segment.data[addr - segment.vaddr] = recv_data[(current_byte * 8)+:8];
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
                n_last++;
            end

            ack_trs = new();
            ack_trs.initialize(0, trs);
            `DEBUG(("%s[%0d]: Sending send ack: write, opcode=%d, strm=%d, host=%d, dest=%d, pid=%d, vfid=%d, last=%d", name, dest, ack_trs.opcode, ack_trs.strm, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid, ack_trs.last))
            acks_mbx.put(ack_trs);
            `DEBUG(("%s[%0d]: Completed send, %0d beats with tlast, %0d drops.", name, dest, n_last, n_drops))
        end
    endtask

    task run_read_queue();
        forever begin
            c_trs_req trs;
            c_trs_ack ack_trs;
            vaddr_t length;
            int n_blocks;
            vaddr_t base_addr;
            byte segment[];
            int n_drops;
            realtime ready_at;

            // We need this as non-blocking with @(...), otherwise timing might be off if we do a busy wait and we would need to wait an additional cycle
            int success = sq_rd_mbx.try_get(trs);
            while (!success) begin
                @(recv_drv.axis.cbm);
                success = sq_rd_mbx.try_get(trs);
            end

            // Delay this request a little after its issue time
            ready_at = trs.req_time + params.latency + jitter_delay(rd_rng);
            if (ready_at > $realtime) begin
                `DEBUG(("%s[%0d]: Delaying recv for: %0t (req_time: %0t, realtime: %0t)", name, dest, ready_at - $realtime, trs.req_time, $realtime))
            end
            wait_until(0, ready_at);

            `DEBUG(("%s[%0d]: Got recv: vaddr=%x, len=%0d", name, dest, trs.data.vaddr, trs.data.len))

            length = trs.data.len;
            n_blocks = (length + AXI_DATA_BYTES - 1) / AXI_DATA_BYTES;
            base_addr = trs.data.vaddr;

            // Copy the requested data out of the memory segments it spans
            if (!mem.read(base_addr, length, segment)) begin
                `FATAL(("%s[%0d]: No segment found to read data from in memory.", name, dest))
            end

            n_drops = 0;
            for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                logic[AXI_DATA_BITS - 1:0] data = 0;
                keep_t keep = -1;
                vaddr_t offset;
                bit last = current_block + 1 == n_blocks;
                // tlast at every MTU of the request; the final beat follows the request's last flag
                bit mtu_end = params.mtu != 0 && ((current_block + 1) * AXI_DATA_BYTES) % params.mtu == 0;

                // Compute the keep offset
                if (last) keep >>= AXI_DATA_BYTES - (length - (current_block * AXI_DATA_BYTES));

                // Compute data offset
                offset = current_block * AXI_DATA_BYTES;

                // Ugly conversion because we use MSB data, but memory is read in LSB fashion
                for (int current_byte = 0; current_byte < AXI_DATA_BYTES; current_byte++) begin
                    data[AXI_DATA_BITS - 1 - ((AXI_DATA_BYTES - 1 - current_byte) * 8)-:8] = segment[offset + current_byte];
                end

                throttle(0, current_block, trs.data.vaddr, n_drops);

                `VERBOSE(("%s[%0d]: Sending data to recv", name, dest))
                recv_drv.send(data, keep, last ? trs.data.last : mtu_end, trs.data.pid);
            end

            ack_trs = new();
            ack_trs.initialize(1, trs);
            `DEBUG(("%s[%0d]: Sending recv ack: read, opcode=%d, strm=%d, host=%d, dest=%d, pid=%d, vfid=%d, last=%d", name, dest, ack_trs.opcode, ack_trs.strm, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid, ack_trs.last))
            acks_mbx.put(ack_trs);
            `DEBUG(("%s[%0d]: Completed recv, %0d drops.", name, dest, n_drops))
        end
    endtask
endclass
