# Partial reconfiguration (shell and application)

**Purpose:** How Coyote reloads logic at run time without touching PCIe/DMA: **shell reconfiguration** (swap the whole shell = dynamic layer + all vFPGAs, `reconfigureShell`) and **application reconfiguration** (swap one vFPGA inside the shell, `reconfigureApp`). Covers the hardware PR data paths on UltraScale+ (ICAPE3) and Versal (PMC slave-boot stream), decoupling/reset sequencing, bitstream formats and build flow, the driver `reconfig_*` code and the `cRcnfg` software class.

## Key files

| Path | Role |
|---|---|
| [static_slave.sv](../../../hw/hdl/static/static_slave.sv) | PR registers: descriptor FIFO, `PR_DONE`, `pr_irq`, `eos_resetn`, `decouple`, `eos_time` |
| [static_top (US+)](../../../hw/templates/ultrascale_plus/static_top_tmplt.txt) | `pr_clock_converter` -> `pr_dwidth_converter` -> `pr_reg_slice` x`N_REG_PR` -> `ICAPE3`, `pr_cmplt` |
| [static_top (Versal)](../../../hw/templates/versal/static_top_tmplt.txt) | `pr_ctrl_versal` + QDMA MM descriptor port `dsc_pr` |
| [pr_cmplt.sv](../../../hw/hdl/static/common/pr/pr_cmplt.sv) | US+: asserts `eos` `eos_time` pclk cycles after last ICAP beat |
| [pr_ctrl_versal.sv](../../../hw/hdl/static/pr_ctrl_versal.sv) | Versal: splits request into 4 KiB QDMA MM H2C descriptors to PMC keyhole; waits for `eos_pmc` |
| [dcpl_select_static.sv](../../../hw/hdl/static/dcpl_select_static.sv), [dcpl_static.sv](../../../hw/hdl/static/dcpl_static.sv) | Static-side decoupling / reset selection |
| [pr_stats.sv](../../../hw/hdl/static/common/stats/pr_stats.sv) | PR/WB channel counters |
| [shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv) | Shell registers `CTRL_DP_REG_SET/CLR` (words 9/10): per-vFPGA decouple (`[N_REGIONS-1:0]`; reset value `'X`) and an unconnected `m_rst_pr` output (REC-03) |
| [cr_pci.tcl (Versal)](../../../hw/bd/versal/cr_pci.tcl) | `dsc_pr` -> CPM `dmaX_h2c_byp_in_mm_0`; address segment `0x1_0210_0000` (PMC `slave_boot_stream`); CIPS `eos` -> `eos_pmc` |
| [reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c) | char-dev `open/release/ioctl/mmap` for `/dev/coyote_fpga_<n>_reconfig` |
| [reconfig_hw.c](../../../driver/src/reconfig/reconfig_hw.c) | `reconfigure_start()`: writes descriptors to `static_slave` |
| [reconfig_isr.c](../../../driver/src/reconfig/reconfig_isr.c) | PR-done interrupt handler |
| [reconfig_mem.c](../../../driver/src/reconfig/reconfig_mem.c) | Bitstream buffer allocation (2 MB pages) / free; hash `reconfig_buffs_map` |
| [reconfig_*.h](../../../driver/include/reconfig/) | Prototypes |
| [coyote_defs.h](../../../driver/include/coyote_defs.h) | `RECONFIG_*`, `IOCTL_*` (`'P'` group), `struct reconfig_dev`, `struct reconfig_buff_metadata` |
| [coyote_setup.c](../../../driver/src/coyote_setup.c) | `alloc/setup/teardown/free_reconfig_device` |
| [cRcnfg.cpp](../../../sw/src/cRcnfg.cpp), [cRcnfg.hpp](../../../sw/include/coyote/cRcnfg.hpp) | User-space API |
| [cSched.cpp](../../../sw/src/cSched.cpp) | Scheduler that calls `reconfigureBase` to swap vFPGA apps on demand |
| [bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in), [fix_bif.py.in](../../../scripts/impl/fix_bif.py.in) | Bitstream/PDI generation |
| [link.tcl.in](../../../scripts/impl/link.tcl.in), [pnr_shell.tcl.in](../../../scripts/impl/pnr_shell.tcl.in), [flow_dyn_ultrascale_plus.tcl.in](../../../scripts/dyn/flow_dyn_ultrascale_plus.tcl.in), [flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in), [flow_app.tcl.in](../../../scripts/dyn/flow_app.tcl.in) | PR implementation flows |
| [examples/05_reconfigure_shell](../../../examples/05_reconfigure_shell/README.md), [examples/10_app_reconfiguration](../../../examples/10_app_reconfiguration/README.md) | Usage examples |

