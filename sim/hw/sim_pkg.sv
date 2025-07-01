package sim_pkg;
    typedef logic[lynxTypes::VADDR_BITS - 1:0] vaddr_t;

    class mem_seg_t;
        vaddr_t vaddr;
        vaddr_t size;
        byte    data[];
        bit     marker;

        function new(vaddr_t vaddr, vaddr_t size, byte data[]);
            this.vaddr  = vaddr;
            this.size   = size;
            this.data   = data;
            this.marker = 0;
        endfunction
    endclass;

    class mem_t; // We need this as a wrapper because you cannot pass queues [$] by reference
        mem_seg_t segs[$];
    endclass
endpackage
