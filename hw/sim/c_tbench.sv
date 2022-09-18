`include "c_env.svh"

program tbench(AXI4SR axis_sink, AXI4SR axis_src, input integer n_trs);

    c_env env;

    initial begin
        // Environment
        env = new(axis_sink, axis_src, n_trs);

        // Run
        env.run();

    end

endprogram