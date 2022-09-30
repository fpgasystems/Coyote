package simTypes;

    // SIM
    parameter CLK_PERIOD = 10ns;
    parameter RST_PERIOD = 2.5 * CLK_PERIOD;
    parameter AST_PERIOD = 4.5 * CLK_PERIOD;
    parameter TT = 2ns;
    parameter TA = 1ns;

    // --------------------------------------------------------------------------
    // CUSTOM STRUCTS
    // These are the structs to edit to adapt to any custom DUT.
    // --------------------------------------------------------------------------
    typedef struct packed {
        integer n_trs;
    } c_struct_t;
    
endpackage