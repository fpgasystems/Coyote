# Build system: CMake, Vivado flows, scripts/

**Purpose:** How a Coyote hardware design is configured (CMake), generated (Jinja templates), synthesized, linked, placed/routed and turned into bitstreams/PDIs; plus a brief note on the driver and software builds. Use it to find *which CMake variable / script / target* controls a given behaviour and how to extend the flow.

## Key files

| Path | Role |
|---|---|
| [cmake/FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) | Entire HW build front-end: defaults (cache vars), `validation_checks_hw()`, `load_apps()`, `create_hw()` (= `gen_scripts()` + `gen_targets()`), dependency lists |
| [cmake/FindVivado.cmake](../../../cmake/FindVivado.cmake) | Locates `vivado` via `VIVADO_ROOT_DIR` / `$XILINX_VIVADO` (`bin/` suffix, plus CMake default prefix paths); sets `VIVADO_BINARY`, `XSC_BINARY` |
| [cmake/FindVitisHLS.cmake](../../../cmake/FindVitisHLS.cmake) | Locates `vitis_hls` (`$XILINX_VITIS_HLS`, `$XILINX_HLS`, `$VITIS_HLS`) else `vitis-run` (`$XILINX_VITIS`/`$VITIS`, Vitis >= 2025.1); honours `VITIS_HLS_ROOT_DIR`; sets `VITIS_HLS_BINARY`, `VITIS_HLS_MODE` = `vitis_hls`/`vitis_run`, `VITIS_HLS` (0/1) |
| [cmake/FindCoyoteSW.cmake](../../../cmake/FindCoyoteSW.cmake) | **Deprecated** SW finder; just `add_subdirectory(${CYT_DIR}/sw)` + warning |
| [scripts/base.tcl.in](../../../scripts/base.tcl.in) | Becomes `<build>/base.tcl`: all dirs + `cfg(...)` array; sourced by every Tcl script **and parsed by `write_hdl.py`** |
| [scripts/export.cmake.in](../../../scripts/export.cmake.in) | Becomes `<build>/export.cmake`; lets an app-flow build re-import a finished shell's configuration |
| [scripts/cr_prjcts/](../../../scripts/cr_prjcts/) | `cr_static/cr_shell/cr_user/cr_sim.tcl.in` project creation + [write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in) (Jinja renderer) |
| [scripts/synth/](../../../scripts/synth/) | `synth_static/shell/user.tcl.in` |
| [scripts/impl/](../../../scripts/impl/) | `link.tcl.in`, `pnr_shell.tcl.in`, `bitgen.tcl.in`, `fix_bif.py.in` |
| [scripts/dyn/](../../../scripts/dyn/) | `flow_dyn_ultrascale_plus.tcl.in`, `flow_dyn_versal.tcl.in`, `flow_app.tcl.in` (per-vFPGA-config PnR for PR) |
| [scripts/ip_inst/](../../../scripts/ip_inst/) | `*_infrastructure.tcl`: Vivado IP instantiation (sourced by `cr_*`) |
| [scripts/apps/](../../../scripts/apps/) | `comp_hls.tcl.in`, `comp_spinal.tcl.in`, `build.sbt` (user HLS / SpinalHDL kernels) |
| [hw/templates/](../../../hw/templates/) | Jinja `*_tmplt.txt` (common / ultrascale_plus / versal), see [README](../../../hw/templates/README.md) |
| [hw/checkpoints/](../../../hw/checkpoints/) | Pre-routed, locked static checkpoints (`static_routed_locked_{u55c,u280,u250,u200}.dcp`, `..._v80_gen{4,5}.dcp`, `static_synthed_v80_gen{4,5}.dcp`) |
| [hw/bd/](../../../hw/bd/) | Block-design Tcl (`cr_pci`, `cr_ctrl`, `cr_hbm`, `cr_ddr`, ...), sourced from `cr_static/cr_shell` |
| [hw/services/network/CMakeLists.txt](../../../hw/services/network/CMakeLists.txt) | `services` target: HLS-builds the network IPs into `<build>/iprepo` |
| [examples/*/hw/CMakeLists.txt](../../../examples/01_hello_world/hw/CMakeLists.txt) | Reference user configs (ex. 10 = PR, ex. 02/12 = HLS/Spinal apps) |
| [sw/CMakeLists.txt](../../../sw/CMakeLists.txt), [driver/Makefile](../../../driver/Makefile) | Software library and kernel-module builds |

**Related:** [coyote_top.md](../coyote_top.md) · [constraints.md](constraints.md) (floorplans, xdc, pblocks) · [../static/static_top.md](../static/static_top.md) (checkpoints) · [../static/reconfig.md](../static/reconfig.md) (loading `.bin`/`.pdi`) · [../shell/shell_top.md](../shell/shell_top.md) · [../user/user_top.md](../user/user_top.md) · [../driver.md](../driver.md) · [../software.md](../software.md) · [../simulation.md](../simulation.md)

---

## 1. Quick start

```bash
# Hardware (set $XILINX_VIVADO / $XILINX_VITIS_HLS, or have vivado/vitis_hls on PATH)
cd <coyote_root>/examples/01_hello_world/hw
mkdir build_hw && cd build_hw
cmake ../ -DFDEV_NAME=u55c          # u55c | u280 | u250 | u200 | v80  (+ any -D<PARAM>=<val> from §4)
make project                        # codegen + HLS + create Vivado projects (fast)
make bitgen                         # synth -> link -> PnR -> bitstreams (hours)
# outputs: build_hw/bitstreams/{cyt_top.bit|.pdi, shell_top.bin|.pdi, ...}

# Driver (on the deployment machine); platform selects XDMA vs QDMA
cd <coyote_root>/driver && make TARGET_PLATFORM=ultrascale_plus   # or: versal (v80)

# Software
cd <coyote_root>/examples/01_hello_world/sw && mkdir build_sw && cd build_sw && cmake ../ && make
```

Step-by-step equivalent of `make bitgen`: `make synth` -> `make link` -> `make shell` -> (`make app` if `EN_PR`) -> `make bitgen` (`link`/`shell` do not exist in the app flow or Versal+`EN_PR`; there `app` follows `synth` directly). Each Vivado invocation is `vivado -mode tcl -source <build>/<script>.tcl -notrace` run from the build directory (relative file names such as `write_hdl.py`, `fix_bif.py` rely on that cwd).

## 2. CMake entry point (what a user `CMakeLists.txt` looks like)

Order is fixed (see [examples/01_hello_world/hw/CMakeLists.txt](../../../examples/01_hello_world/hw/CMakeLists.txt)):

```cmake
cmake_minimum_required(VERSION 3.16)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)                    # REQUIRED: validation_checks_hw() fatals if unset
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)       # declares ALL cache defaults, finds Vivado + Vitis HLS, defines the macros
project(my_project)                   # CMAKE_PROJECT_NAME is used for Vivado project/dir names (<name>_shell, <name>_config_i, ...)
set(EN_STRM 1) ; set(EN_MEM 1) ; set(N_REGIONS 1) ; ...       # configuration
validation_checks_hw()                # derives device/platform/net/mem settings, fatals on illegal combos
load_apps( VFPGA_C0_0 "src" ... )     # optional: one entry per (config, region)
create_hw()                           # gen_scripts() + gen_targets()
```

- `find_package(CoyoteHW)` -> `find_package(Vivado REQUIRED)` + `find_package(VitisHLS REQUIRED)`; failure is `FATAL_ERROR`. `IPREPO_DIR=<build>/iprepo` is created at find time.
- **`load_apps()`** takes exactly `2 * N_REGIONS * N_CONFIG` arguments: keys `VFPGA_C<cfg>_<region>` each followed by **one string** = space-separated list of source dirs *relative to `CMAKE_SOURCE_DIR`*. First dir is the primary one (must hold `vfpga_top.svh`; `hdl/`, `hls/<kernel>/<kernel>.cpp`, `spinal/<kernel>/*.scala`, `init_ip.tcl` are auto-picked); later dirs are libraries (only `hdl/`, `hls/`, `spinal/`, `init_ip.tcl` used; their `hdl` is copied to `hdl/ext/raw/lib<k>`). It sets `LOAD_APPS=1` and `APPS_ALL` (Tcl `set vfpga_c<i>_<j> "<dirs>"` lines injected into `cr_user`, `cr_sim`, `comp_hls`, `comp_spinal`). Without `load_apps()` the projects contain empty wrappers for manual integration. Details of the vFPGA source layout: [../user/user_top.md](../user/user_top.md).
- **Normal-variable shadowing gotcha:** defaults are `set(... CACHE STRING ...)`. A plain `set(FDEV_NAME "u55c")` in the user file shadows `-DFDEV_NAME=...` on the command line (example 10 hard-codes `u55c`). Leave a variable unset in the CMakeLists if it should be overridable from the CLI.
- Software CMake files are independent (see §10).

## 3. The three build flows

Exactly one of `BUILD_STATIC` / `BUILD_SHELL` / `BUILD_APP` must be 1 (`NN != 1` -> fatal "Choose one build flow").

| Flow | Flags | What is synthesized | Static layer | Result |
|---|---|---|---|---|
| **Shell flow** (default) | `BUILD_SHELL=1` | shell (dynamic layer + services) + every user app (`N_CONFIG x N_REGIONS`) | linked from `STATIC_PATH` (`static_routed_locked_<dev>.dcp`, or `..._v80_gen<PCIE_GEN>.dcp`) | full image `cyt_top.*`, partial shell `shell_top.*`, (PR) vFPGA partials |
| **Static flow** | `BUILD_STATIC=1 BUILD_SHELL=0` | static layer + shell + user apps; all routed from scratch | built here (`static_synthed.dcp`) | `cyt_top.*` (+ `static_routed_locked.dcp` in `checkpoints/`). Not compatible with `EN_PR` (fatal) |
| **App flow** | `BUILD_APP=1 BUILD_SHELL=0` | only user apps (all configs) | everything else taken from an already-built shell dir `SHELL_PATH` | partial vFPGA bitstreams only. Requires `EN_PR=1` in that shell (fatal otherwise). `SHELL_PATH` must be set (default `"0"` -> fatal) |

Notes:
- Static checkpoint rule: shell reconfiguration only works if current and new shell were linked against the **same** static checkpoint (PnR is non-deterministic). A static-flow build is therefore only interchangeable with itself ([examples/05_reconfigure_shell/README.md](../../../examples/05_reconfigure_shell/README.md)). See [../static/static_top.md](../static/static_top.md).
- **App flow** (`validation_checks_hw()` else-branch): `include("${SHELL_PATH}/export.cmake")` re-imports most shell parameters (FDEV_NAME, FPGA_PART/ARCH, N_REGIONS, clocks, EN_*, COMP_CORES, BUILD_OPT, FPLAN_PATH, STATIC_PATH, HLS_CLOCK_UNCERTAINTY, ...) with plain `set()`, which **silently overrides** any `-D` or CMakeLists value for those variables in the app build (including `COMP_CORES`, `BUILD_OPT`, `FPLAN_PATH`). Not exported (so they take the app build's own value/cache default): `N_CONFIG` (chosen by the app build), `DATA_DEST_BITS`, `VADDR_BITS`, `N_RDMA_CHAN`, `TCP_STACK_EN`/`ROCE_STACK_EN`, `NR_CC`, `SIM_*`, `EN_XTERM` - keep the first two at their shell values or the app's `lynx_pkg` will not match the shell. Consumes `${SHELL_PATH}/checkpoints/shell_routed_locked.dcp` (written by `flow_dyn` of the original shell build when `EN_PR=1`). Coyote v2 paper (arXiv:2504.21538, Fig. 7b): app flow cuts build time by ~15-20% vs shell flow on a U250.
- **Multiple configs (`N_CONFIG` > 1, needs `EN_PR=1`):** config 0 is placed/routed with the shell and then the shell is locked (`lock_design -level routing`); configs 1..N-1 are PnR'd on the locked shell (fast). Put the most complex app in config 0 (thesis §3.3.5).

### Flow per target (what each stage runs)

```
make project   [services?] [comp_hls.tcl] [comp_spinal.tcl] [cr_static.tcl] cr_shell.tcl cr_user.tcl      (static: all; shell: no cr_static; app: only cr_user, no services)
make synth     [synth_static] -> [synth_shell] -> synth_user      (app flow: synth_user only)
make link      link.tcl        -> checkpoints/shell_linked.dcp
make shell     pnr_shell.tcl   -> shell_opted/placed/phys_opted/routed.dcp (+ static_routed_locked.dcp if static flow)
make app       (EN_PR only) US+: flow_dyn.tcl (subdivide -> cfg0 PnR -> lock -> cfg1.. PnR -> recombine)
                            Versal: flow_dyn.tcl (links static_synthed+shell_synthed+user dcps per config)
                            app flow: flow_app.tcl
make bitgen    bitgen.tcl (+ fix_bif.py + bootgen on Versal)
```

## 4. Configuration parameters

All declared in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) as cache variables (`set(... CACHE ...)`); they reach Tcl via `base.tcl` (`cfg(<key>)`) and Jinja via `write_hdl.py` (`cnfg.<key>`), where `<key>` is the name **as written in [base.tcl.in](../../../scripts/base.tcl.in)** - mostly the lowercase variable name, but see the rename table in §5 - -> [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) (`localparam` / `` `define``) and other templates.

### 4.1 User-facing

| Name | Default | Allowed / notes | Effect | Device constraints |
|---|---|---|---|---|
| `FDEV_NAME` | `"0"` | `u55c`, `u250`, `u280`, `u200`, `v80` | Selects part, arch, memory, constraints dir `hw/constraints/<dev>/`, checkpoint name | `"0"` fatals ("Target device not supported") in shell/static flows. Unused in app flow (from export.cmake) |
| `BUILD_STATIC` / `BUILD_SHELL` / `BUILD_APP` | 0 / 1 / 0 | exactly one = 1 | Flow selection (§3) | `BUILD_STATIC` + `EN_PR` fatal |
| `N_REGIONS` | 1 | 1..15 (fatal if >15; driver `MAX_N_REGIONS`=16) | Number of vFPGAs; `MULT_REGIONS` derived | |
| `N_CONFIG` | 1 | >=1; >1 requires `EN_PR=1` (fatal) | PR configurations per vFPGA; `load_apps` needs `N_REGIONS*N_CONFIG` entries | |
| `EN_PR` | 0 | 0/1 | vFPGA partial reconfiguration; per-vFPGA `.bin/.pdi` | Versal: requires `EN_SHELL_PBLOCK=0` (no nested DFX) |
| `FPLAN_PATH` | `0` | path to `.xdc` or `0` | vFPGA floorplan (PR). Added with `PROCESSING_ORDER LATE` | US+ `EN_PR` with `0`: `make shell` exits 1 with a "floorplan now" message. Versal `EN_PR`: `0` fatal in `flow_dyn`. See [constraints.md](constraints.md) |
| `EN_SHELL_PBLOCK` | 1 | 0/1 | Floorplan the shell (needed for run-time shell reconfiguration + locked static checkpoint). `0` can give better timing | May be 0 only if `BUILD_STATIC=1`, or Versal with `EN_PR=1`. In shell flow (US+) must be 1 (checkpoint already contains pblock) |
| `EOS_TIME` | 1000000 | clock cycles | PR "end of startup" timeout (ICAP done lost across SLRs on U55C); reset value of the static `reconfig_eost` register (`RECONFIG_EOS_TIME`), which the driver overwrites with its own `eost` (default 1000000) when `en_pr` | PR only |
| `EN_STRM` | 1 | 0/1 | Host streams (host <-> vFPGA) | |
| `N_STRM_AXI` | 1 | >=1 (6-bit field in shell cfg) | Host AXI streams per vFPGA; `MULT_STRM_AXI` derived | |
| `EN_MEM` | 0 | 0/1 | Card-memory (HBM/DDR) streams | u200/u250: DDR; u55c/u280/v80: HBM |
| `N_CARD_AXI` | 1 | >=1 | Card AXI streams per vFPGA; Versal "block" HBM: `.dest` = HBM PC | |
| `HBM_SPLIT` | 0 | 0/1 | Concatenate HBM ports (`cr_hbm_split.tcl`) for throughput | US+ HBM only; Versal forced to 0 with warning |
| `HBM_IMPL` | `unified` | `unified`/`block` | Versal HBM mapping (NoC). `unified` also enables Coyote stripe module | Versal only (ignored on US+) |
| `STRIPE_FRAG_SIZE` | 1024 | bytes | Striping fragment size | No effect on US+ HBM (RAMA IP) |
| `DDR_AUTO` | 1 | **must stay 1** | Auto-assign DDR channels `DDR_0..3` (`DDR_0..3` are reset to 0 first; with `DDR_AUTO=0` and `EN_DCARD` the sum check always fatals) | DDR devices (u200, u250) |
| `N_MEM_CHAN` | *derived (listed for reference)* | do not set | `N_REGIONS*N_CARD_AXI + 1` (if `EN_MEM`) + `N_NET_CHAN` (if TCP/RDMA) | validation overwrites |
| `EN_AVX` | 1 | 0/1 | Wide (256-bit AVX) control registers (`cnfg_slave_avx.sv`) | Host CPU must support AVX if SW uses it (§10) |
| `EN_WB` | 1 | 0/1 | Writeback of completions to host memory (polling); "best not to change" | |
| `EN_STATS` | 1 | 0/1 | HW stat counters/VIOs read through sysfs | |
| `EN_RDMA` | 0 | 0/1 | RoCEv2 stack (`rocev2_ip` HLS IP); `N_RDMA_CHAN`, `N_WBS`=4 | Not Versal (fatal) |
| `N_RDMA_AXI` | 1 | >=1 | RDMA AXI streams/vFPGA | |
| `EN_TCP` | 0 | 0/1 | TCP/IP stack (`toe_ip`, `hash_table_ip`) | Not Versal |
| `N_TCP_AXI` | 1 | >=1 | TCP streams/vFPGA | |
| `EN_SNIFFER`, `SNIFFER_VFPGA_ID` | 0, 0 | 0/1, vFPGA id | Packet sniffer; turns on `EN_NET`. Needs `EN_RDMA` or `EN_TCP` too (example 11 sets `EN_RDMA=1`): the network HLS subdirs are gated on `EN_TCP OR EN_RDMA`, so a sniffer-only build has no `services` target and `make project` fails at `make services` | Not Versal |
| `EN_XTERM` | 1 | 0/1 | Colored (`tput`) Tcl console output via `color` proc in `base.tcl`; set 0 for plain logs | |
| `EN_NET_0` / `EN_NET_1` | 1 / 0 | exactly one (both = fatal) | QSFP port (`QSFP` = 0/1) | U55C/U280/U250/U200 |
| `EN_NET` | *derived (reference)* | `EN_RDMA\|EN_TCP\|EN_SNIFFER` | Adds `hw/services/network` subdir, `network_infrastructure.tcl`, CMAC; fatal on Versal | |
| `PMTU_BYTES` | 4096 | power of 2 up to 32768 effective (FIFO sizing in `common_infrastructure.tcl`) | Max packet size; splits transfers; sizes data FIFOs (`axis_data_fifo_512` depth = `N_OUTSTANDING*pmtu/64`); also HLS RoCE config | |
| `N_OUTSTANDING` | 8 | | Outstanding transactions; scales FIFO depths | Versal/QDMA: driver `QDMA_N_ACTIVE_QUEUES` (64) must be >= `3*N_OUTSTANDING`, else rebuild driver |
| `ACLK_F` | 250 | MHz | Shell/system clock; `ACLK_P=1000/ACLK_F` | |
| `EN_NCLK` / `NCLK_F` | 1 / 250 | | Network clock crossing + freq | net builds |
| `EN_UCLK` / `UCLK_F` | 0 / 250 | | Separate vFPGA (user) clock; also HLS target clock period. If `EN_UCLK=0`, user clock = `ACLK_F` | |
| `HCLK_F` | *derived* (450 u55c/u280, 400 v80, 1 u200/u250) | do not set | HBM clock; **overwritten by validation** (a user value is ignored) | HBM devices |
| `SCLK_F` | 250 | MHz | Static-layer clock | Versal only (CIPS-generated); US+ fixed 250. V80 shell flow: forced to **333** (checkpoint was built at that value); only honoured in static flow |
| `PCIE_GEN` | 4 | 4 or 5 | V80: Gen4x16 or Gen5x8 (`PCIE_GT_BITS` 16/8); picks checkpoint `..._gen<N>.dcp` | Versal only; US+ is Gen3x16 |
| `HLS_CLOCK_UNCERTAINTY` | 27 | % | HLS clock uncertainty for user HLS kernels | |
| `STATIC_PROBE`, `SHELL_PROBE` | 1044942 | 32-bit ID | Magic values read by driver (`probe`) | Use a unique `SHELL_PROBE` to tell shells apart (validation prints a hint if equal) |
| `COMP_CORES` | 8 | | `launch_runs -jobs N` for synthesis only (PnR is mostly single-threaded) | |
| `BUILD_OPT` | 0 | 0/1 | PnR directives: `opt_design Explore`, `place_design Auto_1` (Versal >= 2024.2: `AggressiveExplore`), `phys_opt AggressiveExplore`, `route AggressiveExplore`, post-route phys_opt. Much longer | |
| `STATIC_PATH` | `<CYT_DIR>/hw/checkpoints` | dir | Where `static_routed_locked_*.dcp` (shell flow) / `static_synthed_*` (Versal PR) live | |
| `SHELL_PATH` | `"0"` | build dir of a finished shell | App flow input (`export.cmake`, `checkpoints/shell_routed_locked.dcp`) | App flow only |
| `TLBS_S/A/BITS` | 10 / 4 / 12 | | Small-page TLB: 2^S sets, associativity, page order (4 KiB) | Driver asserts page_shift == `PAGE_SHIFT` |
| `TLBL_S/A/BITS` | 9 / 2 / 21 | | Huge-page TLB (2 MiB) | |
| `EN_NRU`, `N_TLB_ACTV` | 0, 16 | | NRU eviction; outstanding PMTUs in MMU | |
| `DATA_DEST_BITS`, `VADDR_BITS` | 4, 48 | | Width of stream-destination field; virtual address bits | |
| `NR_*` (19 vars) | see source | small ints | Register-stage counts on congested paths (`NR_ST_S0/S1`, `NR_SH_*`, `NR_DH_*`, `NR_DC_*`, `NR_DN_*`, `NR_N_S0..2`, `NR_CC`, `NR_SD`, `NR_DD`, `NR_PR`, `NR_NST`, `NR_HST`) | Tweak only for timing closure; `NR_CC` is declared but not exported to `base.tcl` and used nowhere (dead) |
| `UNIT_TEST_DIR`, `SIM_DPI_LIB_NAME`, `SIM_CLOCK_PERIOD` | `<src>/unit-tests`, `coyote_sim`, `4ns` | | Simulation only -> [../simulation.md](../simulation.md) | |

### 4.2 Derived by `validation_checks_hw()` (do not set)

| Variable | Derivation |
|---|---|
| `FPGA_ARCH` | `ultrascale_plus` (u55c/u250/u280/u200) or `versal` (v80); selects `hw/templates/<arch>`, `hw/bd/<arch>`, `flow_dyn_<arch>` |
| `FPGA_PART` (cache, FORCE) | u55c `xcu55c-fsvh2892-2L-e`; u250 `xcu250-figd2104-2L-e`; u200 `xcu200-fsgd2104-2-e`; u280 `xcu280-fsvh2892-2L-e`; v80 `xcv80-lsva4737-2MHP-e-S` |
| `DDR_SIZE`/`HBM_SIZE` (log2 bytes) | u55c: 0/34 (16 GiB HBM); u250, u200: 34/0 (1 DDR chan); u280: 34/33 (HBM used, `AV_DDR=0`); v80: 0/35 (32 GiB HBM) |
| `MC_SIZE`, `N_STRIPE_CHAN`, `MEM_OFFSET` | u55c 29/32/0; u200,u250,u280 =DDR size/`N_DDR_CHAN`/0; v80 30/32/`0x4000000000` (274877906944) |
| `AV_DDR`/`AV_HBM` | `DDR_DEV`={u200,u250}; `HBM_DEV`={u55c,u280,v80} |
| `EN_DCARD`/`EN_HCARD`/`EN_CARD` | Card memory needed if `EN_MEM` **or** `EN_TCP`/`EN_RDMA`; DDR device -> `EN_DCARD`, HBM device -> `EN_HCARD` |
| `EN_MEM_STRIPE` | US+ DDR with >1 channel; Versal with `HBM_IMPL=unified` |
| `N_HCHAN`=3, `N_SCHAN`=2, `N_CHAN` | host channels (stream, migration, PR/WB); `N_CHAN = EN_STRM + EN_MEM`; `STRM_CHAN`/`CARD_CHAN` indices; `EN_XCH_0/1` |
| `N_TCP_CHAN`, `N_RDMA_CHAN`, `N_NET_CHAN`, `N_WBS` (2, or 4 with RDMA), `TCP_STACK_EN`, `ROCE_STACK_EN` | network channel bookkeeping |
| `EN_USER_REG`=0, `POL_INV`=0, `ACLK_P..SCLK_P` | constants / periods (`awk`) |
| `PCIE_GT_BITS` | 16 (US+, V80 Gen4), 8 (V80 Gen5) |

Dead/legacy: `NR_E_S0/1`, `NET_DROP`, branches for unmaintained boards in `ip_inst` scripts; `EN_GP_CTRL/STAT/RW` read undefined `N_GP_*`; `lynx_pkg` tests `cnfg.en_uc`/`cnfg.en_xch_2` which `base.tcl` never defines (always false).

### 4.3 Validation rules (all `FATAL_ERROR` unless noted)

- `CYT_DIR` undefined; zero or >1 flows selected; unsupported `FDEV_NAME`.
- `N_REGIONS > 15`; `N_CONFIG > 1` without `EN_PR`; `BUILD_STATIC && EN_PR`.
- `EN_NET_0 && EN_NET_1`.
- Versal: `PCIE_GEN` not 4/5; `EN_NET` (networking); `EN_PR && EN_SHELL_PBLOCK` (nested DFX unsupported); `EN_SHELL_PBLOCK=0` is only legal for static flow or Versal+`EN_PR`.
- DDR device (`EN_DCARD`): `N_DDR_CHAN` outside 1..4 or `DDR_0..3` sum != `N_DDR_CHAN` (the latter always happens with `DDR_AUTO=0`). `N_DDR_CHAN` is hard-set per device (u200/u250/u280: 1), not a user parameter.
- App flow: `SHELL_PATH == "0"`, or `EN_PR == 0` in the imported shell.
- Warnings: `SHELL_PROBE == STATIC_PROBE` in shell flow; Versal+`HBM_SPLIT=1` (reset to 0).
- `load_apps()` fatals on wrong argument count, missing `VFPGA_C<i>_<j>` key or a key with != 1 value.

## 5. Code generation (templates)

`gen_scripts()` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) `gen_scripts` macro) `configure_file()`s every `scripts/**/*.in` into `<build>/` (CMake `${VAR}` expanded at configure time; Tcl `$var` untouched): `write_hdl.py`, `fix_bif.py`, `base.tcl`, `comp_hls.tcl`, `comp_spinal.tcl`, `coyote_test/__init__.py` (from `scripts/unit_test/__init__.in.py`), `cr_{static,shell,user,sim}.tcl`, `synth_{static,shell,user}.tcl`, `link.tcl`, `pnr_shell.tcl`, `flow_dyn.tcl` (arch-selected), `flow_app.tcl`, `bitgen.tcl`, `export.cmake`.

`write_hdl.py <layer> <cfg> <region>` is called from the `cr_*.tcl` scripts (system `python3`, hard-coded in the scripts, with `PYTHONPATH/PYTHONHOME` unset; needs `jinja2`). It **re-parses `base.tcl`** (`set cfg(name) value` lines; digit-only values become int, anything else - incl. negatives like `strm_chan -1` and floats like periods - stays string) into `cnfg`. Hence **a new parameter must be added to `base.tcl.in` to be visible in templates**. A misspelled/missing key does not error: Jinja renders an undefined `cnfg.<key>` as empty/false (this is how `cnfg.en_uc` and `cnfg.en_xch_2` in `lynx_pkg` are silently always false).

`write_hdl.py` itself injects `cfg['flow']` = `static`/`shell`/`user` (layers 0/1/2) and, for layer 2, overrides `cfg['uclk_p']`. Keys that are *not* simply `lowercase(VAR)`:

| CMake variable | `cfg`/`cnfg` key | | CMake variable | `cfg`/`cnfg` key |
|---|---|---|---|---|
| `FDEV_NAME` | `fdev` | | `STATIC_PROBE` | `stat_probe` |
| `N_REGIONS` | `n_reg` | | `PMTU_BYTES` | `pmtu` |
| `N_CONFIG` | `n_config` | | `COMP_CORES` | `cores` |
| `N_OUTSTANDING` | `n_outs` | | `HLS_CLOCK_UNCERTAINTY` | `hls_clk_u` |
| `BUILD_STATIC/SHELL/APP` | `build_static/shell/app` | | `CMAKE_BINARY_DIR` | `build_dir` |
| `FPGA_ARCH` | `fpga_arch` | | `STATIC_PATH`/`SHELL_PATH`/`FPLAN_PATH` | `static_path`/`shell_path`/`fplan_path` |
| `STRIPE_FRAG_SIZE` | `stripe_frag_size` | | `PCIE_GT_BITS` | `pcie_gt_bits` |

| Layer arg | Where | Renders |
|---|---|---|
| 0 static | `cr_static` | `lynx_pkg.sv`, `cyt_top.sv`, `static_top.sv` (arch dir), `shell_top.sv` -> `<prj>_static/hdl/static/` |
| 1 shell | `cr_shell` | into `<prj>_shell/hdl/`: `lynx_pkg.sv`, `shell_top.sv`, `shell_ctrl.sv`, `dynamic_top.sv`, `dynamic_xbar.sv` (arch dir), `user_wrapper_c<i>_<j>.sv` for every config/region; Versal: `<prj>_shell/xdc/shell_clk.xdc` |
| 2 user | `cr_user` (per cfg i, region j) | under `<prj>_config_<i>/user_c<i>_<j>/`: `hdl/lynx_pkg.sv`, `hdl/wrappers/user_wrapper_c<i>_<j>.sv`, `hdl/wrappers/user_logic_c<i>_<j>.sv`, `xdc/user_clk_c<i>_<j>.xdc` (`uclk_p` = `1000/UCLK_F` if `EN_UCLK` else `1000/ACLK_F`) |
| 3 sim | `cr_sim` | `<build>/sim/lynx_pkg.sv`, `user_logic_c0_0.sv` |

Template roles: [../shell/shell_top.md](../shell/shell_top.md), [../user/user_top.md](../user/user_top.md), [../static/static_top.md](../static/static_top.md). `lynx_pkg` is the single parameter package for all layers (`` `define EN_*`` macros + `localparam` such as `N_REGIONS`, `PMTU_BYTES`, `STAT_PROBE`, `SHELL_PROBE`, `AVX_FLOW`, `PR_FLOW`).

