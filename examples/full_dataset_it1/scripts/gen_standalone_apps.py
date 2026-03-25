#!/usr/bin/env python3
"""Generate 15 standalone app directories from a parameterized template.

Each standalone app is a stream passthrough + ring_osc_array with a specific N_RO count.
Shared HDL files (ring_oscillator.sv, ring_osc_array.sv) are copied into each directory.

Usage:
    python3 gen_standalone_apps.py
"""

import os
import shutil

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDALONE_DIR = os.path.join(BASE, "hw", "apps", "standalone")
PILOT_STANDALONE = os.path.join(BASE, "hw", "apps", "standalone", "ro_0004")

RO_COUNTS = [4, 16, 64, 256, 1024, 4096, 8192, 10000, 12000, 14000, 16000, 18000, 19000, 20000, 22000]

VFPGA_TOP_TEMPLATE = """\
// Full dataset it1 — standalone ro_{nro:04d} (N_RO={nro})
// Stream passthrough (recv[0] -> send[0]) + ring_osc_array (N_RO={nro}).
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

// --- Standalone ring oscillator array (N_RO={nro}) ---
(* DONT_TOUCH = "TRUE" *) wire [{nro_minus1}:0] ro_out;
ring_osc_array #(.N_RO({nro})) inst_ro_array (
    .signal_in  (axis_host_recv[0].tvalid),
    .signal_out (ro_out)
);
"""

INIT_IP = "# No IPs required for standalone.\n"


def main():
    os.makedirs(STANDALONE_DIR, exist_ok=True)

    for nro in RO_COUNTS:
        dirname = f"ro_{nro:04d}"
        app_dir = os.path.join(STANDALONE_DIR, dirname)
        hdl_dir = os.path.join(app_dir, "hdl")
        os.makedirs(hdl_dir, exist_ok=True)

        # vfpga_top.svh
        with open(os.path.join(app_dir, "vfpga_top.svh"), "w") as f:
            f.write(VFPGA_TOP_TEMPLATE.format(nro=nro, nro_minus1=nro - 1))

        # init_ip.tcl
        with open(os.path.join(app_dir, "init_ip.tcl"), "w") as f:
            f.write(INIT_IP)

        # Copy shared HDL from reference standalone dir
        for sv_file in ["ring_oscillator.sv", "ring_osc_array.sv"]:
            src = os.path.join(PILOT_STANDALONE, "hdl", sv_file)
            dst = os.path.join(hdl_dir, sv_file)
            if os.path.abspath(src) != os.path.abspath(dst):
                shutil.copy2(src, dst)

        print(f"  Created {dirname} (N_RO={nro})")

    print(f"\nGenerated {len(RO_COUNTS)} standalone app directories in {STANDALONE_DIR}")


if __name__ == "__main__":
    main()
