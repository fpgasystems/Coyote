

typedef struct packed {
    // Opcode
    logic [OPCODE_BITS-1:0] opcode; // One of the values of fpga::CoyoteOper
    logic [STRM_BITS-1:0] strm;     // One of STRM_CARD, STRM_HOST, STRM_TCP, or STRM_RDMA (this determines the where this request lands)
    logic mode;                     // In the STRM_RDMA case, controls whether to skip the request splitter in the dreq_rdma_parser_wr module
    logic rdma;
    logic remote;

    // ID
    logic [DEST_BITS-1:0] vfid; // rsrvd
    logic [PID_BITS-1:0] pid;
    logic [DEST_BITS-1:0] dest; // The index of the AXI stream that data arrives at/departs from

    // FLAGS
    logic last;

    // DESC
    logic [VADDR_BITS-1:0] vaddr;
    logic [63:0] len; // wide transfer length for supporting more than just 256MB of transfers

    // RSRVD
    logic actv; // rsrvd
    logic host; // rsrvd
    logic [OFFS_BITS-1:0] offs; // rsrvd

    logic [128-OFFS_BITS-2-VADDR_BITS-LEN_BITS-1-2*DEST_BITS-PID_BITS-3-STRM_BITS-OPCODE_BITS-1:0] rsrvd;
} wreq_t;