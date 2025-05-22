/* 
* This class simulates the actions on the other end of the host interface, it holds a virtual memory from which data can be read and written to and also simulates the simple streaming of data without work queue entries
*/

typedef struct packed {
    logic[VADDR_BITS - 1:0] vaddr;
    logic[VADDR_BITS - 1:0] size;
} vaddr_size_t;

class mem_mock #(N_AXI);
    typedef logic[VADDR_BITS - 1:0] vaddr_t;
    typedef logic[7:0]  data_t;
    typedef logic[63:0] keep_t;

    mailbox acks_mbx;
    mailbox sq_rd_mbx[N_AXI];
    mailbox sq_wr_mbx[N_AXI];

    c_axisr send_drv[N_AXI];
    c_axisr recv_drv[N_AXI];

    // Data is stored in simulated memory segments
    // The data segments are defined by the data they hold, their starting address, and the length
    data_t  mem_segments[$][];
    vaddr_t mem_vaddrs[$];
    vaddr_t mem_sizes[$];

    // Files to output a record of all transfers that happened and a dump of the resulting host memory
    integer transfer_file;
    integer data_file;

    function new(
        mailbox acks_mbx,
        mailbox sq_rd_mbx[N_AXI],
        mailbox sq_wr_mbx[N_AXI],
        c_axisr send_drv[N_AXI],
        c_axisr recv_drv[N_AXI]
    );
        this.acks_mbx       = acks_mbx;
        this.sq_rd_mbx = sq_rd_mbx;
        this.sq_wr_mbx = sq_wr_mbx;

        this.send_drv = send_drv;
        this.recv_drv = recv_drv;
    endfunction

    function merge_mem_segments(data_t segments[][], vaddr_t start_addrs[], vaddr_t sizes[], data_t new_seg_data[], vaddr_t new_seg_vaddr, data_t new_seg_size);
        data_t result[];
        vaddr_t resulting_size;

        vaddr_t start_adress = start_addrs[0];
        vaddr_t end_adress = start_addrs[0] + sizes[0];
        vaddr_t offset_new_seg;

        // Find start and end address of the resulting memory segment
        for (int i = 1; i < $size(segments); i++) begin
            if (start_addrs[i] < start_adress) begin
                start_adress = start_addrs[i];
            end
            if (start_addrs[i] + sizes[i] > end_adress) begin
                end_adress = start_addrs[i] + sizes[i];
            end
        end
        
        if (new_seg_vaddr < start_adress) begin
            start_adress = new_seg_vaddr;
        end
        if ((new_seg_vaddr + new_seg_size) > end_adress) begin
            end_adress = (new_seg_vaddr + new_seg_size);
        end

        resulting_size = end_adress - start_adress;
        result = new[resulting_size];

        // Fill in already existing data
        for (int i = 0; i < $size(segments); i++) begin
            vaddr_t offset = start_addrs[i] - start_adress;
            for (int j = 0; j < $size(segments[i]); j++) begin
                result[offset + j] = segments[i][j];
            end
        end
        
        offset_new_seg = new_seg_vaddr - start_adress;
        
        // Add data from the new segment
        for (int i = 0; i < new_seg_size; i++) begin
            result[offset_new_seg + i]  = new_seg_data[i];
        end

        mem_segments.push_back(result);
        mem_vaddrs.push_back(start_adress);
        mem_sizes.push_back(resulting_size);
    endfunction

    function malloc(vaddr_t vaddr, vaddr_t size);
        data_t data[];
        int n_segment;

        data_t mem_segments_to_merge[$][];
        vaddr_t mem_vaddrs_to_merge[$];
        vaddr_t mem_sizes_to_merge[$];

        data = new[size];

        //check if any segments need to be merged together because they are overlapping or directly adjacent to each other
        for (int i = 0; i < $size(mem_segments); i++) begin
            if ((mem_vaddrs[i] <= (vaddr + size)) && (mem_vaddrs[i] + mem_sizes[i]) >= vaddr) begin
                mem_segments_to_merge.push_back(mem_segments[i]);
                mem_vaddrs_to_merge.push_back(mem_vaddrs[i]);
                mem_sizes_to_merge.push_back(mem_sizes[i]);
                mem_segments.delete(i);
                mem_vaddrs.delete(i);
                mem_sizes.delete(i);
                i--;
            end
        end

        if ($size(mem_segments_to_merge) != 0) begin
            merge_mem_segments(mem_segments_to_merge, mem_vaddrs_to_merge, mem_sizes_to_merge, data, vaddr, size);
        end else begin
            mem_segments.push_back(data);
            mem_vaddrs.push_back(vaddr);
            mem_sizes.push_back(size);
        end
        n_segment = $size(mem_segments) - 1;
        $display("Allocated segment at %x with length %x in host memory", mem_vaddrs[n_segment], mem_sizes[n_segment]);
    endfunction

    function write_data(vaddr_t vaddr, data_t data);
        for (int i = 0; i < $size(mem_segments); i++) begin
            if (mem_vaddrs[i] <= vaddr && (mem_vaddrs[i] + mem_sizes[i]) >= vaddr) begin
                mem_segments[i][vaddr - mem_vaddrs[i]] = data;
                break;
            end
        end

        $display("Wrote data %x at address %x", vaddr, data);
    endfunction

    task print_data();
        int number_of_segs = $size(mem_segments);

        for(int i = 0; i < number_of_segs; i++)begin
            $fdisplay(data_file, "Segment number: %x, at vaddr: %x, length: %x", i, mem_vaddrs[i], mem_sizes[i]);
            for(int j = 0; j < mem_sizes[i]; j++)begin
                $fdisplay(data_file, "%x", mem_segments[i][j]);
            end
        end
        $fclose(data_file);
        $fclose(transfer_file);
    endtask

    task initialize(string path_name);
        $display("Host simulation: Initialize");

        transfer_file = $fopen({path_name, "host_transfer_output.txt"}, "w");
        data_file = $fopen({path_name, "host_mem_data_output.txt"}, "w");

        for (int i = 0; i < N_AXI; i++) begin
            send_drv[i].reset_s();
            recv_drv[i].reset_m();
        end
        $display("Host simulation: Initialization complete");
    endtask

    task run_write_queue(input int strm);
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
            sq_wr_mbx[strm].get(trs);

            // delay this request a little after its issue time
            $display(
                "Delaying host_send for: %t (req_time: %t, realtime: %t)",
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );

            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);
            
            $display("HOST SIMULATION: got host_send: vaddr=%d len=%d strm_number=%d", trs.data.vaddr, trs.data.len, strm);

            base_addr = trs.data.vaddr;
            length = trs.data.len;
            n_blocks = (length + 63) / 64;

            
            //Get the right mem_segment
            segment_idx = -1;
            for(int i = 0; i < $size(mem_vaddrs); i++) begin
                if (mem_vaddrs[i] <= base_addr && (mem_vaddrs[i] + mem_sizes[i]) > (base_addr + length)) begin
                    segment_idx = i;
                end
            end

            if(segment_idx == -1) begin
                $display("No segment found to write data to in host mem");
            end else begin            
                //go through every 64 byte block
                for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                    send_drv[strm].recv(recv_data, recv_keep, recv_last, recv_tid);
                        
                    offset = base_addr + (current_block * 64) - mem_vaddrs[segment_idx];

                    for(int current_byte = 0; current_byte < 64; current_byte++)begin

                        // Mask keep signal
                        if(recv_keep[current_byte]) begin
                            mem_segments[segment_idx][offset + current_byte] = recv_data[(current_byte * 8)+:8];
                        end
                    end

                    //write transfer file
                    $fdisplay(transfer_file, "%t: HOST_SEND: %d, %h, %h, %h, %b", $realtime, strm, base_addr + (current_block * 64), recv_data[0+:512], recv_keep, recv_last);
                    $display("HOST_SEND block %h at address %d, keep: %h, last: %b", recv_data[0+:512], base_addr + (current_block * 64), recv_keep, recv_last);
                end
            end
            ack_trs = new(0, trs.data.opcode, trs.data.strm, trs.data.remote, trs.data.host, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("Sending ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks_mbx.put(ack_trs);
            $display("HOST SIMULATION: completed HOST_SEND");
        end
    endtask

    task run_read_queue(input int strm);
        forever begin
            c_trs_req trs;
            c_trs_ack ack_trs;
            vaddr_t length;
            int n_blocks;
            vaddr_t base_addr;
            int segment_idx;
            data_t segment[];
            sq_rd_mbx[strm].get(trs);

            // delay this request a little after its issue time
            $display(
                "Delaying host_recv for: %t (req_time: %t, realtime: %t)",
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );
            
            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);

            $display("HOST SIMULATION: got host_recv[%d]: len=%d, vaddr=%x", strm, trs.data.len, trs.data.vaddr);

            length = trs.data.len;
            n_blocks = (length + 63) / 64;
            base_addr = trs.data.vaddr;

            //Get the right mem_segment
            segment_idx = -1;
            for(int i = 0; i < $size(mem_vaddrs); i++) begin
                if (mem_vaddrs[i] <= base_addr && (mem_vaddrs[i] + mem_sizes[i]) > (base_addr + length)) begin
                    segment_idx = i;
                end
            end

            if(segment_idx == -1) begin
                $display("No segment found to get data from in host mem");
            end else begin

                segment = mem_segments[segment_idx];

                for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                    logic[511:0] data = 512'h00;
                    keep_t keep = ~64'h00;
                    vaddr_t offset;
                    bit last = current_block + 1 == n_blocks;

                    // compute the keep offset
                    if (last) keep >>= 64 - (length - (current_block * 64));

                    // compute data offset
                    offset = base_addr + (current_block * 64) - mem_vaddrs[segment_idx];

                    //ugly conversion because we use MSB data, but memory is read in LSB fashion
                    for (int current_byte = 0; current_byte < 64; current_byte++) begin
                        data[511-((63-current_byte)*8) -:8] = segment[offset + current_byte];
                    end

                    //write transfer file
                    $fdisplay(transfer_file, "%t: HOST_RECV: %d, %h, %x, %x, %d", $realtime, strm, base_addr + (current_block * 64), data, keep, last);
                    $display("Receiving Data HOST_RECV [%d]: %x", strm, data);
                    recv_drv[strm].send(data, keep, last, trs.data.pid);
                end
            end
            ack_trs = new(1, trs.data.opcode, trs.data.strm, trs.data.remote, trs.data.host, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("Sending ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks_mbx.put(ack_trs);
            $display("HOST SIMULATION: completed host_recv");
        end
    endtask

    task run();
        fork
            run_read_queue(0);
            run_write_queue(0);
        join_none
        if(N_AXI > 1) begin
            fork
                run_read_queue(1);
                run_write_queue(1);
            join_none  
        end
        if(N_AXI > 2) begin
            fork
                run_read_queue(2);
                run_write_queue(2);
            join_none
        end
        if(N_AXI > 3) begin
            fork
                run_read_queue(3);
                run_write_queue(3);
            join_none
        end
    endtask
endclass
