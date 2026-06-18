#!/usr/bin/env python3
"""Generate standalone app directories from a parameterized template.

Each standalone app is a stream passthrough + ring_osc_array with a specific N_RO count.
Low-RO apps preserve the original flat ring_osc_array source. High-RO apps use
4096-instance banks to stay below Vivado's generate-loop limit.

Usage:
    python3 gen_standalone_apps.py
"""

import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import BASE, RO_COUNTS, PILOT_STANDALONE_HDL, ITERATION_LABEL

STANDALONE_DIR = os.path.join(BASE, "hw", "apps", "standalone")
VIVADO_LOOP_LIMIT = 65536
RO_BANK_SIZE = 4096

VFPGA_TOP_TEMPLATE = """\
// {label} - standalone ro_{{nro:04d}} (N_RO={{nro}})
// Stream passthrough (recv[0] -> send[0]) + ring_osc_array (N_RO={{nro}}).
// Passthrough keeps the app Coyote-compatible; ROs dominate the resource footprint.

// Stream passthrough
always_comb begin
    axis_host_send[0].tdata  = axis_host_recv[0].tdata;
    axis_host_send[0].tkeep  = axis_host_recv[0].tkeep;
    axis_host_send[0].tlast  = axis_host_recv[0].tlast;
    axis_host_send[0].tvalid = axis_host_recv[0].tvalid;
    axis_host_recv[0].tready = axis_host_send[0].tready;
end

// Unused streams / control signals
always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();

// --- Standalone ring oscillator array (N_RO={{nro}}) ---
(* DONT_TOUCH = "TRUE" *) wire [{{nro_minus1}}:0] ro_out;
ring_osc_array #(.N_RO({{nro}})) inst_ro_array (
    .signal_in  (axis_host_recv[0].tvalid),
    .signal_out (ro_out)
);

// --- Dummy ILA (satisfies debug_bridge_user Chipscope DRC) ---
ila_dummy inst_ila_dummy (
    .clk(aclk),
    .probe0(ro_out[0])
);
""".format(label=ITERATION_LABEL)

INIT_IP = """\
# Minimal dummy ILA - satisfies debug_bridge_user Chipscope DRC (16-320).
# Without an ILA, open_checkpoint fires a non-downgradable ERROR because
# debug_bridge_user (unconditionally instantiated) has no connected clock.
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_dummy
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_dummy
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}
set_property -dict [list CONFIG.C_NUM_OF_PROBES {1}] [get_ips ila_dummy]
"""

BANKED_RING_OSC_ARRAY = """\
// Parameterized ring oscillator array.
// Instantiates N_RO copies of ring_oscillator in 4096-instance banks.
// signal_in gates all oscillators simultaneously (NAND-based enable).
// signal_out bus carries the oscillating outputs; each bit is DONT_TOUCH-preserved.

module ring_osc_array #(
    parameter integer N_RO = 16
) (
    input  wire              signal_in,
    output wire [N_RO-1:0]  signal_out
);

    localparam integer RO_BANK_SIZE = {bank_size};
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
""".format(bank_size=RO_BANK_SIZE)


def should_preserve_existing(nro):
    return nro <= VIVADO_LOOP_LIMIT and os.environ.get("FORCE_REGEN", "0") != "1"


def main():
    os.makedirs(STANDALONE_DIR, exist_ok=True)

    for nro in RO_COUNTS:
        dirname = f"ro_{nro:04d}"
        app_dir = os.path.join(STANDALONE_DIR, dirname)
        if os.path.exists(app_dir) and should_preserve_existing(nro):
            print(f"  Preserved existing {dirname} (N_RO={nro})")
            continue

        hdl_dir = os.path.join(app_dir, "hdl")
        os.makedirs(hdl_dir, exist_ok=True)

        # vfpga_top.svh
        with open(os.path.join(app_dir, "vfpga_top.svh"), "w") as f:
            f.write(VFPGA_TOP_TEMPLATE.format(nro=nro, nro_minus1=nro - 1))

        # init_ip.tcl
        with open(os.path.join(app_dir, "init_ip.tcl"), "w") as f:
            f.write(INIT_IP)

        shutil.copy2(
            os.path.join(PILOT_STANDALONE_HDL, "ring_oscillator.sv"),
            os.path.join(hdl_dir, "ring_oscillator.sv"),
        )
        if nro > VIVADO_LOOP_LIMIT:
            with open(os.path.join(hdl_dir, "ring_osc_array.sv"), "w") as f:
                f.write(BANKED_RING_OSC_ARRAY)
        else:
            shutil.copy2(
                os.path.join(PILOT_STANDALONE_HDL, "ring_osc_array.sv"),
                os.path.join(hdl_dir, "ring_osc_array.sv"),
            )

        print(f"  Created {dirname} (N_RO={nro})")

    print(f"\nGenerated {len(RO_COUNTS)} standalone app directories in {STANDALONE_DIR}")


if __name__ == "__main__":
    main()