## 6. Make targets

Defined in `gen_targets` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)). There is **no `compile` target**; the PnR step is `shell`.

| Target | Exists when | Runs | Output / dependency |
|---|---|---|---|
| `project` | always (content per flow) | `make services` (if `EN_NET`, not app flow) -> (`LOAD_APPS` only) `vitis_hls -f comp_hls.tcl` (or `vitis-run --tcl comp_hls.tcl --mode hls`) -> (`LOAD_APPS` only) `vivado -source comp_spinal.tcl` -> `cr_static` (static flow) -> `cr_shell` (static/shell) -> `cr_user` | Vivado projects in `<build>/<prj>_static`, `<prj>_shell`, `<prj>_config_<i>/user_c<i>_<j>`; HLS IPs in `iprepo/` |
| `services`, `services.<ip>` | `EN_TCP`/`EN_RDMA` (via `add_subdirectory(hw/services/network)`, which is a **git submodule**: `git submodule update --init`; HLS clock fixed at `CLOCK_PERIOD 4` ns / `25%` uncertainty in its CMakeLists, independent of `NCLK_F`) | HLS synth + export of ARP, ICMP, IP handler, IPv4, MAC-IP encode, eth padding (+ `toe`, `hash_table` if TCP; `rocev2` if RDMA) | `iprepo/` |
| `synth` | always | `synth_user.tcl` (all configs x regions; app flow stops here); shell/static flows first run `synth_shell.tcl` (and `synth_static.tcl` for static flow) | `checkpoints/{static,shell,config_<i>}/*_synthed*.dcp`, `reports/.../*.rpt` |
| `link` | static/shell flows only (inside `if(BUILD_SHELL OR BUILD_STATIC)`), and not (`EN_PR` && Versal) | `link.tcl` | `checkpoints/shell_linked.dcp` |
| `shell` | static/shell flows only, and not (`EN_PR` && Versal) | `pnr_shell.tcl` (opt/place/phys_opt/route; reports; static flow also `update_design -black_box` + `lock_design` -> `static_routed_locked.dcp`) | `checkpoints/shell_routed.dcp` (non-PR); with `EN_PR` the declared output is `shell_subdivided.dcp` (actually produced by `flow_dyn`) |
| `app` | `EN_PR` | shell flow US+: `flow_dyn_ultrascale_plus.tcl`; Versal: `flow_dyn_versal.tcl`; app flow: `flow_app.tcl` | `checkpoints/config_<i>/shell_routed_c<i>.dcp`, `shell_routed_locked.dcp`, (US+) `shell_recombined.dcp` |
| `bitgen` | always | `bitgen.tcl` (depends on `app` if `EN_PR`, else on `shell`) | `bitstreams/` (§8) |
| `sim` | always | `cr_sim.tcl` (+ `comp_hls`, `comp_spinal`) and `sim_dpi_c` (xsc DPI lib in `<build>/sim`) | see [../simulation.md](../simulation.md) |

