# Constraints and Floorplans (`hw/constraints/`)

**Purpose:** per-board XDC files (pins, clocks, debug cores, shell pblock) and how the CMake/Vivado flows read them; plus the rules for vFPGA (application-level PR) floorplans supplied by the user via `FPLAN_PATH`.
Code is the source of truth: everything below was derived from `hw/constraints/**`, `scripts/**`, `cmake/FindCoyoteHW.cmake`.

## Key files

| Path | Role |
|---|---|
| [hw/constraints/](../../../hw/constraints) | Root; one folder per board (`u200`, `u250`, `u280`, `u55c`, `v80`) + `LEGACY/` |
| [u55c/fplan/u55c_static_floorplan.xdc](../../../hw/constraints/u55c/fplan/u55c_static_floorplan.xdc) | Shell pblock `pblock_inst_shell` (U55C). Byte-identical to the U280 file |
| [u280/fplan/u280_static_floorplan.xdc](../../../hw/constraints/u280/fplan/u280_static_floorplan.xdc) | Shell pblock (U280) |
| [u250/fplan/u250_static_floorplan.xdc](../../../hw/constraints/u250/fplan/u250_static_floorplan.xdc), [u200/fplan/u200_static_floorplan.xdc](../../../hw/constraints/u200/fplan/u200_static_floorplan.xdc) | Shell pblock (U250, U200); the only ones with `CONTAIN_ROUTING`/`EXCLUDE_PLACEMENT` |
| [v80/fplan/v80_static_floorplan.xdc](../../../hw/constraints/v80/fplan/v80_static_floorplan.xdc) | Shell pblock (V80, Versal) |
| [u55c/static/impl/u55c_static_pcie.xdc](../../../hw/constraints/u55c/static/impl/u55c_static_pcie.xdc) | PCIe refclk + x16 GT pins (US+ boards have the same file layout) |
| [u55c/dynamic/impl/](../../../hw/constraints/u55c/dynamic/impl) | Pins owned by the shell: HBM refclk, QSFP0/1, `fpga_burn` |
| [u280/dynamic/impl/u280_shell_ddr_0.xdc](../../../hw/constraints/u280/dynamic/impl/u280_shell_ddr_0.xdc) | DDR4 pins/IOSTANDARDs (U280 has `ddr_0`, `ddr_1`; U250 and U200 have `ddr_0..3`) |
| [u55c/shell/synth/u55c_shell_base.xdc](../../../hw/constraints/u55c/shell/synth/u55c_shell_base.xdc) | Shell out-of-context synthesis clocks (synth only) |
| [v80/dynamic/impl/empty.xdc](../../../hw/constraints/v80/dynamic/impl/empty.xdc) | Placeholder so the folder exists in git (V80: no network/DDR yet) |
| [examples/10_app_reconfiguration/hw/floorplans/](../../../examples/10_app_reconfiguration/hw/floorplans) | Example vFPGA floorplans: `example_fplan_u55c.xdc`, `example_fplan_v80.xdc` |
| [cmake/FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) | Params `FPLAN_PATH`, `EN_SHELL_PBLOCK`, `EN_PR`, `N_REGIONS`, `STATIC_PATH`, validation |
| [scripts/impl/link.tcl.in](../../../scripts/impl/link.tcl.in) | Static/shell flow: adds constraints folders, `SCOPED_TO_CELLS`, `link_design -reconfig_partitions` |
| [scripts/dyn/flow_dyn_ultrascale_plus.tcl.in](../../../scripts/dyn/flow_dyn_ultrascale_plus.tcl.in) | US+ vFPGA PR flow (`pr_subdivide`, per-config link/PnR, `pr_recombine`) |
| [scripts/dyn/flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in) | Versal vFPGA PR flow (no nested DFX) |
| [scripts/dyn/flow_app.tcl.in](../../../scripts/dyn/flow_app.tcl.in) | App flow (`BUILD_APP=1`): link new apps into a routed+locked shell |
| [hw/templates/common/user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt) | Generated per-vFPGA XDC (clock, `CLOCK_BUFFER_TYPE NONE`) |
| [hw/templates/versal/shell_clk_tmplt.txt](../../../hw/templates/versal/shell_clk_tmplt.txt) | Generated Versal shell XDC (`xclk`) |
| [hw/checkpoints/](../../../hw/checkpoints) | Static DCPs: `static_routed_locked_{u200,u250,u280,u55c}.dcp`, `static_routed_locked_v80_gen{4,5}.dcp` (carry static constraints + shell pblock), `static_synthed_v80_gen{4,5}.dcp` (Versal PR flow) |
| [hw/templates/common/lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | `RECONFIG_EOS_TIME` (from CMake `EOS_TIME`) |
| [hw/templates/common/cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt) | Top-level ports and their `io_buffer_type`, which decides where pin XDCs live |
| [driver/src/reconfig/](../../../driver/src/reconfig) | Driver side of shell/app reconfiguration (`reconfig_ops.c`) |
| [docs/source/intro/v80-notes.rst](../../../docs/source/intro/v80-notes.rst) | Human docs: V80 PR (`EN_SHELL_PBLOCK=0`), timing closure |

**Related:** [build_top.md](build_top.md) (CMake params, flows, targets) · [../static/reconfig.md](../static/reconfig.md) (PR mechanics, ICAP/PDI, decoupling) · [../static/static_top.md](../static/static_top.md) · [../shell/shell_top.md](../shell/shell_top.md) · [../services/memory.md](../services/memory.md) · [../services/network.md](../services/network.md) · [../user/user_top.md](../user/user_top.md) · [../driver.md](../driver.md) · [../software.md](../software.md)

## Layout of `hw/constraints/<board>/`

```
<board>/
  static/synth/<board>_static_synth.xdc   # static OOC synthesis: clocks, debug-hub clk   (synth only)
  static/impl/<board>_static_{base,pcie,debug}.xdc  # power, bitstream compress, PCIe pins, CMAC/HBM clocks, debug hub
  shell/synth/<board>_shell_base.xdc      # shell OOC synthesis: xclk/dclk/HBM/CMAC clocks, debug bridge   (synth only)
  shell/impl/<board>_shell_debug.xdc      # debug bridge settings for implementation (inst_shell/...)
  dynamic/impl/<board>_shell_{hbm,ddr_N,net_N,burn}.xdc   # board pins for shell-owned I/O (HBM refclk, DDR4, QSFP)
  fplan/<board>_static_floorplan.xdc      # pblock_inst_shell (shell pblock). NOT the vFPGA pblocks
```

This is the full layout for U200/U250/U280/U55C only; not every board has every file:

| Board | Deviations |
|---|---|
| U55C | `static/impl` has base/pcie/debug; `dynamic/impl` has `shell_{hbm,net_0,net_1,burn}`; no DDR files |
| U280 | `dynamic/impl` has `shell_{hbm,ddr_0,ddr_1,net_0,net_1}`; `fpga_burn` is in `static/impl/u280_static_base.xdc` |
| U250, U200 | `dynamic/impl` has `shell_{ddr_0..3,net_0,net_1}`, no HBM; `shell/synth/<board>_shell_base.xdc` has only `xclk` + CMAC clocks (no `dclk`); debug files target `pclk` (static) / `inst_shell/dclk` (shell) |
| V80 | Only `static/impl/v80_static_base.xdc` and `static/synth/v80_static_synth.xdc` carry content (PCIe `pcie_ref_clk`, power, compress). `shell/synth`, `shell/impl`, `dynamic/impl` each contain only `empty.xdc`; no `*_pcie`, `*_debug`. `xclk` comes from the generated `shell_clk.xdc` (below) |

Naming caveat: the folder called `dynamic/` holds **shell-level pin constraints** (the "dynamic layer" = shell, see [shell_top.md](../shell/shell_top.md)); it is *not* the vFPGA floorplan. The file `fplan/*_static_floorplan.xdc` is also misleadingly named: it floorplans the **shell** (`inst_shell`), the static layer is simply "everything outside" (there is no explicit static pblock on any board).

## How/when each folder is applied

CMake flow selection (exactly one of `BUILD_STATIC`, `BUILD_SHELL`, `BUILD_APP`; see [build_top.md](build_top.md)). `$fdev` = `FDEV_NAME`.

| Folder | Static flow (`BUILD_STATIC=1`) | Shell flow (`BUILD_SHELL=1`) | App flow (`BUILD_APP=1`) |
|---|---|---|---|
| `static/synth` | Added in [cr_static.tcl.in](../../../scripts/cr_prjcts/cr_static.tcl.in), `used_in_implementation=false` | not used | not used |
| `static/impl` | `link.tcl.in`, `if {$cfg(build_static) eq 1}` branch (US+ and Versal: static synthesised from scratch) | US+: already inside `static_routed_locked_$fdev.dcp`. Versal PR flow: added explicitly ([flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in)) against `static_synthed_*` DCP, `SCOPED_TO_CELLS {inst_static}` | already inside the routed shell DCP |
| `shell/synth` | Added in [cr_shell.tcl.in](../../../scripts/cr_prjcts/cr_shell.tcl.in), `used_in_implementation=false` (shell synth project is used in static and shell flows) | same | not used (shell DCP provided via `SHELL_PATH`) |
| `shell/impl` | `link.tcl.in` | `link.tcl.in`; Versal PR flow (`flow_dyn_versal.tcl.in`) | inside shell DCP |
| `dynamic/impl` | `link.tcl.in` | `link.tcl.in`; PR flows re-add it per config ([US+](../../../scripts/dyn/flow_dyn_ultrascale_plus.tcl.in), config-0 link and per-config loop) | re-added per config ([flow_app.tcl.in](../../../scripts/dyn/flow_app.tcl.in)) |
| `fplan` | [link.tcl.in](../../../scripts/impl/link.tcl.in) (static branch), **only if `EN_SHELL_PBLOCK=1`**; then `link_design -reconfig_partitions {inst_shell}` makes the shell a reconfigurable partition | not re-added in `link.tcl` (pblock is baked into locked static DCP). US+ PR flow (`EN_PR=1`) re-adds the folder at config-0 link ([flow_dyn_ultrascale_plus.tcl.in](../../../scripts/dyn/flow_dyn_ultrascale_plus.tcl.in)); Versal: not added | not added |
| user `FPLAN_PATH` | n/a (static builds reject `EN_PR`) | US+ PR: added at config-0 link (not at the first `link.tcl` link), `PROCESSING_ORDER LATE` ([flow_dyn_ultrascale_plus.tcl.in](../../../scripts/dyn/flow_dyn_ultrascale_plus.tcl.in)). Effectively required on US+ too (see below). Versal PR: **required**, same ordering ([flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in)) | not added; vFPGA pblocks come from the locked shell checkpoint |
| generated `xdc/` (project) | `shell_clk` (Versal) | same | `user_clk_c<cfg>_<reg>.xdc` per vFPGA, synth only |

Mechanics worth knowing:
- Folders are added as a whole (`add_files -fileset constrs_1 <dir>`): **every** `.xdc` in `dynamic/impl` is read regardless of `EN_NET_0/1`, `EN_MEM`, etc. [`cyt_top`](../../../hw/templates/common/cyt_top_tmplt.txt) declares the board's QSFP/DDR/HBM ports unconditionally for a given `fdev` (U280/U250/U200 DDR0/1 ports are always present), so most files match real ports; whether any file hits missing ports is listed under Unverified.
- `synth/` XDCs get `used_in_implementation false`; `impl/` XDCs are read only at `link_design`. Hence clock definitions exist twice (synth + impl copies, e.g. `create_clock` in both `u55c_static_synth.xdc` and `u55c_static_base.xdc`, the latter with `-name`).
- Each synth project also gets an empty `local.xdc` as `target_constrs_file` for throw-away debug constraints (not committed).
- Synthesised DCPs are bound to hierarchy with `SCOPED_TO_CELLS`: shell → `inst_shell`; vFPGA j → `inst_shell/inst_dynamic/inst_user_wrapper_<j>` ([link.tcl.in](../../../scripts/impl/link.tcl.in), `# Shell` / `# User` blocks). The floorplan cell paths must match these names.
- Static builds write `static_routed_locked.dcp` (shell blackboxed, `lock_design -level routing`) after PnR ([pnr_shell.tcl.in](../../../scripts/impl/pnr_shell.tcl.in)); copying it to `hw/checkpoints/static_routed_locked_<fdev>.dcp` (`STATIC_PATH`, [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)) is how the static floorplan/pins are "shipped" to shell/app builds.
- Port buffering: shell-owned I/O ports are declared `(* io_buffer_type = "none" *)` in [cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt) so the top does not insert IBUF/OBUF; buffers are instantiated in the shell. This is why pin XDCs for those ports live in `dynamic/impl` rather than `static/impl`. Because buffering is deliberately incomplete at the static/shell link, `link.tcl.in` suppresses `[DRC RPBF-3] IO port buffering is incomplete` (`set_msg_config -suppress` in [link.tcl.in](../../../scripts/impl/link.tcl.in)).

## Pin / IO constraints

| Interface | File | Notes |
|---|---|---|
| PCIe refclk + 16 lanes | `static/impl/<board>_static_pcie.xdc` | `PACKAGE_PIN` for `pcie_clk_clk_{p,n}`, `pcie_x16_{rx,tx}{p,n}[15:0]`; `create_clock -period 10.000 -name pcie_ref_clk`. U55C: refclk AR15/AR14. V80 has no PCIe pin file: QDMA/CPM is hardened, only the clock is created in `v80_static_base.xdc` |
| HBM refclk (100 MHz) | `dynamic/impl/<board>_shell_hbm.xdc` (U55C: BK10/BL10 LVDS; U280: BJ43/BJ44) | Needed by the HBM IP/APB clock; U55C/U280 only. On Versal HBM is reached via the NoC, no pin file |
| QSFP0/1 (CMAC) | `dynamic/impl/<board>_shell_net_{0,1}.xdc` | GT refclk + 4 lanes per port. U55C 161.1328125 MHz refclk (6.206 ns, matches XDC). U250 and U200 156.25 MHz (6.4 ns, matches XDC). U280: pins are the 156.25 MHz ones (`gt0_refclk_{n,p}` in [u280_shell_net_0.xdc](../../../hw/constraints/u280/dynamic/impl/u280_shell_net_0.xdc), under `# Clock (156.25 MHz)`) but the XDC clocks use 6.206 ns (static) and 3.103 ns (shell synth), never 6.4 ns (BLD-07). Alternative refclk pins left commented. U250 and U200 also constrain `qsfpN_{resetn,lpmode,modseln}` and `set_false_path -to` them |
| DDR4 | `dynamic/impl/<board>_shell_ddr_N.xdc` | U250/U200: 4 channels (`ddr_0..3`); U280: 2 (`ddr_0..1`); `cN_sys_clk` + `cN_ddr4_*` with SSTL12_DCI / POD12_DCI. U280 `c0_sys_clk` pins (BJ43/BJ44) are the **same** as the `hbm_clk_clk` pins (`u280_shell_hbm.xdc`). `cyt_top` declares both the DDR ports and `hbm_clk` ports for U280 and all `dynamic/impl` XDCs are read, so two distinct top ports are assigned to the same package pins; the DDR-vs-HBM choice (HBM default; move u280 between `HBM_DEV` and `DDR_DEV`) is made at shell/IP level, and how Vivado resolves the pin overlap in the unused case is unverified |
| `fpga_burn` | U55C: `dynamic/impl/u55c_shell_burn.xdc` (BE45, LVCMOS18, pulldown); U280: `static/impl/u280_static_base.xdc` (D32) | Power-burn pin; location differs by `io_buffer_type`: U55C port is `io_buffer_type="none"` (buffer in shell) so its pin is in `dynamic/impl`; U280 port is a plain output tied to 0 in `cyt_top` (`fpga_burn` port and `assign fpga_burn = 1'b0` in [cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt)), buffered in the static top, so its pin is in `static/impl` |
| Power / bitstream | `static/impl/<board>_static_base.xdc` | `set_operating_conditions -design_power_budget 160`, `BITSTREAM.GENERAL.COMPRESS TRUE` (also V80) |

## Timing constraints

All timing XDC is minimal and lives in the `*_base`/`*_synth` files:
- **Clock definitions** (ports only; internal clocks are derived from XDMA/QDMA/clocking wizards/IPs):
  - `pcie_clk_clk_p` 10.000 ns (100 MHz) all boards; `hbm_clk_clk_p` 10.000 ns (U55C/U280).
  - `gt{0,1}_refclk_p`: 6.206 ns (U55C; U280 static synth+impl), 6.4 ns (U250, U200), **3.103 ns** (U280 `shell/synth` only; BLD-07). V80: the XDC lines are commented out, but the generated `shell_clk.xdc` ([template](../../../hw/templates/versal/shell_clk_tmplt.txt)) creates active `gt0/1_refclk_p` clocks at 6.206 ns as placeholders (no V80 networking yet).
  - Shell OOC: `xclk` 4.000 ns (250 MHz = XDMA user clock, US+) in all US+ `*_shell_base.xdc`; `dclk` 10.000 ns (debug) only in U55C/U280 (U250/U200 have no `dclk` there). Versal: `xclk` period = `SCLK_F` from generated `shell_clk.xdc` (`CLOCK_BUFFER_TYPE NONE`, Vivado AR 73360: no clock buffers across PR boundaries).
  - vFPGA OOC: `create_clock -period <uclk_p> [get_ports aclk]` from [user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt); `uclk_p = 1000/UCLK_F` if `EN_UCLK` else `1000/ACLK_F` ([write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in)). With `EN_PR=1`, `CLOCK_BUFFER_TYPE NONE` on `aclk`; with Versal+PR, `dclk` at `SCLK_F`.
- **CDC**: no `set_false_path`/`set_max_delay` for internal CDC in `hw/constraints`. CDCs are RTL-handled (XPM CDC, enabled via `xpm_libraries XPM_CDC XPM_MEMORY` in project scripts; clock crossing wrappers per `EN_NCLK/EN_UCLK/EN_HCLK`). The only `set_false_path` are U250/U200 QSFP sideband outputs.
- **Debug hubs** (US+ only; V80 has no debug XDC): `C_CLK_INPUT_FREQ_HZ 100000000`, `C_ENABLE_CLK_DIVIDER false`, `C_USER_SCAN_CHAIN 1` on three cores. Static hub `inst_static/inst_debug_hub`: `connect_debug_port` in `static/synth` (U55C/U280: `dclk`; U250/U200: `pclk` in `<board>_static_synth.xdc` and `<board>_static_debug.xdc`). Shell bridge `inst_shell/inst_debug_bridge_dynamic`: settings in `shell/impl/*_shell_debug.xdc`; the clock hookup is in `shell/synth` on U55C/U280 ([u55c_shell_base.xdc](../../../hw/constraints/u55c/shell/synth/u55c_shell_base.xdc), `connect_debug_port` on `dclk`) and in `shell/impl` on U250/U200 (`inst_shell/dclk`). vFPGA bridge `inst_debug_bridge_user` is configured from the generated [user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt) (US+ branch only).

## Per-board summary

| Board (`FDEV_NAME`) | Part (`FPGA_PART`) | Arch | SLRs | Static pblock | Shell pblock (`pblock_inst_shell`) | Card memory | Network | Notes |
|---|---|---|---|---|---|---|---|---|
| `u55c` | `xcu55c-fsvh2892-2L-e` | US+ | 3 (clock-region rows Y0-11) | none (static = complement of shell pblock) | clock regions `X0Y11:X3Y11 X0Y6:X7Y10 X0Y4:X5Y5 X0Y3:X3Y3 X0Y0:X5Y2` + HBM BLI/APB `X25..31`, `PCIE4CE4_X1Y0`, `HPIOB_DCI_SNGL_X0Y0:Y3`, `HPIO_RCLK_PRBS_X0Y0`, BUFG_GT, DSP/BRAM/URAM/LAGUNA sub-ranges | HBM2, 16 GiB (`HBM_SIZE=34`), `HCLK_F=450`, no DDR | 2x QSFP28 (CMAC) | PCIe Gen3x16 (XDMA). Network default `EN_NET_0=1`, `EN_NET_1=0` for all US+ boards |
| `u280` | `xcu280-fsvh2892-2L-e` | US+ | 3 | none | identical XDC to U55C | HBM2 8 GiB (`HBM_SIZE=33`) default (`HBM_DEV`); DDR4 variant (`DDR_DEV`) default `N_DDR_CHAN=1`, 16 GiB, constraint files for 2 channels | 2x QSFP28 | DDR0 and HBM refclk share pins |
| `u200` | `xcu200-fsgd2104-2-e` | US+ | 3 (device fact; clock-region rows Y0-14) | none | clock regions `X0Y11:X5Y14 X0Y4:X2Y10 X0Y0:X5Y3`, `IOB_X1Y208:X1Y519`, LAGUNA; + `CONTAIN_ROUTING 1`, `EXCLUDE_PLACEMENT 1` | DDR4, up to 4 channels (`ddr_0..3`), default `N_DDR_CHAN=1`, 16 GiB each; no HBM | 2x QSFP28 | Same file layout and DDR/QSFP pins structure as U250 |
| `u250` | `xcu250-figd2104-2L-e` | US+ | 4 (rows Y0-15) | none | clock regions `X0Y9:X7Y15 X0Y3:X3Y8 X0Y0:X7Y2`, `IOB_X0Y156:X0Y415`, LAGUNA; + `CONTAIN_ROUTING 1`, `EXCLUDE_PLACEMENT 1` | DDR4, up to 4 channels (`ddr_0..3`), default `N_DDR_CHAN=1`, 16 GiB each; no HBM | 2x QSFP28 | Outside-shell (static) region `X4-7,Y3-8` spans SLR0-2 |
| `v80` | `xcv80-lsva4737-2MHP-e-S` | Versal | not determined from repo (no SLR-specific constraints in the XDC) | none | clock regions `X1Y11:X7Y11 X1Y7:X8Y10 X1Y5:X9Y6 X5Y3:X9Y4 X4Y1:X8Y2 X5Y0:X10Y0` + NoC NMU/NSU/NPS, HBM_MC/PHY, `DCMAC_X0Y2`, `MRMAC_X0Y2:X0Y4`, `GTM_QUAD`, DPLL, BUFG_FABRIC/GT | HBM2e 32 GiB via NoC (`HBM_SIZE=35`, `HCLK_F=400`, `HBM_IMPL` unified/block); DDR present on board but unsupported | none yet (`EN_NET` fatal on Versal) | QDMA, PCIe Gen4x16 or Gen5x8 (`PCIE_GEN`); `SCLK_F` forced to 333 MHz for shell/app flows |

SLR counts are device facts, not read from XDC; the SLR split above is inferred from the clock-region rows used in each pblock. Part, memory and network numbers are from [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) (per-`FDEV_NAME` device blocks, `DDR_DEV`/`HBM_DEV`).

LEGACY (`hw/constraints/LEGACY/`): kept for reference only, older flat layout (`<board>_{base,pcie,net_N,ddr_N}.xdc`). `LEGACY/u200` is superseded by `hw/constraints/u200`; `FindCoyoteHW.cmake` rejects the other LEGACY boards ("Target device not supported"). Do not use them as a template for new boards; copy `u55c/` or `v80/`.

## Floorplan details

### Shell pblock (`pblock_inst_shell`, all boards)
- Created with `add_cells_to_pblock ... inst_shell`; ranges are Vivado's derived output (SLICE, DSP, RAMB18/36, URAM288, LAGUNA, BUFG_GT, HBM interface sites, clock regions). Flags: `SNAPPING_MODE ON`, `IS_SOFT FALSE`. On U250 and U200 additionally `CONTAIN_ROUTING 1` + `EXCLUDE_PLACEMENT 1`; **U55C/U280/V80 do not set them**.
- The pblock is the reconfigurable-partition boundary for shell reconfiguration. `HD.RECONFIGURABLE` is not set in any XDC: the partition is declared by `link_design -reconfig_partitions {inst_shell}` ([link.tcl.in](../../../scripts/impl/link.tcl.in)) when `EN_SHELL_PBLOCK=1`.
- Static layer = everything outside `inst_shell` (PCIe/XDMA or QDMA, PR controller). It has no explicit pblock; placement is free outside `inst_shell`. Note the shell pblock itself contains IO/hard sites (U55C: `PCIE4CE4_X1Y0`, `HPIOB_DCI_SNGL_X0Y0:Y3`, `HPIO_RCLK_PRBS_X0Y0`, HBM interface sites; U250: `IOB_X0Y156:X0Y415`, U200: `IOB_X1Y208:X1Y519`; V80: DCMAC/MRMAC/GTM/NoC/HBM sites), which is why shell-owned pins (HBM/DDR/QSFP) are assigned with `dynamic/impl` while the shell is the placing owner. Which site the static XDMA/QDMA actually occupies was not checked.
- `EN_SHELL_PBLOCK` (default 1) rules ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), `SHELL_PBLOCK_OPT_VALID`): may be 0 only for (a) static builds, (b) Versal with `EN_PR=1`. It is invalid for shell builds on US+ (needs the floorplanned static DCP). The whole validation sits inside `if(BUILD_SHELL OR BUILD_STATIC)` (FindCoyoteHW.cmake), so it is **not** run for `BUILD_APP` (the in-code comment says `TODO: What about app flow?`). On Versal, `EN_PR=1 && EN_SHELL_PBLOCK=1` is a fatal error (no nested DFX). Without a shell pblock there is no `shell_top.bit/.pdi` partial ([bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in)), and timing closure is typically easier.

