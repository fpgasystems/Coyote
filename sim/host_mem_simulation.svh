

class host_mem_simulation;
    bit[511:0] recv_data;
    bit[63:0] recv_keep;
    bit recv_last;
    bit[5:0] recv_pid;
    mailbox mem_read[N_STRM_AXI];
    mailbox mem_write[N_STRM_AXI];
    c_axisr host_send[N_STRM_AXI];
    c_axisr host_recv[N_STRM_AXI];

    typedef logic[47:0] addr_t;
    typedef logic[7:0] data_t;
    typedef logic[63:0] keep_t;

    // Data in memory
    data_t mem_segments[$][];
    addr_t mem_vaddrs[$];
    addr_t mem_lengths[$];

    // Files to output transfers
    integer write_file;
    integer read_file;
    integer data_file;

    function new(
        mailbox mail_host_mem_read[N_STRM_AXI],
        mailbox mail_host_mem_write[N_STRM_AXI],
        c_axisr axis_host_send[N_STRM_AXI],
        c_axisr axis_host_recv[N_STRM_AXI]
    );
        mem_read = mail_host_mem_read;
        mem_write = mail_host_mem_write;
        host_send = axis_host_send;
        host_recv = axis_host_recv;
    endfunction

    //TODO: Merge Overlapping Mem Segments
    function set_data(string path_name, string file_name
    );
        addr_t vaddr;
        addr_t length;
        string full_file_name;
        data_t data[];
        int n_segment;

        data_t mem_segments_to_merge[$][];
        addr_t mem_vaddrs_to_merge[$];
        addr_t mem_lengths_to_merge[$];
        $sscanf(file_name, "seg-%x-%x.txt", vaddr, length);

        full_file_name = {
            path_name,
            file_name
        };
        $display(full_file_name);
        data = new[length];
        $readmemh(full_file_name, data);

        for(int i = 0; i < $size(mem_segments); i++) begin
            if((mem_vaddrs[i] <= (vaddr + length)) && ((mem_vaddrs[i] + mem_lengths[i]) >= vaddr))begin
                mem_segments_to_merge.push_back(mem_segments[i]);
                mem_vaddrs_to_merge.push_back(mem_vaddrs[i]);
                mem_lengths_to_merge.push_back(mem_lengths[i]);
                mem_segments.delete(i);
                mem_vaddrs.delete(i);
                mem_lengths.delete(i);
                i--;
            end
        end

        if($size(mem_segments_to_merge) != 0) begin
            merge_mem_segments(mem_segments_to_merge, mem_vaddrs_to_merge, mem_lengths_to_merge, data, vaddr, length);
        end else begin
            mem_segments.push_back(data);
            mem_vaddrs.push_back(vaddr);
            mem_lengths.push_back(length);
        end
        n_segment = $size(mem_segments) - 1;
        $display(
            "Loaded Segment '%s' at %x with length %x",
            file_name,
            mem_vaddrs[n_segment],
            mem_lengths[n_segment]
        );
    endfunction

    function merge_mem_segments(data_t segments[][], addr_t start_addrs[], addr_t lengths[], data_t new_seg[], addr_t new_seg_start, data_t new_seg_length);
        data_t result[];
        addr_t resulting_length;

        addr_t start_adress = start_addrs[0];
        addr_t end_adress = start_addrs[0] + lengths[0];
        addr_t offset_new_seg;

        for(int i = 1; i < $size(segments); i++) begin
            if(start_addrs[i] < start_adress) begin
                start_adress = start_addrs[i];
            end
            if(start_addrs[i] + lengths[i] > end_adress) begin
                end_adress = start_addrs[i] + lengths[i];
            end
        end

        if(new_seg_start < start_adress) begin
            start_adress = new_seg_start;
        end
        if((new_seg_start + new_seg_length) > end_adress) begin
            end_adress = (new_seg_start + new_seg_length);
        end

        resulting_length = end_adress - start_adress;
        result = new [resulting_length];

        for(int i = 0; i < $size(segments); i++) begin
            addr_t offset = start_addrs[i] - start_adress;
            for(int j = 0; j < $size(segments[i]); j++) begin
                result[offset + j] = segments[i][j];
            end
        end
        
        offset_new_seg = new_seg_start - start_adress;
        
        for(int i = 0; i < new_seg_length; i++) begin
            result[offset_new_seg + i]  = new_seg[i];
        end

        mem_segments.push_back(result);
        mem_vaddrs.push_back(start_adress);
        mem_lengths.push_back(resulting_length);
    endfunction

    task print_data();
        int number_of_segs = $size(mem_segments);

        for(int i = 0; i < number_of_segs; i++)begin
            $fdisplay(data_file, "Segment number: %x, at vaddr: %x, length: %x", i, mem_vaddrs[i], mem_lengths[i]);
            for(int j = 0; j < mem_lengths[i]; j++)begin
                $fdisplay(data_file, "%x", mem_segments[i][j]);
            end
        end
        $fclose(data_file);
    endtask

    task reset(string path_name);
        write_file = $fopen({path_name, "host_mem_write_output.txt"}, "w");
        read_file = $fopen({path_name, "host_mem_read_output.txt"}, "w");
        data_file = $fopen({path_name, "host_mem_data_output.txt"}, "w");

        $display("Host Memory Simulation: reset");
        for (int i = 0; i < N_STRM_AXI; i++) begin
            host_send[i].reset_s();
            host_recv[i].reset_m();
        end
        $display("Host Memory Simulation: reset complete");
    endtask

    // TODO: reimplement
    task run_send(input int strm);
            forever begin
                c_trs_req trs;
                addr_t base_addr;
                int length;
                int n_blocks;
                int offset;
                int segment_idx;
                mem_write[strm].get(trs);

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
                
                $display("HOST MEM SIMULATION: got mem_write: vaddr=%d len=%d strm_number=%d", trs.data.vaddr, trs.data.len, strm);

                // TODO: for now there is no start offset
                base_addr = trs.data.vaddr;
                length = trs.data.len;
                n_blocks = (length + 63) / 64;

                
                //Get the right mem_segment
                segment_idx = -1;
                for(int i = 0; i < $size(mem_vaddrs); i++) begin
                    $display(mem_vaddrs[i]);
                    if (mem_vaddrs[i] <= base_addr && (mem_vaddrs[i] + mem_lengths[i]) > (base_addr + length)) begin
                        segment_idx = i;
                    end
                end

                if(segment_idx == -1) begin
                    $display("No segment found to write data to in host mem");
                end

                    // TODO: implement delay for accepting writes
            

                    //for each received transaction, go through every 64 byte block
                    for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                        host_send[strm].recv(recv_data, recv_keep, recv_last, recv_pid);

                        $display(
                            "HOST_SEND received chunk: data=%x keep=%x last=%x pid=%x",
                            recv_data, recv_keep, recv_last, recv_pid
                        );
                        
                        if(segment_idx != -1) begin
                            offset = base_addr + (current_block * 64) - mem_vaddrs[segment_idx];

                            for(int current_byte = 0; current_byte < 64; current_byte++)begin

                                // Mask keep signal
                                //TODO: what happens when a single byte has recv_keep 0? do we zero it? append the rest? or just leave as is?
                                if(recv_keep[current_byte]) begin

                                    //write to memory
                                    mem_segments[segment_idx][offset + current_byte] = recv_data[(current_byte * 8)+:8];
                                    $display("Written byte %h at offset %d", recv_data[(current_byte * 8)+:8], (offset + current_byte));

                                    /*write transfer file in the format STREAM NUMBER, ADDRESS, DATA*/
                                    $fdisplay(write_file, "%d, %h, %h", strm, (base_addr + offset + current_byte), recv_data[(current_byte * 8)+:8]);
                                end
                            end
                        end
                    end
                $display("HOST MEM SIMULATION: completed mem_write");
            end
    endtask

    // TODO: reimplement
    // TODO: possibly interleave responses
    task run_recv(input int strm);
        forever begin
            c_trs_req trs;
            addr_t length;
            int n_blocks;
            addr_t base_addr;
            int segment_idx;
            data_t segment[];
            mem_read[strm].get(trs);

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
                "HOST MEM SIMULATION: got mem_read[%d]: len=%d, vaddr=%x",
                strm,
                trs.data.len,
                trs.data.vaddr
            );

            // TODO: for now, there is no start offset and memory is read at the start index
            length = trs.data.len;
            n_blocks = (length + 63) / 64;
            $display("N_blocks = %x, length = %x", n_blocks, length);
            base_addr = trs.data.vaddr;
            // TODO: for now, nothing else is relevant


            //Get the right mem_segment
            segment_idx = -1;
            for(int i = 0; i < $size(mem_vaddrs); i++) begin
                $display(mem_vaddrs[i]);
                if (mem_vaddrs[i] <= base_addr && (mem_vaddrs[i] + mem_lengths[i]) > (base_addr + length)) begin
                    segment_idx = i;
                end
            end

            if(segment_idx == -1) begin
                $display("No segment found to read data from in host mem");
            end else begin

                segment = mem_segments[segment_idx];

                for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                    logic[511:0] data = 512'h00;
                    keep_t keep = ~64'h00;
                    addr_t offset;
                    bit last = current_block + 1 == n_blocks;

                    // compute the keep offset
                    if (last) keep >>= 64 - (length - (current_block * 64));

                    // compute data offset
                    offset = base_addr + (current_block * 64) - mem_vaddrs[segment_idx];

                    //ugly conversion because we use MSB data, but memory is read in LSB fashion
                    for (int current_byte = 0; current_byte < 64; current_byte++) begin
                        data[511-((63-current_byte)*8) -:8] = segment[offset + current_byte];
                        $display("Byte from segment: %x, value: %x offset: %x", segment_idx, segment[offset + current_byte], offset + current_byte);
                    end

                    // transfer tdata, tkeep, tlast and the tpid for the transfer
                    $display("Sending Data [%d]: %x", strm, data);
                    /*Write to file in format
                    STRM_NUMBER, DATA, KEEP, LAST*/
                    $fdisplay(read_file, "%d, %x, %x, %d", strm, data, keep, last);
                    $display("before");
                    host_recv[strm].send(data, keep, last, trs.data.pid);
                    $display("after");
                end
            end

            $display("HOST MEM SIMULATION: completed mem_read");

        end
    endtask
endclass