`shell` with `EN_PR` on US+ declares `shell_subdivided.dcp` as output, but `pnr_shell.tcl` never writes it (only `flow_dyn` does), so `make shell` re-runs PnR every time in that configuration. `bitgen` custom-command OUTPUTs point at `checkpoints/cyt_top.bit`/`shell_top.bit` (non-PR) or `bitstreams/config_<i>/vfpga_*.bit` (PR; US+ actually writes `.bin`), none of which exist, so `make bitgen` always re-runs `bitgen.tcl`. Upstream stages are correctly incremental.

## 7. scripts/ map

| Script | Called by | What it does |
|---|---|---|
| `base.tcl` | all | dirs (`build/{checkpoints,reports,logs,bitstreams,iprepo}`), `cfg()`; `color` helper; warns if `iprepo` missing |
| `cr_static.tcl` | `project` (static) | project `<prj>_static`; `write_hdl 0`; adds `hw/hdl/{pkg,static}`, constraints `hw/constraints/<dev>/static/synth`; sources `pci_infrastructure.tcl` + `hw/bd/<arch>/cr_pci.tcl` (`design_static` BD, hierarchical) |
| `cr_shell.tcl` | `project` | project `<prj>_shell`; `write_hdl 1`; adds `hdl/{pkg,shell,mmu,common}`, `stripe`+`cdma/cdma_u` if `EN_CARD`, `network/{cmac,stack,rdma,tcp}` if net; IP scripts `shell/common/[memory]/[network]_infrastructure`; BDs `cr_ctrl` (+ Versal `cr_xbar` per region), `cr_ddr`, `cr_hbm`/`cr_hbm_split` (+ Versal `cr_bd_hbm_cc_dwc`) |
| `cr_user.tcl` | `project` | project per (cfg, region) `<prj>_config_<i>/user_c<i>_<j>`, top `design_user_wrapper_<j>`; `write_hdl 2`; with `load_apps`: copies `hdl/` (raw), creates `<kernel>_hls_ip` instances, adds Spinal Verilog, copies `vfpga_top.svh`, sources `init_ip.tcl`. Versal: synthesised **out-of-context** (ILA/DebugHub reasons) |
| `cr_sim.tcl` | `sim` | single project `<build>/sim`, top `tb_user`, config 0 region 0 only |
| `synth_*.tcl` | `synth` | `launch_runs -jobs COMP_CORES synth_1`, write `*_synthed.dcp` + utilization report. `synth_user` loops serially over configs/regions |
| `link.tcl` | `link` | In-memory project; adds static (static flow: `static_synthed.dcp` + `static/impl` xdc + `fplan` xdc if pblock; else checkpoint from `STATIC_PATH`, Versal needs Vivado >= 2024.2), shell dcp `SCOPED_TO_CELLS inst_shell`, config-0 user dcps scoped to `inst_shell/inst_dynamic/inst_user_wrapper_<j>`; constraints `shell/impl`, `dynamic/impl`; `link_design [-reconfig_partitions inst_shell] -top cyt_top` |
| `pnr_shell.tcl` | `shell` | `opt_design`->`place_design`->`phys_opt_design`->`route_design`; reports (utilization, route status, timing, DRC `bitstream_checks`) |
| `flow_dyn_ultrascale_plus.tcl` | `app` (PR, shell flow) | `pr_subdivide` shell into vFPGA cells -> PnR config 0 with `fplan` + `FPLAN_PATH` -> `update_design -black_box` + `lock_design` (`shell_routed_locked.dcp`) -> PnR configs 1.. -> `pr_recombine` (`shell_recombined.dcp`) |
| `flow_dyn_versal.tcl` | `app` (PR, Versal) | No subdivide/recombine: loads `static_synthed_<dev>_gen<N>.dcp` (scoped `inst_static`), `shell_synthed.dcp`, user dcps + `FPLAN_PATH`; PnR each config; config 0 also saved as `shell_{linked,opted,placed,phys_opted,routed}.dcp`. Requires `FPLAN_PATH`, `EN_SHELL_PBLOCK=0`, not static flow |
| `flow_app.tcl` | `app` (app flow) | Per config: link user dcps against `${SHELL_PATH}/checkpoints/shell_routed_locked.dcp` and PnR |
| `bitgen.tcl` | `bitgen` | Non-PR: open `shell_routed.dcp`; PR: open each `config_<i>/shell_routed_c<i>.dcp` for the vFPGA partials, then (shell flow) US+: open `shell_recombined.dcp` -> `shell_top.bin` + `cyt_top.bit`; Versal: reopen `shell_routed.dcp` (saved from config 0 by `flow_dyn_versal`) -> `cyt_top.pdi` only; writes `.ltx` probes |
| `fix_bif.py` | `bitgen` (Versal) | Inserts `boot_device { pcie }` into the `.bif` after `bitstream_master:` `id =`; then `bootgen -arch versal` regenerates `cyt_top.pdi` so it can be loaded through PCIe |
| `comp_hls.tcl` | `project` | For each `hls/<kernel>/` dir: copies sources, `csynth_design`, `export_design -ipname <kernel>_hls_ip -vendor user.org -version 1.0`, copies to `iprepo/<kernel>_hls_ip`. Clock = `UCLK_P` if `EN_UCLK` else `ACLK_P`, uncertainty `HLS_CLOCK_UNCERTAINTY`%. Top function name must equal directory/file name `<kernel>` |
| `comp_spinal.tcl` | `project` | For each `spinal/<kernel>/*.scala`: copies [build.sbt](../../../scripts/apps/build.sbt) (SpinalHDL 1.14.2, Scala 2.13.18), `sbt "runMain <kernel>Verilog"`, expects `gen/*.v`; needs `sbt` + JDK >= 11; exits silently if no spinal kernels |

