import sim_pkg::*;

`include "log.svh"
`include "stream_simulation.svh"

/* 
* This class simulates the actions on the other end of a memory interface, it holds a virtual memory from which data can be read and written to and also simulates the simple streaming of data without work queue entries
*/

class mem_mock #(N_AXI);
    string name;

    c_axisr send_drv[N_AXI];
    c_axisr recv_drv[N_AXI];

    // Data is stored in simulated memory segments
    // The data segments are defined by the data they hold, their starting address, and the length
    mem_t mem;

    stream_simulation strm_runners[N_AXI];

    function new(
        input string name,
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

    function void malloc(vaddr_t vaddr, vaddr_t size);
        byte data[] = new[size];
        int n_segment;
        mem_seg_t new_seg;

        // Check if any segments are overlapping which should never happen
        for (int i = 0; i < $size(mem.segs); i++) begin
            if (vaddr < (mem.segs[i].vaddr + mem.segs[i].size) && (vaddr + size) > mem.segs[i].vaddr) begin
                `FATAL(("New memory segment at vaddr=%x, len=%0d overlaps with memory segment %0d at vaddr=%x, len=%0d", vaddr, size, i, mem.segs[i].vaddr, mem.segs[i].size))
            end
        end

        new_seg = new(vaddr, size, data);
        mem.segs.push_back(new_seg);

        n_segment = $size(mem.segs) - 1;
        `DEBUG(("%s: Allocated segment at %x with length %0d in memory.", name, mem.segs[n_segment].vaddr, mem.segs[n_segment].size))
    endfunction

    function void free(vaddr_t vaddr);
        for (int i = 0; i < $size(mem.segs); i++) begin
            if (mem.segs[i].vaddr == vaddr) begin
                mem.segs.delete(i);
                `DEBUG(("%s: Freed memory segment at address %x.", name, vaddr))
                return;
            end
        end
        `FATAL(("%s: There was no memory segment for vaddr %x", name, vaddr))
    endfunction

    function mem_seg_t get_mem_seg(vaddr_t vaddr);
        for (int i = 0; i < $size(mem.segs); i++) begin
            if (mem.segs[i].vaddr <= vaddr && (mem.segs[i].vaddr + mem.segs[i].size) >= vaddr) begin
                return mem.segs[i];
                break;
            end
        end
        `FATAL(("%s: There was no memory segment for vaddr %x", name, vaddr))
    endfunction;

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
