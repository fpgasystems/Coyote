# Static layer (static_top)

**Purpose:** The static layer is the part of Coyote that is never reconfigured at run time. It owns the PCIe link and host DMA core, the static control/status registers (`static_slave`), the PR (partial reconfiguration) datapath, decoupling, and the debug bridge. It exposes a small, platform-independent interface (`m_axi_main`, per-channel AXI-Stream + `dmaIntf`, `s_usr_irq`, `s_wback`) to the shell.
Everything platform-specific (XDMA on UltraScale+, CIPS/QDMA/NoC on Versal) is hidden behind this interface.

## Key files

| Path | Role |
|---|---|
| [static_top_tmplt.txt (US+)](../../../hw/templates/ultrascale_plus/static_top_tmplt.txt) | Jinja template of `static_top` for U55C/U280/U250/U200 (XDMA, ICAPE3) |
| [static_top_tmplt.txt (Versal)](../../../hw/templates/versal/static_top_tmplt.txt) | Jinja template of `static_top` for V80 (QDMA, `pr_ctrl_versal`) |
| [cr_pci.tcl (US+)](../../../hw/bd/ultrascale_plus/cr_pci.tcl) | Block design `design_static`: XDMA, clk_wiz, reset controllers, address segments |
| [cr_pci.tcl (Versal)](../../../hw/bd/versal/cr_pci.tcl) | Block design `design_static`: CIPS (CPM5 QDMA), AXI NoC, smartconnects, clk_wizard |
| [static_slave.sv](../../../hw/hdl/static/static_slave.sv) | Static AXI4-Lite register file (PR control, DMA stats, QDMA prefetch tag) |
| [dcpl_select_static.sv](../../../hw/hdl/static/dcpl_select_static.sv) | Selects decouple/eos_resetn source: SW register vs VIO |
| [dcpl_static.sv](../../../hw/hdl/static/dcpl_static.sv) | Register slicing + decoupling of all static<->shell interfaces; instantiates `wback_dma` |
| [wback_dma.sv](../../../hw/hdl/static/wback_dma.sv) | Writeback request -> 4-byte DMA write on the PR/WB channel |
| [xdma_wrapper.sv](../../../hw/hdl/static/xdma_wrapper.sv) | `dmaIntf` -> XDMA descriptor-bypass (US+) |
| [qdma_rd_wrapper.sv](../../../hw/hdl/static/qdma_rd_wrapper.sv), [qdma_wr_wrapper.sv](../../../hw/hdl/static/qdma_wr_wrapper.sv), [qdma_reg_slice.sv](../../../hw/hdl/static/qdma_reg_slice.sv), [qdma_interrupt_wrapper.sv](../../../hw/hdl/static/qdma_interrupt_wrapper.sv) | `dmaIntf` -> QDMA streaming bypass, IRQ serializer (Versal) |
| [pr_ctrl_versal.sv](../../../hw/hdl/static/pr_ctrl_versal.sv) | Versal PR controller (QDMA MM descriptor to PMC SBI) |
| [pr_cmplt.sv](../../../hw/hdl/static/common/pr/pr_cmplt.sv) | US+ PR completion (`eos`) after `eos_time` pclk cycles |
| [pr_stats.sv](../../../hw/hdl/static/common/stats/pr_stats.sv) | Counters on the PR/WB channel (`hdma_stat_t`) |
| [common/decouplers/](../../../hw/hdl/static/common/decouplers/), [common/regs/](../../../hw/hdl/static/common/regs/) | `*_decoupler_static`, `*_reg_array_static` building blocks |
| [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | `lynxTypes` package: `N_HCHAN`, `N_SCHAN`, `STAT_PROBE`, `QDMA_*_QUEUE_*`, `dma_req_t`, `hdma_stat_t` |
| [cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt) | Instantiates `static_top` (`inst_static`) next to `shell_top` (`inst_shell`) |
| [pci_infrastructure.tcl](../../../scripts/ip_inst/pci_infrastructure.tcl) | IPs used by the static layer (FIFOs, PR converters/slices, debug bridge/hub, VIOs, `qdma_ecc`) |
| [cr_static.tcl.in](../../../scripts/cr_prjcts/cr_static.tcl.in), [synth_static.tcl.in](../../../scripts/synth/synth_static.tcl.in) | Static project creation / synthesis |
| [hw/checkpoints/](../../../hw/checkpoints/) | Pre-routed, locked static checkpoints (see "Routed-locked checkpoints") |
| [pci_xdma.c](../../../driver/src/platform/pci_xdma.c), [pci_qdma.c](../../../driver/src/platform/pci_qdma.c) | Driver PCI probe, BAR mapping, IRQ setup (see [host_dma.md](host_dma.md)) |
| [coyote_defs.h](../../../driver/include/coyote_defs.h) | `struct cyt_stat_cnfg_regs`, BAR indices, IOCTL numbers |

**Related:** [host_dma.md](host_dma.md) (DMA wrappers, IRQs, driver PCI code) | [reconfig.md](reconfig.md) (PR / shell reconfiguration) | [../shell/shell_top.md](../shell/shell_top.md) (the other side of the interface) | [../coyote_top.md](../coyote_top.md) | [../build/build_top.md](../build/build_top.md) | [../build/constraints.md](../build/constraints.md) | [../driver.md](../driver.md) | [../software.md](../software.md)

## 1. What the static layer does

- Terminates PCIe and the host DMA IP (XDMA or QDMA) and converts it to Coyote's neutral interfaces:
  - `m_axi_main` (AXI4, 512-bit): CPU MMIO to the shell (BAR for shell registers, 256 MB window).
  - `N_SCHAN` pairs of `m_axis_dyn_out` / `s_axis_dyn_in` (512-bit AXI-Stream) and `s_dma_rd_req` / `s_dma_wr_req` (`dmaIntf`): host <-> shell data channels.
  - `s_wback` (`metaIntf`, `wback_t`): shell-issued write-back of completion counters to host memory.
  - `s_usr_irq[14:0]`: one interrupt line per vFPGA (shell `cnfg_slave.irq_pending`), plus bit 15 = PR-complete generated inside the static layer.
- Hosts `static_slave` (AXI4-Lite BAR) which the driver uses to start PR, decouple the shell, pulse the shell reset, read DMA stats and (Versal) hand QDMA prefetch tags to the hardware.
- Implements the PR datapath: bitstream arrives as a normal H2C DMA on the extra "PR/WB" channel and goes to ICAPE3 (US+) or the PMC (Versal). See [reconfig.md](reconfig.md).
- Provides decoupling (`dcpl_static`) so the shell can be reconfigured while PCIe/DMA stay alive.
- Provides the debug bridge/hub (US+: BSCAN chain to the shell; Versal: AXI debug-hub aperture via NoC).

## 2. Top-level structure

`static_top` is generated from a per-architecture template (selected by `FPGA_ARCH`, see [hw/templates/README.md](../../../hw/templates/README.md)). The ports differ:

| Port group | US+ ([template](../../../hw/templates/ultrascale_plus/static_top_tmplt.txt)) | Versal ([template](../../../hw/templates/versal/static_top_tmplt.txt)) |
|---|---|---|
| Clocks/resets out | `xclk, xresetn, dclk, dresetn` | `xclk, xresetn` only |
| PCIe pins | `pcie_clk_clk_{n,p}`, `pcie_x16_{rx,tx}{n,p}[15:0]` | `pcie_clk_clk_{n,p}`, `pcie_{rx,tx}{n,p}[PCIE_GT_BITS-1:0]` (16 for Gen4x16, 8 for Gen5x8) |
| Extra to shell | `dyn_bscan_*` (BSCAN master to shell debug) | `m_axi_debug_hub` (AXI4 128-bit, to shell's debug hub IP) |
| Common | `s_usr_irq[14:0]`, `m_axi_main`, `m_axis_dyn_out[N_SCHAN]`, `s_axis_dyn_in[N_SCHAN]`, `s_dma_rd_req[N_SCHAN]`, `s_dma_wr_req[N_SCHAN]`, `s_wback` | same |

Internal pipeline (both architectures), channel index `N_SCHAN` = the extra PR/WB channel:

```
 host <-PCIe-> [XDMA | CIPS QDMA] <- design_static (BD) ->
    axi_cnfg  (AXI4-Lite) -> static_slave (static regs)
    axi_main  (AXI4 512b) -> addr trim to 28 bits -> dcpl_static -> m_axi_main -> shell
    H2C/C2H streams + descriptor bypass ->
        ch 0..N_SCHAN-1 : dcpl_static <-> shell (s_dma_*_req / axis_dyn_*)
        ch N_SCHAN      : PR (read, static_slave -> DMA) and writeback (write, wback_dma)
```

- `N_HCHAN = 3` (fixed in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), "streaming data, migration, PR&WB"), `N_SCHAN = N_HCHAN-1 = 2`. Shell channel 0 = host streaming (`STRM_CHAN`) if `EN_STRM`, next = card/migration (`CARD_CHAN`) if `EN_MEM`; unused shell channels are tied off in the shell.
- Static-internal channel arrays are `[N_HCHAN]` (`axis_dyn_in_int`, `dma_rd_req_int`, ...); the shell-visible arrays are `[0+:N_SCHAN]`.
- US+: each channel `i<N_HCHAN` gets an `xdma_wrapper` (`dmaIntf` -> `xdmaIntf` -> BD `dsc_bypass_{c2h,h2c}_i`). Versal: one `qdma_rd_wrapper` (N_SCHAN channels), one `qdma_wr_wrapper` (N_HCHAN channels), one `qdma_reg_slice`, one `qdma_interrupt_wrapper`.
- `static_slave.m_pr_dma_rd_req` drives `dma_rd_req_int[N_SCHAN]` directly (PR is not decoupled).
- `dcpl_static` maps `s_wback` -> `wback_dma` -> `dma_wr_req_int[N_SCHAN]` + `axis_dyn_in_int[N_SCHAN]` (32-bit value padded to 512-bit, `tkeep` = 4 bytes).
- Stats: `pr_stats` counts requests/completions/beats on channel `N_SCHAN` only, feeding `static_slave.s_hdma_stats` (so "hdma stats" in the static register file are PR/WB-channel stats; shell-side channel stats live in the shell register file).

### Sub-components

| Module | Notes |
|---|---|
| `dcpl_select_static` ([src](../../../hw/hdl/static/dcpl_select_static.sv)) | `decouple = pr_slct ? decouple_vio : decouple_sw`; same for `eos_resetn`. `N_STAGES` default 1 (not overridden in templates); with the selection register it adds ~2-3 cycles of latency to `decouple`/`eos_resetn`. Versal ties `pr_slct=0`, `*_vio` inactive (no VIO). |
| `dcpl_static` ([src](../../../hw/hdl/static/dcpl_static.sv)) | Per shell-facing interface: register slices on the static side (`N_STAGES_0 = N_REG_STAT_S0`, default 2) then a decoupler at the shell boundary (valid/ready forced low when `decouple`). The `decouple` flag is combinational at stage 0 and then passes `N_REG_STA_DCPL-1` registers (default `NR_SD`=3 -> 2 flops). `N_STAGES_1` is declared but unused. Module defaults are `N_STAGES_0=3`; the templates override it from CMake `NR_ST_S0` (default 2). |
| `*_decoupler_static` ([dir](../../../hw/hdl/static/common/decouplers/)) | `axis`, `axi`, `dma`, `meta`, `logic`: gate `valid`/`ready` (and `rsp`) when decoupled; `logic_decoupler_static` gates the IRQ vector. |
| `wback_dma` ([src](../../../hw/hdl/static/wback_dma.sv)) | Splits `wback_t {paddr, value}` into a 4-byte DMA write request (`last=1`, `len=4`) + a 32-bit data beat, with two small FIFOs (`axis_data_fifo_wb_dma_static` depth 16, `axis_data_fifo_wb_data_static` depth 16) and `N_REG_DYN_HOST_S0` slices. |
| `pr_stats` ([src](../../../hw/hdl/static/common/stats/pr_stats.sv)) | 6x32-bit counters: `bpss_{h2c,c2h}_{req,cmpl,axis}_counter`, delayed by `HDMA_STATS_DELAY` (`NR_HST`=4). Versal: `axis_rd` tied 0 (PR data never crosses fabric), `dma_rd_req/done` from `pr_ctrl_versal`. |
| Debug (US+) | `debug_bridge_static` (BSCAN: master 0 -> shell via `dyn_bscan_*`, master 1 -> `debug_hub_static` on `dclk`); `vio_static_decoupling` (probe_in: `decouple`, `eos_resetn`; probe_out: `pr_slct`, `decouple_vio`, `eos_resetn_vio` init 1); `vio_static_xstats` (6x32-bit probes of `hdma_stats_stat`). |
| Debug (Versal) | No VIO/bridge in static. AXI debug-hub aperture `0x202_4000_0000` (2 MB) reached through the NoC from the PMC (`PMC_NOC_AXI_0`), exported as `m_axi_debug_hub` to the shell. |

## 3. UltraScale+ vs Versal

Cross-layer summary: [UltraScale+ vs Versal](../coyote_top.md#ultrascale-vs-versal-summary). Static-layer details:

| Aspect | UltraScale+ | Versal |
|---|---|---|
| Host DMA IP | XDMA 4.1/4.2 (AXI-Stream mode, descriptor bypass for all `N_HCHAN` channels, `xdma_num_usr_irq=16`, MSI-X) | CIPS CPM5 QDMA (`versal_cips 3.4`): AXI-MM + AXI-Stream, descriptor bypass (`DSC_BYPASS_RD/WR`) |
| PCI BARs | AXI-Lite BAR, XDMA register BAR, 256 MB bypass BAR | BAR0 AXI-Bridge-Master, BAR2 DMA regs, BAR4 bridge (256 MB) -> `axi_main` (BAR4 type not set explicitly in `cr_pci.tcl`) |
| PCIe | Gen3 x16, `PCIE4C_X1Y1` on u55c/u280 | `PCIE_GEN=4` -> CPM PCIE0 x16 (16 GT/s); `PCIE_GEN=5` -> CPM PCIE1 x8 (32 GT/s). Build switches in `cr_pci.tcl` |
| `xclk` source | XDMA `axi_aclk` | `clk_wizard` from CIPS `pl0_ref_clk` (frequency `SCLK_F`, see [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), `SCLK_F`). Also drives CIPS `dma{0,1}_intrfc_clk`. |
| Other clocks | `pclk` 200 MHz (PR/ICAP), `dclk` 100 MHz (debug); both from `clk_wiz_0` (`clk_out1`/`clk_out2`), input = XDMA `ext_ch_gt_drpclk` | none (NoC/CPM clocks internal to the BD) |
| `sresetn` | `proc_sys_reset_1` on XDMA `axi_aresetn` | `proc_sys_reset_s` on CPM `dma{0,1}_axi_aresetn` |
| `xresetn` | `proc_sys_reset_x`, `ext_reset_in = AND(1, eos_resetn)` (i.e. only `eos_resetn` resets the shell domain) | `proc_sys_reset_x`, `ext_reset_in = eos_resetn` |
| Control BAR path | XDMA `M_AXI_LITE` -> `axi_cnfg` (1 MB seg @0); `M_AXI_BYPASS` -> `axi_main` (256 MB seg @0) | CPM NoC: BAR0 -> `axi_cnfg`, BAR4 -> `axi_main`, via `axi_noc_0` + `smartconnect_{0,1}` (apertures in the summary and section 5) |
| PR path | PR bitstream = H2C stream ch `N_SCHAN` -> `pr_clock_converter` -> `pr_dwidth_converter` (64B->4B) -> `N_REG_PR` x `pr_reg_slice` -> `ICAPE3`; `pr_cmplt` generates `eos` | `pr_ctrl_versal` issues QDMA MM H2C descriptors (queue 0) to PMC `slave_boot_stream` `0x1_0210_0000`; CIPS `eos` -> `eos_pmc` -> `eos_ctrl` |
| Interrupts | `usr_irq[15:0]` straight to XDMA `usr_irq_req` | `qdma_interrupt_wrapper` serializes one-hot IRQs to `usr_irq_valid/vec/fnc/ack/fail` |
| VIO decoupling override | yes (`pr_slct`) | no (SW registers only) |
| Supported-device decode in driver | XDMA default device IDs (`0x10ee:*`, see `pci_ids` in [pci_xdma.c](../../../driver/src/platform/pci_xdma.c)) | `0x10ee:{B03F,B13F,B23F,B33F}` in [pci_qdma.c](../../../driver/src/platform/pci_qdma.c) |

## 4. Clocks and resets

| Signal | Domain / meaning |
|---|---|
| `xclk` | Static-layer "main" clock; all static logic, static_slave, DMA wrappers, shell-facing AXI interfaces run here. The shell's `aclk` crosses into it in the shell (see [../shell/shell_top.md](../shell/shell_top.md), `shell_data_cc`). |
| `xresetn` | Reset exported to the shell/dynamic domain. Asserted **only** via `eos_resetn` (low), then released by `proc_sys_reset_x` after its hold counter. Not tied to PCIe reset on US+. |
| `sresetn` | Static-layer reset (follows PCIe/DMA IP reset). Used by `static_slave`, wrappers, `dcpl_*`, `pr_stats`. After reset `slv_reg[PR_EOST_RESET]` = 1 (shell not in reset). |
| `eos_resetn` | Output of `dcpl_select_static` (SW register `PR_EOST_RESET_REG` bit 0, or VIO). Input port of `design_static`; low = reset shell domain. Default 1. |
| `pclk`/`presetn` (US+) | 200 MHz PR/ICAP domain. `pr_clock_converter` (xclk->pclk), `pr_dwidth_converter`, `pr_reg_slice`, `pr_cmplt`, `ICAPE3` all run here. `presetn` from `proc_sys_reset_p` with `ext_reset_in=1`. |
| `dclk`/`dresetn` (US+) | 100 MHz debug domain (`debug_hub_static`); also exported to shell for its ILA/VIO. |
| `eos` (US+) | `pr_cmplt` -> 4-FF CDC (`xpm_cdc_single`) -> xclk; one-cycle pulse `eos_time` pclk cycles after the **last** ICAP beat (`pr_val & pr_last`). `ICAPE3.PRDONE` is unused (wired to `icap_done`, not consumed): ICAP completions are not reliable on US+ (comment on the `eos_time` port in [static_slave.sv](../../../hw/hdl/static/static_slave.sv); `EOS_TIME` comment in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) cites the done signal being lost when crossing SLRs on the U55C). |
| `eos_pmc`/`eos_ctrl` (Versal) | CIPS `eos` (PS_USE_STARTUP) -> `pr_ctrl_versal` forwards it as `eos_ctrl` only while in `ST_WAIT_EOS`. |
| `eos_time` | `static_slave.PR_EOST_REG`, reset value `RECONFIG_EOS_TIME` (CMake `EOS_TIME`, default 1,000,000 = 5 ms @200 MHz). Driver module param `eost` overrides it **only** when the loaded shell has `EN_PR=1` (`read_shell_config`, [coyote_setup.c](../../../driver/src/coyote_setup.c), `if(data->en_pr)` block); US+ shell-only PR (`EN_PR=0`) therefore always uses the `RECONFIG_EOS_TIME` baked into the checkpoint's reset value. `shell_pci_init` re-runs `read_shell_config` after every shell swap. Unused on Versal. |
| `sys_reset` (US+ template) | Constant 0, unused. `lckresetn` (clk_wiz locked) left open. |

## 5. BARs and address map

Driver maps the first three **non-empty** PCI BARs (`map_bars`, `CYT_BARS=3`) to `bd_data->bar[0..2]`:

| Index | Name (`coyote_defs.h`) | US+ (XDMA) | Versal (QDMA) | Content |
|---|---|---|---|---|
| 0 | `BAR_STAT_CONFIG` | BAR with AXI4-Lite master (1 MB `axi_cnfg`) | PCI BAR0 (1 MB, `PCIEBAR2AXIBAR` -> `0x201_0000_0000`) | `static_slave` registers; only first 32 KB mapped by driver (`FPGA_STAT_CNFG_SIZE`) |
| 1 | `BAR_DMA_CONFIG` | XDMA register BAR (engines @`0x0`/`0x1000`+ch*0x100, SGDMA +0x4000, IRQ block @`0x2000`) | PCI BAR2 (QDMA registers: context regs `0x804..`, `0x844`, MM ctrl `0x1204`, etc.) | DMA IP control (driver only) |
| 2 | `BAR_SHELL_CONFIG` | XDMA AXI bypass BAR (256 MB `axi_main`) | PCI BAR4 (256 MB, -> `0x208_0000_0000`) | Shell registers (`shell_slave`, per-vFPGA `cnfg_slave`, TLBs, user regs); see [../shell/shell_top.md](../shell/shell_top.md). Driver maps first 32 KB as `shell_cnfg`; vFPGA windows are mapped separately via `mmap` |

Notes:
- `axi_main` is a 64-bit AXI address bus; `static_top` keeps only `AXI_BPSS_BAR_BITS = 28` low bits (256 MB) and zeroes the rest. On Versal the NoC address (`0x208_0000_0000`) upper bits are routing-only and are discarded.
- Versal NoC apertures (from `cr_pci.tcl`): `M00 = 0x201_0000_0000/1G` (axi_cnfg), `M01 = 0x208_0000_0000/1G` (axi_main), `M03 = 0x202_4000_0000/1G` (debug hub, 2 MB segment, accessed by PMC not PCIe), `M02` = PMC (`slave_boot_stream` `0x1_0210_0000`/64 KB, reached from `CPM_PCIE_NOC_1` for PR data). `S00` (`CPM_PCIE_NOC_0`) carries register access, `S01` (`CPM_PCIE_NOC_1`) carries QDMA MM (PR) data to avoid contention.
- Interrupt vectors: user IRQ `i` (vFPGA `i`, `0..14`) -> MSI-X vector `i`; PR IRQ is vector 15 (`FPGA_RECONFIG_IRQ_VECTOR`). See [host_dma.md](host_dma.md#6-user-interrupts).

## 6. static_slave register map

AXI4-Lite, 32-bit, base = BAR0 (`bar_phys_addr[BAR_STAT_CONFIG]`). 32 word slots (`N_REGS=32`), address decode uses only `ADDR_LSB+log2(N_REGS)` = 7 bits, so offsets alias every `0x80`. Source: [static_slave.sv](../../../hw/hdl/static/static_slave.sv) (`localparam` register-map block); driver view: `struct cyt_stat_cnfg_regs` ([coyote_defs.h](../../../driver/include/coyote_defs.h)).

| Word | Offset | Name (driver field) | Access | Fields / behaviour |
|---|---|---|---|---|
| 0 | `0x00` | `PROBE_REG` (`probe`) | RO | `STAT_PROBE` (CMake `STATIC_PROBE`, default 1044942 = `0xFF1CE`); logged by the driver at probe (`dbg_info`); **not** exposed via sysfs (`cyt_attr_cnfg` prints only the shell probe) |
| 1 | `0x04` | `PR_CTRL_REG` (`reconfig_ctrl`) | W (self-clearing) / R | W: bit0 `PR_START` (push descriptor into FIFO), bit1 `PR_CTL` (descriptor is last), bit2 `PR_CLR` (clear `PR_DONE`, deasserts `pr_irq`). Whole register cleared every cycle. R: FIFO write-data-count (`pr_used`), i.e. descriptors currently queued. Driver values: `RECONFIG_CTRL_START_MIDDLE=0x1`, `START_LAST=0x7`, `IRQ_CLR_PENDING=0x4`. Note `START_LAST` (0x7) also carries `PR_CLR`, so the last descriptor clears any stale `PR_DONE`/`pr_irq` before the new PR starts |
| 2 | `0x08` | `PR_STAT_REG` (`reconfig_stat`) | RO | bit0 `PR_DONE` (set by `eos`, cleared by `PR_CLR`), bit1 `PR_READY` (= descriptor FIFO `s_axis_tready`) |
| 3 | `0x0C` | `PR_CNT_REG` (`reconfig_cnt`) | RO | Number of `eos` events since reset |
| 4 | `0x10` | `PR_ADDR_LOW_REG` (`reconfig_addr_low`) | RW | Host physical address [31:0] of bitstream chunk |
| 5 | `0x14` | `PR_ADDR_HIGH_REG` (`reconfig_addr_high`) | RW | Address [43:32] (`PADDR_BITS=44`) |
| 6 | `0x18` | `PR_LEN_REG` (`reconfig_len`) | RW | Chunk length in bytes (`LEN_BITS=28`) |
| 7 | `0x1C` | `PR_EOST_REG` (`reconfig_eost`) | RW | `eos_time` in pclk cycles (US+ only). Reset = `RECONFIG_EOS_TIME` |
| 8 | `0x20` | `PR_EOST_RESET_REG` (`reconfig_eost_reset`) | RW (reads 0) | bit0 -> `eos_resetn` (active low shell reset). Reset value 1. Name is historical; it resets the shell domain, not the EOS timer |
| 9 | `0x24` | `PR_DCPL_REG_SET` (`reconfig_dcpl_set`) | W1S (reads 0) | bit0 = `decouple`. Writing 1 sets |
| 10 | `0x28` | `PR_DCPL_REG_CLR` (`reconfig_dcpl_clr`) | W1C (reads 0) | Writing 1 to bit0 clears `decouple` (RMW into reg 9) |
| 11 | `0x2C` | `HDMA_STAT_BPSS_RD` (`hdma_debug[0]`) | RO | PR/WB channel H2C request count |
| 12 | `0x30` | `HDMA_STAT_BPSS_WR` (`hdma_debug[1]`) | RO | C2H request count |
| 13 | `0x34` | `HDMA_STAT_CMPL_RD` (`hdma_debug[2]`) | RO | H2C completion count |
| 14 | `0x38` | `HDMA_STAT_CMPL_WR` (`hdma_debug[3]`) | RO | C2H completion count |
| 15 | `0x3C` | `HDMA_STAT_AXIS_RD` (`hdma_debug[4]`) | RO | H2C data beats (0 on Versal) |
| 16 | `0x40` | `HDMA_STAT_AXIS_WR` (`hdma_debug[5]`) | RO | C2H data beats |
| 17 | `0x44` | `QDMA_PFCH_TAG_REG` (`qdma_pfch_tag`) | RW | Versal only. `[6:0]` prefetch tag, `[19:8]` queue index relative to `QDMA_WR_QUEUE_START_IDX`, `[31]` valid (level; the driver writes the tag, waits, then writes 0 to drop valid, [pci_qdma.c](../../../driver/src/platform/pci_qdma.c), `stat_cnfg->qdma_pfch_tag`). Tied to hardware only by `qdma_wr_wrapper`; unused on US+ (outputs left unconnected) |

Behaviour details:
- `pr_req` descriptor = `{paddr, len, last}` pushed into `axis_data_fifo_static_slave` (12-byte entries, depth 32, [pci_infrastructure.tcl](../../../scripts/ip_inst/pci_infrastructure.tcl)). `pr_req.valid` is a one-cycle pulse; **if the FIFO is full the pulse is lost** (no back-pressure to AXI-Lite).
- `pr_irq` = registered `PR_DONE` (level) -> `usr_irq[15]`.
- `eos_resetn` default 1; `decouple` default 0 (reset). `decouple` comes from SW (`PR_DCPL_REG_SET/CLR`) or, on US+, from the VIO when `pr_slct`=1 (never OR'd).
- `eos`/`eos_resetn`/`eos_time`: US+ from `pr_cmplt` / to `design_static`; Versal `eos` is `eos_ctrl` from `pr_ctrl_versal`, `eos_time` unconnected.

## 7. Decoupling

- Decoupling cuts valid/ready (and `rsp`, IRQ bits, and `axi_main` handshakes) between static and shell, so a shell being reconfigured cannot corrupt the DMA IPs or the host bus.
- Source of `decouple`: `static_slave` (`PR_DCPL_REG_SET/CLR`) or VIO (`vio_static_decoupling.probe_out1`, selected by `probe_out0` = `pr_slct`) via `dcpl_select_static`. Versal: SW only.
- Applies to: `m_axi_main` (via `axi_decoupler_static`), all `N_SCHAN` streams and `dmaIntf` channels, `s_wback`, `s_usr_irq`. It does **not** apply to the PR channel `N_SCHAN` read path (needed to load the bitstream).
- App-level (vFPGA) decoupling is separate: `reconfig_dcpl_app_{set,clr}` in the shell register file, see [../shell/shell_top.md](../shell/shell_top.md) and [reconfig.md](reconfig.md).

## 8. Routed-locked checkpoints

Build flows (CMake `BUILD_STATIC` / `BUILD_SHELL` / `BUILD_APP`, exactly one set; defaults `0/1/0`, see [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)):

| Flow | Static source | Notes |
|---|---|---|
| `BUILD_SHELL=1` (default) | `$STATIC_PATH/static_routed_locked_<fdev>.dcp` (US+) or `..._<fdev>_gen<PCIE_GEN>.dcp` (Versal, needs Vivado >= 2024.2) | [link.tcl.in](../../../scripts/impl/link.tcl.in) `add_files`; then shell + user DCPs are linked against it with `link_design -reconfig_partitions {inst_shell}` and P&R'd ([pnr_shell.tcl.in](../../../scripts/impl/pnr_shell.tcl.in)). Static placement/routing is frozen, which makes shell PR bitstreams from different shell builds compatible. |
| `BUILD_STATIC=1` | Re-synthesized from [hw/hdl/static](../../../hw/hdl/static/) + templates + `design_static` BD | Constraints from `hw/constraints/<fdev>/static/{synth,impl}` (+ `fplan` if `EN_SHELL_PBLOCK`). After route: `update_design -cell inst_shell -black_box; lock_design -level routing; write_checkpoint static_routed_locked.dcp` in the build dir. Copy it into `hw/checkpoints/` (name as above) to publish a new one. `BUILD_STATIC` with `EN_PR=1` is an error. |
| `BUILD_APP=1` | n/a (uses `$SHELL_PATH/checkpoints/shell_routed_locked.dcp`) | [flow_app.tcl.in](../../../scripts/dyn/flow_app.tcl.in) |
| Versal + `EN_PR=1` (with `BUILD_SHELL=1`) | `static_synthed_v80_gen{4,5}.dcp` (not routed) | [flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in): static is re-implemented together with the shell since nested PR is unsupported and shell pblock is off |

Consequences:
- The prebuilt V80 checkpoints imply `xclk` = 333 MHz (`SCLK_F` is forced to 333 for `BUILD_SHELL`/`BUILD_APP` on v80, [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)). The comment above `set(NN 0)` in FindCoyoteHW.cmake ("Versal always re-synthesizes the static layer") is stale: [link.tcl.in](../../../scripts/impl/link.tcl.in) (Versal branch, `vcompare` check) links `static_routed_locked_v80_gen<PCIE_GEN>.dcp`; only Versal with `EN_PR=1` re-implements static from `static_synthed_*`.
- Edits to anything in [hw/hdl/static](../../../hw/hdl/static/), the static templates, `cr_pci.tcl`, or parameters baked into the static layer (`N_HCHAN`, `N_REG_STAT_S0/S1`, `NR_PR`, `EOS_TIME`, `STATIC_PROBE`, `N_OUTSTANDING`, ...) are **not** reflected in a normal shell build; the committed DCP is used. Rebuild with `-DBUILD_STATIC=1 -DBUILD_SHELL=0`.
- Outputs: `BUILD_STATIC=1` produces `cyt_top.bit`/`.pdi` (full image, programmed via JTAG/flash and PCIe rescan); `BUILD_SHELL=1` produces `shell_top.bin`/`.pdi` (partial, loaded at run time by `cRcnfg`) plus `cyt_top.*` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), `DEP_DCP_LIST_BGEN`, [example 5](../../../examples/05_reconfigure_shell/README.md)).
- Shell PR bitstreams are only valid for the static DCP they were linked against. Mixing a shell built against a self-built static with another shell breaks `reconfigureShell` (see [../../../examples/05_reconfigure_shell/README.md](../../../examples/05_reconfigure_shell/README.md)).
- `hw/checkpoints` DCPs are Git-tracked binaries: `static_routed_locked_*.dcp` are ~70-77 MB each and are what the default flow needs; `static_synthed_v80_gen{4,5}.dcp` are ~19-20 MB (synthesized only, used by the Versal `EN_PR=1` flow); Vivado version compatibility for V80 checkpoints is >= 2024.2 ([v80-notes.rst](../../source/intro/v80-notes.rst)).

## 9. Config knobs

| Knob | Where | Effect on static layer |
|---|---|---|
| `FDEV_NAME` | CMake | Selects device, `FPGA_ARCH` (template + BD dir), XDMA settings |
| `N_HCHAN` (fixed 3) / `N_SCHAN` | [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) -> [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | Number of DMA channels; XDMA `xdma_{r,w}num_chnl`, bypass bitmask |
| `SCLK_F` | CMake | Versal `xclk` frequency (US+ fixed 250) |
| `PCIE_GEN` | CMake | Versal CPM PCIE0 x16 vs PCIE1 x8, `PCIE_GT_BITS` |
| `NR_ST_S0` (`N_REG_STAT_S0`, default 2) | CMake | Register stages in `dcpl_static` (module default 3 is overridden) |
| `NR_ST_S1` (`N_REG_STAT_S1`, default 2) | CMake | No effect (`N_STAGES_1` unused in `dcpl_static`) |
| `N_REG_STA_DCPL` (`NR_SD`, default 3) | CMake | Pipeline stages of the decouple flag |
| `NR_PR` (`N_REG_PR`, default 4) | CMake | `pr_reg_slice` stages before ICAPE3 (US+) |
| `NR_HST` (`HDMA_STATS_DELAY`, default 4) | CMake | Stats register delay |
| `EOS_TIME` (`RECONFIG_EOS_TIME`, default 1000000) | CMake | Initial `PR_EOST_REG` |
| `N_OUTSTANDING` | CMake | Versal: write queues per channel (`qdma_wr_wrapper.N_QUEUES_PER_CHAN`) |
| `EN_PR`, `EN_SHELL_PBLOCK` | CMake | Static layer always contains the PR path; these select the build flow/constraints and driver features |
| `STATIC_PROBE` | CMake | Value of static reg 0 |

## Driver & software interaction

The static layer has **no direct user-space access**: user space never `mmap`s BAR0 (`MMAP_*` in [coyote_defs.h](../../../driver/include/coyote_defs.h) are `MMAP_WB`/`MMAP_CNFG`/`MMAP_CNFG_AVX`/`MMAP_CTRL` for vFPGAs and `MMAP_RECONFIG` for bitstream buffers). All static-register access is from kernel code via `bd_data->stat_cnfg` (`ioremap` of BAR0, set in `pci_probe`).

Forward path (SW -> HW), PR as the main user:

1. SW: [`cRcnfg::reconfigureShell` / `reconfigureApp`](../../../sw/src/cRcnfg.cpp) -> `reconfigureBase` -> `ioctl(reconfig_fd, IOCTL_RECONFIGURE_SHELL|APP)` on `/dev/coyote_fpga_<n>_reconfig`.
2. Driver: [`reconfig_dev_ioctl`](../../../driver/src/reconfig/reconfig_ops.c) -> [`reconfigure_start`](../../../driver/src/reconfig/reconfig_hw.c) writes `stat_cnfg->reconfig_{addr_low,addr_high,len,ctrl}`.
3. HW: `static_slave` -> descriptor FIFO -> `dma_rd_req_int[N_SCHAN]` -> `xdma_wrapper` (US+) / `pr_ctrl_versal` (Versal). Detail in [reconfig.md](reconfig.md).

Reverse path (HW -> SW): `eos` -> `PR_DONE` -> `pr_irq` -> `usr_irq[15]` -> MSI-X vector 15 -> [`reconfig_isr`](../../../driver/src/reconfig/reconfig_isr.c) (sets `wait_rcnfg`, wakes `waitqueue_rcnfg`, writes `PR_CLR`) -> `ioctl` returns to SW.

Probe-time register use ([pci_xdma.c](../../../driver/src/platform/pci_xdma.c) / [pci_qdma.c](../../../driver/src/platform/pci_qdma.c) `pci_probe`):
- `ioremap` BAR0 -> `stat_cnfg` (32 KB), BAR2-index -> `shell_cnfg` (32 KB).
- Pulse `reconfig_eost_reset` 0 -> 1 (resets the shell domain once at load).
- `read_shell_config()` ([coyote_setup.c](../../../driver/src/coyote_setup.c)): reads `probe`, then shell config; if the shell has `EN_PR`, writes `stat_cnfg->reconfig_eost = eost` (module param).
- Versal only: per C2H queue, `stat_cnfg->qdma_pfch_tag = {valid, qid, tag}` (see [host_dma.md](host_dma.md)).

| Register / item | RTL source | Driver accessor | SW / user-visible |
|---|---|---|---|
| `PROBE` (0x00) | [static_slave.sv](../../../hw/hdl/static/static_slave.sv) | `read_shell_config()` -> `bd_data->probe_stat` | none (not exposed; `cyt_attr_cnfg` shows `probe_shell` only) |
| `PR_CTRL/ADDR/LEN` (0x04,0x10-0x18) | `static_slave` PR FIFO | [`reconfigure_start`](../../../driver/src/reconfig/reconfig_hw.c) | `cRcnfg::reconfigureShell/App` -> `IOCTL_RECONFIGURE_{SHELL,APP}` |
| `PR_STAT/CNT` (0x08,0x0C) | `static_slave` | not read by driver (only `reconfig_ctrl` readback for throttling) | none |
| `PR_EOST` (0x1C) | `static_slave` -> `pr_cmplt.eos_time` | `read_shell_config()` (only if shell has `EN_PR`); sysfs `cyt_attr_eost` show/store (user-visible; store ineffective, REC-09) | none directly (sysfs only) |
| `PR_EOST_RESET` (0x20) | `static_slave.eos_resetn` -> `dcpl_select_static` -> BD `eos_resetn` | `pci_probe`, `IOCTL_RECONFIGURE_SHELL` | none |
| `PR_DCPL_SET/CLR` (0x24,0x28) | `static_slave.decouple` | `IOCTL_RECONFIGURE_SHELL` (`reconfig_dcpl_set/clr`) | none |
| `HDMA_STAT_*` (0x2C-0x40) | `pr_stats` -> `static_slave` | `IOCTL_PR_WB_STATS` ([reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c)), sysfs `cyt_attr_prstats` | `IOCTL_PR_WB_STATS` defined in [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp) but no sw call site |
| `QDMA_PFCH_TAG` (0x44) | `static_slave` -> `qdma_wr_wrapper` | `enable_queue()` ([pci_qdma.c](../../../driver/src/platform/pci_qdma.c)) | none |
| `usr_irq[15]` | `static_slave.pr_irq` | `reconfig_isr` | `cRcnfg` blocks in `ioctl` |
| `IOCTL_PR_CNFG` | shell `pr_cnfg` (not static) | `reconfig_dev_ioctl` returns `bd_data->en_pr` | [`cSched` ctor](../../../sw/src/cSched.cpp) |

Driver-side files: [coyote_driver.c](../../../driver/src/coyote_driver.c) (module params `eost`, `ip_addr`, `mac_addr`), [coyote_setup.c](../../../driver/src/coyote_setup.c) (shell config, reconfig device creation), [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c) (`cyt_attr_prstats`, `cyt_attr_eost`, `cyt_attr_qdma_debug_regs`; `/sys/kernel/coyote_sysfs_<id>/`). Overall driver docs: [../driver.md](../driver.md#static-layer--host-dma) and [../driver.md](../driver.md#reconfiguration); host library: [../software.md](../software.md#reconfiguration).

## Gotchas and invariants

- **Static changes need a new checkpoint.** The default flow links the prebuilt DCP; HDL edits in `hw/hdl/static` do nothing unless `BUILD_STATIC=1`. Shell and static DCP must match (`static_slave` register map, channel counts, `lynxTypes`).
- `N_HCHAN` is hard-coded to 3 and `XDMA_MAX_NUM_CHANNELS = 3` in the driver; XDMA IP is configured with `N_HCHAN` read+write channels. Changing it touches the BD, templates, driver (`XDMA_*`, `N_HDMA_STAT_CH_REGS = 12/3`) and `qdma_*_wrapper` queue maps.
- Only 15 user IRQ bits exist (`s_usr_irq[14:0]`), so `N_REGIONS <= 15`; CMake enforces it ("Max 15 vFPGAs supported", [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)) although the driver allows `MAX_N_REGIONS = 16`.
- PR channel (`N_SCHAN`) carries both PR reads (H2C) and writeback writes (C2H); H2C of that channel is used for the PR bitstream only, and C2H for 4-byte writeback only.
- `static_slave` never returns an AXI error response: writes to unmapped/RO offsets are ignored and unmapped reads return 0.
- US+ `ICAPE3` input bus is the 32-bit word fully bit-reversed (`icap_data` assignment in the template), and `ICAP_AUTO_SWITCH="DISABLE"`.
- `xresetn` is reset only through `eos_resetn` (not by PCIe reset) on both architectures; after power-up the driver pulses it once.
- The Coyote v1 thesis (Korolija, ch. 3; external) describes v1 (XDMA only, services in static layer); trust the RTL.
- Known defects in this area: [known_issues.md](../known_issues.md) (`STA-*`, `REC-09`, `REC-11`, `DOC-04`).

## How to modify / extend

**Add a static register**
1. Add a `localparam` index + write/read cases in [static_slave.sv](../../../hw/hdl/static/static_slave.sv) (`N_REGS=32`, indices 18-31 free; remember the 7-bit decode).
2. Mirror it in `struct cyt_stat_cnfg_regs` ([coyote_defs.h](../../../driver/include/coyote_defs.h)) at the same word offset (struct is `__packed`, fields are 32-bit).
3. Route any new ports through both [static_top templates](../../../hw/templates/) (US+ and Versal) and tie off in the architecture that does not use it.
4. Rebuild static checkpoint (`BUILD_STATIC=1 BUILD_SHELL=0`), copy `static_routed_locked.dcp` into `hw/checkpoints/<name>`, rebuild the driver.

**Support a new device**
1. Add the device branch in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) (part, memory, clocks, `PCIE_GT_BITS`), constraints under `hw/constraints/<dev>/{static,shell,dynamic,fplan}`.
2. Add a `fdev` case to the XDMA block in [hw/bd/ultrascale_plus/cr_pci.tcl](../../../hw/bd/ultrascale_plus/cr_pci.tcl) or a CIPS config for Versal.
3. Add PCI device IDs to `pci_ids` in the relevant `pci_*.c`.
4. Generate and commit the routed-locked checkpoint.

**Change static clock / pipeline depth**: edit `SCLK_F` (Versal) or `NR_ST_S0/S1`, `NR_PR`, then rebuild the static checkpoint.

**Add a shell<->static signal**: extend `static_top` ports in both templates, `dcpl_static` (add slice + decoupler), [cyt_top_tmplt.txt](../../../hw/templates/common/cyt_top_tmplt.txt) and the shell side; if it is a register-visible event, add a register as above.
