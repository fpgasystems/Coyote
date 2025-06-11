package sim_pkg;
    typedef logic[lynxTypes::VADDR_BITS - 1:0] vaddr_t;

    typedef struct {
        vaddr_t vaddr;
        vaddr_t size;
        byte    data[];
    } mem_seg_t;
endpackage
