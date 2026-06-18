// Parameterized ring oscillator array.
// Instantiates N_RO copies of ring_oscillator.
// signal_in gates all oscillators simultaneously (NAND-based enable).
// signal_out bus carries the oscillating outputs; each bit is DONT_TOUCH-preserved.
//
// Usage for Class 1 (paired-injected suspicious): N_RO = 16
// Usage for Class 2 (standalone families):        N_RO = 5 / 200 / 3000 / 30000

module ring_osc_array #(
    parameter integer N_RO = 16
) (
    input  wire              signal_in,
    output wire [N_RO-1:0]  signal_out
);

    genvar i;
    generate
        for (i = 0; i < N_RO; i++) begin : gen_ro
            ring_oscillator inst_ro (
                .signal_in  (signal_in),
                .signal_out (signal_out[i])
            );
        end
    endgenerate

endmodule
