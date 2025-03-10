/* This class simulates the actions on the other end of the card interface,
    it holds a virtual memory from which data can be read and written to.
*/

class card_driver_simulation;
    bit[511:0] recv_data;
    bit[63:0] recv_keep;
    bit recv_last;
    bit[5:0] recv_tid;

    mailbox drv_read[N_CARD_AXI];
    mailbox drv_write[N_CARD_AXI];
    mailbox acks;

    c_axisr card_send[N_CARD_AXI];
    c_axisr card_recv[N_CARD_AXI];

    typedef logic[47:0] addr_t;
    typedef logic[7:0] data_t;
    typedef logic[63:0] keep_t;

    /*Data in a simulated card memory
    * Data can be comprised of multiple disjunct segments, defined by the data they hold, their starting address and the length
    */
    data_t mem_segments[$][];
    addr_t mem_vaddrs[$];
    addr_t mem_lengths[$];

    //Files to output a record of all transfers that happened and a record of the resulting card memory
    integer transfer_file;
    integer data_file;

    function new(
        mailbox mail_ack,
        mailbox mail_card_drv_read[N_CARD_AXI],
        mailbox mail_card_drv_write[N_CARD_AXI],
        c_axisr axis_card_send[N_CARD_AXI],
        c_axisr axis_card_recv[N_CARD_AXI]
    );
        acks = mail_ack;
        drv_read = mail_card_drv_read;
        drv_write = mail_card_drv_write;
        card_send = axis_card_send;
        card_recv = axis_card_recv;
    endfunction

    function set_data(string path_name, string file_name);
        addr_t vaddr;
        addr_t length;
        string full_file_name;
        data_t data[];
        int n_segment;

        data_t mem_segments_to_merge[$][];
        addr_t mem_vaddrs_to_merge[$];
        addr_t mem_lengths_to_merge[$];

        $sscanf(file_name, "seg-%x-%x.txt", vaddr, length);

        full_file_name = {path_name, file_name};

        data = new[length];
        $readmemh(full_file_name, data);

        //check if any segments need to be merged together because they are overlapping or directly adjacent to each other
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
            "Loaded Segment '%s' at %x with length %x in card memory",
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

        //find start and end address of the resulting memory segment
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

        //fill in already existing data
        for(int i = 0; i < $size(segments); i++) begin
            addr_t offset = start_addrs[i] - start_adress;
            for(int j = 0; j < $size(segments[i]); j++) begin
                result[offset + j] = segments[i][j];
            end
        end
        
        offset_new_seg = new_seg_start - start_adress;
        
        //add data from the new segment
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
        $fclose(transfer_file);
    endtask

    task initialize(string path_name);
        transfer_file = $fopen({path_name, "card_transfer_output.txt"}, "w");
        data_file = $fopen({path_name, "card_mem_data_output.txt"}, "w");

        $display("Card Simulation: initialize");
        for (int i = 0; i < N_CARD_AXI; i++) begin
            card_send[i].reset_s();
            card_recv[i].reset_m();
        end
        $display("Card Simulation: initialization complete");
    endtask

    task run_write_queue(input int strm);
            forever begin
                c_trs_req trs;
                c_trs_ack ack_trs;
                addr_t base_addr;
                int length;
                int n_blocks;
                int offset;
                int segment_idx;
                drv_write[strm].get(trs);

                // delay this request a little after its issue time
                $display(
                    "Delaying card_send for: %t (req_time: %t, realtime: %t)",
                    trs.req_time + 50ns - $realtime,
                    trs.req_time,
                    $realtime
                );

                if (trs.req_time + 50ns - $realtime > 0)
                    #(trs.req_time + 50ns - $realtime);
                
                $display("CARD SIMULATION: got card_send: vaddr=%d len=%d strm_number=%d", trs.data.vaddr, trs.data.len, strm);

                base_addr = trs.data.vaddr;
                length = trs.data.len;
                n_blocks = (length + 63) / 64;

                
                //Get the right mem_segment
                segment_idx = -1;
                for(int i = 0; i < $size(mem_vaddrs); i++) begin
                    if (mem_vaddrs[i] <= base_addr && (mem_vaddrs[i] + mem_lengths[i]) > (base_addr + length)) begin
                        segment_idx = i;
                    end
                end

                if(segment_idx == -1) begin
                    $display("No segment found to write data to in card mem");
                end else begin            
                    //go through every 64 byte block
                    for (int current_block = 0; current_block < n_blocks; current_block ++) begin
                        card_send[strm].recv(recv_data, recv_keep, recv_last, recv_tid);
                            
                        offset = base_addr + (current_block * 64) - mem_vaddrs[segment_idx];

                        for(int current_byte = 0; current_byte < 64; current_byte++)begin

                            // Mask keep signal
                            if(!recv_keep[current_byte]) begin
                               recv_data[(current_byte * 8)+:8] = 8'b00000000;
                            end
                        end

                        //write transfer file
                        $fdisplay(transfer_file, "%t: CARD_SEND: %d, %h, %h, %h, %b", $realtime, strm, base_addr + (current_block * 64), recv_data[0+:512], recv_keep, recv_last);
                        $display("CARD_SEND block %h at address %d, keep: %h, last: %b", recv_data[0+:512], base_addr + (current_block * 64), recv_keep, recv_last);
                    end
                end
                ack_trs = new(0, trs.data.opcode, trs.data.strm, trs.data.remote, trs.data.host, trs.data.dest, trs.data.pid, trs.data.vfid);
                $display("Sending ack: write, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
                acks.put(ack_trs);
                $display("CARD SIMULATION: completed CARD_SEND");
            end
    endtask

    task run_read_queue(input int strm);
        forever begin
            c_trs_req trs;
            c_trs_ack ack_trs;
            addr_t length;
            int n_blocks;
            addr_t base_addr;
            int segment_idx;
            data_t segment[];
            drv_read[strm].get(trs);

            // delay this request a little after its issue time
            $display(
                "Delaying card_recv for: %t (req_time: %t, realtime: %t)",
                trs.req_time + 50ns - $realtime,
                trs.req_time,
                $realtime
            );
            
            if (trs.req_time + 50ns - $realtime > 0)
                #(trs.req_time + 50ns - $realtime);

            $display("CARD SIMULATION: got card_recv[%d]: len=%d, vaddr=%x", strm, trs.data.len, trs.data.vaddr);

            length = trs.data.len;
            n_blocks = (length + 63) / 64;
            base_addr = trs.data.vaddr;

            //Get the right mem_segment
            segment_idx = -1;
            for(int i = 0; i < $size(mem_vaddrs); i++) begin
                if (mem_vaddrs[i] <= base_addr && (mem_vaddrs[i] + mem_lengths[i]) > (base_addr + length)) begin
                    segment_idx = i;
                end
            end

            if(segment_idx == -1) begin
                $display("No segment found to get data from in card mem");
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
                    end

                    //write transfer file
                    $fdisplay(transfer_file, "%t: CARD_RECV: %d, %h, %x, %x, %d", $realtime, strm, base_addr + (current_block * 64), data, keep, last);
                    $display("Receiving Data CARD_RECV [%d]: %x", strm, data);
                    card_recv[strm].send(data, keep, last, trs.data.pid);
                end
            end
            ack_trs = new(1, trs.data.opcode, trs.data.strm, trs.data.remote, trs.data.host, trs.data.dest, trs.data.pid, trs.data.vfid);
            $display("Sending ack: read, opcode=%d, strm=%d, remote=%d, host=%d, dest=%d, pid=%d, vfid=%d", ack_trs.opcode, ack_trs.strm, ack_trs.remote, ack_trs.host, ack_trs.dest, ack_trs.pid, ack_trs.vfid);
            acks.put(ack_trs);
            $display("CARD SIMULATION: completed card_recv");
        end
    endtask

    task run();
        fork
            run_read_queue(0);
            run_write_queue(0);
        join_none
        if(N_CARD_AXI > 1) begin
            fork
                run_read_queue(1);
                run_write_queue(1);
            join_none  
        end
        if(N_CARD_AXI > 2) begin
            fork
                run_read_queue(2);
                run_write_queue(2);
            join_none
        end
        if(N_CARD_AXI > 3) begin
            fork
                run_read_queue(3);
                run_write_queue(3);
            join_none
        end
    endtask
endclass
