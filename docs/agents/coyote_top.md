# Coyote — Agent Entry Point

**Purpose:** Orientation map for coding agents working on Coyote (open-source FPGA shell, "OS for FPGAs"). Read this first, then follow links to the layer docs. Code is the source of truth; the published papers/thesis (external, not in this repo) may be stale.

**Supported devices:** AMD Alveo U55C, U280, U250, U200 (UltraScale+, `FPGA_ARCH=ultrascale_plus`) and V80 (Versal, `FPGA_ARCH=versal`). Deprecated/ignore: U50, VCU118, Enzian and everything under [scripts/LEGACY](../../scripts/LEGACY/), [driver/LEGACY](../../driver/LEGACY/), [hw/hdl/LEGACY](../../hw/hdl/LEGACY/), [hw/constraints/LEGACY](../../hw/constraints/LEGACY/).

## What Coyote is / problem it solves
- Data-center FPGAs are usually used as raw devices: each project re-implements host communication, memory controllers, networking and isolation, and that infrastructure is rarely reusable (Coyote v2 paper, §1).
- Coyote provides OS-like abstractions on the FPGA, packaged as a reusable **shell**:
  - **Processes/threads →** vFPGAs (spatially partitioned app regions, optionally reconfigurable) + software `cThread`s (up to `N_CTID_MAX=64` SW threads per vFPGA, distinguished in HW by `ctid`).
  - **Virtual memory →** per-vFPGA MMU/TLBs, shared virtual address space with the host process (host memory, FPGA card memory, GPU memory via dmabuf); TLB misses are served by the driver.
  - **Services →** host DMA, card memory (HBM/DDR, striping), 100G RoCEv2 RDMA, TCP/IP (not buildable as shipped, see glossary), packet sniffer (requires `EN_RDMA`).
  - **Execution environment / ABI →** one *unified user logic interface* per vFPGA (AXI4-Lite CSRs, send/completion queues, AXI4-Stream data to host/card/network, interrupts).
  - **Reconfiguration →** run-time shell reconfiguration (swap services + apps) and app reconfiguration of single vFPGAs, without taking the device offline.
