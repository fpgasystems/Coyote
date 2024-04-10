package simTypes;

    // STRM TYPES
    parameter integer STRM_CARD = 0;
    parameter integer STRM_HOST = 1;
    parameter integer STRM_RREQ = 2;
    parameter integer STRM_RRSP = 3;
    parameter integer STRM_TCP  = 4;

    // --------------------------------------------------------------------------
    // CUSTOM STRUCTS
    // These are the structs to edit to adapt to any custom DUT.
    // --------------------------------------------------------------------------
    typedef struct packed {
        integer n_trs;
        integer delay;
    } c_struct_t;
    
endpackage