### IP instantiation scripts ([scripts/ip_inst/](../../../scripts/ip_inst/))

| Script | Sourced by | IPs created (versions: `xilinx.com:ip:<name>`) |
|---|---|---|
| `pci_infrastructure.tcl` | `cr_static` | `axi_register_slice` 2.1, `axis_register_slice` 1.1 (static 512/32/req 96), PR path (`pr_clock_converter`, `pr_dwidth_converter`, `pr_reg_slice`), data FIFOs (WB, slave); US+: `debug_bridge_static`, `debug_hub_static`, VIOs; Versal: QDMA register slices, `ecc` (`qdma_ecc`). XDMA/QDMA/CIPS themselves come from the BD `hw/bd/<arch>/cr_pci.tcl` |
| `shell_infrastructure.tcl` | `cr_shell` | `proc_sys_reset` x3 (a/n/u), HBM/stripe `axis_data_fifo`s, TLB/cch FIFOs; US+: `debug_bridge_dynamic`, VIOs, `axi_crossbar` `dyn_crossbar_<i>` per region (Versal uses SmartConnect BD `cr_xbar.tcl` instead) |
| `common_infrastructure.tcl` | `cr_shell`, `cr_user`, `cr_sim` | register slices, clock converters (`axil_clock_converter`; Versal: SmartConnect BD), `axis_clock_converter`s, `axis_data_fifo`s for meta/req queues; data FIFOs sized by `PMTU_BYTES` x `N_OUTSTANDING` |
| `memory_infrastructure.tcl` | `cr_shell` if `EN_CARD` | Versal: `clk_wizard` `clk_gen_hbm`; DDR4 IPs for u200/u250/u280 |
| `network_infrastructure.tcl` | `cr_shell` if `EN_NET` | VIOs, `cmac_usplus_axis_0` (per device/QSFP; needs CMAC license), CC/FIFO/slices for RDMA/TCP, HLS IPs `rocev2_ip` 0.82 (RDMA), `toe_ip` 1.6 + `hash_table_ip` 1.0 (TCP), `ethernet_frame_padding_512_ip` |
| `user_infrastructure.tcl` | `cr_user` | US+: `debug_bridge_user` 3.0; Versal: BD `debug_hub_user` (`axi_dbg_hub`) |