### vFPGA pblocks (application PR, `EN_PR=1`)
- One pblock per vFPGA, **user-provided**, passed with `-DFPLAN_PATH=<abs path to .xdc>` (CMake cache var, default `0`; [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)). The file must define `N_REGIONS` pblocks, one per vFPGA (max 15), with this exact naming:

```tcl
create_pblock pblock_inst_user_wrapper_<j>
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_<j>] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_<j>]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_<j>] -add {CLOCKREGION_X0Y7:CLOCKREGION_X5Y10 ...}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_<j>]
set_property IS_SOFT FALSE   [get_pblocks pblock_inst_user_wrapper_<j>]
```
  `<j>` = vFPGA index 0..N_REGIONS-1 (same index as `VFPGA_C<cfg>_<j>` in `load_apps`). The cell path comes from `dynamic_top`/`shell_top` instance names; renaming RTL instances breaks the floorplan.
- Not region/config dependent in size: the same pblock is reused for all `N_CONFIG` configurations, so it must fit the **largest** app of vFPGA j across configs.
- Reconfigurable partition = `inst_shell/inst_dynamic/inst_user_wrapper_<j>` via `link_design -mode default -reconfig_partitions {...}` (flow_dyn / flow_app). Vivado inserts **partition pins** at the pblock boundary automatically (Korolija thesis §3.3.6, external: they pin the crossing interfaces and constrain routing around the pblock, a source of congestion). The AXI interfaces crossing the boundary are decoupled in RTL (`*_decoupler` in [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt)); the XDC does not model decoupling.
- **US+ order of events** (`EN_PR=1`, `BUILD_SHELL=1`): `link.tcl` (no vFPGA pblocks) -> `pnr_shell.tcl` (full place/route of shell + config-0 apps, writes `shell_routed.dcp`; exits 1 here if `FPLAN_PATH=0`) -> `flow_dyn.tcl` (`pr_subdivide` of `shell_routed.dcp` into `shell_subdivided.dcp`, relink with `fplan/` + `FPLAN_PATH`, re-place/route config 0, lock, then configs 1..N-1; `pr_recombine`) -> `bitgen`. **Versal** (`EN_PR=1`): no `link`/`shell` targets; `flow_dyn.tcl` starts from the synthesised static/shell/user DCPs plus `FPLAN_PATH` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), `NOT (EN_PR AND FPGA_ARCH STREQUAL "versal")` guard around the `link`/`shell` targets).
- Config 0 is placed & routed with the floorplan; then the shell is locked (`update_design -black_box` per vFPGA, `lock_design -level routing`, `shell_routed_locked.dcp`) and configs 1..N-1 are linked against it with `dynamic/impl` constraints only.
- `FPLAN_PATH` file is added with `PROCESSING_ORDER LATE` so it overrides earlier constraints.
- No `FPLAN_PATH` with `EN_PR=1`: US+ `pnr_shell.tcl` ends with `exit 1` and a message telling the user to floorplan `checkpoints/shell_subdivided.dcp` ([pnr_shell.tcl.in](../../../scripts/impl/pnr_shell.tcl.in), "Sanity check for vFPGA floorplan"). **That checkpoint does not exist yet at this point**: it is only written by `flow_dyn` (`pr_subdivide` + `write_checkpoint`), which is never reached after the `exit 1`; a re-run overwrites it. (Also, the CMake `shell` target lists `shell_subdivided.dcp` as output of `pnr_shell`, which does not write it.) So on US+ `FPLAN_PATH` is effectively required; to floorplan interactively, open `shell_routed.dcp` and run `pr_subdivide` yourself, or iterate with an initial floorplan. Versal flow errors immediately ([flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in), `No vFPGA floorplan provided`).
- Not set in the example floorplans: `CONTAIN_ROUTING`, `EXCLUDE_PLACEMENT`, `RESET_AFTER_RECONFIG`. Add them if DFX DRCs or routing leakage appear (UG909).

