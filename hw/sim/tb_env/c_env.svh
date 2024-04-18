
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

    // Stream type
    string strm_type;  

    // Completion
    event done;

    // 
    // C-tor
    //
    function new(virtual AXI4SR axis_sink, virtual AXI4SR axis_src, input c_struct_t params, input string strm_type);
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
        
        this.strm_type = strm_type;
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
    task env_threads();
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
    task env_done();
        wait(gen.done.triggered);
        wait(scb.done.triggered);
    endtask
    
    //
    // Run
    //
    task run;
        reset();
        env_threads();
        env_done();
        if(scb.fail == 0) begin 
            $display("Stream run completed, type: %s", strm_type);
        end
        else begin
            $display("Stream run failed, type: %s", strm_type);
        end
        -> done;
    endtask

endclass