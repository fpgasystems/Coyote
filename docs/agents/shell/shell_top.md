# Shell (dynamic layer + application layer): `shell_top`

**Purpose:** The reconfigurable part of Coyote above the static layer. `shell_top` is a generated hub that wires the static-layer interfaces (`axi_main` host control bus, host DMA channels, writeback, IRQs) to the shell services (MMU/TLB, card memory, network, per-vFPGA config) and to the N_REGIONS user wrappers (vFPGAs).
This file covers the shell skeleton, the control-path address map, the shell-level and per-vFPGA register maps, clocks/CDC, and the HW <-> driver <-> SW linkage. Service internals live in sibling docs.

## Key files

| Path | Role |
|---|---|
| [shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt) | Jinja template -> `shell_top.sv`: ctrl CC, data CC, `shell_slave`, network, memory (DDR/HBM), `design_dynamic_top`, DMA stats |
| [shell_ctrl_tmplt.txt](../../../hw/templates/common/shell_ctrl_tmplt.txt) | `shell_ctrl_cc`: wrapper of BD `design_ctrl` (clocks, resets, AXI split of `axi_main`) |
| [cr_ctrl.tcl (US+)](../../../hw/bd/ultrascale_plus/cr_ctrl.tcl), [cr_ctrl.tcl (Versal)](../../../hw/bd/versal/cr_ctrl.tcl) | Create BD `design_ctrl` (`cr_bd_design_ctrl`); defines the AXI address map |
| [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt) | `design_dynamic_top`: decoupling, host/card/net slicing + CDC to uclk, `dynamic_crossbar`, `mmu_top`, `design_user_wrapper_i` |
| [dynamic_xbar_tmplt.txt (US+)](../../../hw/templates/ultrascale_plus/dynamic_xbar_tmplt.txt), [dynamic_xbar_tmplt.txt (Versal)](../../../hw/templates/versal/dynamic_xbar_tmplt.txt) | `dynamic_crossbar`: per-region 1->4 AXI-Lite split (lTLB / sTLB / user CSR / vFPGA cnfg) |
| [shell_infrastructure.tcl](../../../scripts/ip_inst/shell_infrastructure.tcl) | Creates IP `dyn_crossbar_<i>` (US+ only; base addresses/width), `debug_bridge_dynamic`, VIOs |
| [cr_xbar.tcl (Versal)](../../../hw/bd/versal/cr_xbar.tcl) | Versal replacement for `dyn_crossbar_<i>`: SmartConnect BD (`cr_bd_dyn_xbar`) |
| [cr_shell.tcl.in](../../../scripts/cr_prjcts/cr_shell.tcl.in) | Calls `cr_bd_design_ctrl` (line ~138) and `cr_bd_dyn_xbar` per region (Versal, line ~147) |
| [shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv) | Shell-level config/status registers (`axi_cnfg`) |
| [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv) | Per-vFPGA config registers, AXI4-Lite, 64-bit regs (`EN_AVX=0`) |
| [cnfg_slave_avx.sv](../../../hw/hdl/shell/cnfg_slave_avx.sv) | Same registers, AXI4 256-bit, one posted command = one 256-bit write (`EN_AVX=1`) |
| [shell_data_cc.sv](../../../hw/hdl/shell/shell_data_cc.sv) | xclk <-> aclk crossing of host data streams, DMA requests, writeback, user IRQs |
| [shell_split_data.sv](../../../hw/hdl/shell/shell_split_data.sv) | 1 -> N_CHAN fan-out of one static channel (only instantiated if `N_CHAN > N_SCHAN`) |
| [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | `lynxTypes` package + `` `define EN_* `` flags: all SV params (N_REGIONS, AXI_BPSS_BAR_BITS, ...) |
| [user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt), [shell_clk_tmplt.txt (Versal)](../../../hw/templates/versal/shell_clk_tmplt.txt) | XDC templates for the user-flow clock and Versal xclk |
| [write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in) | Renders the templates per build flow (`static`/`shell`/`user`) |
| [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) | Defines/derives all config knobs (N_REGIONS, EN_*, N_CHAN, N_SCHAN, clocks, ...) |
| [coyote_defs.h](../../../driver/include/coyote_defs.h) | Driver register structs (`cyt_shell_cnfg_regs`, `vfpga_cnfg_regs`), offsets, mmap/ioctl IDs |
| [coyote_setup.c](../../../driver/src/coyote_setup.c) | `read_shell_config()`, vFPGA BAR address computation (line ~393) |
| [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c) | `vfpga_dev_mmap()` (line 641), ioctls incl. `IOCTL_READ_SHELL_CONFIG` |
| [vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c), [vfpga_isr.c](../../../driver/src/vfpga/vfpga_isr.c) | Driver accessors of `cnfg_regs` (ISR, TLB invalidate, offload/sync), ISR |
| [cThread.cpp](../../../sw/src/cThread.cpp), [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp) | SW: `mmapFpga`, `postCmd`, `setCSR/getCSR`, `checkCompleted`; reg enums/consts |

## Related
- Entry point: [../coyote_top.md](../coyote_top.md); static layer: [../static/static_top.md](../static/static_top.md), [../static/host_dma.md](../static/host_dma.md), [../static/reconfig.md](../static/reconfig.md)
- Services: [../services/mmu.md](../services/mmu.md), [../services/memory.md](../services/memory.md), [../services/network.md](../services/network.md)
- User side: [../user/user_top.md](../user/user_top.md); driver: [../driver.md](../driver.md); software: [../software.md](../software.md); build: [../build/build_top.md](../build/build_top.md), [../build/constraints.md](../build/constraints.md); sim: [../simulation.md](../simulation.md)

---

## 1. What the shell is and how it is generated

- Layering: `cyt_top` -> { `static_top` (PCIe/XDMA|QDMA, static regs, PR/ICAP) , `shell_top` (this doc) }. `cyt_top` ([cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt)) instantiates `static_top inst_static` and `shell_top inst_shell`; they are joined by `axi_main_st2sh` (512-bit AXI4, 6-bit ID), `N_SCHAN` pairs of `axis_dyn_*` + `dma_rd/wr_req`, `wback`, `usr_irq[14:0]`, and `xclk/xresetn`.
- `shell_top` is **rendered** by Jinja ([write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in), `trim_blocks`), once per build flow. Body is wrapped in `{% if cnfg.flow == 'shell' %}` ([shell_top_tmplt.txt:403](../../../hw/templates/common/shell_top_tmplt.txt)), so in the *static* flow (`BUILD_STATIC=1`) only the port list is emitted (empty shell stub inside the static checkpoint).
  - In the *shell* flow (`BUILD_SHELL=1`) rendered: `lynx_pkg`, `shell_top`, `shell_ctrl`, (Versal) `shell_clk.xdc`, `dynamic_top`, `dynamic_xbar`, `user_wrapper` x (n_config x n_reg).
  - *User/app* flow renders only `lynx_pkg`, `user_wrapper`, `user_logic`, `user_clk.xdc`.
- Feature flags reach RTL two ways: (a) Jinja `cnfg.*` conditionals in templates; (b) `` `define EN_* `` in generated `lynxTypes` (used by hand-written RTL such as `shell_slave`, `cnfg_slave*`, `mmu_top` via `` `ifdef``). Localparams from `lynx_pkg_tmplt.txt` (e.g. `N_REGIONS`, `N_CHAN`, `AVX_FLOW`, `STRM_FLOW`, `PR_FLOW`) are what the shell regs report to the driver.

### 1.1 Module hierarchy (shell flow)

```
shell_top
 ├─ shell_ctrl_cc            -> BD design_ctrl: clk_wiz (aclk/nclk/uclk), proc_sys_reset x3, axi_interconnect|smartconnect
 │    outputs: axi_cnfg (AXI4L), axi_ctrl[N_REGIONS] (AXI4L), axim_ctrl[N_REGIONS] (AXI4 256b, if EN_AVX), clocks/resets
 ├─ shell_data_cc            -> xclk<->aclk crossing, N_SCHAN channels, usr_irq, wback
 ├─ shell_split_data         -> only if N_CHAN > N_SCHAN (never true with current CMake: N_SCHAN = 2 >= N_CHAN)
 ├─ debug_bridge_dynamic     -> US+ only: demux of the shell BSCAN chain into N_REGIONS user chains
 ├─ shell_slave              -> axi_cnfg regs (probe, config readback, IP/MAC, decouple, DMA/net stats)
 ├─ network_top              -> if EN_NET (RDMA / TCP / sniffer); see ../services/network.md
 ├─ axi_stripe, design_ddr | design_hbm (+Versal clk_gen_hbm, hbm_cc_dwc)   -> if EN_CARD; see ../services/memory.md
 ├─ design_dynamic_top (dynamic_top_tmplt)
 │    ├─ dcpl_select, decoupling of all vFPGA-facing interfaces (axis/dma/axil/meta decouplers)
 │    ├─ host path (EN_STRM): dma_reg_array -> mux_host -> credits -> [axis_ccross to uclk] -> slices -> decoupler
 │    ├─ card path (EN_MEM): cdma (sync/offload + per-vFPGA), axi_stripe, last-rewriter, credits, [ccross], slices, decoupler
 │    ├─ rdma / tcp slices + arbiters (+ccross) ; ARP lookup
 │    ├─ dynamic_crossbar     -> per region: lTLB / sTLB / user CSR / cnfg
 │    ├─ mmu_top              -> per region: TLBs + cnfg_slave[_avx]  (see ../services/mmu.md)
 │    └─ design_user_wrapper_{i} (i < N_REGIONS)  -> vFPGA (see ../user/user_top.md)
 └─ dma_stats (xch_0/xch_1) [+ vio_shell_xstats on US+]   -> EN_STATS
```

### 1.2 What is instantiated depending on config

| Knob (CMake -> `cnfg.*` / `` `EN_*``) | Effect in shell |
|---|---|
| `N_REGIONS` (`n_reg`, max 15) | #vFPGAs: `axi_ctrl[i]`, `axim_ctrl[i]`, `dyn_crossbar_i`, `cnfg_slave[_avx]` i, `design_user_wrapper_i`, BSCAN masters. Limit 15 because `usr_irq` is 15 bits and IRQ vector 15 is the PR/reconfig IRQ |
| `EN_STRM` (`en_strm`), `N_STRM_AXI` | host streaming path in dynamic_top; `m_host_dma_*`, `axis_host`; channel index `STRM_CHAN` (0 if enabled) |
| `EN_MEM` (`en_mem`), `N_CARD_AXI` | card path (cdma, stripe, `m_axi_ddr[1+N_REGIONS*N_CARD_AXI]`); channel `CARD_CHAN` (0 or 1); needs `EN_CARD` (HBM/DDR) |
| `EN_RDMA`, `EN_TCP`, `EN_SNIFFER`, `EN_NET_0/1` -> `EN_NET` | `network_top`, ARP/RDMA/TCP meta interfaces through dynamic_top, `net_stats`, per-stack DDR/HBM AXI (`axi_ddr_rdma/tcp` -> `axi_stripe` -> `axi_mem[0..N_NET_CHAN-1]`). Versal: network not supported (CMake fatal) |
| `EN_AVX` (`en_avx`) | `axim_ctrl` ports on `design_ctrl`/dynamic_top; `mmu_top` uses `cnfg_slave_avx`; `axi_ctrl_cnfg` of the crossbar is tied off |
| `EN_WB` (`en_wb`), `N_WBS` (2, or 4 with RDMA) | writeback FIFOs in `cnfg_slave*`, `m_wback` through `shell_data_cc` to static layer (host-memory completion counters) |
| `EN_PR` (`en_pr`) | vFPGA decoupling is meaningful; `CLOCK_BUFFER_TYPE NONE` on user `aclk` ([user_clk](../../../hw/templates/common/user_clk_tmplt.txt)); Versal: debug hub goes to vFPGA instead of shell |
| `EN_UCLK`/`UCLK_F`, `EN_NCLK`/`NCLK_F`, `ACLK_F`, `SCLK_F`, `HCLK_F` | see section 6 |
| `EN_STATS` (+`EN_XCH_0/1`) | `dma_stats` instances (`hdma_stats_0/1`), `net_stat_t`, `vio_shell_*` (US+); registers 64-69/96-104 in `shell_slave` |
| `EN_CRED_LOCAL/REMOTE`, `N_OUTSTANDING`, `NR_*` (pipeline stages) | credit logic in dynamic_top; register-slice depths `N_REG_SHELL_S0/S1`, `N_REG_DYN_*` |
| `TLBS_*/TLBL_*`, `N_TLB_ACTV`, `EN_NRU` | TLB geometry; reported in `CTRL_CNFG_REG` so the driver adapts (see [../services/mmu.md](../services/mmu.md)) |
| `FDEV_NAME` | selects HBM/DDR/GT ports, `fpga_burn` OBUF (u55c), QSFP low-speed pins (u200/u250) |

Channel numbering (CMake `FindCoyoteHW.cmake` ~line 745-775): `N_HCHAN=3` host DMA channels in static (stream, migration, PR/WB); `N_SCHAN = N_HCHAN-1 = 2` cross into the shell; `N_CHAN = EN_STRM + EN_MEM`. `STRM_CHAN`/`CARD_CHAN` are compacted indices into `axis_dyn_in/out[N_CHAN]`, `dma_*_req[N_CHAN]`. If `N_CHAN < N_SCHAN`, unused channels are tied off with `tie_off_s/m()` ([shell_top_tmplt.txt:596](../../../hw/templates/common/shell_top_tmplt.txt)). `EN_XCH_0 = N_CHAN>0`, `EN_XCH_1 = N_CHAN>1`.

---

## 2. Control path: `axi_main` -> address map

### 2.1 shell_ctrl / `design_ctrl`

`shell_ctrl_cc` ([shell_ctrl_tmplt.txt](../../../hw/templates/common/shell_ctrl_tmplt.txt)) only instantiates BD `design_ctrl` and maps the AXI interface structs onto its flattened ports. It does three jobs:

1. **Clocks**: `clk_wiz_0` (US+: `clk_wiz` 6.0, 250 MHz in; Versal: `clk_wizard` 1.0, input `SCLK_F`; note the Versal `cr_ctrl.tcl` IP-availability check still lists `clk_wiz:6.0`, not `clk_wizard:1.0`) from `xclk` -> `aclk` (`ACLK_F`), `nclk` (`NCLK_F`), `uclk` (`UCLK_F`). All three outputs are *always* generated; `EN_NCLK`/`EN_UCLK` only decide whether downstream logic crosses into them. `lckresetn` = `clk_wiz.locked`; `sys_reset` (active high, tied `1'b0` by `shell_top`) -> `clk_wiz.reset`.
2. **Resets**: three `proc_sys_reset` (a/n/u), `ext_reset_in = xresetn`, `slowest_sync_clk` = each generated clock -> `aresetn/nresetn/uresetn`. (`dcm_locked` is not wired.)
3. **Control crossbar**: one slave `axi_main` (AXI4, 512b data, 64b addr, ID 6b, on `xclk`) split into masters on `aclk`:
   - `axi_cnfg` : AXI4-Lite 64b
   - `axi_ctrl_i`: AXI4-Lite 64b, one per region
   - `axim_ctrl_i`: AXI4 256b (only if `EN_AVX`), one per region
   - Master numbering: M00 = cnfg; no-AVX: M(1+i) = ctrl_i; AVX: M(1+2i) = ctrl_i, M(2+2i) = axim_ctrl_i. `NUM_MI = 1 + n_reg (x2 if AVX)`.
   - US+: `axi_interconnect` 2.1 (`STRATEGY=2`, `S00_HAS_REGSLICE=4`, `S00_HAS_DATA_FIFO=2`, per-M regslice; xclk on S side, `aclk` on M side). Versal: `smartconnect` 1.0 (`NUM_CLKS=2`; `aclk`=xclk, `aclk1`=clk_wiz out1), no `arregion/awregion` pins (template omits them via `fpga_arch == 'ultrascale_plus'` guards).

### 2.2 Address map of `axi_main` (offsets within the shell BAR, driver `BAR_SHELL_CONFIG`)

Naming: throughout this doc "BAR2" = driver index `BAR_SHELL_CONFIG = 2` into `bar[CYT_BARS=3]`, i.e. the third Coyote BAR (the 64-bit PCIe BARs are 0, 2, 4 -> static regs, DMA core regs, shell bypass; see comment at [coyote_defs.h:126](../../../driver/include/coyote_defs.h)). So physically it is PCIe BAR4.

The static layer masks the bypass-BAR address to `AXI_BPSS_BAR_BITS = 28` bits (256 MB BAR; `lynx_pkg`, [static_top templates](../../../hw/templates/ultrascale_plus/static_top_tmplt.txt)), so these offsets are the PCIe BAR offsets.

| Segment | Offset | Range | Sink (AXI) | Driver const |
|---|---|---|---|---|
| `axi_cnfg` | `0x0000_0000` | `0x8000` (32 KB) | `shell_slave` (AXI4L) | `FPGA_SHELL_CNFG_OFFS/SIZE` |
| `axi_ctrl_i` | `0x0010_0000 + i*0x4_0000` (= `0x(10+4i)_0000`) | `0x4_0000` (256 KB) | `dynamic_top.s_axi_ctrl[i]` -> `dyn_crossbar_i` | `VFPGA_CTRL_OFFS`, `VFPGA_CTRL_SIZE` |
| `axim_ctrl_i` (EN_AVX) | `0x0100_0000 + i*0x4_0000` (= `0x(100+4i)_0000`) | `0x4_0000` | `dynamic_top.s_axim_ctrl[i]` -> `mmu_top` -> `cnfg_slave_avx_i` directly | `VFPGA_CTRL_CNFG_AVX_OFFS`, `..._AVX_SIZE` |

(Format strings in `cr_ctrl.tcl`: `0x000%02x0000` with `0x10+4i`; `0x00%03x0000` with `0x100+4i`.) Static-layer config (`static_slave`, probe, reconfig, ...) is a *different* BAR (`BAR_STAT_CONFIG`), see [../static/static_top.md](../static/static_top.md).

### 2.3 Per-region sub-split (`dynamic_crossbar`)

`dynamic_top` first registers `s_axi_ctrl[i]` (`axil_reg_array`, `N_REG_DYN_HOST_S0`), then `dynamic_crossbar` splits each 256 KB window into four 64 KB slave regions:

| Window offset (in `axi_ctrl_i`) | Crossbar master | Interface out | Consumer | Driver const |
|---|---|---|---|---|
| `+0x00000` | M00 | `m_axi_ctrl_lTlb[i]` | large-page TLB slave (`mmu_top`) | `VFPGA_CTRL_LTLB_OFFS = 0x0` |
| `+0x10000` | M01 | `m_axi_ctrl_sTlb[i]` | small-page TLB slave | `VFPGA_CTRL_STLB_OFFS = 0x10000` |
| `+0x20000` | M02 | `m_axi_ctrl_user[i]` | **user CSRs** -> (uclk crossing, slice, decouple) -> `design_user_wrapper_i.axi_ctrl` | `VFPGA_CTRL_USER_OFFS = 0x20000` |
| `+0x30000` | M03 | `m_axi_ctrl_cnfg[i]` | `cnfg_slave` (non-AVX), tied off if `EN_AVX` | `VFPGA_CTRL_CNFG_OFFS = 0x30000` |

Implementation: US+ = IP `dyn_crossbar_<i>` (`axi_crossbar` 2.1, `NUM_MI=4`, `ADDR_WIDTH=64`, `DATA_WIDTH=64`, `M0k_A00_BASE_ADDR = 0x(10+4i+k)_0000`, `M0k_A00_ADDR_WIDTH=16` = size of each decoded region; the IP does not strip the base, and the US+ template does not mask, so outputs keep the full address) from [shell_infrastructure.tcl](../../../scripts/ip_inst/shell_infrastructure.tcl). Versal = BD `dyn_crossbar_<i>` (SmartConnect, same bases, range `0x10000`) from [cr_xbar.tcl](../../../hw/bd/versal/cr_xbar.tcl); SmartConnect does not remap either, and the Versal template masks every output address with `& 64'hFFFF` ([versal/dynamic_xbar_tmplt.txt:81-160](../../../hw/templates/versal/dynamic_xbar_tmplt.txt)); its comment claims the US+ IP did this via `ADDR_WIDTH`, but the US+ template shows no masking, so treat the US+ unmasked behaviour as authoritative.
The packed `axi_xbar_*` buses in the template concatenate masters as [lTlb | sTlb | user | cnfg] = indices 0..3.

**User-CSR address -> BAR address:** user logic sees `axi_ctrl` (64-bit data) addresses starting at `0` on Versal but with the region base still present on US+ (`0x(12+4i)_0000 + offs*8`); user CSR slaves therefore must decode only the low address bits (the generated `user_wrapper`/HLS AXI-Lite slaves do). SW `setCSR(val, offs)` writes `ctrl_reg[offs]` (uint64 index) => BAR2 + `0x100000 + vfid*0x40000 + 0x20000 + offs*8`. The window is 64 KB, so `offs < 8192` (SW `CTRL_REGION_SIZE = 64*1024`).

---

## 3. Shell-level registers: `shell_slave` (`axi_cnfg`)

Source: [shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv) (`N_REGS=128`, 64-bit regs, byte offset = index*8; BAR2 + offset). Driver view: `struct cyt_shell_cnfg_regs` ([coyote_defs.h:548](../../../driver/include/coyote_defs.h)), mapped once in [pci_xdma.c:638](../../../driver/src/platform/pci_xdma.c) / [pci_qdma.c:816](../../../driver/src/platform/pci_qdma.c) as `bd_data->shell_cnfg` (`ioremap` of BAR2+0, 32 KB). Mostly read at probe; some written by driver.

| Idx (byte) | RTL name | Dir | Contents | Driver field / accessor |
|---|---|---|---|---|
| 0 (0x00) | `PROBE_REG` | R | `SHELL_PROBE` (`SHELL_PROBE` CMake, default 1044942). Comment says RW but no write path | `probe` -> `probe_shell` (`read_shell_config`) |
| 1 (0x08) | `N_CHAN_REG` | R | `N_CHAN` | `n_chan` -> `n_fpga_chan` |
| 2 (0x10) | `N_REGIONS_REG` | R | `N_REGIONS` | `n_regions` -> `n_fpga_reg` |
| 3 (0x18) | `CTRL_CNFG_REG` | R | [0] `AVX_FLOW`, [1] BPSS(=1), [2] TLBF(=0), [3] `WB_FLOW`, [7:4] `TLB_S_ORDER`, [11:8] `N_S_ASSOC`, [15:12] `TLB_L_ORDER`, [19:16] `N_L_ASSOC`, [25:20] `PG_S_BITS`, [31:26] `PG_L_BITS` | `ctrl_cnfg`; masks `EN_AVX_MASK`, `TLB_*_MASK` -> `stlb_meta/ltlb_meta`, `en_avx`, `en_wb`. Also forwarded to SW (`IOCTL_READ_SHELL_CONFIG` `tmp[1]`) |
| 4 (0x20) | `MEM_CNFG_REG` | R | [0] `STRM_FLOW`, [1] `MEM_FLOW`, [7:2] `N_STRM_AXI`, [13:8] `N_CARD_AXI`, [14] `BLOCK_MEM_IMPL_EN` (Versal HBM block impl) | `mem_cnfg` -> `en_strm`, `en_mem`, `n_host_axi`, `n_card_axi`, `en_block_mem` |
| 5 (0x28) | `PR_CNFG_REG` | R | `PR_FLOW` | `pr_cnfg` -> `en_pr` |
| 6 (0x30) | `SHELL_PBLOCK_CNFG_REG` | R | `SHELL_PBLOCK_EN` | `shell_pblock_cnfg` -> `en_shell_pblock` |
| 7 (0x38) | `RDMA_CNFG_REG` | R | [0] `RDMA_FLOW`, [1] `QSFP` | `rdma_cnfg` -> `en_rdma`, `qsfp` |
| 8 (0x40) | `TCP_CNFG_REG` | R | [0] `TCP_FLOW`, [1] `QSFP` | `tcp_cnfg` -> `en_tcp` |
| 9 (0x48) | `CTRL_DP_REG_SET` | W1S | [N_REGIONS-1:0] = `m_decouple` (to `dynamic_top.s_decouple_sw`); [32+:N_REGIONS] = `m_rst_pr` (left unconnected in `shell_top`). Not readable (no read case, returns 0) | `reconfig_dcpl_app_set` (written in `reconfig_ops.c:163` as `1 << vfid`) |
| 10 (0x50) | `CTRL_DP_REG_CLR` | W1C | clears bits of reg 9 | `reconfig_dcpl_app_clr` (`reconfig_ops.c:177`) |
| 32 (0x100) | `NET_IPADDR_REG` | W | [31:0] IP -> `m_set_ip_addr` (1-cycle `valid` per write) -> `network_top` | `net_ip`; sysfs `cyt_attr_ip`, `IOCTL_SET_IP_ADDRESS`; initial value from module param `ip_addr` (`coyote_setup.c:121`) |
| 33 (0x108) | `NET_MACADDR_REG` | W | [47:0] MAC -> `m_set_mac_addr` | `net_mac`; sysfs `cyt_attr_mac`, `IOCTL_SET_MAC_ADDRESS` |
| 34 (0x110) | `TCP_OFFS_REG` | RW | DDR/HBM offset for TCP buffers -> `m_ddr_offset_addr_tcp` | `tcp_offs` |
| 35 (0x118) | `RDMA_OFFS_REG` | RW | same for RDMA -> `m_ddr_offset_addr_rdma` | `rdma_offs` |
| 64/65/66 (0x200..) | `HDMA_STAT_0_{BPSS,CMPL,AXIS}` | R | `{c2h[31:0], h2c[31:0]}` req / completion / AXIS-beat counters of `dma_stats` ch0 (EN_STATS+EN_XCH_0) | `hdma_debug[0..2]`; sysfs `cyt_attr_hstats`, `IOCTL_SHELL_HDMA_STATS` |
| 67/68/69 | `HDMA_STAT_1_*` | R | same for ch1 (EN_XCH_1) | `hdma_debug[3..5]` |
| 96..104 (0x300..) | `NET_STAT_{PKG,ARP,ICMP,TCP,RDMA,IBV,DROP,SESS,DOWN}_REG` | R | `{tx,rx}` packet counters per protocol; DROP = `{retrans, psn_drop}`; SESS = TCP sessions [31:0]; DOWN = `axis_stream_down` [0] (EN_STATS+EN_NET) | `net_debug[0..8]`; sysfs `cyt_attr_nstats`, `IOCTL_SHELL_NET_STATS` |

Notes: `slv_reg` is reset to `'X` (only `CTRL_DP_REG_SET[63:32] <= 1'b1`, i.e. just bit 32 (`shell_slave.sv:163`), and RDMA/TCP offsets=0 are defined); the decouple bits rely on the driver (or synthesis don't-care) before first write. `N_HDMA_STAT_REGS`/`N_NET_STAT_REGS` in the driver are 12 / 10 slots (padded: `reserved_3[32-12]`, index 105 not implemented in RTL).

Aliasing: `shell_slave` decodes only `ADDR_MSB = log2(128)` index bits (1 KB) of the 32 KB `axi_cnfg` aperture, so offsets repeat every 0x400. Stats-ioctl mismatch: `IOCTL_SHELL_HDMA_STATS` copies `n_fpga_chan * N_HDMA_STAT_CH_REGS` words, and `N_HDMA_STAT_CH_REGS = 12/XDMA_MAX_NUM_CHANNELS(3) = 4`, but RTL/sysfs ([coyote_sysfs.c:138-159](../../../driver/src/coyote_sysfs.c)) use **3 regs per channel**, so ioctl channel 1 data is shifted by one register.

### 3.1 How to add a shell-level register
1. In `shell_slave.sv`: add `localparam integer FOO_REG = <free idx>` (keep idx < 128; 0..10, 32..35, 64..69, 96..104 are taken); add a write `case` arm (use `wstrb` byte loop, see `RDMA_OFFS_REG`) and/or a read arm in the `case (axi_araddr[ADDR_LSB+:ADDR_MSB])`; export through a new port.
2. Wire the new port in [shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt) `shell_slave inst_shell_slave (...)` (guard with `{% if cnfg.en_* %}` and mirror with `` `ifdef`` in the module).
3. Driver: add the field to `struct cyt_shell_cnfg_regs` **at the right index** (struct is `__packed` uint64 array; use `reserved_*` padding: idx 11..31 = `reserved_0[21]`, 36..63 = `reserved_2[28]`), then read/write via `bus_data->shell_cnfg->foo` (see `coyote_setup.c`, `coyote_sysfs.c`).
4. Rebuild shell *and* driver; bump `SHELL_PROBE` if the driver must reject old shells.

---

## 4. Per-vFPGA config registers: `cnfg_slave` vs `cnfg_slave_avx`

Both are instantiated once per region inside `mmu_top` (`inst_cnfg_slave`, `ID_REG=i`; [mmu_top.sv:259](../../../hw/hdl/mmu/mmu_top.sv)) and selected by `` `ifdef EN_AVX``. They implement the host's command/IRQ interface of a vFPGA (see [../services/mmu.md](../services/mmu.md) for the consumers of `m_host_sq`, page-fault/invalidate queues, offload/sync).

| | `cnfg_slave.sv` | `cnfg_slave_avx.sv` |
|---|---|---|
| Bus | AXI4-Lite, 64-bit, `BAR2 + 0x100000 + i*0x40000 + 0x30000` | AXI4 (burst-capable), 256-bit, `BAR2 + 0x1000000 + i*0x40000` |
| Register size / stride | 8 B (`N_REGS = 3*64`) | 32 B (`N_REGS = 2*64`, `ADDR_LSB=5`) |
| Posting a command | 4 x 64-bit writes, order `VADDR_WR(3)`, `CTRL_2(2)`, `VADDR_RD(1)`, then `CTRL(0)` (the write to reg 0 triggers `post`) | one 256-bit write to reg 0 = {vaddr_wr, ctrl_2, vaddr_rd, ctrl} (atomic) |
| Decode | low `ADDR_MSB` bits only; the rest of the 64 KB / 256 KB window aliases | same |

Same layout for the two on purpose: AVX reg `n` at byte `32n` overlays non-AVX regs at `8*(4n..4n+3)`, so the driver uses **one** `struct vfpga_cnfg_regs` for both (`vfpga_dev.cnfg_regs` is `ioremap`'d from the AVX or non-AVX region, [coyote_setup.c:397-402](../../../driver/src/coyote_setup.c)).

### 4.1 Register map (byte offsets within the cnfg window)

| Non-AVX idx -> byte | AVX reg -> byte | Name (RTL / driver struct) | R/W | Fields |
|---|---|---|---|---|
| 0 -> 0x00 | 0 -> 0x00 [63:0] | `CTRL_REG` / `ctrl` | W: post, R: used count | W: [4:0] opcode (`CTRL_OPCODE_OFFS=0`; [7:5] unused), [9:8] strm (CARD/HOST/RDMA/TCP), [15:10] pid (ctid), [19:16] dest, [20] last, [21] `ACTV` (start), [22] `CLR_STAT` (clear completion counter of `pid`), [59:32] len (`CTRL_LEN_OFFS=32`). R: [31:0] occupancy of the host command FIFO (`axis_data_fifo_req_256_used`, depth 32 in SW `CMD_FIFO_DEPTH`) |
| 1 -> 0x08 | 0 [127:64] | `VADDR_RD_REG` / `vaddr_rd` | RW | read-side virtual address |
| 2 -> 0x10 | 0 [191:128] | `CTRL_REG_2` / `ctrl_2` | RW | same fields as ctrl for the *write* channel of a combined (transfer) request; `ACTV` of both set = local read+write |
| 3 -> 0x18 | 0 [255:192] | `VADDR_WR_REG` / `vaddr_wr` | RW | write-side virtual address |
| 4 -> 0x20 | 1 -> 0x20 [63:0] | `ISR_REG` / `isr_ctrl,isr_meta_1..3` | RW | W [15:0]: b0 `CLR_IRQ_PENDING`, b1 `RESTART_RD`, b2 `RESTART_WR`, b3 `SUCCESS`, b4 `INVLDT`, b5 `INVLDT_LAST`, b6 `INVLDT_LOCK`. R: [31:16] IRQ type (`IRQ_OFFL=0, SYNC=1, INVLDT=2, PFAULT=3, NOTIFY=4`), [32] invalidate-ctrl ready, [33] pfault-ctrl ready, [49:48] stream of miss, [56] miss was write |
| 5 -> 0x28 | 1 [95:64], [127:96] | `ISR_HPID_PID_MISS_REG` / `isr_pid` | W (driver ack/invalidate args), R (latched miss info) | [31:0] pid (ctid) of miss / notify; [63:32] host pid (hpid, used for invalidation) |
| 6 -> 0x30 | 1 [191:128] | `ISR_VADDR_MISS_REG` / `isr_vaddr` | W (driver ack/invalidate args), R (latched miss info) | miss / invalidate virtual address |
| 7 -> 0x38 | 1 [223:192], [255:224] | `ISR_VAL_LEN_MISS_REG` / `isr_len` | W (driver ack/invalidate args), R (latched miss info) | [31:0] length of miss / invalidate range; [63:32] notification value (user IRQ) |
| 8..11 -> 0x40..0x58 | 2 -> 0x40 | `STAT_SENT_{LOCAL_RD,LOCAL_WR,REMOTE_RD,REMOTE_WR}` / `stat_sent[4]` | R | 32-bit counters of posted requests (AVX: 4 x 64-bit lanes of one reg) |
| 12..14 -> 0x60..0x70 | 3 -> 0x60 | `STAT_{INVLDT,PFAULT,NOTIFY}` / `stat_irq[4]` | R | IRQ counters |
| 16..19 -> 0x80..0x98 | 4 -> 0x80 | `WBACK_{LCL_RD,LCL_WR,RMT_RD,RMT_WR}_OFFS` / `wback[4]` | RW (EN_WB) | host physical base of writeback counter arrays (set by driver at load, `coyote_setup.c:482`) |
| 20 -> 0xA0 | 5 -> 0xA0 | `OFFL_CTRL_REG` / `offl_ctrl` | W: post, R: queue used | [0] `START`, [1] `CTL` (last), [2] `CLR`, [59:32] len (`MEM_LEN_OFFS=32`). (EN_MEM) |
| 21, 22 -> 0xA8, 0xB0 | 5 [127:64], [191:128] | `OFFL_HOST_OFFS`, `OFFL_CARD_OFFS` / `offl_host_offs`, `offl_card_offs` | RW | physical addresses for HOST->card offload. Driver struct also has `offl_len` (idx 23) and `sync_len` (idx 31): **no RTL register exists for them**; length lives in `*_CTRL[59:32]` |
| 24 -> 0xC0 | 6 -> 0xC0 | `OFFL_STAT_REG` / `offl_stat` | R | RTL increments a 32-bit completed-offload counter in `slv_reg[OFFL_STAT_REG][31:0]` (:478). AVX read returns the whole reg; **non-AVX read returns only `[0] <= slv_reg[..][MEM_DONE]`** (:854) and `MEM_DONE` is not declared anywhere (REG-03) |
| 28..30 -> 0xE0..0xF0 | 7 -> 0xE0 | `SYNC_CTRL/HOST/CARD` / `sync_*` | as offload | card->host sync (AVX read-back: REG-04) |
| 32 -> 0x100 | 8 -> 0x100 | `SYNC_STAT_REG` / `sync_stat` | R | sync counter (:486); read-back bugs: REG-03, REG-04 |
| 36 -> 0x120 | 9 -> 0x120 | `NET_ARP_REG` | W/R | [31:0] IP (byte-swapped) -> `m_arp_lookup_request`; R[0] = ready |
| 40..42 -> 0x140..0x150 | 10 -> 0x140 | `RDMA_CTX_REG_0..2` / `RDMA_CTX_REG` | W | QP context: qpn[23:0], rkey [63:32]; lpsn/rpsn; vaddr. Write of last word pulses `m_rdma_qp_interface.valid` |
| 44..46 -> 0x160..0x170 | 11 -> 0x160 | `RDMA_CONN_REG_0..2` / `RDMA_CONN_REG` | W | local qpn [15:0], remote qpn [39:16], udp port [55:40], remote IP (128b) |
| 48, 52, 56, 60 -> 0x180, 0x1A0, 0x1C0, 0x1E0 | 12..15 | `TCP_OPEN_PORT[_STAT]`, `TCP_OPEN_CONN[_STAT]` | RW | listen / connect commands + status (EN_TCP) |
| 64..127 -> 0x200 + pid*8 | 64.. -> 0x800 + pid*32 | `STAT_DMA_REG` (BRAM read mux) | R | per-**pid** completion counters (`ram_tp_nc` x2): non-AVX [31:0] local-read done, [63:32] local-write done; AVX 32-bit lanes {rd, wr, rdma-rd, rdma-wr}. `CLR_STAT` in ctrl zeroes one entry |
| 128..191 -> 0x400 + pid*8 | (lane 2,3 of the above) | RDMA completion counters (non-AVX only separate range) | R | [31:0] rdma-read-resp, [63:32] rdma-write acks |

SW mirrors: `enum class CnfgLegRegs` / `CnfgAvxRegs` in [cDefs.hpp:128-191](../../../sw/include/coyote/cDefs.hpp) (indices above; AVX `STAT_DMA_REG = 64`). `checkCompleted()` uses writeback memory if `en_wb` else reads these counters.

### 4.2 Request/IRQ flow inside cnfg_slave
- **Host command:** `CTRL` write with `ACTV` -> `local_post`/`remote_post` (remote iff `strm` is RDMA/TCP, `is_strm_local()`), builds `dreq_t{req_1 (rd), req_2 (wr)}` (`vfid=ID_REG`, `host=1`) -> command FIFO -> `m_host_sq` -> MMU. Completion `ack_t` comes back on `s_host_done_*` / `s_card_done_*` / `s_rdma_done`, increments the per-pid BRAM counter and (EN_WB) emits a `wback_t` {paddr = WBACK base + pid*4, value = counter} that rides `m_wback` to the static layer. End-to-end path: [../user/user_top.md#71-invoke---registers---hardware](../user/user_top.md#71-invoke---registers---hardware).
- **IRQ:** one `irq_pending` bit; priority order `offload > sync > invalidate > pfault-rd > pfault-wr > notify`. `usr_irq = irq_pending` (-> `m_usr_irq[i]` -> `shell_data_cc` -> static layer MSI-X vector `i`). Driver clears via `ISR.CLR_IRQ_PENDING`. QDMA (Versal) interrupt arbiter holds the bit until cleared ([qdma_interrupt_wrapper.sv](../../../hw/hdl/static/qdma_interrupt_wrapper.sv)).

---

## 5. Driver & software interaction

End-to-end linkage; deeper per-side detail in [../driver.md#shell-registers](../driver.md#shell-registers), [../driver.md#interrupt-flow](../driver.md#interrupt-flow), [../software.md#shell-registers](../software.md#shell-registers).

### 5.1 Forward path (SW -> HW)

| SW API | Mapping / syscall | Driver | BAR + offset | RTL |
|---|---|---|---|---|
| `cThread` ctor -> `mmapFpga()` ([cThread.cpp:292](../../../sw/src/cThread.cpp)) | `mmap` of `MMAP_CNFG_AVX<<12` (256 KB, `CNFG_AVX_REGION_SIZE`) if SW `EN_AVX` **and** `fcnfg.en_avx`, else `MMAP_CNFG<<12` (64 KB, `CNFG_REGION_SIZE`); also `MMAP_CTRL` (64 KB) and `MMAP_WB` (`4*64*4` B) | see next three rows | | |
| ... driver side | | `vfpga_dev_mmap()` ([vfpga_ops.c:641](../../../driver/src/vfpga/vfpga_ops.c)): `vm_pgoff` 3 = user CSR, 1 = cnfg, 2 = cnfg_avx, 0 = writeback (`dma_mmap_coherent`); `remap_pfn_range`, `pgprot_noncached` | | |
| ... BAR + offset | | | CTRL: `BAR2 + 0x100000 + vfid*0x40000 + 0x20000`, 64 KB; CNFG: `+0x30000`, 64 KB; CNFG_AVX: `BAR2 + 0x1000000 + vfid*0x40000`, 256 KB; bases computed in `coyote_setup.c:393-394` | |
| ... RTL consumer | | | | `dynamic_crossbar` M02/M03 or `axim_ctrl` -> `cnfg_slave[_avx]`; the SW pointer is stored as opaque `volatile void* cnfg_reg_avx` (typed via `avxRegs()` only `#ifdef EN_AVX`, [cThread.hpp:100-141](../../../sw/include/coyote/cThread.hpp)) so the `cThread` layout does not depend on `EN_AVX` |
| `cThread::setCSR(val, offs)` / `getCSR(offs)` ([cThread.cpp:770](../../../sw/src/cThread.cpp)) | plain store/load to `ctrl_reg[offs]` | none (direct MMIO) | user window `+0x20000 + offs*8` | vFPGA `axi_ctrl` (AXI4L) in [user wrapper](../user/user_top.md); 64-bit; address is `offs*8` on Versal, `0x(12+4i)_0000 + offs*8` on US+ (decode low bits only) |
| `postCmd(o3,o2,o1,o0)` <- `invoke()` ([cThread.cpp:254](../../../sw/src/cThread.cpp)) | AVX store or 4 stores to the cnfg window, FIFO throttle: see [../user/user_top.md#71-invoke---registers---hardware](../user/user_top.md#71-invoke---registers---hardware) | none | cnfg window, reg 0 | `cnfg_slave*`: `CTRL_REG` write -> `m_host_sq` |
| `checkCompleted(oper)` / `clearCompleted()` ([cThread.cpp:1011](../../../sw/src/cThread.cpp)) | reads `wback[]` (EN_WB) or the counter reg; clear writes `CTRL_CLR_STAT\|ctid<<10`: see [../user/user_top.md#71-invoke---registers---hardware](../user/user_top.md#71-invoke---registers---hardware) | writeback buffer allocated by driver, base written into `wback[4]` regs | wb: host DRAM; else cnfg `0x200+ctid*8` (non-AVX) / `0x800+ctid*32` (AVX) | per-pid `ram_tp_nc` counters; `wback` FIFO |
| `cThread::doArpLookup`, `cThread::writeQpContext` (writes QP context and connection regs) | MMIO to `NET_ARP_REG`, `RDMA_CTX_*`, `RDMA_CONN_*` | none | cnfg window | `m_arp_lookup_request`, `m_rdma_qp_interface`, `m_rdma_conn_interface` |
| `IOCTL_READ_SHELL_CONFIG` (ctor) | `ioctl` | `vfpga_ops.c:550`: packs `en_*`/`n_fpga_*` cached at probe by `read_shell_config()` into `tmp[0]`; only `ctrl_cnfg` (0x18, `tmp[1]`) is read live from the register ([vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c)) | BAR2 + 0x00..0x40 | `shell_slave` regs 1-8 |
| `IOCTL_SET/GET_IP_ADDRESS`, `..._MAC_...` | `ioctl` | `vfpga_ops.c:488-528` | BAR2 + 0x100 / 0x108 | `shell_slave` -> `network_top` |
| mapped-memory ioctls (`IOCTL_MAP_USER_MEM`, offload/sync) | `ioctl` | `vfpga_gup.c`, `vfpga_hw.c` (`create_tlb_mapping` -> `fpga_lTlb/fpga_sTlb` = `+0x0` / `+0x10000`; `offl_*`, `sync_*` regs) | cnfg + TLB windows | `tlb_slave_axil`, `cnfg_slave` offload/sync queues (see [../services/mmu.md](../services/mmu.md), [../services/memory.md](../services/memory.md)) |
| Reconfiguration (`cRcnfg`) | `IOCTL_RECONFIGURE_APP` | `reconfig_ops.c:163/177` set/clear decouple | BAR2 + 0x48/0x50 | `shell_slave` `m_decouple` -> `dcpl_select` -> decouplers ([../static/reconfig.md](../static/reconfig.md)) |

### 5.2 Reverse path (HW -> SW)

1. HW event (page fault, TLB invalidate done, offload/sync done, user `notify`) -> `cnfg_slave*` latches `ISR_*` regs, sets `irq_pending` -> `usr_irq[i]` -> `dynamic_top.m_usr_irq` -> `shell_data_cc` (CDC aclk->xclk, `N_REG_SHELL_S0` regs) -> static layer -> MSI-X vector `i` (vector 15 = reconfig).
2. `vfpga_isr()` ([vfpga_isr.c:24](../../../driver/src/vfpga/vfpga_isr.c)) reads `cnfg_regs->isr_meta_1` (type, `read_irq_type`), then `isr_pid/isr_vaddr/isr_len/isr_meta_3` (`read_irq_pfault/notify`); offload/sync/invalidate set a waitqueue flag; page fault / notify are deferred to workqueues (`vfpga_pfault_handler` maps pages and calls `create_tlb_mapping`, then `restart_mmu()` = `isr_pid=ctid; isr_ctrl=PF_{RD,WR}_SUCCESS` or `drop_irq_pfault`; `vfpga_notify_handler` signals the eventfd registered with `IOCTL_REGISTER_EVENTFD`, SW `eventHandler` thread calls the user `uisr`).
3. ISR always ends with `clear_irq()` -> `isr_ctrl = FPGA_CNFG_CTRL_IRQ_CLR_PENDING (0x1)`.
4. Completions: no IRQ; vFPGA data movement ack -> counter / writeback (`m_wback` -> static host DMA PR/WB channel -> host DRAM page mapped by `MMAP_WB`); SW polls `checkCompleted`.
5. Stats/config reads: sysfs files (`coyote_sysfs.c`: `cyt_attr_ip/mac/nstats/hstats/cnfg/...`) and ioctls read `shell_cnfg->*` directly.

### 5.3 Register -> accessor table

| Register | RTL source | Driver accessor | SW accessor |
|---|---|---|---|
| shell probe/config (idx 0-8) | `shell_slave.sv` | `read_shell_config()` (`coyote_setup.c:28`) | `IOCTL_READ_SHELL_CONFIG` -> `FpgaCnfg::parseCnfg/parseCtrlReg` ([cDefs.hpp:443](../../../sw/include/coyote/cDefs.hpp)) |
| `CTRL_DP_REG_SET/CLR` | `shell_slave.sv:358` (`assign m_decouple = slv_reg[CTRL_DP_REG_SET][0+:N_REGIONS]`) | `shell_cnfg->reconfig_dcpl_app_set/clr` | via `cRcnfg` ioctls |
| IP/MAC | `shell_slave.sv` | sysfs / ioctls / module params `ip_addr`,`mac_addr` | `cThread` ctor (`IOCTL_GET_IP_ADDRESS`) for RDMA QP setup |
| `CTRL/VADDR_*/CTRL_2` | `cnfg_slave*.sv` | (driver does not post commands; only offload/sync) | `postCmd` |
| `ISR_*` | `cnfg_slave*.sv` | `vfpga_hw.c` helpers (`read_irq_*`, `restart_mmu`, `drop_irq_pfault`, `invalidate_tlb_entry`, `change_tlb_lock`, `clear_irq`) | - |
| `OFFL_*`, `SYNC_*` | `cnfg_slave*.sv` | `vfpga_hw.c:~136-200` (`offload/sync` loops poll `*_ctrl` occupancy) | via `IOCTL_OFFLOAD_REQ/SYNC_REQ` |
| `STAT_*` counters | `cnfg_slave*.sv` | - | `cThread::printDebug` (cThread.cpp ~1411) |
| `WBACK_*` | `cnfg_slave*.sv` | written at driver load per vFPGA (`coyote_setup.c:482`, `wb_phys_addr + j*N_CTID_MAX*4`) | none (reads `wback` mapping) |
| completion counters | `cnfg_slave*.sv` BRAM | - | `checkCompleted/clearCompleted` |
| user CSRs | user wrapper `axi_ctrl` | - | `setCSR/getCSR` |

---

## 6. Clock domains and CDC

| Clock | Source | Freq knob | Users |
|---|---|---|---|
| `xclk`/`xresetn` | static layer (US+: XDMA 250 MHz fixed; Versal: `SCLK_F`, V80 shell/app flows force 333 MHz) | `SCLK_F` (Versal only) | `axi_main`, `shell_data_cc` static side, interconnect S side, Versal debug hub |
| `aclk`/`aresetn` | `clk_wiz` out1 | `ACLK_F` (250 default) | shell logic: `shell_slave`, `cnfg_slave*`, `dynamic_top`, `mmu_top`, memory stack, network control; `axi_cnfg/ctrl/axim` |
| `nclk`/`nresetn` | `clk_wiz` out2 | `NCLK_F`, gated by `EN_NCLK` (`CROSS_EARLY`) | network stack core (CMAC side); [../services/network.md](../services/network.md) |
| `uclk`/`uresetn` | `clk_wiz` out3 | `UCLK_F`, gated by `EN_UCLK` | vFPGA user logic only (`user_wrapper` clocked by `uclk` if `EN_UCLK` else `aclk`) |
| `hclk` (HBM) | US+: `IBUFDS0_inst` from the board `hbm_clk_clk_p/n` pins, `hresetn = lckresetn` ([shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt), declared at :414, driven ~1322-1330) into `design_hbm`; Versal: `clk_gen_hbm` from `aclk` | `HCLK_F`: u55c/u280 450 MHz, u200/u250 1 (no HBM), v80 400 ([FindCoyoteHW.cmake:368,387,406,425,444](../../../cmake/FindCoyoteHW.cmake)); Versal recommend `2*ACLK_F` | HBM AXI ports (US+: CDC inside `design_hbm`; Versal: width converter 512->256 + CDC `hbm_cc_dwc_i` in shell_top) |
| `dclk` | static (US+, 100 MHz) / Versal: `xclk` | - | debug bridge, BSCAN, network init clock |

CDC points:
- **xclk <-> aclk**: only `shell_data_cc` (`axis_ccross`, `dma_req_ccross`, `meta_ccross` (wback), `logic_ccross` (15-bit usr_irq)), bracketed by `N_REG_SHELL_S0` (xclk side) and `N_REG_SHELL_S1` (aclk side) register slices. The control bus crossing is inside `design_ctrl` (interconnect/SmartConnect with different S/M clocks). Naming in `shell_data_cc` is crossed: `inst_s*_axis_dyn_out` is the *input* direction instance and vice versa.
- **aclk <-> uclk** (`EN_UCLK`): in `dynamic_top`: `axis_ccross` for host/card/RDMA/TCP streams, `axil_ccross` for user CSR, `meta_ccross` for `notify`, `host_sq`, `bpss_{rd,wr}_{sq,cq}` (user<->MMU), `tcp_ccross_ul`, RDMA cross, `xpm_cdc_single` (4 FF) for `decouple` -> `decouple_uclk`. Without `EN_UCLK` these are plain wire assigns (`META_ASSIGN`, `AXIL_ASSIGN`) and `uclk` is unused by the logic.
- **aclk <-> nclk**: inside `network_top` (`CROSS_EARLY=EN_NCLK`, `CROSS_LATE=1`).
- User constraint file ([user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt)): `create_clock -period uclk_p [get_ports aclk]` of the user wrapper (`uclk_p` falls back to `aclk` period when `EN_UCLK=0`, [write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in)); `CLOCK_BUFFER_TYPE NONE` on `aclk` when `EN_PR` (Vivado AR 73360: no clock buffers across PR boundaries); US+ also constrains `dclk` 10 ns and wires the user debug core `inst_debug_bridge_user` to it.

---

## 7. UltraScale+ vs Versal

Summary table: [../coyote_top.md#ultrascale-vs-versal-summary](../coyote_top.md#ultrascale-vs-versal-summary). Shell-specific details:

| Aspect | UltraScale+ | Versal |
|---|---|---|
| Shell BD interconnect | `axi_interconnect` 2.1 + regslices, address segments with `create_bd_addr_seg`; `arregion/awregion` used | `smartconnect` 1.0, `NUM_CLKS=2`; no region signals (template ifdefs them out); `ADVANCED_PROPERTIES` disable low-area mode (wrap/narrow bursts supported on S00) |
| Clock generator | `clk_wiz` 6.0 (MMCM) | `clk_wizard` 1.0 (BUFG outputs), `PRIM_IN_FREQ = SCLK_F`; XDC `shell_clk` generated (`create_clock xclk`, `CLOCK_BUFFER_TYPE NONE`, placeholder GT refclk constraints for DCMAC) |
| Per-region crossbar | `dyn_crossbar_<i>` `axi_crossbar` IP; `M0k_A00_ADDR_WIDTH=16` only sizes the decoded region, it does **not** remap or mask: [template](../../../hw/templates/ultrascale_plus/dynamic_xbar_tmplt.txt) passes `araddr/awaddr` through unmasked, so slaves see the full BAR offset (e.g. `0x12_0000+offs` for region 0 user CSRs) and must decode only low bits | SmartConnect BD `dyn_crossbar_<i>`; template masks every output address with `& 64'hFFFF`, so slaves see offsets from 0 |
| `axi_main` source | XDMA bypass AXI | CPM bridge; interrupts via `qdma_interrupt_wrapper`; QDMA queues > `3*N_OUTSTANDING` constraint |
| Debug | `debug_bridge_dynamic` (BSCAN demux) in shell, per-vFPGA `S_BSCAN_*`, `dclk` | `axi_dbg_hub` in `design_ctrl` when `EN_PR=0` (`axi_debug_hub` port on shell_ctrl, fixed address `0x0202_4000_0000`, 2 MB); when `EN_PR=1` the hub AXI port is forwarded through `dynamic_top` into each user wrapper instead |
| HBM | `design_hbm` BD (+RAMA IP striping); `hclk` from the HBM reference pins via `IBUFDS`, `hresetn = lckresetn`, `hclk`/`hresetn`/`dclk` into `design_hbm` | `clk_gen_hbm` + per-channel `hbm_cc_dwc` (dwc 512->256 + CDC) + `design_hbm` NoC; `BLOCK_MEM_IMPL_EN` in `MEM_CNFG_REG[14]` |
| Driver constants | `N_MEM_BLOCKS=1`, `MEM_START=256 MB` | `N_MEM_BLOCKS=64`, `MEM_START=256 GB` (`PLATFORM_VERSAL` in `coyote_defs.h`) |

---

## 8. Gotchas / invariants

- **SW/HW AVX mismatch hangs the bus.** In AVX shells `axi_ctrl_cnfg` is tied off with `AXIL_TIE_OFF_S` (`awready=arready=1`, `wready=0`, `bvalid=rvalid=0`): software built without `EN_AVX` (`sw/CMakeLists.txt` option) maps `MMAP_CNFG` and any access to `+0x30000` never completes. Conversely, SW built with `EN_AVX` against a non-AVX shell correctly falls back (runtime `fcnfg.en_avx`). Build HW and SW with the same `EN_AVX`.
- `EN_AVX`: lTLB/sTLB/user CSR still go through `axi_ctrl` (AXI4L); *only* cnfg moves to `axim_ctrl`.
- Address pairing is rigid: `cr_ctrl.tcl` segment offsets, `dyn_crossbar` base addresses (`shell_infrastructure.tcl`, `cr_xbar.tcl`) and `coyote_defs.h` (`VFPGA_CTRL_OFFS=0x100000`, `VFPGA_CTRL_SIZE=256K`, `*_USER_OFFS=0x20000`, `*_CNFG_OFFS=0x30000`, `*_AVX_OFFS=0x1000000`) must change together; `0x10 + 4*i` / `0x100 + 4*i` formulas are duplicated in three Tcl places.
- Region count limits: `N_REGIONS <= 15` (CMake), `MAX_N_REGIONS=16` in driver; BAR window max index must stay < 256 MB (`AXI_BPSS_BAR_BITS=28`) -> `0x100_0000 + 15*0x40000` fits.
- `CTRL_REG` write posts a request **on every write** (`post <= 1'b1`), also for clear-stat; the non-AVX flow depends on writing reg 0 last.
- Completion counters are per **pid** (6 bits, `N_CTID_MAX=64`); wrap/clear with `CTRL_CLR_STAT`. RDMA counters (non-AVX 0x400 range) and `STAT_RDMA_REG` (128) in SW.
- `N_SCHAN` (2) vs `N_CHAN`: `shell_split_data` is instantiated only for `N_CHAN > N_SCHAN`, which does not occur today; keep it as the guarded branch when adding shell channels (also needs a mux on the static side).
- `m_decouple` and `m_rst_pr`: only decouple is consumed (`dcpl_select`, default `N_STAGES=1` register, then `decouple_uclk` CDC). Decouple gates `axis/dma/axil/meta` interfaces of the user wrapper; the AXI `ctrl` window of the *user CSRs* is decoupled but `cnfg_slave` and TLB windows are not.
- Known defects in this area: [known_issues.md](../known_issues.md) (`REG-*`, `REC-01`, `REC-03`).
- The published Coyote v1 thesis (ch.4), OSDI'20 paper and Coyote v2 paper (external) describe the older Coyote v1 layout (per-vFPGA `ctrl` with `cnfg`/`ctrl` regs in a single slave, "static" owning TLB); this file follows the code.

---

## 9. How to modify / extend

**Add a per-vFPGA config register**
1. Pick the next free index in both `cnfg_slave.sv` (64-bit idx) and `cnfg_slave_avx.sv` (32-byte reg index; sub-fields by bit offset) so the byte offsets keep overlaying (non-AVX idx = 4 x AVX reg + lane). Add `localparam`, write/read arms.
2. Add the field to `struct vfpga_cnfg_regs` ([coyote_defs.h:579](../../../driver/include/coyote_defs.h)) at that byte offset (comment says "Rest is user space" after `sync_stat`; use `rsrvd_*` padding).
3. Extend `CnfgLegRegs` / `CnfgAvxRegs` in [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp) and use in `cThread.cpp` (both branches).
4. Remember the decode only uses low bits: stay within 2 KB (non-AVX) / 4 KB (AVX) and keep clear of completion-counter ranges (reg 64+).

**Add a user CSR / find its BAR address:** user CSRs need no shell change. User logic reads `axi_ctrl` (see [../user/user_top.md](../user/user_top.md)); host address = BAR2 `0x100000 + vfid*0x40000 + 0x20000 + 8*offs`; SW: `setCSR(val, offs)`.

**Add another AXI-Lite window per region:** extend `NUM_MI` and bases in `shell_infrastructure.tcl` (US+) and `cr_xbar.tcl` (Versal), add an output in [both dynamic_xbar templates](../../../hw/templates/ultrascale_plus/dynamic_xbar_tmplt.txt) (widen `axi_xbar_*` packed vectors and the `& 64'hFFFF` masks on Versal), route through `dynamic_top`, and add a driver offset. Mind the 256 KB per-region limit in `cr_ctrl.tcl`.

**Add a third `axi_ctrl`-style master or change region window size:** edit address segments in both `cr_ctrl.tcl` files, `shell_top_tmplt` / `dynamic_top_tmplt` ports, and `VFPGA_CTRL_*` in `coyote_defs.h`.

**Add a new shell service (e.g., another stream/channel):** new Jinja-guarded block in `shell_top_tmplt.txt`, new `dynamic_top` port + slicing/CDC pattern (copy the `en_strm` host block), new `` `define`` in `lynx_pkg_tmplt.txt`, new CMake var in `FindCoyoteHW.cmake` + `scripts/base.tcl.in` (`set cfg(...)`), and a status bit in `MEM_CNFG_REG`/`CTRL_CNFG_REG` if the driver/SW must discover it.

**Debug tips:** the shell-flow generated sources are in `<build>/<project>_shell/hdl/` (`shell_top.sv`, `dynamic_top.sv`, `lynx_pkg.sv`); check there which `` `EN_*`` and `cnfg` branches were taken. Driver logs the decoded shell config at insmod (`dbg_info` in `read_shell_config`); `sysfs` `cyt_attr_cnfg` dumps it.