### Example floorplans (examples/10_app_reconfiguration)
- `example_fplan_u55c.xdc` (committed version, `git show HEAD:...`): single pblock `pblock_inst_user_wrapper_0` with `SLICE_X0Y660:X116Y719`, `DSP48E2_X0Y258:X15Y281`, `RAMB18_X0Y264:X7Y287`, `RAMB36_X0Y132:X7Y143`, `URAM288_X0Y176:X1Y191` plus clock regions `X0Y7:X5Y10` and `X0Y0:X3Y6`. The explicit site ranges are the "additional resize commands" mentioned in its comment (non-clock-region-aligned boundary).
- `example_fplan_v80.xdc`: single pblock with explicit `SLICE_X204Y192:X323Y383`, `DSP58_CPLX`, `DSP`, `RAMB18/36`, `URAM288`, `URAM_CAS_DLY` ranges.
- Used by [hw/CMakeLists.txt](../../../examples/10_app_reconfiguration/hw/CMakeLists.txt): `set(EN_PR 1) set(N_CONFIG 2) set(N_REGIONS 1) set(FPLAN_PATH ".../floorplans/example_fplan_u55c.xdc")`. Switch to V80: use the V80 lines **and** `EN_SHELL_PBLOCK=0` ([README](../../../examples/10_app_reconfiguration/README.md)).