- v2 vs v1 (OSDI'20 / thesis): services moved from the static layer into the reconfigurable shell (three layers), unified interface with multiple parallel streams, multithreading, FPGA-initiated DMA, generic interrupts, QDMA/Versal support, GPU P2P.

## Architecture (three hardware layers + driver + software)
```
Host: application (C++ / pyCoyote)
  libcoyote (sw/): cThread, cRcnfg, cService/cFunc, cConn, cBench
    | ioctl + mmap: /dev/coyote_fpga_<d>_v<vfid>, /dev/coyote_fpga_<d>_reconfig
  coyote_driver.ko (driver/)
    | PCIe: BAR0 static cnfg | BAR1 XDMA/QDMA core | BAR2 shell (axi_main, 256 MB)
FPGA
  STATIC LAYER (fixed, routed+locked checkpoint)
    XDMA (US+) | CIPS/CPM-QDMA + NoC (Versal), DMA wrappers, static_slave,
    PR engine (ICAP | PMC), decouplers, writeback, IRQ fan-in
  SHELL (reconfigurable) = DYNAMIC (SERVICE) LAYER + APPLICATION LAYER
    shell_ctrl_cc: clocks aclk/nclk/uclk + AXI xbar; shell_slave regs
    per region: cnfg_slave(_avx), user_wrapper, MMU (TLBs, credits, arbiters)
    card memory: HBM/DDR, striping, CDMA | network: CMAC + RoCEv2/TCP, sniffer
    vFPGA_0 .. vFPGA_{N_REGIONS-1} (N_REGIONS <= 15)
```
- **Shell** = dynamic + application layer, built against a locked static checkpoint ([hw/checkpoints/](../../hw/checkpoints/)). PR nesting differs per architecture, see the [summary](#ultrascale-vs-versal-summary).
- The static layer does not interpret data. It routes DMA streams, commands and control between PCIe and the shell.

| Layer | Main HW sources | Doc |
|---|---|---|
| Static | [hw/hdl/static/](../../hw/hdl/static/), `hw/bd/*/cr_pci.tcl` ([US+](../../hw/bd/ultrascale_plus/cr_pci.tcl), [Versal](../../hw/bd/versal/cr_pci.tcl)), `static_top_tmplt.txt` ([US+](../../hw/templates/ultrascale_plus/static_top_tmplt.txt), [Versal](../../hw/templates/versal/static_top_tmplt.txt)) | [static/static_top.md](static/static_top.md) → [host_dma.md](static/host_dma.md), [reconfig.md](static/reconfig.md) |
| Shell / dynamic | [hw/templates/common/](../../hw/templates/common/) (`shell_top`, `shell_ctrl`, `dynamic_top`, `cyt_top`, `lynx_pkg`), [hw/hdl/shell/](../../hw/hdl/shell/), `cr_ctrl.tcl` ([US+](../../hw/bd/ultrascale_plus/cr_ctrl.tcl), [Versal](../../hw/bd/versal/cr_ctrl.tcl)) | [shell/shell_top.md](shell/shell_top.md) |
| Service: memory virtualization | [hw/hdl/mmu/](../../hw/hdl/mmu/) | [services/mmu.md](services/mmu.md) |
| Service: card memory | `cr_hbm.tcl` ([US+](../../hw/bd/ultrascale_plus/cr_hbm.tcl), [Versal](../../hw/bd/versal/cr_hbm.tcl)), [cr_ddr.tcl](../../hw/bd/ultrascale_plus/cr_ddr.tcl), [hw/hdl/stripe/](../../hw/hdl/stripe/), [hw/hdl/cdma/](../../hw/hdl/cdma/) | [services/memory.md](services/memory.md) |
| Service: networking | [hw/hdl/network/](../../hw/hdl/network/), [hw/services/network/](../../hw/services/network/) (HLS; git submodule, `git submodule update --init`) | [services/network.md](services/network.md) |
| Application (vFPGA) | [user_wrapper_tmplt.txt](../../hw/templates/common/user_wrapper_tmplt.txt), [user_logic_tmplt.txt](../../hw/templates/common/user_logic_tmplt.txt), [hw/hdl/user/](../../hw/hdl/user/) | [user/user_top.md](user/user_top.md) |
| Driver | [driver/](../../driver/) | [driver.md](driver.md) |
| Software API | [sw/](../../sw/) | [software.md](software.md) |
| Simulation | [sim/](../../sim/) | [simulation.md](simulation.md) |
| Build | [cmake/](../../cmake/), [scripts/](../../scripts/) | [build/build_top.md](build/build_top.md) |
| Constraints / floorplans | [hw/constraints/](../../hw/constraints/) | [build/constraints.md](build/constraints.md) |

## How the layers interact
**Control path (host → vFPGA registers):** `cThread::setCSR/getCSR` and command posting write to the mmap'd per-vFPGA window of BAR2 (`axi_main`) → static `dcpl_static` → `shell_ctrl_cc` crossbar: shell regs `axi_cnfg` (0x0, 32 KB), per-region `axi_ctrl_i` at `0x(10+4i)0000` (256 KB each), AVX `axim_ctrl_i` at `0x(100+4i)0000` (only with `EN_AVX`) → per-region dynamic xbar → vFPGA config regs (`cnfg_slave[_avx].sv`), sTLB/lTLB write ports, user CSRs (`axi_ctrl` of user logic). See [shell/shell_top.md](shell/shell_top.md).

**Host-initiated data path:** `invoke(...)` → `cnfg_slave` → `user_wrapper` → MMU → host DMA / card memory / RDMA → AXI4-Stream to user logic → completion counters → `checkCompleted()`; step by step in [user/user_top.md](user/user_top.md#71-invoke---registers---hardware). User logic never sees host requests on `sq_*`, only their completions on `cq_*`.

**FPGA-initiated data path:** user logic issues `sq_rd/sq_wr` directly (example 07). RDMA remote requests reach user logic on `rq_rd/rq_wr`. Sniffer taps arrive on `axis_rx/tx_sniffer`.

**Interrupt paths (MSI-X):**
- vFPGA *i* → vector *i* → `vfpga_isr` ([vfpga_isr.c](../../driver/src/vfpga/vfpga_isr.c)): page faults and invalidation acks are handled in the kernel. User `notify` → [vfpga_uisr.c](../../driver/src/vfpga/vfpga_uisr.c) → eventfd → `cThread` event thread → user callback (example 04).
- PR completion → reserved vector 15 (`FPGA_RECONFIG_IRQ_VECTOR`) → `reconfig_isr` ([driver/src/reconfig/](../../driver/src/reconfig/)). Vector 15 being reserved is why `N_REGIONS ≤ 15`.

**Reconfiguration path:** `cRcnfg::reconfigureShell(path)` / `reconfigureApp(path, vfid)` ([cRcnfg.hpp](../../sw/include/coyote/cRcnfg.hpp)) → `/dev/coyote_fpga_<d>_reconfig` ioctls → bitstream copied into driver DMA buffers → static layer streams it to ICAP (US+) or the PMC (Versal) (see the [summary](#ultrascale-vs-versal-summary)), with decoupling and `eos_resetn`. Shells can only be swapped if both were linked against the same static checkpoint. Example 10 wraps app reconfiguration in a background `cService` daemon (internal `cSched`) that clients call through `cConn`/`cFunc`. See [static/reconfig.md](static/reconfig.md).

## UltraScale+ vs Versal (summary)
Single cross-layer summary; layer docs link here and only add layer-specific details.

| Aspect | UltraScale+ (u55c/u280/u250/u200) | Versal (v80) |
|---|---|---|
| Boards | u55c, u280, u250, u200 (`FPGA_ARCH=ultrascale_plus`) | v80 (`FPGA_ARCH=versal`) |
| Host DMA | XDMA Gen3x16, descriptor bypass per channel | CPM QDMA Gen4x16 or Gen5x8 (`PCIE_GEN`), `qdma_*_wrapper.sv` |
| Interconnect | AXI interconnect (`cr_ctrl.tcl`), `axi_crossbar` per region | NoC, apertures `0x201_0000_0000` (static cnfg) / `0x208_0000_0000` (shell); SmartConnect (`cr_ctrl.tcl`, `cr_xbar.tcl` per region) |
| PR mechanism | DMA stream → ICAPE3, `.bin` partials (full image `.bit`) | QDMA MM descriptor → PMC `slave_boot_stream` (`pr_ctrl_versal.sv`), `.pdi` for all images, `eos_pmc`; `fix_bif.py` + bootgen for PCIe boot |
| PR nesting | shell PR + nested vFPGA PR | shell PR **or** vFPGA PR (`EN_PR=1` ⇒ `EN_SHELL_PBLOCK=0`, no shell partial) |
| Debug | BSCAN debug bridge/hub, VIOs | AXI debug hub over NoC (only when `EN_PR=0`) |
| Card memory | u55c/u280: HBM IP (u280 DDR needs CMake edit); u250/u200: DDR4 (`N_DDR_CHAN`=1) | HBM via NoC HBM-NMUs at `MEM_OFFSET 0x40_0000_0000`; `HBM_IMPL=unified|block` (block ⇒ SW `mem_block`); DDR unsupported |
| Networking | CMAC 100G, RoCEv2 RDMA, TCP, sniffer | **Not supported**: CMake `FATAL_ERROR` if `EN_RDMA`/`EN_TCP`/`EN_SNIFFER` set |
| Clocks | static fixed by XDMA (250 MHz); `HCLK_F` 450 (u55c/u280) | `SCLK_F` (forced to 333 MHz for shell/app builds); `HCLK_F` 400 |
| Static checkpoint | `static_routed_locked_<dev>.dcp` | `static_routed_locked_v80_gen{4,5}.dcp` (per `PCIE_GEN`) |
| Driver build | `make TARGET_PLATFORM=ultrascale_plus` → `PLATFORM_ULTRASCALE_PLUS` (`pci_xdma.c`) | `TARGET_PLATFORM=versal` → `PLATFORM_VERSAL` (`pci_qdma.c`) |
| Vivado | ≥ 2022.1 | ≥ 2024.2 (older requires rebuilding static) |

Arch-specific code lives in `hw/bd/{ultrascale_plus,versal}/`, `hw/templates/{ultrascale_plus,versal}/`, `{% if cnfg.fpga_arch == ... %}` blocks in common templates, and `#ifdef PLATFORM_*` in the driver.

## Key configuration knobs (CMake, set in an example's `hw/CMakeLists.txt` or with `-D`)
| Group | Parameters |
|---|---|
| Flow | `FDEV_NAME`, `BUILD_STATIC` / `BUILD_SHELL` (default) / `BUILD_APP` |
| Regions / PR | `N_REGIONS` (≤15), `EN_PR`, `N_CONFIG`, `FPLAN_PATH`, `EN_SHELL_PBLOCK` |
| Interfaces | `EN_STRM`/`N_STRM_AXI`, `EN_MEM`/`N_CARD_AXI`, `EN_RDMA`/`N_RDMA_AXI`, `EN_TCP` (broken), `EN_SNIFFER` (needs `EN_RDMA`), `EN_NET_0/1` (QSFP, one at a time) |
| Clocks | `ACLK_F`, `NCLK_F`, `UCLK_F`, `EN_UCLK`, `EN_NCLK`, `SCLK_F`/`PCIE_GEN` (Versal) |
| Features | `EN_AVX`, `EN_WB`, `EN_STATS`, `HBM_SPLIT` (US+), `HBM_IMPL` (Versal), `TLBS_*`/`TLBL_*` (TLB sizes), `EN_CRED_LOCAL/REMOTE` (forced to 1) |

Full table, defaults and targets (`project`, `synth`, `shell`, `link`, `app`, `bitgen`, `sim`): [build/build_top.md](build/build_top.md).

## Fixed limits / IDs
- `N_HCHAN = 3` host DMA channels: data, sync/offload, PR + writeback.
- MSI-X: vector *i* = vFPGA *i*, vector 15 = reconfiguration. Driver `MAX_N_REGIONS 16` vs CMake limit 15.
- `N_CTID_MAX = 64` cThreads per vFPGA ([cDefs.hpp](../../sw/include/coyote/cDefs.hpp)).

## Use cases (from examples)
| Example | Demonstrates | Key features / flags |
|---|---|---|
| [01_hello_world](../../examples/01_hello_world/) | Build flow, data movement, `cThread` | `axis_host_*`, `axis_card_*` (`EN_MEM`), `invoke(LOCAL_*)`, hugepages |
| [02_hls_vadd](../../examples/02_hls_vadd/) | HLS kernel, multiple parallel streams | `N_STRM_AXI>1`, SG `dest` → `tdest` |
| [03_multitenancy](../../examples/03_multitenancy/) | Multiple vFPGAs, user CSRs | `N_REGIONS>1`, `axi_ctrl`, `setCSR` |
| [04_user_interrupts](../../examples/04_user_interrupts/) | HW→SW interrupts | `notify`, uisr callback |
| [05_reconfigure_shell](../../examples/05_reconfigure_shell/) | Run-time shell reconfiguration | sw only; reuses bitstreams of 04 + 02; `cRcnfg::reconfigureShell` |
| [06_gpu_p2p](../../examples/06_gpu_p2p/) | FPGA↔GPU DMA bypassing CPU | sw only; reuses 01 bitstream; dmabuf, `EN_ROCM`/`EN_CUDA` |
| [07_perf_fpga](../../examples/07_perf_fpga/) | FPGA-initiated DMA | user logic drives `sq_*`, consumes `cq_*` |
| [08_multithreading](../../examples/08_multithreading/) | Many SW threads share one vFPGA | `ctid`, pipelined AES |
| [09_perf_rdma](../../examples/09_perf_rdma/) | 100G RoCEv2 (US+ only) | `EN_RDMA`, `cThread::initRDMA` (out-of-band TCP QP exchange), `invoke(REMOTE_RDMA_*)` |
| [10_app_reconfiguration](../../examples/10_app_reconfiguration/) | App reconfiguration + background service | `EN_PR`, `N_CONFIG`, `FPLAN_PATH`, `cService`, `cFunc`, `cConn` |
| [11_packet_sniffer](../../examples/11_packet_sniffer/) | Custom service: capture/filter traffic → pcap (US+ only) | `EN_SNIFFER`, `EN_RDMA`, `EN_MEM` |
| [12_spinal_hdl](../../examples/12_spinal_hdl/) | SpinalHDL user logic | [comp_spinal.tcl.in](../../scripts/apps/comp_spinal.tcl.in) |

Per-example details and a "first vFPGA" recipe: [user/user_top.md](user/user_top.md). Build/run instructions: [examples/README.md](../../examples/README.md).

## Typical workflow
1. HW (examples with a `hw/` dir): `cd examples/<ex>/hw && mkdir build_hw && cd build_hw && cmake ../ -DFDEV_NAME=<u55c|u280|u250|u200|v80> && make project && make bitgen` → `bitstreams/cyt_top.{bit,pdi}`, plus shell/app partials. See [build/build_top.md](build/build_top.md).
2. Driver: `cd driver && make TARGET_PLATFORM=<ultrascale_plus|versal>` → `build/coyote_driver.ko`. Program the FPGA, rescan PCIe ([util/](../../util/)), then `insmod coyote_driver.ko [ip_addr=0x.. mac_addr=0x..]` (hex, networking only). The driver also exposes sysfs for stats and IP/MAC. See [driver.md](driver.md).
3. SW: `cd examples/<ex>/sw && mkdir build_sw && cd build_sw && cmake ../ && make`. See [software.md](software.md).
4. Simulation without HW: see [simulation.md](simulation.md).

## Repository map
| Path | Content |
|---|---|
| [hw/hdl/](../../hw/hdl/) | SystemVerilog: `static`, `shell`, `mmu`, `user`, `network`, `cdma`, `stripe`, `common` (arbiters, CDC, decouplers, queues, RAMs, regs, stats), `pkg` (interfaces, macros) |
| [hw/templates/](../../hw/templates/) | Jinja templates rendered at project creation into top-levels and `lynx_pkg` |
| [hw/bd/](../../hw/bd/) | Block-design Tcl per arch (PCIe/static, ctrl, HBM, DDR) |
| [hw/services/network/](../../hw/services/network/) | HLS network stack (git submodule `fpga-network-stack`, branch `coyote-TCP-RDMA`) |
| [hw/constraints/](../../hw/constraints/) | Per-board static/shell/dynamic XDC + floorplans |
| [hw/checkpoints/](../../hw/checkpoints/) | Routed+locked static DCPs (`static_routed_locked_<dev>.dcp`, v80 gen4/gen5) |
| [cmake/](../../cmake/) | `FindCoyoteHW`, `FindCoyoteSW`, `FindVivado`, `FindVitisHLS` |
| [scripts/](../../scripts/) | Tcl/Python flows: `cr_prjcts`, `synth`, `impl`, `dyn`, `ip_inst`, `apps`, `unit_test` |
| [driver/](../../driver/) | Linux kernel module |
| [sw/](../../sw/) | libcoyote C++ API (`cThread`, `cRcnfg`, `cService`, `cFunc`/`bFunc`, `cConn`, `cBench`, `cOps.hpp`, `cDefs.hpp`) |
| [sim/](../../sim/) | Simulation (SV testbench, sim cThread, Python unit tests) |
| [examples/](../../examples/) | 12 examples (hw + sw) |
| [util/](../../util/) | Programming / hot-reset helper scripts |
| [contrib/](../../contrib/) | Community contributions. `contrib/vm` is Coyote v1 and untested with v2 |

## Known issues
All known defects live in one table, [known_issues.md](known_issues.md) (ID, severity, location, status); layer docs link to it instead of keeping their own lists. Check it before relying on a feature, e.g. card-memory allocator double allocation (MEM-01), driver ctid ownership (DRV-01), non-AVX `cnfg_slave` read-back bugs (REG-01..REG-03).

## Further documentation
- Agent docs (this tree): see the layer table above.
- Human docs (Sphinx): [docs/source/intro/](../source/intro/) (overview, features, quick-start, faq, [v80-notes](../source/intro/v80-notes.rst)), [docs/source/system/](../source/system/) (static, dynamic, application), [docs/source/api/](../source/api/) (driver, sw), [docs/source/developer/](../source/developer/).
- READMEs: [examples/README.md](../../examples/README.md) + per-example READMEs, [driver/README.md](../../driver/README.md), [sw/README.md](../../sw/README.md), [sim/README.md](../../sim/README.md), [sim/unit_test/README.md](../../sim/unit_test/README.md), [hw/templates/README.md](../../hw/templates/README.md), [util/README.md](../../util/README.md), [CONTRIBUTING.md](../../CONTRIBUTING.md).
- Publications (external, not in the repo; may be stale relative to code):
  - D. Korolija, "Abstractions for Modern Heterogeneous Systems", PhD thesis, ETH Zurich (Coyote v1): ch.2 OS abstractions, ch.3 static layer, ch.4 shell/services, ch.5 application layer
  - B. Ramhorst, D. Korolija et al., "Coyote v2: Raising the Level of Abstraction for Data Center FPGAs", arXiv:2504.21538, 2025
  - D. Korolija, T. Roscoe, G. Alonso, "Do OS abstractions make sense on FPGAs?", OSDI 2020
- Python runtime: pyCoyote (external, github.com/fpgasystems/pyCoyote).

## Glossary
| Term | Meaning |
|---|---|
| Static layer | Fixed FPGA region: PCIe/DMA, PR engine, static regs. Never reconfigured at run-time. |
| Shell | Dynamic + application layer, rebuilt per configuration. |
| Service | Shell component shared by vFPGAs (MMU, HBM/DDR, RDMA, TCP, sniffer). |
| cConn / cService | `cService` = background daemon owning a vFPGA (scheduling + app reconfiguration); `cConn` = AF_UNIX client to it (not RDMA). |
| vFPGA / region | One application slot (`vfid`, `N_REGIONS` ≤ 15), one char device each; a PR partition when `EN_PR=1`. |
| App config (`N_CONFIG`) | Alternative user-logic variants per region for app reconfiguration. |
| cThread | SW handle bound to one vFPGA; owns mmaps, memory mappings, event thread; `lock()/unlock()` give an inter-process vFPGA mutex. |
| `ctid` / `hpid` | Coyote thread ID (HW-visible, distinguishes threads sharing a vFPGA) / host process ID. |
| sq / cq / rq | Send queue (requests from user logic), completion queue (acks), receive queue (remote RDMA requests served by user logic). |
| Credits / arbitration | Per-vFPGA credit-based flow control in the user wrapper ([hw/hdl/user/credits](../../hw/hdl/user/credits/); `EN_CRED_LOCAL` always 1, MMU-level `mmu_credits_*` are legacy) and round-robin arbitration across vFPGAs/ctids for shared services. |
| Decoupling | Isolating a partition's interfaces during PR (`dcpl_static`, decouplers in [hw/hdl/common/decouplers](../../hw/hdl/common/decouplers/)). |
| TLB (sTLB / lTLB) | Small-page / large (huge) page translation tables in the MMU, written by the driver. |
| Sync / offload | User-invoked blocking page migration (`invoke(LOCAL_SYNC|LOCAL_OFFLOAD, syncSg)`): sync = card→host, offload = host→card; executed by the driver. |
| Allocation types | `CoyoteAllocType` REG / THP / HPF / GPU for `cThread::getMem`; `userMap` registers existing buffers. |
| Writeback (WB) | `EN_WB=1`: completion counters DMA'd to host memory for `checkCompleted`; otherwise read over MMIO. |
| PR / EOS | Partial reconfiguration / end-of-startup (PR done, releases decoupling/reset). |
| AVX path | `EN_AVX`: 256-bit command/register access via `axim_ctrl` for faster command posting. |
| TCP | `EN_TCP` exists but is **not buildable as shipped** (template/RTL defects, see [services/network.md](services/network.md) and [user/user_top.md](user/user_top.md)); `REMOTE_TCP_SEND` is marked unsupported in [cOps.hpp](../../sw/include/coyote/cOps.hpp); no example enables it. |
| US+ / Versal | `ultrascale_plus` (XDMA) vs `versal` (QDMA + NoC) architecture families. |