IP versions are pinned in these scripts and in `hw/bd/*`: e.g. `axis_data_fifo` 2.0, `axis_register_slice`/`axis_clock_converter` 1.1, `proc_sys_reset` 5.0, `vio` 3.0, `axi_noc` 1.1, `hbm` 1.0, `rama` 1.1, `ddr4` 2.2; **XDMA** 4.1, or 4.2 when Vivado >= 2025.1 (selected by string compare in [hw/bd/ultrascale_plus/cr_pci.tcl](../../../hw/bd/ultrascale_plus/cr_pci.tcl)); `util_ds_buf` is version-checked as 2.2 (u55c) / 2.1 in the IP check list, but instantiated unversioned. A Vivado whose catalog lacks a pinned version fails in `cr_*`.

## 8. Outputs

Build dir layout (`<build>` = cmake binary dir):

| Path | Content |
|---|---|
| `<prj>_static/`, `<prj>_shell/`, `<prj>_config_<i>/user_c<i>_<j>/` | Vivado projects; generated HDL in `hdl/`, constraints `xdc/`; `hdl/wrappers/` holds the (re)generated user wrapper (manual integration point if no `load_apps`) |
| `iprepo/` | Exported HLS IPs (network + user) |
| `checkpoints/{static,shell,config_<i>}/`, `checkpoints/*.dcp` | `*_synthed.dcp`, `shell_{linked,opted,placed,phys_opted,routed}.dcp`, `shell_subdivided/recombined/routed_locked.dcp`, `static_routed_locked.dcp` (static flow) |
| `reports/`, `logs/` | utilization/timing/DRC per stage and config |
| `bitstreams/` | Final images, below |

