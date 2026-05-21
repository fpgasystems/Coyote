// Parameterized ring oscillator array.
// Instantiates N_RO copies of ring_oscillator in 4096-instance banks.
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

    localparam integer RO_BANK_SIZE = 4096;
    localparam integer N_BANKS = (N_RO + RO_BANK_SIZE - 1) / RO_BANK_SIZE;

    genvar b, i;
    generate
        for (b = 0; b < N_BANKS; b++) begin : gen_bank
            localparam integer BANK_START = b * RO_BANK_SIZE;
            localparam integer BANK_COUNT =
                (N_RO - BANK_START > RO_BANK_SIZE) ? RO_BANK_SIZE : (N_RO - BANK_START);

            for (i = 0; i < BANK_COUNT; i++) begin : gen_ro
                ring_oscillator inst_ro (
                    .signal_in  (signal_in),
                    .signal_out (signal_out[BANK_START + i])
                );
            end
        end
    endgenerate

endmodule
