/* 
* This class simulates the actions on the other end of a memory interface, it holds a virtual memory from which data can be read and written to and also simulates the simple streaming of data without work queue entries
*/

import sim_pkg::*;

`include "stream_simulation.svh"

class mem_mock #(N_AXI);
    string name;

    c_axisr send_drv[N_AXI];
    c_axisr recv_drv[N_AXI];

    // Data is stored in simulated memory segments
    // The data segments are defined by the data they hold, their starting address, and the length
    mem_t mem;

    stream_simulation strm_runners[N_AXI];

    function new(
        string name,
        mailbox #(c_trs_ack) acks_mbx,
        mailbox #(c_trs_req) sq_rd_mbx[N_AXI],
        mailbox #(c_trs_req) sq_wr_mbx[N_AXI],
        c_axisr send_drv[N_AXI],
        c_axisr recv_drv[N_AXI],
        scoreboard scb
    );
        this.name = name;

        this.send_drv = send_drv;
        this.recv_drv = recv_drv;

        this.mem = new();

        for (int i = 0; i < N_AXI; i++) begin
            strm_runners[i] = new(i, name, acks_mbx, sq_rd_mbx[i], sq_wr_mbx[i], send_drv[i], recv_drv[i], mem, scb);
        end
    endfunction

    function void merge_mem_segments(mem_seg_t segs[$], mem_seg_t new_seg);
        byte result[];
        vaddr_t resulting_size;

        vaddr_t start_adress = segs[0].vaddr;
        vaddr_t end_adress = segs[0].vaddr + segs[0].size;
        vaddr_t offset_new_seg;

        mem_seg_t merged_seg;

        // Find start and end address of the resulting memory segment
        for (int i = 1; i < $size(segs); i++) begin
            if (segs[i].vaddr < start_adress) begin
                start_adress = segs[i].vaddr;
            end
            if (segs[i].vaddr + segs[i].size > end_adress) begin
                end_adress = segs[i].vaddr + segs[i].size;
            end
        end
        
        if (new_seg.vaddr < start_adress) begin
            start_adress = new_seg.vaddr;
        end
        if ((new_seg.vaddr + new_seg.size) > end_adress) begin
            end_adress = (new_seg.vaddr + new_seg.size);
        end

        resulting_size = end_adress - start_adress;
        result = new[resulting_size];

        // Fill in already existing data
        for (int i = 0; i < $size(segs); i++) begin
            vaddr_t offset = segs[i].vaddr - start_adress;
            for (int j = 0; j < $size(segs[i].data); j++) begin
                result[offset + j] = segs[i].data[j];
            end
        end
        
        offset_new_seg = new_seg.vaddr - start_adress;
        
        // Add data from the new segment
        for (int i = 0; i < new_seg.size; i++) begin
            result[offset_new_seg + i]  = new_seg.data[i];
        end

        merged_seg = {start_adress, resulting_size, result};
        mem.segs.push_back(merged_seg);
    endfunction

    function void malloc(vaddr_t vaddr, vaddr_t size);
        byte data[];
        int n_segment;

        mem_seg_t new_seg;
        mem_seg_t mem_segs_to_merge[$];

        data = new[size];

        // Check if any segments need to be merged together because they are overlapping or directly adjacent to each other
        for (int i = 0; i < $size(mem.segs); i++) begin
            if ((mem.segs[i].vaddr <= (vaddr + size)) && (mem.segs[i].vaddr + mem.segs[i].size) >= vaddr) begin
                mem_seg_t merge_seg = {mem.segs[i].vaddr, mem.segs[i].size, mem.segs[i].data};
                mem_segs_to_merge.push_back(merge_seg);
                mem.segs.delete(i);
                i--;
            end
        end

        new_seg = {vaddr, size, data};
        if ($size(mem_segs_to_merge) != 0) begin
            merge_mem_segments(mem_segs_to_merge, new_seg);
        end else begin
            mem.segs.push_back(new_seg);
        end

        n_segment = $size(mem.segs) - 1;
        $display("%s mock: Allocated segment at %x with length %0d in memory.", name, mem.segs[n_segment].vaddr, mem.segs[n_segment].size);
    endfunction

    function void free(vaddr_t vaddr);
        for (int i = 0; i < $size(mem.segs); i++) begin
            if (mem.segs[i].vaddr == vaddr) begin
                mem.segs.delete(i);
                return;
            end
        end
        $fatal("There was no memory segment for vaddr %x", vaddr);
    endfunction

    function void write_data(vaddr_t vaddr, byte data);
        for (int i = 0; i < $size(mem.segs); i++) begin
            if (mem.segs[i].vaddr <= vaddr && (mem.segs[i].vaddr + mem.segs[i].size) >= vaddr) begin
                mem.segs[i].data[vaddr - mem.segs[i].vaddr] = data;
                break;
            end
        end
    endfunction

    task initialize();
        for (int i = 0; i < N_AXI; i++) begin
            send_drv[i].reset_s();
            recv_drv[i].reset_m();
        end
    endtask

    task run();
        for (int i = 0; i < N_AXI; i++) begin
            fork
                automatic int j = i; // We need this line. Otherwise the tasks throw null pointer exceptions
                strm_runners[j].run_read_queue();
                strm_runners[j].run_write_queue();
            join_none
        end
    endtask
endclass
