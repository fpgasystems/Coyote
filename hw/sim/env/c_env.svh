import lynxTypes::*;
import simTypes::*;

`include "c_trs.svh"
`include "c_gen.svh"
`include "c_drv.svh"
`include "c_mon.svh"
`include "c_scb.svh"

// Environment
class c_env;

    // Instances
    c_gen gen;
    c_drv drv;
    c_mon mon;
    c_scb scb;

    // Mailboxes
    mailbox gen2drv;
    mailbox drv2scb;
    mailbox mon2scb;

    // Interface handle
    virtual AXI4SR axis_sink;
    virtual AXI4SR axis_src;   

    // 
    // C-tor
    //
    function new(virtual AXI4SR axis_sink, virtual AXI4SR axis_src, input c_struct_t params);
        // Interface
        this.axis_sink = axis_sink;
        this.axis_src = axis_src;

        // Mailbox
        gen2drv = new();
        drv2scb = new();
        mon2scb = new();

        // Env
        gen = new(gen2drv, params);
        drv = new(axis_sink, gen2drv, drv2scb);
        mon = new(axis_src, mon2scb);
        scb = new(mon2scb, drv2scb, params);
    endfunction

    // 
    // Reset
    //
    task reset();
        drv.reset_m();
        mon.reset_s();
        #(AST_PERIOD);
    endtask

    //
    // Run
    //
    task threads();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_any
    endtask

    //
    // Finish
    //
    task done();
        wait(gen.done.triggered);
        wait(scb.done.triggered);
    endtask
    
    //
    // Run
    //
    task run;
        reset();
        threads();
        done();
        if(scb.fail == 0) $display("TBENCH PASSED"); else $display("TBENCH FAILED");
        $finish;
    endtask

endclass