| Flow / arch | File | Use |
|---|---|---|
| Any (full image) | `bitstreams/cyt_top.bit` (US+) / `cyt_top.pdi` (Versal) + `cyt_top.ltx` | Initial programming (Vivado HW manager, [util/program_hacc_local.sh](../../../util/program_hacc_local.sh)). Versal `.pdi` is re-bootgen'd with `boot_device {pcie}` |
| Shell flow (`BUILD_SHELL=1`; only if `EN_SHELL_PBLOCK=1`, or `EN_PR` on US+) | `bitstreams/shell_top.bin` (US+, partial, `-bin_file -no_binary_bitfile`; no `.bit` is produced) / `shell_top.pdi` + `shell_top.ltx` (Versal non-PR only) | Run-time shell reconfiguration through the driver (`cRcnfg::reconfigureShell`) |
| `EN_PR` | `bitstreams/config_<i>/vfpga_c<i>_<j>.bin` (US+) / `.pdi` (Versal) + `.ltx` | `cRcnfg::reconfigureApp(path, vfid)` |
| Static flow | **only** `bitstreams/cyt_top.{bit,pdi}` + `.ltx` (no `shell_top.*`: the `build_static` branch of `bitgen.tcl` writes just the full image; declared bitgen output `checkpoints/cyt_top.{bit,pdi}`); routed static netlist at `checkpoints/static_routed_locked.dcp` | To publish as a new provided checkpoint copy/rename to `hw/checkpoints/static_routed_locked_<dev>.dcp` (Versal: `..._<dev>_gen<N>.dcp`, `static_synthed_..`) |
| App flow | only `bitstreams/config_<i>/vfpga_*` | Must match the running shell (same `SHELL_PATH` build) |