## UltraScale+ vs Versal (V80)

Cross-layer summary: [UltraScale+ vs Versal](../coyote_top.md#ultrascale-vs-versal-summary). Constraints and flow details:

| Aspect | UltraScale+ | Versal (V80) |
|---|---|---|
| Static layer in shell/app flow | Routed + locked `hw/checkpoints/static_routed_locked_<fdev>.dcp` | No-PR: `static_routed_locked_v80_gen{4,5}.dcp`. PR (`EN_PR=1`): `static_synthed_v80_gen{4,5}.dcp` re-placed every build, `SCOPED_TO_CELLS {inst_static}`. Requires Vivado >= 2024.2 ([link.tcl.in](../../../scripts/impl/link.tcl.in), `vcompare` check) |
| Shell pblock | Always on for shell builds | `EN_SHELL_PBLOCK` can be 0 (needed for `EN_PR=1`) |
| Nested DFX artifacts | `pr_subdivide -cell inst_shell` then per-config link/PnR, then `pr_recombine` | No `shell_subdivided.dcp`, no `shell_recombined.dcp`, no `shell_top.pdi` when `EN_PR=1` |
| vFPGA floorplan | `FPLAN_PATH` effectively required (the flow exits after shell PnR otherwise; see above) | Mandatory `FPLAN_PATH` (error at link) |
| Image format | vFPGA/shell partials: `.bin` (+`.ltx`; `-no_binary_bitfile -bin_file`, no `.bit`); full `cyt_top.bit` | `.pdi`; full image re-generated with `fix_bif.py` + `bootgen` so `boot_device=PCIe` ([bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in)) |
| Hard blocks in shell pblock | HBM interface sites, PCIE4CE4, BUFG_GT, LAGUNA (SLR crossings) | NoC NMU/NSU/NPS, `HBM_MC/PHY`, DCMAC/MRMAC, GTM quads, DPLL |
| Memory I/O | HBM IP + refclk pins / DDR4 pins | HBM via NoC (no pin XDC); NoC connections are IP config in `hw/bd/versal/cr_hbm.tcl`, not XDC |

## Relation to runtime (driver & software)

- vFPGA index `j` in `pblock_inst_user_wrapper_<j>` / `VFPGA_C<cfg>_<j>` is the same `vfid` used at run time: `cThread(vfid, ...)` selects the vFPGA register window and `cRcnfg::reconfigureApp(path, vfid)` selects the partition to overwrite ([software.md](../software.md)).
- Build outputs per pblock (US+: `bitstreams/config_<cfg>/vfpga_c<cfg>_<j>.bin` + `.ltx`; Versal: `.pdi`; shell partial `shell_top.bin` / `shell_top.pdi`; full image `cyt_top.bit` / `cyt_top.pdi`; see [bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in)) are exactly what `cRcnfg` reads: `reconfigureApp` -> `IOCTL_RECONFIGURE_APP` (vfid in the arg), `reconfigureShell` -> `IOCTL_RECONFIGURE_SHELL` ([cDefs.hpp](../../../sw/include/coyote/cDefs.hpp), [cRcnfg.cpp](../../../sw/src/cRcnfg.cpp), [coyote_defs.h](../../../driver/include/coyote_defs.h)). The driver handles both ioctls in [reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c) (`case IOCTL_RECONFIGURE_SHELL` / `case IOCTL_RECONFIGURE_APP`) and streams the bitstream through the static layer's PR path ([../static/reconfig.md](../static/reconfig.md), [../driver.md](../driver.md)). `IOCTL_RECONFIGURE_SHELL` returns -1 if the build had `EN_SHELL_PBLOCK=0` (`bus_data->en_shell_pblock`), `IOCTL_RECONFIGURE_APP` requires `EN_PR`; hence on Versal with `EN_PR=1` `reconfigureShell` fails (see [example 10 README](../../../examples/10_app_reconfiguration/README.md)).
- A bitstream is only valid for the floorplan/checkpoint it was built against: shell `.bin` for a different static checkpoint or vFPGA `.bin` for a different pblock shape/shell routing corrupts or hangs the device. Pin and pblock changes in `hw/constraints/` therefore require rebuilding the static checkpoint (`BUILD_STATIC`), and every shell/app bitstream built against it.
- `N_REGIONS` (pblocks) must match the shell the driver is loaded for (number of vFPGA char devices / register windows); `EOS_TIME` (CMake, default 1000000) only sets the **reset value** of static register `PR_EOST_REG` ([lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) `RECONFIG_EOS_TIME` -> [static_slave.sv](../../../hw/hdl/static/static_slave.sv) reset of `slv_reg[PR_EOST_REG]`). The runtime value comes from the driver: module parameter `eost` (default 1000000, [coyote_driver.c](../../../driver/src/coyote_driver.c) `module_param(eost, ...)`) is written to the register at load if `EN_PR` ([coyote_setup.c](../../../driver/src/coyote_setup.c), `data->stat_cnfg->reconfig_eost = eost`); the `cyt_attr_eost` sysfs store does not change it (it writes the module variable `eost`, REC-09) and the attribute reads 0 without `EN_PR` (REC-10). It matters on the U55C, where ICAP done is lost across SLRs.

## Gotchas

- **Static-pin changes need a new static checkpoint**: `hw/checkpoints/*.dcp` embeds the static pblock/pins; editing `static/impl` or `fplan` XDCs has no effect on shell/app flows on US+ until the DCP is regenerated and replaced.
- `fpga_burn` pin constraint is in `static/impl` for U280 but `dynamic/impl` for U55C (explained by `io_buffer_type`, see pin table); U250/U200/V80 have none.
- `SNAPPING_MODE ON` means the implemented range (`DERIVED_RANGES`) can differ from the XDC (info message `Constraints 18-4422`). Check the `report_utilization -pblocks` output, not the XDC numbers.
- Clock-region-only pblocks (current U55C example) leave fabric columns inside the region unreserved; DFX wants pblock edges aligned to reconfiguration-frame boundaries (UG909). Hence the committed U55C example adds explicit SLICE/DSP/RAMB/URAM ranges.
- Vivado AR 73360: no clock buffers across PR boundaries; do not remove `CLOCK_BUFFER_TYPE NONE` from generated clock XDC.
- `link.tcl` suppresses `DRC RPBF-3` (IO buffering incomplete), `Constraints 18-4866` and `Vivado 12-2261/4385` (HD.PARTPIN_RANGE); real problems of those kinds will not show in the link log. Newly added top-level ports without `io_buffer_type="none"` or a buffer in the shell will not be flagged by RPBF-3 here.
- US+ PR with a floorplan crossing SLRs: ICAP done is lost; keep the driver `eost` (default 1000000 cycles) large enough (see runtime section).
- Max 15 vFPGAs (`N_REGIONS`), each needs its own pblock.
- Known defects in this area: [known_issues.md](../known_issues.md) (`BLD-02`, `BLD-07`, `BLD-08`, `BLD-11`).

## Unverified

- Severity of Vivado messages for `dynamic/impl` constraints on ports not present for a given configuration.
- SLR counts and V80 die layout are device knowledge, not read from repo files; which PCIe site static XDMA/QDMA occupies relative to the shell pblock was not checked.
- Recipe heuristics (pblock size margins, debug tips) are general DFX practice, not repo-encoded.

## Recipes

### Make a vFPGA larger / change the number of vFPGAs
1. Start from `example_fplan_*.xdc` (or an existing floorplan) and edit it. To draw interactively on US+: build the shell with `EN_PR=1` and any valid `FPLAN_PATH` once, then open `build/checkpoints/shell_subdivided.dcp` (written by `flow_dyn`, not by `pnr_shell`) in Vivado; with `FPLAN_PATH` unset the flow exits at `pnr_shell` before that file exists, so open `build/checkpoints/shell_routed.dcp` and run `pr_subdivide` yourself instead.
2. Draw a rectangle for each `pblock_inst_user_wrapper_<j>` in Device view; stay inside `pblock_inst_shell`'s clock regions (vFPGA is a child of `inst_shell`); keep HBM/NoC/CMAC-adjacent areas that the shell services use outside the vFPGA pblocks when possible. Use `report_utilization -pblocks` and the app's synthesis report to size each pblock >= 1.2-1.5x the largest app across configs.
3. Copy only the `create_pblock`, `add_cells_to_pblock`, `resize_pblock` and `set_property` (`SNAPPING_MODE`, `IS_SOFT`) lines for the vFPGA pblocks into a new `.xdc`, names exactly `pblock_inst_user_wrapper_<j>`, `N_REGIONS` of them.
4. Re-run configure with `-DFPLAN_PATH=/abs/path/new.xdc` (use an absolute path; the example uses `${CMAKE_SOURCE_DIR}/floorplans/...`), `make project && make bitgen`. Check `reports/config_*/shell_timing_summary_c*.rpt`, `shell_route_status_c*.rpt`, `shell_drc_bitstream_checks_c*.rpt`.
5. Remember: all vFPGA bitstreams must be rebuilt (they depend on the pblock), and the shell partial bitstream from the same build must be used with them.

### Add a new board's constraints
1. Copy `hw/constraints/u55c` (US+, HBM) or `u250`/`u200` (US+, DDR) or `v80` (Versal) to `hw/constraints/<newboard>/` keeping the six-folder layout (`static/{synth,impl}`, `shell/{synth,impl}`, `dynamic/impl`, `fplan`). Empty `.xdc` placeholders are fine, folders must exist (scripts add whole directories; see `v80/*/empty.xdc`).
2. Fill pins from the board's master XDC: PCIe refclk + lanes (`static/impl`), QSFP/refclk (`dynamic/impl/*_net_N.xdc`), memory refclk/DDR pins, board sidebands. Match port names to [cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt) (extend its `fdev` conditionals if ports differ).
3. Set clocks consistent with the refclk frequency actually wired (see U280 mismatch above).
4. Add the device in `FindCoyoteHW.cmake` (`FPGA_ARCH`, `FPGA_PART`, memory sizes, `DDR_DEV`/`HBM_DEV`), the PCIe/clocking in `hw/bd/*/cr_pci.tcl`, `scripts/ip_inst/*`, and the template conditionals keyed on `cnfg.fdev`.
5. Build the static layer with no floorplan first: `-DBUILD_STATIC=1 -DBUILD_SHELL=0 -DEN_SHELL_PBLOCK=0`. Open `shell_routed.dcp`, floorplan `inst_shell` (leave PCIe/XDMA/ICAP corner for static), write the pblock into `fplan/<newboard>_static_floorplan.xdc`, then rebuild with `EN_SHELL_PBLOCK=1` to produce `static_routed_locked_<fdev>.dcp` and copy it to `hw/checkpoints/`. (For Versal also produce `static_synthed_<fdev>_gen<N>.dcp`.)
6. Verify the shell flow (`BUILD_SHELL=1`) links against the new DCP and that an example with `EN_PR=1` + a custom `FPLAN_PATH` completes.

### Debug placement/routing failures at the PR boundary
- Symptoms and first checks:
  - `link_design` errors about reconfig partitions / missing cells: pblock cell path or `SCOPED_TO_CELLS` mismatch (`inst_shell/inst_dynamic/inst_user_wrapper_<j>`); check `N_REGIONS` equals the number of pblocks.
  - `place_design` "Placer failed": pblock too small for a config's app (run `report_utilization -pblocks`; resources include the decoupler and the user wrapper register slices) or pblock overlaps the HBM/CMAC/PCIe-attached hard sites; enlarge or move.
  - Routing congestion / negative slack on boundary nets: partition pins are fixed after config 0; move the pblock so shell-side logic driving the interface sits adjacent; add pipeline stages in the vFPGA interface; try `BUILD_OPT=1`; lower `UCLK_F`/`ACLK_F`.
  - DRC failures in `shell_drc_bitstream_checks_c*.rpt` (e.g. partial-reconfig frame alignment, clock buffers on PR boundary): align pblock edges, keep `CLOCK_BUFFER_TYPE NONE`, avoid BUFGs inside the vFPGA.
  - Config N > 0 fails but config 0 passes: config N uses `shell_routed_locked.dcp` with fixed routing; the app uses more of an unconstrained resource type than config 0 (e.g. BRAM columns) or has different clock-crossing structure; check `config_N/shell_*_cN.rpt`.
  - Shell-pblock overflow (static or shell flow): use `EN_SHELL_PBLOCK=0` on a static build to see if timing closes without it (loses shell reconfiguration; commands in [v80-notes.rst](../../../docs/source/intro/v80-notes.rst), section "Tuning clock frequency & timing closure").
- Tools: open `build/checkpoints/shell_subdivided.dcp` (US+) or `shell_routed.dcp` in Vivado GUI; `show_objects`/`highlight_objects` the pblock; `report_timing -from/-through` on `inst_shell/inst_dynamic/inst_user_wrapper_<j>` pins; `report_route_status`; `report_methodology`.
- Cheap experiments: single vFPGA, `N_CONFIG=1`, remove services (`EN_STRM/EN_MEM/EN_RDMA`) to see whether the failure is shell-side; try different clock regions for the pblock before touching RTL.