**Related:** [static_top.md](static_top.md) (register map, clocks, checkpoints) | [host_dma.md](host_dma.md) (DMA channel `N_SCHAN`, QDMA queue 0, interrupts) | [../shell/shell_top.md](../shell/shell_top.md) | [../build/build_top.md](../build/build_top.md) | [../build/constraints.md](../build/constraints.md) (shell/vFPGA pblocks, `FPLAN_PATH`) | [../driver.md](../driver.md#reconfiguration) | [../software.md](../software.md#reconfiguration)

## 1. Concepts

| | Shell reconfiguration | App (vFPGA) reconfiguration |
|---|---|---|
| Region | `inst_shell` (reconfigurable partition of `cyt_top`) | `inst_shell/inst_dynamic/inst_user_wrapper_<j>` (nested inside the shell) |
| Enabled by | `EN_SHELL_PBLOCK=1` (default); `shell_pblock_cnfg` | `EN_PR=1` (+ `N_CONFIG`, `FPLAN_PATH`); `pr_cnfg` |
| SW | `cRcnfg::reconfigureShell(path)` | `cRcnfg::reconfigureApp(path, vfid)` or `cSched` |
| Driver ioctl | `IOCTL_RECONFIGURE_SHELL` | `IOCTL_RECONFIGURE_APP` |
| Decoupling | static layer (`reconfig_dcpl_set/clr` in static regs) + shell goes through `shell_pci_remove/init` | vFPGA only (`reconfig_dcpl_app_set/clr` in shell regs, bit = vFPGA id) |
| Resets shell afterwards | Yes: `reconfig_eost_reset` 0 -> 1 (`eos_resetn`) | No `eos_resetn` pulse in the driver |
| Other vFPGAs | all offline during PR | unaffected (independent) |
| Bitstream | `shell_top.bin` (US+) / `shell_top.pdi` (Versal) | `vfpga_c<cfg>_<vfid>.bin` (US+) / `.pdi` (Versal) under `bitstreams/config_<cfg>/` |
| Static layer | untouched (same routed-locked checkpoint required) | untouched |
| Both on same build | US+: yes (nested DFX via `pr_subdivide`/`pr_recombine`); Versal: no, CMake `FATAL_ERROR` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) ~L558-559; see [summary](../coyote_top.md#ultrascale-vs-versal-summary)) |

Shell and app reconfiguration use the **same** hardware PR channel and the same host DMA path; only the bitstream content and decoupling differ. Typical times: ~50 ms (shell; the `dmesg` "shell reconfiguration time" spans the whole ioctl body: `shell_pci_remove`, PR, reset, `shell_pci_init`, [reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c) ~L94-138, not just the PR transfer), ~850 ms end-to-end including reading the bitstream and kernel buffer setup (example 5).

## 2. Hardware data path

ICAP vs PMC mechanism: [UltraScale+ vs Versal](../coyote_top.md#ultrascale-vs-versal-summary).

Common start: the driver programs `{paddr, len, last}` into `static_slave` (`PR_ADDR_LOW/HIGH`, `PR_LEN`, then `PR_CTRL`), which pushes the descriptor into a 32-deep FIFO (`axis_data_fifo_static_slave`) that feeds `dma_rd_req_int[N_SCHAN]`. Each descriptor is one host-memory chunk (driver uses 2 MB buffer pages; last chunk may be shorter). `last` is set only on the final descriptor of the bitstream.

### 2.1 UltraScale+ (XDMA + ICAPE3)

```
host mem --XDMA H2C ch N_SCHAN (descriptor bypass)--> axis_dyn_out_int[N_SCHAN] (512b, xclk)
  -> pr_clock_converter (xclk 250 -> pclk 200 MHz)
  -> pr_dwidth_converter (512b -> 32b)
  -> pr_reg_slice x N_REG_PR (default 4)           // axis_icap[0..N_REG_PR]
  -> ICAPE3 (CSIB = ~tvalid, tready = 1, data = 32-bit full bit-reversal of tdata)
  -> pr_cmplt: on (tvalid & tlast) wait eos_time pclk cycles -> eos -> CDC -> xclk -> static_slave
```

- ICAP is write-only (`RDWRB=0`), `ICAP_AUTO_SWITCH="DISABLE"`. `PRDONE`, `PRERROR`, `AVAIL`, `O` are wired to internal nets (`icap_done`, ...) but unused. The timer replaces `PRDONE` because ICAP completions are not reliable on US+ ([static_slave.sv](../../../hw/hdl/static/static_slave.sv) ~L52); the `EOS_TIME` comment in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) ~L169 attributes it to the done signal being lost across SLRs on the U55C.
- `eos_time` = `PR_EOST_REG` (default `EOS_TIME`=1,000,000 pclk cycles = 5 ms at 200 MHz; driver module param `eost`). The timer starts at the last ICAP beat of the *whole* bitstream. For shell PR use the default; too small a value raises `pr_irq` before the region is live.
- Throughput bound: 32-bit @ 200 MHz = 800 MB/s.
- `pr_stats`: counts request, completion (`rsp.done` = XDMA descriptor completed) and beats on channel `N_SCHAN`.
- Decoupling uses `dcpl_static` (static <-> shell); PR data is not decoupled.

### 2.2 Versal (CIPS QDMA MM -> PMC SBI)

```
host mem --QDMA MM H2C queue 0 (bypass, MM channel 0, NoC_1)--> CPM_PCIE_NOC_1
  -> axi_noc_0 M02 -> NOC_PMC_AXI_0 -> PMC slave_boot_stream @ 0x1_0210_0000 (64 KB keyhole)
  -> PMC loads the partial PDI; CIPS `eos` -> eos_pmc
```

[pr_ctrl_versal.sv](../../../hw/hdl/static/pr_ctrl_versal.sv) FSM (`PARSE_SIZE = 4096`):

| State | Action |
|---|---|
| `ST_IDLE` | `s_pr_dma_rd_req.ready=1`; latch `paddr,len,last` on `valid` |
| `ST_PARSE` | Take next <=4 KiB piece (`len_prev`, `paddr_rd_prev`), advance `paddr_rd` |
| `ST_SEND` | Present `qdma_h2c_mm_desc {raddr=paddr, waddr=0x1_0210_0000, len[15:0], qid=0 (QDMA_PR_QUEUE_IDX), mrkr_req=1}`; on `ready` (and `last_C` set) `rsp.done` is pulsed for **every** accepted piece, not just the last; then go to `ST_PARSE` if bytes remain, else `ST_WAIT_EOS` (if `last`) or `ST_WAIT_NEXT` |
| `ST_WAIT_NEXT` | `rsp.done=1`; wait for next descriptor from `static_slave` |
| `ST_WAIT_EOS` | `eos_ctrl = eos_pmc`; return to `ST_IDLE` when `eos_pmc` |

- No DMA error handling: `pr_cmd_done` (status `op==3`, `qid==0`, no error bit) is statistics only; completion is **solely** `eos_pmc`. A failed/corrupt PDI therefore hangs the driver waiting for the IRQ (no timeout).
- `eos_time` is unused (left open); `PR_EOST_REG` is meaningless on Versal.
- `pr_stats.axis_rd` tied 0: PR data bypasses the fabric.
- The descriptor port is `qdmaH2CDescMM` ([lynx_intf.sv](../../../hw/hdl/pkg/lynx_intf.sv)), connected to `versal_cips_0/dmaX_h2c_byp_in_mm_0`; MM channel 1 and C2H MM are tied off.
- The PDI **must** be the partial image for the reconfigurable cell; the full image has `boot_device { pcie }` set so the PMC accepts SBI data from PCIe (see bitstream formats).
- Shell-region PR on Versal requires the NoC/QDMA to stay alive: only the shell is decoupled.

### 2.3 Completion and IRQ (both)

`eos` -> `slv_reg[PR_STAT][PR_DONE]=1`, `PR_CNT++` -> `pr_irq` (registered level) = `usr_irq[15]` -> MSI-X vector 15 -> `reconfig_isr`. The ISR writes `PR_CTRL = 0x4` (`PR_CLR`) which drops `PR_DONE` and the IRQ line (this is also required on Versal so `qdma_interrupt_wrapper` can advance). The driver's `0x1` = `PR_START`; `0x7` = `PR_START|PR_CTL|PR_CLR` ([static_slave.sv](../../../hw/hdl/static/static_slave.sv) L111-113), so the last descriptor also clears any stale `PR_DONE`/`pr_irq`.

## 3. Decoupling and reset sequencing

Registers: static `PR_DCPL_REG_SET/CLR` (0x24/0x28), `PR_EOST_RESET_REG` (0x20); shell `reconfig_dcpl_app_set/clr` (byte offsets 0x48 / 0x50 of the shell BAR: words 9/10 of `struct cyt_shell_cnfg_regs`, which is 64-bit per word). Static decouple gates valid/ready of all shell-facing interfaces in `dcpl_static`; shell decouple (`m_decouple`) gates one vFPGA's interfaces in `dynamic_top` (`axis_decoupler`, `meta_decoupler`, ...).

**Shell reconfiguration (`IOCTL_RECONFIGURE_SHELL`, [reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c)):**

1. `mutex_lock(rcnfg_lock)`.
2. `shell_pci_remove()`: disable vFPGA IRQs (US+), free vFPGA char devices, card memory, sysfs, HMM chunks.
3. `stat_cnfg->reconfig_dcpl_set = 1` (static decouple).
4. `reconfigure_start()` pushes descriptors; PR data flows.
5. `wait_event_interruptible(waitqueue_rcnfg, wait_rcnfg == FLAG_SET)` (woken by `reconfig_isr`); clear flag.
6. `reconfig_eost_reset = 0; = 1` (resets `xresetn`: new shell comes out of reset).
7. `reconfig_dcpl_clr = 1` (couple).
8. `shell_pci_init()`: `read_shell_config()` (new `N_REGIONS`, features, TLB geometry), sysfs, card memory, new vFPGA devices, IRQs (`irq_setup(.., false)`; reconfig IRQ stays), US+ `vfpga_interrupts_enable`.
9. `mutex_unlock`.

**App reconfiguration (`IOCTL_RECONFIGURE_APP`):**

1. `mutex_lock`.
2. `shell_cnfg->reconfig_dcpl_app_set = 1 << vfid` (decouple that vFPGA; no vFPGA reset after app PR, REC-03).
3. `reconfigure_start()`; wait for `reconfig_isr` as above.
4. `shell_cnfg->reconfig_dcpl_app_clr = 1 << tmp[3]` (see REC-01).
5. `mutex_unlock`. No `shell_pci_*` and no `eos_resetn` pulse; the vFPGA device nodes remain.

VIO override (US+ only): `vio_static_decoupling.probe_out0 (pr_slct)=1` makes `decouple`/`eos_resetn` follow the VIO instead of static registers, for hardware debug.

## 4. Bitstream formats and build

| | UltraScale+ | Versal |
|---|---|---|
| Initial image | `cyt_top.bit` (JTAG) | `cyt_top.pdi` (JTAG/other), regenerated by `bootgen` with `boot_device { pcie }` |
| Shell partial | `shell_top.bin` (`write_bitstream -bin_file -no_binary_bitfile -cell inst_shell`); `.bin` raw words for ICAP, **not** `.bit` | `shell_top.pdi` (`write_device_image -cell inst_shell`); not produced when `EN_PR=1` |
| vFPGA partial | `config_<i>/vfpga_c<i>_<j>.bin` (`-cell inst_shell/inst_dynamic/inst_user_wrapper_<j>`) | `config_<i>/vfpga_c<i>_<j>.pdi` |
| Debug probes | `.ltx` per image (`write_debug_probes -cell ...`) | same |

[bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in) (arch branches in `if/elseif` on `$cfg(fpga_arch)`; `en_pr` selects the per-config loop over `shell_routed_c<i>.dcp`).

**Why `fix_bif.py` (Versal):** Vivado 2025.1 cannot set `boot_device` to PCIe from Tcl. The flow is: `write_device_image` produces `cyt_top.pdi` and `cyt_top.bif`; `rm cyt_top.pdi`; `python fix_bif.py cyt_top.bif` inserts ` boot_device { pcie }` after the first `id =` line following `bitstream_master:` ([fix_bif.py.in](../../../scripts/impl/fix_bif.py.in), copied to the CMake binary dir by [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) L901); `bootgen -arch versal -image cyt_top.bif -w -o cyt_top.pdi`. Without this, partial PDIs sent over PCIe are not accepted. `python` and `bootgen` must be on `PATH`.

**Implementation flows (CMake `BUILD_*`, see [static_top.md](static_top.md#8-routed-locked-checkpoints)):**
- Shell flow, no app PR (`EN_PR=0`): link synthed shell/user DCPs against the static checkpoint, `link_design -reconfig_partitions {inst_shell}`, P&R, `shell_routed.dcp`; bitgen writes `shell_top.*` and `cyt_top.*` from the same DCP.
- US+ app PR (`EN_PR=1`): [flow_dyn_ultrascale_plus.tcl.in](../../../scripts/dyn/flow_dyn_ultrascale_plus.tcl.in): `pr_subdivide` the routed shell into vFPGA cells -> link/P&R config 0 with `FPLAN_PATH` floorplan -> lock (`shell_routed_locked.dcp`) -> P&R configs 1..N-1 on the locked shell -> `pr_recombine` (`shell_recombined.dcp`) used for the shell bitstream.
- Versal app PR: [flow_dyn_versal.tcl.in](../../../scripts/dyn/flow_dyn_versal.tcl.in): no subdivide/recombine; static re-implemented with `static_synthed_<FDEV_NAME>_gen<PCIE_GEN>.dcp`, vFPGAs as reconfig partitions directly, requires `EN_SHELL_PBLOCK=0` and `FPLAN_PATH`.
- `BUILD_STATIC=1` produces only `cyt_top.*` (no `shell_top.*`, [bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in) ~L48). Versal with `EN_PR=1`: `cyt_top.pdi` comes from `shell_routed.dcp`, the vFPGA PDIs from `config_<i>/shell_routed_c<i>.dcp` (bitgen.tcl.in ~L110-146).
- `BUILD_APP=1`: link new apps into an existing shell (`SHELL_PATH`/checkpoints/`shell_routed_locked.dcp`), [flow_app.tcl.in](../../../scripts/dyn/flow_app.tcl.in).
- Invariant: a partial image is only valid for the exact routed-locked static (and, for app PR, shell) checkpoint it was built against (example 5: "same static layer checkpoint").
- Floorplans: `hw/constraints/<fdev>/fplan` (shell pblock) and the user's `FPLAN_PATH` ([examples/10_app_reconfiguration/hw/floorplans](../../../examples/10_app_reconfiguration/hw/floorplans/)) for vFPGA pblocks; see [../build/constraints.md](../build/constraints.md).

## 5. Config knobs

| Knob | Effect |
|---|---|
| `EN_PR` | Build vFPGA reconfigurable partitions; sets `PR_FLOW`/`pr_cnfg` (driver `en_pr`) |
| `N_CONFIG` | Number of app configurations per vFPGA (`N_REGIONS x N_CONFIG` apps via `load_apps`) |
| `FPLAN_PATH` | vFPGA floorplan XDC (required for `EN_PR=1`) |
| `EN_SHELL_PBLOCK` | Floorplan + reconfigurability of shell (`shell_pblock_cnfg`); must be 0 with `EN_PR=1` on Versal; only `0` allowed for `BUILD_STATIC=1` or Versal+PR |
| `EOS_TIME` / module param `eost` | US+ end-of-startup delay in pclk cycles |
| `NR_PR` (`N_REG_PR`) | `pr_reg_slice` stages before ICAP (US+) |
| `NR_SD` / `NR_ST_S0/S1` | Static decouple/slice depth |
| `PCIE_GEN`, `FDEV_NAME` | Selects checkpoint name for Versal |
| Driver constants | `RECONFIG_THRESHOLD=32`, `RECONFIG_CTRL_START_MIDDLE=0x1`, `START_LAST=0x7`, `IRQ_CLR_PENDING=0x4`, `RECONFIG_BUFF_PAGE_SHIFT=21` (2 MB), `MAX_RECONFIG_BUFF_NUM=128` (256 MB max bitstream) |

## Driver & software interaction

### SW -> HW (forward path)

1. **Allocate and load bitstream.** `cRcnfg::reconfigureShell|reconfigureApp(path[, vfid])` ([cRcnfg.cpp](../../../sw/src/cRcnfg.cpp)) -> `readBitstream()`: file size -> `n_pages = ceil(len/2MB)` -> `getMem({PRM, n_pages})`:
   - `ioctl(fd, IOCTL_ALLOC_HOST_RECONFIG_MEM, {n_pages, pid, crid})` -> `reconfig_dev_ioctl` -> [`alloc_reconfig_buffer`](../../../driver/src/reconfig/reconfig_mem.c): `alloc_pages(GFP_ATOMIC, order 9)` per 2 MB page, `dma_map_single(..., DMA_TO_DEVICE)` -> `hpages[]` (bus addresses), saved in `device->curr_buff`.
   - `mmap(NULL, (n_pages+1)*2MB, fd, MMAP_RECONFIG)` -> `reconfig_dev_mmap`: aligns vaddr to 2 MB, inserts `reconfig_buff_metadata {vaddr, pid, crid, n_pages, pages, hpages}` into `reconfig_buffs_map` (hash on vaddr), `remap_pfn_range` each page (uncached).
   - The file is read **byte by byte** into the mapped buffer (`readByte`); a named inter-process mutex `reconfig_mtx` guards alloc+mmap.
2. **Trigger.** `reconfigureBase(bitstream, vfid)`: `ioctl(fd, IOCTL_RECONFIGURE_APP|SHELL, {vaddr, len, pid, crid[, vfid]})` (`vfid = -1` selects shell).
3. **Driver.** [`reconfigure_start(device, vaddr, len, pid, crid)`](../../../driver/src/reconfig/reconfig_hw.c) finds the buffer by `(vaddr, pid, crid)`, then for each full 2 MB page writes `reconfig_addr_low/high`, `reconfig_len = 2MB`, then `reconfig_ctrl = 0x1` (`0x7` for the final chunk); a trailing partial page uses `len % 2MB` and `0x7`.
   - Throttle: polls `reconfig_ctrl` (FIFO occupancy) while `cmd_sent >= 32`; effectively unthrottled (STA-01).
4. **HW.** `static_slave` -> FIFO -> `dma_rd_req_int[N_SCHAN]` -> [US+: `xdma_wrapper` -> XDMA H2C channel `N_SCHAN` (= `N_HCHAN-1`, the third channel) -> ICAP] / [Versal: `pr_ctrl_versal` -> QDMA MM q0 -> PMC] (section 2).
5. **Cleanup.** `cRcnfg::~cRcnfg()` / `freeMem()`: `munmap` + `IOCTL_FREE_HOST_RECONFIG_MEM {aligned vaddr, pid, crid}` -> [`free_reconfig_buffer`](../../../driver/src/reconfig/reconfig_mem.c) (`dma_unmap_single`, `__free_pages`, `vfree`, `hash_del`). Buffers are only released in `~cRcnfg` or an explicit `freeMem` (SW-07, SW-08).

### HW -> SW (reverse path)

`eos` (US+: `pr_cmplt`; Versal: `eos_pmc`) -> `static_slave.PR_DONE` -> `pr_irq` = `usr_irq[15]` -> XDMA user IRQ 15 / QDMA `usr_irq_vec=15` -> MSI-X vector 15 (`FPGA_RECONFIG_IRQ_VECTOR`) -> [`reconfig_isr`](../../../driver/src/reconfig/reconfig_isr.c): `spin_lock_irqsave(irq_lock)`, `atomic_set(wait_rcnfg, FLAG_SET)`, `wake_up_interruptible(waitqueue_rcnfg)`, write `reconfig_ctrl = RECONFIG_CTRL_IRQ_CLR_PENDING` -> the sleeping `reconfig_dev_ioctl` resumes (decouple release, shell re-init) -> `ioctl` returns -> `cRcnfg` returns. No eventfd / user callback is involved; the call is synchronous.

IRQ registration: `irq_setup(bd_data, pdev, enable_reconfig_irq=true)` at probe (`request_irq(pci_irq_vector(15), reconfig_isr, ..., bd_data->reconfig_dev)`); US+ also `reconfig_interrupt_enable()` (`user_int_enable_w1s = 0x8000`) and `write_msix_vectors()`.

### Registers / ioctls involved

| Item | RTL source | Driver accessor | SW |
|---|---|---|---|
| `PR_ADDR_LOW/HIGH/LEN` (0x10/0x14/0x18) | `static_slave` -> FIFO `{paddr,len,last}` | `reconfigure_start` (`stat_cnfg->reconfig_addr_*`, `reconfig_len`) | via `IOCTL_RECONFIGURE_*` |
| `PR_CTRL` (0x04): start/last/clear, read=FIFO count | `static_slave` | `reconfigure_start`, `reconfig_isr` | - |
| `PR_STAT` (0x08): bit0 `PR_DONE`, bit1 `PR_READY` (descriptor FIFO `tready`); `PR_CNT` (0x0C) | `static_slave` | not read by the driver (`PR_READY` would be the natural flow-control signal for a throttle fix) | - |
| `PR_EOST` (0x1C) | `pr_cmplt.eos_time` | `read_shell_config` (if `en_pr`), sysfs `cyt_attr_eost` | - |
| `PR_EOST_RESET` (0x20) | `eos_resetn` -> `xresetn` | `pci_probe`, `IOCTL_RECONFIGURE_SHELL` | - |
| `PR_DCPL_SET/CLR` (0x24/0x28) | `dcpl_static` | `IOCTL_RECONFIGURE_SHELL` | - |
| shell `reconfig_dcpl_app_set/clr` (0x48/0x50) | `shell_slave` `CTRL_DP_REG_SET/CLR` -> `dynamic_top` decouplers | `IOCTL_RECONFIGURE_APP` | - |
| `usr_irq[15]` | `pr_irq` | `reconfig_isr` | blocks `ioctl` |
| `IOCTL_ALLOC_HOST_RECONFIG_MEM` `_IOW('P',1)` | - | `alloc_reconfig_buffer` | `cRcnfg::getMem` |
| `IOCTL_FREE_HOST_RECONFIG_MEM` `_IOW('P',2)` | - | `free_reconfig_buffer` | `cRcnfg::freeMem` |
| `IOCTL_RECONFIGURE_APP` `_IOW('P',3)` | - | `reconfig_dev_ioctl` | `reconfigureApp` / `cSched` |
| `IOCTL_RECONFIGURE_SHELL` `_IOW('P',4)` | - | `reconfig_dev_ioctl` | `reconfigureShell` |
| `IOCTL_PR_CNFG` `_IOR('P',5)` | `pr_cnfg` (shell) | returns `bd_data->en_pr` | [`cSched::cSched`](../../../sw/src/cSched.cpp) -> `fcnfg.en_pr` |
| `IOCTL_PR_WB_STATS` `_IOR('P',6)` | `pr_stats` | copies only `hdma_debug[0..3]` (4 of 6; the AXIS beat counters are dropped). On Versal `pr_stats` counts 4 KiB QDMA descriptors via `pr_ctrl_versal`, not 2 MB chunks | none (defined in [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp)) |
| `mmap` offset `MMAP_RECONFIG` | - | `reconfig_dev_mmap` (compares `vma->vm_pgoff == 0x100`, a page offset) | `cRcnfg::getMem` (`MMAP_RECONFIG = 0x100 << PAGE_SHIFT`, byte offset, [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp) L273) |
| sysfs `cyt_attr_prstats`, `cyt_attr_eost` | `pr_stats`, `PR_EOST` | [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c) | shell |

Higher-level users: [`cSched`](../../../sw/src/cSched.cpp) (inherits `cRcnfg`): for each scheduled task whose function bitstream differs from the loaded one it calls `reconfigureBase(function->getBitstreamPointer(), vfid)` (only if `en_pr`); the bitstream is read once per function in `cSched::addFunction` ([cSched.hpp](../../../sw/include/coyote/cSched.hpp) ~L242, `readBitstream` -> `cFunc::setBitstreamPointer`, which only stores the pointer). Example 5 calls `reconfigureShell`; example 10 uses `cService` + `cSched`: its README renames the partials to `sw/build_server/app_euclidean_distance.<bin|pdi>` and `app_cosine_similarity.<bin|pdi>` and the server takes `-e bin|pdi` ([server/main.cpp](../../../examples/10_app_reconfiguration/sw/src/server/main.cpp) ~L42). It avoids the crid/vfid bug only because the first `cRcnfg` has crid 0 and `DEFAULT_VFPGA_ID` is 0.

See [../driver.md](../driver.md#reconfiguration) and [../software.md](../software.md#reconfiguration).

## Gotchas and invariants

- **One unmapped buffer at a time / same process.** `alloc_reconfig_buffer` refuses a second allocation until the previous one is `mmap`ed (`curr_buff.n_pages != 0`), and `reconfig_dev_mmap` only succeeds for the process that allocated it.
- **`eos_resetn` naming.** Driver field `reconfig_eost_reset` / RTL `PR_EOST_RESET_REG` actually drives the shell reset (`xresetn`). App PR does not reset the shell.
- **US+ eos timing.** `eos` is a one-pclk-cycle pulse crossed into xclk by `xpm_cdc_single`.
- **`eos_time` counts pclk (200 MHz) cycles**, not xclk.
- Static layer decoupling does not cover the PR channel; do not decouple/reset `sresetn` during PR.
- Shell PR changes `N_REGIONS`/features: the driver re-reads shell config, and stale user-space `cThread` handles on old vFPGAs are invalid after `reconfigureShell`.
- `reconfigureShell` on a build with `en_shell_pblock=0` fails in the driver (`-1`); on Versal builds with `EN_PR=1` the PDI for the shell is not generated (examples/10 README).
- Both `cRcnfg` instances and `cSched` open `/dev/coyote_fpga_<n>_reconfig`; only one reconfiguration is processed at a time per device (`rcnfg_lock`).
- Known defects in this area: [known_issues.md](../known_issues.md) (`REC-*`, `STA-01`, `DRV-04`, `DRV-05`, `DRV-06`, `SW-07`, `SW-08`).

## How to modify / extend

- **Change PR throughput/robustness (driver):** see STA-01, REC-02 and REC-05 (throttle, error-path unlock, wait timeout) in [reconfig_hw.c](../../../driver/src/reconfig/reconfig_hw.c) / [reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c).
- **Add a timeout/error status for Versal PR:** extend `pr_ctrl_versal` to consume `s_qdma_h2c_sts` error bits and expose them in a new `static_slave` status bit (and `PR_STAT_REG`), then read in `reconfig_dev_ioctl`.
- **Change ICAP clock/width:** edit `clk_wiz_0` outputs in [cr_pci.tcl](../../../hw/bd/ultrascale_plus/cr_pci.tcl) (`pclk` 200 MHz), the `pr_*` IPs in [pci_infrastructure.tcl](../../../scripts/ip_inst/pci_infrastructure.tcl); `EOS_TIME` scales with `pclk`. Requires a static rebuild.
- **Add a vFPGA reconfiguration config:** raise `N_CONFIG`, add `VFPGA_C<i>_<j>` entries in `load_apps(...)` ([examples/10_app_reconfiguration/hw/CMakeLists.txt](../../../examples/10_app_reconfiguration/hw/CMakeLists.txt)), ensure `FPLAN_PATH` has pblocks for all `N_REGIONS`.
- **Use app PR from your own code:** `coyote::cRcnfg rcnfg(dev); rcnfg.reconfigureApp(path, vfid);` after ensuring no `cThread` is running on that vFPGA; or register `cFunc`s with bitstream paths and let `cSched` swap.
- **Port to a new device:** need a PR loader path (ICAPE3 or SBI), static `eos` source, `pr_cnfg` bit in the shell, bitgen branch in [bitgen.tcl.in](../../../scripts/impl/bitgen.tcl.in), PCI ids and static checkpoint ([static_top.md](static_top.md#how-to-modify--extend)).