Loading: [../static/reconfig.md](../static/reconfig.md). Bitstream `.bin` for dynamic loading; `.bit` for JTAG ([quick-start.rst](../../source/intro/quick-start.rst)). Reconfiguration with mismatched static checkpoints hangs the card (needs reboot).

## 9. UltraScale+ vs Versal

Cross-layer summary: [coyote_top.md](../coyote_top.md#ultrascale-vs-versal-summary). Build-specific differences:

| Aspect | UltraScale+ | Versal (v80) |
|---|---|---|
| Templates / BDs / flow script | `hw/templates/ultrascale_plus`, `hw/bd/ultrascale_plus`, `flow_dyn_ultrascale_plus` | `.../versal`, `flow_dyn_versal`, + `shell_clk_tmplt` xdc |
| Targets with `EN_PR=1` | `link`, `shell`, `app` | no `link`/`shell` targets; each config linked from synthesized dcps (`flow_dyn_versal`) -> `shell_top.pdi` not generated |
| User synthesis | in-context | out-of-context (`-mode out_of_context`), resource numbers only valid after PnR |
| `BUILD_OPT` place directive | `Auto_1` | `Auto_1` (< 2024.2) / `AggressiveExplore` (>= 2024.2) |
| App flow (`BUILD_APP`) | Supported | Not validated (TODO in `gen_targets`); `flow_app.tcl` is arch-agnostic and `flow_dyn_versal` does write `shell_routed_locked.dcp`, but it has not been tested |

## 10. How build parameters reach driver & software

No generated header is shared with C/C++: the HW configuration is **discovered at run time** from registers (details: [../driver.md](../driver.md), [../software.md](../software.md)).

| CMake param(s) | RTL constant ([lynx_pkg](../../../hw/templates/common/lynx_pkg_tmplt.txt)) | Register (RTL) -> driver field ([coyote_setup.c](../../../driver/src/coyote_setup.c) `read_shell_config`) |
|---|---|---|
| `STATIC_PROBE` | `STAT_PROBE` | static cfg reg 0 ([static_slave.sv](../../../hw/hdl/static/static_slave.sv)) -> `probe_stat` |
| `SHELL_PROBE`, `N_CHAN`, `N_REGIONS` | `SHELL_PROBE`, `N_CHAN`, `N_REGIONS` | shell cfg regs 0-2 ([shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv)) -> `probe_shell`, `n_fpga_chan`, `n_fpga_reg` |
| `EN_AVX`, `EN_WB`, `TLBS_*`, `TLBL_*` | `AVX_FLOW`, `WB_FLOW`, TLB orders/assoc/page shift | `ctrl_cnfg` -> `en_avx`, `en_wb`, `stlb_meta`, `ltlb_meta` |
| `EN_STRM`, `EN_MEM`, `N_STRM_AXI`, `N_CARD_AXI`, `HBM_IMPL=block` | `STRM_FLOW`, `MEM_FLOW`, ..., `BLOCK_MEM_IMPL_EN` | `mem_cnfg` -> `en_strm`, `en_mem`, `n_host_axi`, `n_card_axi`, `en_block_mem` |
| `EN_PR`, `EN_SHELL_PBLOCK`, `EOS_TIME` | `PR_FLOW`, `SHELL_PBLOCK_EN`, `RECONFIG_EOS_TIME` | `pr_cnfg`, `shell_pblock_cnfg` -> `en_pr`, `en_shell_pblock` (driver writes `reconfig_eost` from its `eost` module param) |
| `EN_RDMA`/`EN_TCP`, `QSFP` | `RDMA_FLOW`, `TCP_FLOW`, `QSFP` | `rdma_cnfg`/`tcp_cnfg` -> `en_rdma`, `en_tcp`, `qsfp` (IP/MAC come from driver module params) |

- `N_STRM_AXI` and `N_CARD_AXI` are each 6-bit fields (`N_STRM_AXI_MASK` 0xfc, `N_CARD_AXI_MASK` 0x3f00). `EN_STATS` has no driver-visible register (it only gates stats RTL/VIOs that sysfs reads).
- Not discoverable (compile-time only): `PMTU_BYTES`, `N_OUTSTANDING`, `STRIPE_FRAG_SIZE`, clocks. Driver-side limits to keep in sync: `QDMA_N_ACTIVE_QUEUES >= 3*N_OUTSTANDING` and `MAX_N_REGIONS` in [coyote_defs.h](../../../driver/include/coyote_defs.h).
- Everything is visible through sysfs (`/sys/kernel/coyote_sysfs_0/cyt_attr_cnfg`); `dmesg` prints the parsed values and `probe returning 0` on success.
- **Driver build** ([driver/Makefile](../../../driver/Makefile)): `make TARGET_PLATFORM=ultrascale_plus|versal` (default `ultrascale_plus`) -> `build/coyote_driver.ko`; selects `pci_xdma.o` + `-DPLATFORM_ULTRASCALE_PLUS` or `pci_qdma.o` + `-DPLATFORM_VERSAL`. Must be built on the target host (kernel headers via `KERNELDIR`). Insert: `insmod coyote_driver.ko [ip_addr=.. mac_addr=.. eost=<cycles> en_hmm=<bool>]` (`eost` default 1000000; `en_hmm` legacy/deprecated, see [driver/src/coyote_driver.c](../../../driver/src/coyote_driver.c)).
- **Software build** ([sw/CMakeLists.txt](../../../sw/CMakeLists.txt)): shared library `libcoyote.so` (C++17, `-march=native`). Options: `EN_AVX` (default 1 -> `-DEN_AVX -mavx`, **compiles in** the AVX register path; at run time `cThread` still checks the HW's `en_avx` from the driver, so HW `EN_AVX=0` works with an `EN_AVX` library), `EN_ROCM`/`EN_CUDA` (GPU P2P, mutually exclusive; ROCm needs `CXX=hipcc`), requires Boost. Examples link it with `add_subdirectory(<root>/sw coyote)`, or `EN_SIM=ON` -> `add_subdirectory(<root>/sim/sw coyote)` for simulation ([../simulation.md](../simulation.md)). `find_package(CoyoteSW)` is deprecated. `VERBOSE_DEBUG_1..3` enable run-time prints.

## 11. Gotchas

- **Vivado versions:** US+ >= 2022.1 (tested through 2025.1); V80 >= 2024.2 (static checkpoint). HLS: `vitis_hls` or, if absent, `vitis-run` (2025.1+).
- Environment: `XILINX_VIVADO` / `XILINX_VITIS_HLS` must point to the install (`find_path` searches `VIVADO_ROOT_DIR`, `$XILINX_VIVADO` and CMake's default prefixes, which include `PATH` entries with a `bin` suffix; setting the env var is the most reliable). Vivado is spawned with `PYTHONPATH/PYTHONHOME` unset and the `cr_*` scripts call the system `python3` (needs `jinja2`); `bootgen` must be on `PATH` (Versal).
- `cr_*` and `pnr_shell` scripts `exit 1` on any Tcl error (`catch` wrapper); read `vivado.log`/`logs/`.
- `make project` must be re-run after changing any CMake parameter or user source; user `hdl/` and `vfpga_top.svh` are *copied* into the project at `project` time. Re-run `make project` (not just `synth`) after editing app sources.
- HLS user kernel IPs are named `<kernel>_hls_ip`, global in `iprepo/`: two apps with the same kernel name overwrite each other (warning printed).
- `STATIC_PATH` shell flow with a non-matching Vivado version can fail at `link` (DCP version). Never mix `.bin` shells built against different static checkpoints.
- `EN_PR` + `N_CONFIG > 1`: `FPLAN_PATH` strongly advised; without it US+ `make shell` aborts by design.
- `N_OUTSTANDING`/`PMTU_BYTES` increase BRAM/URAM for data FIFOs and hurt timing, especially with many HBM channels.
- `SHELL_PROBE` default equals `STATIC_PROBE`; give different shells unique IDs to tell them apart in `dmesg`.
- Known defects in this area: [known_issues.md](../known_issues.md) (`BLD-*`).

## 12. Recipes

### 12.1 Add a new CMake parameter end-to-end (e.g. `EN_FOO`)
1. [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake): `set(EN_FOO 0 CACHE STRING "...")` in the matching section; add validation/derivation inside `validation_checks_hw()` (inside the `BUILD_SHELL OR BUILD_STATIC` branch).
2. [base.tcl.in](../../../scripts/base.tcl.in): `set cfg(en_foo) ${EN_FOO}` (needed for Tcl scripts **and** `write_hdl.py`; keep value on one line, last word = value; the key spelling is what templates must use - a typo silently renders as undefined).
3. [export.cmake.in](../../../scripts/export.cmake.in): `set(EN_FOO ${EN_FOO})` so app-flow builds inherit it (otherwise the app build falls back to the cache default).
4. [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt): `` {% if cnfg.en_foo %}`define EN_FOO{% endif %} `` and/or `localparam integer FOO_FLOW = {{ cnfg.en_foo }};`. Use `cnfg.en_foo` in other templates / `cfg(en_foo)` in `cr_*.tcl` (e.g., conditional `add_files`, IP instantiation).
5. If the driver/SW must know: add a bit to a `shell_slave.sv` config register (`axi_rdata[..] <= FOO_FLOW;`), the mask/shift + `struct cyt_shell_cnfg_regs` use in [coyote_defs.h](../../../driver/include/coyote_defs.h) and a read in `read_shell_config()` ([../driver.md](../driver.md)).
6. Re-run `cmake` + `make project`.

### 12.2 Add a new IP to `ip_inst`
1. Pick the layer: static -> `pci_infrastructure.tcl`; shell/services -> `shell_infrastructure.tcl`, `memory_infrastructure.tcl`, or `network_infrastructure.tcl`; shared by shell+user+sim -> `common_infrastructure.tcl`; user-only -> `user_infrastructure.tcl`.
2. Append `create_ip -name <ip> -vendor xilinx.com -library ip -version <v> -module_name <inst_name>` and `set_property -dict [list CONFIG.* ...] [get_ips <inst_name>]`. Gate with `$cfg(...)` for parameters/arch (`$cfg(fpga_arch) eq "versal"`). Pin the version; IPs from HLS use `-vendor user.org -library hls` and must be exported into `iprepo/` first.
3. Instantiate `<inst_name>` in HDL under `hw/hdl/**` (or a template). New HDL dirs must be added in the relevant `cr_*.tcl` `add_files`.
4. `make project`. Note that `cr_user`/`cr_sim` source `common_infrastructure.tcl` too, so a heavy IP there is created in every project.

### 12.3 Build only an app against an existing shell (app flow)
```bash
# 1. Build the shell once with PR enabled (US+). N_CONFIG, FPLAN_PATH as needed:
cmake <path> -DFDEV_NAME=u55c -DEN_PR=1 -DFPLAN_PATH=<floorplan.xdc> && make project && make bitgen   # in build_shell/
# 2. New project dir: reuse the shell's configuration through SHELL_PATH
mkdir build_app && cd build_app
cmake <app_hw_dir> -DBUILD_SHELL=0 -DBUILD_APP=1 -DSHELL_PATH=<abs path to build_shell>
make project && make bitgen        # -> bitstreams/config_<i>/vfpga_c<i>_<j>.bin
```
`<app_hw_dir>/CMakeLists.txt` must not hard-code `BUILD_SHELL`/`BUILD_APP` (they would shadow `-D`; device and other shell parameters come from `export.cmake`), must call `validation_checks_hw()` and `load_apps(...)` with a path for every (config, region) of the new build. `SHELL_PATH` must contain `export.cmake` and `checkpoints/shell_routed_locked.dcp`. Supported/validated on US+ only (Versal app flow is untested).

### 12.4 Rebuild the static layer
`cmake ... -DBUILD_STATIC=1 -DBUILD_SHELL=0 [-DSCLK_F=.. -DEN_SHELL_PBLOCK=0 -DBUILD_OPT=1]` -> `make project && make bitgen`. Takes the longest; result is self-consistent only with shells built from the same dir. V80 with Vivado < 2024.2 requires this.
