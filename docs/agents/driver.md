# Linux kernel driver (`driver/`)

**Purpose**: Out-of-tree Linux module `coyote_driver.ko` that binds to the Coyote PCIe function, maps the BARs, enables MSI-X, manages the host DMA core (XDMA on UltraScale+, QDMA on Versal), and exposes one char device per vFPGA plus one reconfiguration char device. All user-space access (libcoyote, see [software.md](software.md)) goes through `open/mmap/ioctl` on these nodes.
**Scope**: kernel side only. RTL behaviour is documented in the HW files linked per subsystem below; user-space API usage in [user/user_top.md](user/user_top.md).

## Key files

| Path | Role |
|---|---|
| [driver/Makefile](../../driver/Makefile) | Kbuild wrapper; `TARGET_PLATFORM` selects XDMA vs QDMA objects |
| [driver/include/coyote_defs.h](../../driver/include/coyote_defs.h) | Constants, IOCTL numbers, mmap offsets, HW register structs, all core structs (`bus_driver_data`, `vfpga_dev`, `reconfig_dev`, ...) |
| [driver/src/coyote_driver.c](../../driver/src/coyote_driver.c) | `module_init/exit`, module parameters |
| [driver/src/coyote_setup.c](../../driver/src/coyote_setup.c) | `read_shell_config`, card-memory allocators, vFPGA/reconfig device creation/teardown, sysfs registration |
| [driver/src/coyote_sysfs.c](../../driver/src/coyote_sysfs.c) | sysfs show/store handlers |
| [driver/src/platform/pci_xdma.c](../../driver/src/platform/pci_xdma.c) | US+ `pci_probe/pci_remove`, XDMA engines, MSI-X, `shell_pci_init/remove` |
| [driver/src/platform/pci_qdma.c](../../driver/src/platform/pci_qdma.c) | Versal equivalent (QDMA queues/contexts) |
| [driver/src/platform/pci_util.c](../../driver/src/platform/pci_util.c) | `msix_capable`, `build_vector_reg`, PCIe capability helper |
| [driver/src/vfpga/vfpga_ops.c](../../driver/src/vfpga/vfpga_ops.c) | vFPGA `open/release/ioctl/mmap` |
| [driver/src/vfpga/vfpga_hw.c](../../driver/src/vfpga/vfpga_hw.c) | Register-level ops: ISR regs, TLB entry writes, offload/sync triggers, card alloc |
| [driver/src/vfpga/vfpga_gup.c](../../driver/src/vfpga/vfpga_gup.c) | Page-fault handler, pin/unpin, TLB (un)mapping, migration, dmabuf (GPU) |
| [driver/src/vfpga/vfpga_isr.c](../../driver/src/vfpga/vfpga_isr.c) | per-vFPGA ISR + page-fault / notify workqueue handlers |
| [driver/src/vfpga/vfpga_uisr.c](../../driver/src/vfpga/vfpga_uisr.c) | eventfd registration for user interrupts |
| [driver/src/reconfig/reconfig_ops.c](../../driver/src/reconfig/reconfig_ops.c) | reconfig device `open/release/ioctl/mmap` |
| [driver/src/reconfig/reconfig_hw.c](../../driver/src/reconfig/reconfig_hw.c), [reconfig_mem.c](../../driver/src/reconfig/reconfig_mem.c), [reconfig_isr.c](../../driver/src/reconfig/reconfig_isr.c) | Bitstream DMA trigger, bitstream buffers, completion IRQ |
| [driver/LEGACY/](../../driver/LEGACY/) | Not built: ECI (Enzian) and HMM (`fpga_hmm.c`) code |
| [driver/README.md](../../driver/README.md), [docs/source/api/driver.rst](../source/api/driver.rst) | Human docs (Doxygen via headers) |

**Related**: [software.md](software.md) (user-space counterpart), [coyote_top.md](coyote_top.md), [static/static_top.md](static/static_top.md), [static/host_dma.md](static/host_dma.md), [static/reconfig.md](static/reconfig.md), [shell/shell_top.md](shell/shell_top.md), [services/mmu.md](services/mmu.md), [services/memory.md](services/memory.md), [services/network.md](services/network.md), [user/user_top.md](user/user_top.md), [simulation.md](simulation.md) (no driver in sim), [build/build_top.md](build/build_top.md).

## Build and load

```
cd driver && make TARGET_PLATFORM=<ultrascale_plus|versal>   # default: ultrascale_plus
sudo insmod build/coyote_driver.ko ip_addr=<hex> mac_addr=<hex> [eost=<cycles>]
```
- [Makefile](../../driver/Makefile) copies `src/`, `include/`, `Makefile` into `driver/build/`, runs `make -C $(KERNELDIR) M=build modules` (`KERNELDIR` defaults to `/lib/modules/$(uname -r)/build`), then deletes the copies. Output: `driver/build/coyote_driver.ko`.
- `TARGET_PLATFORM=versal` -> `-DPLATFORM_VERSAL`, objects `pci_qdma.o`; `ultrascale_plus` -> `-DPLATFORM_ULTRASCALE_PLUS`, `pci_xdma.o`. Anything else is a hard `$(error)`. Must match the board (U55C/U280/U250 = US+, V80 = Versal) and the built shell.
- Flags: `-std=gnu11 -Wno-declaration-after-statement`, include dirs `include/{,reconfig,vfpga,platform}`. `HMM_KERNEL` is **not** set by the Makefile (see [HMM](#hmm-mmu-notifiers-and-dmabuf)).
- Kernel version gates (all in-code `LINUX_VERSION_CODE`): `class_create` signature (6.5), `devnode` const (6.0), `pin_user_pages_remote` variants (5.4/5.9/6.5), `eventfd_signal` (6.8), `MODULE_IMPORT_NS("DMA_BUF")` quoting (6.13), dmabuf ioctls only >= 6.2 (otherwise `-1`), `dma_buf_attach_ops.invalidate_mappings` instead of `move_notify` (>= 7.1, [vfpga_gup.c:767](../../driver/src/vfpga/vfpga_gup.c)).

Module parameters ([coyote_driver.c](../../driver/src/coyote_driver.c), all perm `0000`: not exported under `/sys/module/coyote_driver/parameters/`, only settable at `insmod`):

| Param | Type / default | Use |
|---|---|---|
| `ip_addr` | charp `"0B01D4D1"` | hex IP; parsed with `kstrtol(...,16)` in `read_shell_config`, written to `shell_cnfg->net_ip` if RDMA/TCP enabled |
| `mac_addr` | charp `"000A35029DE5"` | hex MAC -> `shell_cnfg->net_mac` |
| `eost` | long `1000000` | end-of-startup cycles written to `stat_cnfg->reconfig_eost` if `en_pr` (needed on U55C: no bitstream-done detect) |
| `en_hmm` | bool `false` | only meaningful with `-DHMM_KERNEL=1` (legacy); see gotchas |

Load order: program static bitstream -> PCIe rescan -> `insmod` (shell registers are read at probe). See [examples/README.md](../../examples/README.md).

## Source layout

```
driver/
  Makefile
  include/  coyote_defs.h  coyote_driver.h  coyote_setup.h  coyote_sysfs.h
            platform/{pci_xdma,pci_qdma,pci_util}.h   reconfig/{reconfig_hw,_isr,_mem,_ops}.h
            vfpga/{vfpga_hw,_isr,_uisr,_gup,_ops}.h      (Doxygen docstrings live in headers)
  src/      coyote_driver.c coyote_setup.c coyote_sysfs.c
            platform/*.c   reconfig/*.c   vfpga/*.c
  LEGACY/   eci/ hmm/   (reference only)
```
Platform split: `pci_xdma.c` / `pci_qdma.c` both define the same symbols (`pci_init/exit`, `pci_probe`, `irq_setup`, `shell_pci_init/remove`, ...); exactly one is linked. Everything else is platform-neutral except `#ifdef PLATFORM_*` blocks in `coyote_defs.h` (card memory geometry, `bus_driver_data` fields) and `vfpga_gup.c`/`vfpga_hw.c` (memory-block selection).

## Probe and remove flow

`coyote_init` ([coyote_driver.c:59](../../driver/src/coyote_driver.c)) -> `pci_init` ([pci_xdma.c:864](../../driver/src/platform/pci_xdma.c)) -> `pci_register_driver` with ID table (vendor `0x10ee`; US+: a discrete list `0x9011, 0x9012, 0x9014, 0x9018, 0x901F, 0x9021, ...`, `0x8011, ...`, `0x7011, ...` - see `pci_ids[]`; Versal: `0xB03F, 0xB13F, 0xB23F, 0xB33F`). `pci_probe` ([pci_xdma.c:553](../../driver/src/platform/pci_xdma.c), [pci_qdma.c:741](../../driver/src/platform/pci_qdma.c)):

1. `devm_kzalloc` `bus_driver_data`; `dev_set_drvdata`.
2. `pci_enable_device`; `assign_device_id` (static counter `current_device++` -> `dev_id`; names `coyote_fpga_<id>` and `coyote_fpga_<id>_reconfig`).
3. PCIe tuning: relaxed ordering, extended tags, `pcie_set_readrq(512)`, `pci_set_master`.
4. `pci_check_msix`: `pci_alloc_irq_vectors(MSIX)` - US+: 6 engine + 16 user = 22 vectors; Versal: `QDMA_N_MAX_IRQ`=16.
5. `pci_request_regions`; `map_bars`: maps the first `CYT_BARS`=3 non-empty BARs (physical BAR0, BAR2, BAR4, 64-bit) into logical `bar[0..2]` = `BAR_STAT_CONFIG` (AXI-Lite static), `BAR_DMA_CONFIG` (XDMA/QDMA regs), `BAR_SHELL_CONFIG` (AXI4 bypass -> shell). Lengths capped to `INT_MAX`. Below, "BAR0/BAR1/BAR2" mean these logical `bar[]` indices.
6. `dma_set_mask_and_coherent(DMA_BIT_MASK(44))` (= `TLB_PADDR_RANGE`).
7-9. **Order differs per platform** (steps 7-9 are not the same code):
   - US+ ([pci_xdma.c:627-645](../../driver/src/platform/pci_xdma.c)): `probe_engines` (scan H2C/C2H channels 0..2, check IDs `0x1fc0/0x1fc1`, start engines) -> `init_spin_locks` -> `ioremap` `stat_cnfg` (BAR0, 32 KB) and `shell_cnfg` (BAR2 offset 0, 32 KB) -> shell reset (`stat_cnfg->reconfig_eost_reset` 0 then 1, `wmb` + sleep).
   - Versal ([pci_qdma.c:815-833](../../driver/src/platform/pci_qdma.c)): `ioremap` `stat_cnfg`/`shell_cnfg` first -> `enable_queues` (PR MM queue 0, 64 H2C streaming queues from idx 1, 64 C2H from idx 256, H2C MM engine; needs `stat_cnfg` because each C2H queue's prefetch tag is forwarded to `stat_cnfg->qdma_pfch_tag`) -> shell reset -> `init_spin_locks`.
10. `read_shell_config` ([coyote_setup.c:28](../../driver/src/coyote_setup.c)) -> see [Shell registers](#shell-registers). Also builds `stlb_meta`/`ltlb_meta`, sets EOST, IP/MAC.
11. `create_sysfs_entry` (`/sys/kernel/coyote_sysfs_<id>/`).
12. `allocate_card_resources` (if `en_mem`).
13. `alloc_reconfig_device` + `setup_reconfig_device`; `alloc_vfpga_devices` + `setup_vfpga_devices` (see below).
14. `irq_setup(..., enable_reconfig_irq=true)`; US+ additionally `reconfig_interrupt_enable` + `vfpga_interrupts_enable`.

`pci_remove` undoes in reverse (disable IRQs, teardown vFPGA devs, reconfig dev, card resources, sysfs, engines/queues, BARs, regions, MSI-X).

**Shell reconfiguration re-init**: `shell_pci_remove` / `shell_pci_init` ([pci_xdma.c:457,523](../../driver/src/platform/pci_xdma.c)) redo steps 10-12 + vFPGA devices + vFPGA IRQs (`enable_reconfig_irq=false`) while keeping BARs, DMA engines, reconfig device and reconfig IRQ alive. **Hazard**: vFPGA devices are freed (`free_vfpga_devices` kfrees the `vfpga_dev` array) while processes may still hold open fds (`file->private_data`), pinned `user_pages` are not released, `hash_init(user_buff_map)` in the re-init wipes the entries (pinned-page leak), and vFPGA ioctls do not take `rcnfg_lock` - close all cThreads before shell reconfiguration. Called from `IOCTL_RECONFIGURE_SHELL`. The shell layout (n_regions, TLB geometry, features) can change, hence everything derived from `shell_cnfg` is rebuilt.

**Per-vFPGA device set-up** (`setup_vfpga_devices`, [coyote_setup.c:378](../../driver/src/coyote_setup.c)), for `i < n_fpga_reg`:
- `vfpga_cnfg_phys_addr = bar_phys[BAR_SHELL_CONFIG] + 0x100000 + i*256KB`; AVX variant at `+ 0x1000000 + i*256KB`.
- `ioremap`: `fpga_lTlb` (+0x0), `fpga_sTlb` (+0x10000), `cnfg_regs` (AVX region if `en_avx`, else +0x30000).
- Allocate `ctid_chunks[N_CTID_MAX=64]`, `pid_array[64]`; init `irq_lock`(spin), `mmu_lock`, `offload_lock`, `sync_lock`, `pid_lock` (mutex), two single-threaded unbound workqueues `wqueue_pfault`, `wqueue_notify`, three waitqueues + atomic flags, `hash_init(user_buff_map[i][ctid])`.
- If `en_wb`: `dma_alloc_coherent(WB_SIZE)`, `set_memory_uc`, program `cnfg_regs->wback[0..3] = wb_phys + j*64*4`.
- `device_create(class, "coyote_fpga_<dev>_v<i>")`, `cdev_init/cdev_add` with `vfpga_ops`; mode `rw-rw-rw-` via `devnode` callback.

## Device nodes, IOCTLs and mmap

| Node | Created by | File ops | Opened by |
|---|---|---|---|
| `/dev/coyote_fpga_<dev>_v<vfid>` | `setup_vfpga_devices` | `vfpga_ops` | `cThread` ([cThread.cpp:130](../../sw/src/cThread.cpp)) |
| `/dev/coyote_fpga_<dev>_reconfig` | `setup_reconfig_device` | `reconfig_ops` | `cRcnfg` ([cRcnfg.cpp:38](../../sw/src/cRcnfg.cpp)) |

`open` stores `vfpga_dev*`/`reconfig_dev*` in `file->private_data`; vFPGA `open` increments `ref_cnt`. `release` frees all leftover per-ctid state **only when `ref_cnt` reaches 0** ([vfpga_ops.c:47](../../driver/src/vfpga/vfpga_ops.c)): `tlb_put_user_pages_ctid`, ctid chunk return, hpid map cleanup.

**IOCTL ABI convention**: user passes a pointer to `uint64_t tmp[MAX_USER_ARGS=32]`; driver does `copy_from_user(tmp, arg, N*8)` for N args and `copy_to_user` for results. Return value `0` = ok; non-zero = failure (note: failed `copy_from_user` returns the positive uncopied byte count, not `-EFAULT`; unknown command returns `1`). `IOCTL_MAP_USER_MEM` may return `99` (`BUFF_NEEDS_EXP_SYNC_RET_CODE`): mapping OK but `dma_need_sync()` true (SWIOTLB/non-coherent) - SW warns only. Numbers must match [cDefs.hpp:47-119](../../sw/include/coyote/cDefs.hpp) exactly (magic `'F'` vFPGA, `'P'` reconfig; all use `unsigned long` as size type).

### vFPGA device (`'F'`) - [vfpga_dev_ioctl](../../driver/src/vfpga/vfpga_ops.c) (`:100`)

| # | Name | Args in (`tmp[]`) -> out | Handler / HW block touched |
|---|---|---|---|
| 1 | `REGISTER_CTID` | `[0]=hpid` -> `[1]=ctid` | allocate ctid from `pid_alloc` free list, `pid_array[ctid]=hpid`, add to `hpid_ctid_map[vfid]` (`pid_lock`); no HW |
| 2 | `UNREGISTER_CTID` | `[0]=ctid` | `tlb_put_user_pages_ctid` -> unmap TLB, free card mem, unpin; return ctid to free list |
| 3 | `REGISTER_EVENTFD` | `[0]=ctid,[1]=efd` | `vfpga_register_eventfd` ([vfpga_uisr.c:34](../../driver/src/vfpga/vfpga_uisr.c)); see [User interrupts](#user-interrupts) |
| 4 | `UNREGISTER_EVENTFD` | `[0]=ctid` | `vfpga_unregister_eventfd` |
| 5 | `MAP_USER_MEM` | `[0]=vaddr,[1]=len,[2]=ctid,[3]=mem_block(-1=any)` | `mmu_lock`; `change_tlb_lock`; `mmu_handler_gup(..., stream=true)`; TLB regs + card allocator; returns 0/99/err |
| 6 | `UNMAP_USER_MEM` | `[0]=vaddr,[1]=ctid` | `tlb_put_user_pages` -> TLB unmap + invalidate (waits for `IRQ_INVLDT`) |
| 7 | `MAP_DMABUF` | `[0]=dmabuf fd,[1]=vaddr,[2]=ctid,[3]=mem_block` | `p2p_attach_dma_buf`; kernel >= 6.2 |
| 8 | `UNMAP_DMABUF` | `[0]=vaddr,[1]=ctid` | `p2p_detach_dma_buf`; driver comment says "fd" but the code (and SW, [cThread.cpp:465](../../sw/src/cThread.cpp)) use the vaddr |
| 9 | `OFFLOAD_REQ` | `[0]=vaddr,[1]=len,[2]=ctid` | `offload_user_pages` -> `trigger_dma_offload` (`offl_*` regs); requires `en_mem` |
| 10 | `SYNC_REQ` | same | `sync_user_pages` -> `trigger_dma_sync` (`sync_*` regs) |
| 11 | `SET_IP_ADDRESS` | `[0]=ip` | `shell_cnfg->net_ip` under `stat_lock`; needs `en_net` |
| 12 | `SET_MAC_ADDRESS` | `[0]=mac` | `shell_cnfg->net_mac`; needs `en_net` |
| 13 | `GET_IP_ADDRESS` | -> `[0]` | cached `bd_data->net_ip_addr` (not re-read from HW) |
| 14 | `GET_MAC_ADDRESS` | -> `[0]` | cached `net_mac_addr` |
| 15 | `READ_SHELL_CONFIG` | -> `[0]` packed flags, `[1]=ctrl_cnfg` raw | bits: 0 avx, 1 wb, 2 strm, 3 mem, 4 pr, 16 rdma, 17 tcp, `[39:32]` n_chan, `[55:48]` n_regions; parsed by `fpgaCnfg::parseCnfg` ([cDefs.hpp:431](../../sw/include/coyote/cDefs.hpp)) |
| 16 | `SHELL_HDMA_STATS` | -> `n_fpga_chan*4` values (stride `N_HDMA_STAT_CH_REGS`=4/ch, but RTL has 3 regs/ch: `shell_slave.sv:137-142`, regs 64-69; sysfs `hstats` uses 3/ch) | `shell_cnfg->hdma_debug[]` (dma_stats.sv) |
| 17 | `SHELL_NET_STATS` | -> 10 values (RTL has 9, regs 96-104); needs `en_net` | `shell_cnfg->net_debug[]`. SW name is `IOCTL_NET_STATS` (same number) |
| 18 | `SET_NOTIFICATION_PROCESSED` | `[0]=ctid` | `mutex_unlock(user_notifier_lock[vfid][ctid])` |
| 19 | `GET_NOTIFICATION_VALUE` | `[0]=ctid` -> `[0]=value` | reads `interrupt_value[vfid][ctid]` |

### Reconfiguration device (`'P'`) - [reconfig_dev_ioctl](../../driver/src/reconfig/reconfig_ops.c) (`:49`)

| # | Name | Args | Handler / HW block |
|---|---|---|---|
| 1 | `ALLOC_HOST_RECONFIG_MEM` | `[0]=n_pages(2 MB),[1]=pid,[2]=crid` | `alloc_reconfig_buffer` ([reconfig_mem.c:28](../../driver/src/reconfig/reconfig_mem.c)): `alloc_pages(order 9)` x n, `dma_map_single`; max `MAX_RECONFIG_BUFF_NUM`=128; only one un-mmapped buffer at a time (`curr_buff`) |
| 2 | `FREE_HOST_RECONFIG_MEM` | `[0]=vaddr,[1]=pid,[2]=crid` | `free_reconfig_buffer` |
| 3 | `RECONFIGURE_APP` | `[0]=vaddr,[1]=len,[2]=pid,[3]=crid,[4]=vfid` | requires `en_pr`; `rcnfg_lock`; `shell_cnfg->reconfig_dcpl_app_set = 1<<vfid`; `reconfigure_start`; wait `wait_rcnfg`; `reconfig_dcpl_app_clr` |
| 4 | `RECONFIGURE_SHELL` | `[0..3]` as above | requires `en_shell_pblock`; `shell_pci_remove`; `stat_cnfg->reconfig_dcpl_set=1`; `reconfigure_start`; wait; pulse `reconfig_eost_reset` 0->1; `reconfig_dcpl_clr=1`; `shell_pci_init` |
| 5 | `PR_CNFG` | -> `[0]=en_pr` | cached |
| 6 | `PR_WB_STATS` | -> `N_HDMA_STAT_CH_REGS` (=4) values (only 4 of the 6 `hdma_debug` regs, [reconfig_ops.c:200](../../driver/src/reconfig/reconfig_ops.c)) | `stat_cnfg->hdma_debug[]` (pr_stats.sv) |

### mmap regions (`vm_pgoff` = byte offset >> 12; all `pgprot_noncached`)

| `vm_pgoff` (SW const) | Device | Maps | Size | Source |
|---|---|---|---|---|
| `0` `MMAP_WB` | vFPGA | writeback buffer (`dma_mmap_coherent`) | `WB_SIZE`=4 blocks x 64 ctid x 4 B = 1 KB | host RAM written by `wback_dma.sv`; layout `[blk*64 + ctid]`, blk 0=RD,1=WR,2=RD_RDMA,3=WR_RDMA |
| `1` `MMAP_CNFG` | vFPGA | non-AVX `cnfg_slave` regs (BAR2 `0x100000+i*0x40000+0x30000`) | 64 KB | [cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv) |
| `2` `MMAP_CNFG_AVX` | vFPGA | AVX `cnfg_slave_avx` regs (BAR2 `0x1000000+i*0x40000`) | 256 KB | [cnfg_slave_avx.sv](../../hw/hdl/shell/cnfg_slave_avx.sv) |
| `3` `MMAP_CTRL` | vFPGA | user CSRs, `axi_ctrl` of user logic (BAR2 `0x100000+i*0x40000+0x20000`) | 64 KB | vFPGA `axi_ctrl` ([user/user_top.md](user/user_top.md)) |
| `0x100` `MMAP_RECONFIG` | reconfig | buffers from `ALLOC_HOST_RECONFIG_MEM`, `remap_pfn_range` per 2 MB page; start aligned up to 2 MB; only valid if `curr_buff.pid == current->pid` | n x 2 MB | host RAM |

TLBs are **not** mmapped; only the driver writes them. Exactly one of the CNFG regions is useful per shell build (`en_avx` is a compile-time HW choice, `EN_AVX` in HW and SW must agree - see [software.md](software.md)).

## Core data structures

All in [coyote_defs.h](../../driver/include/coyote_defs.h).

| Struct (line) | Meaning / lifetime |
|---|---|
| `bus_driver_data` (`:1093`) | One per PCI function; `devm_kzalloc` in probe. Holds `pci_dev`, BARs (`bar[3]`, `bar_phys_addr`, `bar_len`), DMA engine/queue arrays (`#ifdef` platform), parsed shell config (`n_fpga_reg`, `en_*`, `n_host_axi`, `n_card_axi`, `qsfp`, IP/MAC, `eost`), `stat_cnfg` / `shell_cnfg` ioremaps, `vfpga_dev*` array, `reconfig_dev*`, `cyt_kobj`, `stlb_meta`/`ltlb_meta`, `dif_order_page_*`, `n_pages_in_huge`, `stat_lock`, `card_lock`, MSI-X state, `card_lblocks/sblocks`, `card_huge_offs/card_reg_offs` |
| `vfpga_dev` (`:949`) | One per vFPGA (array of `n_fpga_reg`); `cdev`, `id`, `ref_cnt`, ioremaps (`fpga_lTlb`, `fpga_sTlb`, `cnfg_regs`), writeback buffer, ctid allocator (`ctid_chunks`, `pid_alloc`, `pid_array[ctid]=hpid`), locks, workqueues, waitqueues + `wait_*` atomics |
| `reconfig_dev` (`:1051`) | One per card; `cdev`, `rcnfg_lock` (mutex), `irq_lock`, `mem_lock`, `waitqueue_rcnfg`/`wait_rcnfg`, `curr_buff` (staging for alloc->mmap handoff) |
| `tlb_metadata` (`:889`) | Page/key/tag/phys geometry for the small and large TLB; built from `ctrl_cnfg` in `read_shell_config` |
| `user_pages` (`:724`) | One mapped buffer: `vaddr` (**in 4 KB page numbers**, not bytes), `n_pages` (4 KB units even for huge), `huge`, `host` (1 = data currently on host, 0 = on card), `pages[]` (pinned), `hpages[]` (DMA addrs), `cpages[]` (card addrs), dmabuf fields (`buf`, `dma_attach`, `sgt`), `needs_explicit_sync` |
| `pf_aligned_desc` (`:775`) | Page-fault window after alignment to TLB page size |
| `vfpga_irq_pfault` / `vfpga_irq_notify` (`:905`, `:929`) | `kzalloc(GFP_ATOMIC)` in ISR, carries decoded ISR regs + `work_struct`; freed by worker |
| `memory_partition` + `chunk` (`:877`, `:862`) | Card-memory allocator state (circular linked chunk array, `alloc` cursor, `free_chunks`) |
| `reconfig_buff_metadata` (`:795`) | Bitstream staging buffer: `vaddr`, `pid`, `crid`, `pages[]`, `hpages[]` |
| `hpid_ctid_pages`, `ctid_entry` | hpid -> list of ctids (per vFPGA) |

Global tables (module-wide, **shared by all cards**, indexed by vfid - at most `MAX_N_REGIONS`=16): `hpid_ctid_map[vfid][hash]` ([vfpga_ops.c:25](../../driver/src/vfpga/vfpga_ops.c)), `user_buff_map[vfid][ctid][hash]` ([vfpga_gup.c:25](../../driver/src/vfpga/vfpga_gup.c)), `reconfig_buffs_map[hash]` ([reconfig_mem.c](../../driver/src/reconfig/reconfig_mem.c)), `user_notifier/user_notifier_lock/interrupt_value[vfid][ctid]` ([vfpga_uisr.c:25-32](../../driver/src/vfpga/vfpga_uisr.c)).

**Register struct mirrors** (must match RTL byte offsets; both `__packed`):

| Struct | RTL | Notes |
|---|---|---|
| `cyt_stat_cnfg_regs` (`:517`, 32-bit regs at BAR0; struct covers regs 0-17 of the RTL's `N_REGS`=32) | [static_slave.sv](../../hw/hdl/static/static_slave.sv) (`PROBE_REG`=0, `PR_CTRL`=1, `PR_STAT`=2, `PR_CNT`=3, `PR_ADDR_LOW/HIGH`=4/5, `PR_LEN`=6, `PR_EOST`=7, `PR_EOST_RESET`=8, `PR_DCPL_SET/CLR`=9/10, `hdma_debug[6]`=11..16, `QDMA_PFCH_TAG`=17) | 32 registers total |
| `cyt_shell_cnfg_regs` (`:541`, 64-bit regs at BAR2+0) | [shell_slave.sv](../../hw/hdl/shell/shell_slave.sv): probe, n_chan, n_regions, ctrl_cnfg, mem_cnfg, pr_cnfg, shell_pblock_cnfg, rdma_cnfg, tcp_cnfg, `dcpl_app_set/clr` (regs 0-10); `net_ip`=32, `net_mac`=33, `tcp_offs`=34, `rdma_offs`=35; `hdma_debug[12]`=64..75; `net_debug[10]`=96.. | padding arrays (`reserved_*`) encode the gaps |
| `vfpga_cnfg_regs` (`:572`, 64-bit fields) | [cnfg_slave_avx.sv](../../hw/hdl/shell/cnfg_slave_avx.sv) and [cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv) | **Same byte layout for both**: AVX regs are 32 B wide (reg n at `32n`), legacy regs 8 B (reg `4n` at `32n`). `ctrl`@0 `vaddr_rd`@8 `ctrl_2`@16 `vaddr_wr`@24 \| `isr_ctrl`@32 (16-bit; `isr_meta_1`=type@34, `meta_2`@36, `meta_3`=stream/wr@38) `isr_pid`@40 `isr_vaddr`@48 `isr_len`@56 \| `stat_sent[4]`@64 \| `stat_irq[4]`@96 \| `wback[4]`@128 \| `offl_ctrl/host_offs/card_offs/len`@160 \| `offl_stat`@192 \| `sync_ctrl/...`@224 |

Changing a register in RTL requires the matching struct edit here and the `CnfgAvxRegs`/`CnfgLegRegs` enums in [cDefs.hpp](../../sw/include/coyote/cDefs.hpp).

## Interrupt flow

- MSI-X vector `i` (0..`n_fpga_reg-1`) -> `vfpga_isr(dev=&vfpga_dev[i])`; vector `FPGA_RECONFIG_IRQ_VECTOR`=15 -> `reconfig_isr`. Therefore at most 15 vFPGAs fit with PR IRQ enabled. Registered in `irq_setup` ([pci_xdma.c:87](../../driver/src/platform/pci_xdma.c)); US+ also programs XDMA `user_msi_vector[0..3]` with identity mapping `build_vector_reg(0,1,2,3)...(12..15)` (`write_msix_vectors`, only in `pci_probe`, not on shell re-init) and enables user IRQ lines (`0x7fff` vFPGAs, `0x8000` reconfig). Versal: vectors routed by [qdma_interrupt_wrapper.sv](../../hw/hdl/static/qdma_interrupt_wrapper.sv); no enable write.
- `vfpga_isr` ([vfpga_isr.c:24](../../driver/src/vfpga/vfpga_isr.c)) holds `irq_lock` (spin, irqsave), reads `isr_meta_1` (type; values from `lynx_pkg`: `IRQ_OFFL`=0, `IRQ_SYNC`=1, `IRQ_INVLDT`=2, `IRQ_PFAULT`=3, `IRQ_NOTIFY`=4 = `IRQ_DMA_OFFL` ... `IRQ_NOTIFY` in `coyote_defs.h`), then:

| Type | ISR action | Consumer |
|---|---|---|
| `IRQ_DMA_OFFL` | `wait_offload=SET`, wake `waitqueue_offload` | `migrate_to_card` |
| `IRQ_DMA_SYNC` | `wait_sync=SET`, wake | `migrate_to_host` |
| `IRQ_INVLDT` | `wait_invldt=SET`, wake | `tlb_unmap_gup` |
| `IRQ_PFAULT` | decode regs (`read_irq_pfault`), `queue_work(wqueue_pfault, vfpga_pfault_handler)` | [MMU and page faults](#mmu-and-page-faults) |
| `IRQ_NOTIFY` | decode (`read_irq_notify`), `queue_work(wqueue_notify, vfpga_notify_handler)` | [User interrupts](#user-interrupts) |

  then always `clear_irq` (`isr_ctrl = 0x1`) before unlock. Workqueues are `WQ_UNBOUND|WQ_MEM_RECLAIM`, `max_active=1` => per-vFPGA serialisation. Note both workqueues are allocated with the same name string `coyote_driver`.
- `reconfig_isr` ([reconfig_isr.c:24](../../driver/src/reconfig/reconfig_isr.c)): `wait_rcnfg=SET`, wake `waitqueue_rcnfg`, write `stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_IRQ_CLR_PENDING (0x4)`.
- ISR control word written to `isr_ctrl` ([coyote_defs.h:302-309](../../driver/include/coyote_defs.h)): `0x1` clear pending; `0x2`/`0x4` restart rd/wr as **drop**; `0xa`/`0xc` = restart + success (bit 3); `0x10` invalidation, `0x30` + last, `0x50` = invalidation command with lock bit (bit 6, used as TLB lock toggle by `change_tlb_lock`). Bits map to `ISR_*` localparams in [cnfg_slave_avx.sv:290-298](../../hw/hdl/shell/cnfg_slave_avx.sv).

## Static layer & host DMA

**RTL counterpart**: static layer + XDMA/QDMA wrappers: [static/static_top.md](static/static_top.md), [static/host_dma.md](static/host_dma.md) (`xdma_wrapper.sv`, `qdma_*_wrapper.sv`, `wback_dma.sv`, `static_slave.sv`).
- Driver files: [pci_xdma.c](../../driver/src/platform/pci_xdma.c) (US+), [pci_qdma.c](../../driver/src/platform/pci_qdma.c) (Versal), [pci_util.c](../../driver/src/platform/pci_util.c); structs `xdma_engine`, `xdma_engine_regs`, `xdma_interrupt_regs`, `qdma_queue`.
- The driver does **not** issue DMA descriptors for user data. Data moves are started by SW writing commands into the vFPGA `ctrl` register (see [Shell registers](#shell-registers)); the host DMA core is driven by RTL. The driver only (a) initialises the core (US+: engine `ctrl` run bits + completion interrupt enables; Versal: queue contexts via `QDMA_CTX_*` regs, `0xab0` C2H buffer size, and the **C2H prefetch-tag handoff**: for each C2H queue the driver reads the tag from `QDMA_C2H_PFCH_BYP_{QID,TAG}_REG` and writes `(1<<31)|(qid<<8)|tag` into `stat_cnfg->qdma_pfch_tag` (static_slave reg 17, [pci_qdma.c:405-420](../../driver/src/platform/pci_qdma.c)) so `qdma_wr_wrapper` can use it), (b) uses it indirectly for PR bitstream and writeback (static layer channel 2), (c) reads debug counters.
- Logical BAR roles: `bar[BAR_STAT_CONFIG]` -> `stat_cnfg`, `bar[BAR_DMA_CONFIG]` -> DMA IP regs, `bar[BAR_SHELL_CONFIG]` -> shell (see probe). XDMA channel/engine constants: `XDMA_*` in [coyote_defs.h:130-160](../../driver/include/coyote_defs.h); QDMA: `QDMA_N_ACTIVE_QUEUES`=64 (<= 64 due to bypass prefetch tags), `QDMA_PR_QUEUE_IDX`=0.
- Writeback (RTL names `WBACK_LCL_RD/LCL_WR/RMT_RD/RMT_WR`): `en_wb` shell flag -> coherent UC buffer per vFPGA, base address programmed into `wback[]`; SW polls it via mmap offset 0 ([cThread::checkCompleted](../../sw/src/cThread.cpp)). HW: `wback_dma.sv`.
- Stats (see stride mismatches in the ioctl table): `IOCTL_SHELL_HDMA_STATS`, `IOCTL_PR_WB_STATS`, sysfs `cyt_attr_hstats`, `cyt_attr_prstats`, `cyt_attr_engines` (US+), `cyt_attr_qdma_debug_regs` (Versal).
- SW side: [software.md#static-layer--host-dma](software.md#static-layer--host-dma).

## Reconfiguration

**RTL counterpart**: ICAP/PMC reconfiguration controller, decouplers, EOS: [static/reconfig.md](static/reconfig.md) (`static_slave.sv` PR regs, `dcpl_static.sv`, `pr_ctrl_versal.sv`); app decoupling in `shell_slave.sv`.
- Files: [reconfig_ops.c](../../driver/src/reconfig/reconfig_ops.c), [reconfig_mem.c](../../driver/src/reconfig/reconfig_mem.c), [reconfig_hw.c](../../driver/src/reconfig/reconfig_hw.c), [reconfig_isr.c](../../driver/src/reconfig/reconfig_isr.c).
- Sequence (SW `cRcnfg`): `ALLOC_HOST_RECONFIG_MEM` -> `mmap(MMAP_RECONFIG)` -> user `memcpy` bitstream -> `RECONFIGURE_{APP,SHELL}` -> (blocks) -> `munmap` + `FREE_HOST_RECONFIG_MEM`.
- `reconfigure_start` ([reconfig_hw.c:24](../../driver/src/reconfig/reconfig_hw.c)): finds buffer by `(vaddr, pid, crid)` in `reconfig_buffs_map`; for each 2 MB page writes `reconfig_addr_low/high`, `reconfig_len`, then `reconfig_ctrl = 0x1` (middle) or `0x7` (last); intended throttle polls `reconfig_ctrl` (outstanding count) against `RECONFIG_THRESHOLD`=32, but `cmd_sent` is only incremented for the final partial page ([reconfig_hw.c:79](../../driver/src/reconfig/reconfig_hw.c)), never in the full-page loop (`:46-63`), so full 2 MB pages are never throttled. Completion = reconfig IRQ (vector 15) -> `wait_rcnfg`.
- App path (`en_pr`): decouple vFPGA `1<<vfid` via `shell_cnfg->reconfig_dcpl_app_set`; shell path (`en_shell_pblock`): `shell_pci_remove`, decouple whole shell via `stat_cnfg->reconfig_dcpl_set`, after completion reset EOST (`reconfig_eost_reset`) and `shell_pci_init` (re-reads shell config, recreates `/dev/coyote_fpga_*_v*` nodes - processes holding old fds are invalid).
- US+ has no "done" signal from ICAP: `eost` clocks delay the shell reset release (`reconfig_eost`).
- SW: [software.md#reconfiguration](software.md#reconfiguration).

## Shell registers

**RTL counterpart**: [shell/shell_top.md](shell/shell_top.md) (`shell_slave.sv`, `cnfg_slave*.sv`, address map `shell_ctrl`).
- `read_shell_config` decodes `shell_cnfg->ctrl_cnfg` ([coyote_defs.h:236-272](../../driver/include/coyote_defs.h) masks): `en_avx` bit0, `en_wb` bit3, small TLB order[7:4]/assoc[11:8], large TLB order[15:12]/assoc[19:16], small page shift [25:20] (must equal `PAGE_SHIFT`, `BUG_ON` otherwise), large page shift [31:26]; `mem_cnfg`: `en_strm` bit0, `en_mem` bit1, `n_host_axi` [7:2], `n_card_axi` [13:8], `en_block_mem` bit14; `pr_cnfg` bit0; `shell_pblock_cnfg` bit0; `rdma_cnfg` bit0 + `qsfp` bit1; `tcp_cnfg` bit0.
- Per-vFPGA data-path registers are driven **directly from user space** through the mmapped CNFG region: `ctrl` (command post), `stat_*`, writeback, RDMA ctx/conn, ARP. The driver itself uses `vfpga_cnfg_regs` only for ISR handling (`isr_*`), offload/sync (`offl_*`, `sync_*`), and writeback base programming.
- Command encoding (done in SW, `postCmd`): see [software.md#shell-registers](software.md#shell-registers).
- sysfs `cyt_attr_cnfg` dumps the parsed config. `read_shell_config` re-applies the `eost` module param on every shell re-init, discarding a value set via sysfs, and re-`kzalloc`s `stlb_meta`/`ltlb_meta` without freeing the old ones.

## MMU and page faults

**RTL counterpart**: [services/mmu.md](services/mmu.md) (`hw/hdl/mmu/*`: `tlb_controller.sv`, `tlb_slave_axil.sv`, `mmu_arbiter_isr.sv`), ISR regs in `cnfg_slave*.sv`.
- Memory model: driver pins pages (`pin_user_pages_remote(FOLL_WRITE|FOLL_LONGTERM)`, [vfpga_gup.c:301](../../driver/src/vfpga/vfpga_gup.c)), obtains DMA addresses via `dma_map_single` (IOMMU-aware; `dma_need_sync` -> `needs_explicit_sync` -> ret 99), optionally allocates card pages, then writes TLB entries. Because pages are pinned long-term, no MMU notifier is needed (see HMM section).
- TLB write: `create_tlb_mapping` ([vfpga_hw.c:80](../../driver/src/vfpga/vfpga_hw.c)) writes two 64-bit words to `fpga_{s,l}Tlb[0..1]`: `[0]= phys>>shift | hpid<<32`, `[1]= key | tag | ctid(6b) | host(2b) | valid | phys`. `key = (vaddr>>(shift-12)) & key_mask`, `tag = rest`. Unmap = same words with valid=0. Small = 4 KB (`stlb_meta`), large = 2 MB (`ltlb_meta`) typically.
- Page-fault path: HW miss -> `isr_*` regs + MSI-X -> `vfpga_isr` (`IRQ_PFAULT`) -> `vfpga_pfault_handler` ([vfpga_isr.c:156](../../driver/src/vfpga/vfpga_isr.c)): `mutex_lock(mmu_lock)`, `hpid = pid_array[ctid]`, `mmu_handler_gup(vaddr, len, ctid, stream, hpid, mem_block=-1)`. On Versal with `en_block_mem`, `mem_block=-1` yields `-EINVAL` in `tlb_get_user_pages` ([vfpga_gup.c:407-418](../../driver/src/vfpga/vfpga_gup.c)): the fault is dropped for buffers that were not pre-mapped with `userMap(..., mem_block)`. On success `restart_mmu` (`isr_pid=ctid; isr_ctrl=0xa|0xc`), else `drop_irq_pfault`.
- `mmu_handler_gup` ([vfpga_gup.c:27](../../driver/src/vfpga/vfpga_gup.c)): finds task/mm via `find_vpid(hpid)`, `is_vm_hugetlb_page(find_vma())` to choose small/large TLB, aligns window (`pf_desc`), `map_present` (existing `user_pages` hit/overlap trims `n_pages`):
  - hit + stream HOST + data on host -> `tlb_map_gup`; hit + HOST + data on card -> `tlb_unmap_gup`, `migrate_to_host` (sync DMA), map; hit + CARD + data on host -> `migrate_to_card` (offload DMA), map.
  - miss -> `tlb_get_user_pages` (pin, DMA-map, card alloc, insert in `user_buff_map`), then map (stream=HOST) or migrate to card first (stream=CARD).
  - `tlb_map_gup` maps at most `MAX_N_MAP_PAGES`=256 entries per fault; HW re-faults for the rest. For regular pages it coalesces runs of `n_pages_in_huge` physically contiguous, 2 MB-aligned pages into one large-TLB entry.
- Unmap/invalidate: `tlb_unmap_gup` writes invalid entries, then `invalidate_tlb_entry` per (huge) page (last one carries `...INVLDT_LAST`), then `wait_event_interruptible(waitqueue_invldt)` for `IRQ_INVLDT`. Used by `UNMAP_USER_MEM`, migrations, ctid teardown.
- `change_tlb_lock` (writes `isr_ctrl = 0x50`, an invalidation command with the lock bit) brackets MAP/UNMAP/DMABUF ioctls (called twice: lock, unlock) so the MMU is quiesced while the driver writes TLB entries; exact HW semantics in [services/mmu.md](services/mmu.md).
- Explicit migration: `IOCTL_OFFLOAD_REQ` / `SYNC_REQ` -> `offload_user_pages`/`sync_user_pages` -> unmap, flip `user_pg->host`, `migrate_to_{card,host}` (`offload_lock`/`sync_lock`, `trigger_dma_{offload,sync}`: per-page `offl_host_offs/card_offs/ctrl` writes with `DMA_THRSH`=32 outstanding), remap.
- SW: `cThread::userMap/userUnmap/getMem/invoke(syncSg)` -> [software.md#mmu-and-page-faults](software.md#mmu-and-page-faults).

## Card memory

**RTL counterpart**: [services/memory.md](services/memory.md) (HBM/DDR, striping, `hw/hdl/cdma`, `hw/hdl/stripe`).
- Only if `en_mem`. Allocators created in `allocate_card_resources` ([coyote_setup.c:136](../../driver/src/coyote_setup.c)); `card_sblocks[]`/`card_lblocks[]` are arrays of `N_MEM_BLOCKS` `memory_partition`, each a circular list of `N_SMALL_CHUNKS`/`N_LARGE_CHUNKS` 4 KB `chunk`s.

| | US+ | Versal |
|---|---|---|
| `N_MEM_BLOCKS` | 1 | 64 (HBM pseudo-channel ports) |
| `MEM_START` | 256 MB | 256 GB |
| chunks per partition (small / large) | 1 Mi / 1 Mi (4 GB each) | 64 Ki / 64 Ki (256 MB each) |
| `MEM_BLOCK_SIZE` | unused | 512 MB |

- Address = `(chunk_id << 12) + (card_reg_offs=0 | card_huge_offs=N_SMALL_CHUNKS*4KB) + block*MEM_BLOCK_SIZE + MEM_START` ([vfpga_hw.c:238,253](../../driver/src/vfpga/vfpga_hw.c)). Huge-page buffers are also allocated as 4 KB chunks (n_pages is always in 4 KB units). **No alignment/contiguity guarantee**: allocation walks `alloc->next` without checking `used` (`:237-243,252-258`) and `free_card_memory` moves the cursor to the freed chunk (`:291,312`), so after frees the allocator can hand out chunks that are still in use (double allocation) and 2 MB-aligned contiguous runs needed for large-TLB coalescing are not guaranteed.
- `mem_block` (ioctl arg `[3]`, `CoyoteAlloc.mem_block`): ignored on US+. Versal: `en_block_mem` => required; remapped `target = DIV_ROUND_CLOSEST(N_MEM_BLOCKS*(vfid*n_card_axi+mem_block+1), n_regions*n_card_axi+1) - 1` (mirrors the PC spacing in `cr_hbm.tcl`); unified mode allows `-1` (first partition with free chunks).
- `free_card_memory` sets the `alloc` cursor to each freed chunk. Guard: `card_lock` spinlock.
- SW: `CoyoteAlloc.mem_block`, `LOCAL_OFFLOAD/LOCAL_SYNC`, `STRM_CARD` -> [software.md#card-memory](software.md#card-memory).

## Networking

**RTL counterpart**: [services/network.md](services/network.md) (CMAC, ARP, RoCE/RDMA, TCP; regs `NET_*`, `RDMA_*`, `TCP_*` in `cnfg_slave*.sv`, `NET_IPADDR_REG`/`NET_MACADDR_REG` in `shell_slave.sv`).
- Driver involvement is limited to IP/MAC and statistics (RTL regs `NET_IPADDR_REG`=32, `NET_MACADDR_REG`=33, stats `NET_STAT_*`=96-104 in `shell_slave.sv`): module params -> `read_shell_config`; `IOCTL_{SET,GET}_{IP,MAC}_ADDRESS` (the setters write `shell_cnfg->net_ip/net_mac`, cached copies returned by getters); sysfs `cyt_attr_ip/mac` (rw), `cyt_attr_nstats` (RX/TX, ARP, ICMP, TCP, RoCE, IBV, PSN drops, retransmissions, TCP sessions), `IOCTL_SHELL_NET_STATS`.
- QP context / connection context / ARP lookups are written by user space directly into mmapped `cnfg_slave*` registers (`cThread::writeQpContext`, `doArpLookup`); the driver is not on that path. `en_rdma`/`en_tcp`/`qsfp` come from `rdma_cnfg`/`tcp_cnfg`.
- `qsfp` (port index) is read from `rdma_cnfg` bit 1; IP/MAC module params apply to every card the module probes.
- SW: `cThread::initRDMA` etc. -> [software.md#networking](software.md#networking).

## User interrupts

**RTL counterpart**: `notify` interface of the vFPGA ([user/user_top.md](user/user_top.md), [shell/shell_top.md](shell/shell_top.md)), raised via `cnfg_slave*.sv` (`IRQ_NOTIFY`, pid + value fields).
- Flow: user logic `notify` -> ISR regs set (`isr_pid` low 32 = ctid, `isr_len` high 32 = value; RTL: AVX `ISR_REG` fields `ISR_PID_OFFS`/`ISR_VAL_OFFS`, legacy `ISR_HPID_PID_MISS_REG`=5 and `ISR_VAL_LEN_MISS_REG`=7; counted in `STAT_NOTIFY`) -> MSI-X -> `vfpga_isr` -> `vfpga_notify_handler` ([vfpga_isr.c:103](../../driver/src/vfpga/vfpga_isr.c)): `mutex_lock(user_notifier_lock[vfid][ctid])` -> drop if no eventfd registered (unlocks) -> `interrupt_value[vfid][ctid]=value` -> `eventfd_signal(user_notifier[vfid][ctid])` (kernel >= 6.8 increments by 1 only; value no longer travels through the eventfd).
- The mutex stays **locked** until SW calls `IOCTL_SET_NOTIFICATION_PROCESSED` (a deliberate cross-context unlock) - this serialises notifications per cThread and prevents overwriting `interrupt_value`. User space: epoll on eventfd -> `IOCTL_GET_NOTIFICATION_VALUE` -> callback -> `IOCTL_SET_NOTIFICATION_PROCESSED` ([cThread.cpp:48](../../sw/src/cThread.cpp), eventHandler).
- Hazards: the single-threaded `wqueue_notify` blocks on `user_notifier_lock` of one slow cThread, delaying notifications for all cThreads of that vFPGA (head-of-line blocking); unlocking a mutex from a different task violates the mutex API (works in practice); the lock is only `mutex_init`ed in `REGISTER_EVENTFD`, so notifications/ioctls before registration touch an uninitialised mutex; `GET_NOTIFICATION_VALUE` copies only 4 bytes back.
- `vfpga_register_eventfd` ([vfpga_uisr.c:34](../../driver/src/vfpga/vfpga_uisr.c)) `mutex_init`s the lock and `eventfd_ctx_fdget`s the user fd.
- Example: [examples/04_user_interrupts](../../examples/04_user_interrupts/).
- SW: [software.md#user-interrupts](software.md#user-interrupts).

## Sysfs

Directory `/sys/kernel/coyote_sysfs_<dev_id>/` created by `create_sysfs_entry` ([coyote_setup.c:285](../../driver/src/coyote_setup.c)); attribute table in `coyote_setup.c:247-279`, handlers in [coyote_sysfs.c](../../driver/src/coyote_sysfs.c). All dumps are `cat`-able.

| File | Mode | Content |
|---|---|---|
| `cyt_attr_ip`, `cyt_attr_mac` | rw | network address (`sscanf` hex; stores take no `stat_lock` and do not check `en_net`) |
| `cyt_attr_eost` | rw | EOST cycles |
| `cyt_attr_nstats` | r | network counters |
| `cyt_attr_hstats` | r | host DMA stats per channel (requests/completions/beats H2C/C2H) |
| `cyt_attr_prstats` | r | PR + writeback DMA channel stats |
| `cyt_attr_cnfg` | r | parsed shell config incl. TLB geometry |
| `cyt_attr_engines` | r | US+ only, XDMA engine registers |
| `cyt_attr_qdma_debug_regs` | r | Versal only |

## HMM, MMU notifiers and dmabuf

- **HMM**: removed from the default build. `HMM_KERNEL` is only checked inside `#ifdef`s (struct fields, ioctl/ISR branches, `mmu_interval_notifier_insert` in `REGISTER_CTID`); implementations (`mmu_handler_hmm`, `cyt_interval_invalidate`, `fpga_migrate_to_{host,card}`, `tlb_map_hmm`, `free_card_mem`) live only in [driver/LEGACY/hmm/fpga_hmm.c](../../driver/LEGACY/hmm/fpga_hmm.c) and are not compiled; the `en_hmm` parameter and `<linux/hmm.h>`/`<linux/mmu_notifier.h>` includes remain. Design intent (Korolija PhD thesis, §4.2.5-4.2.7, external): unified virtual memory where the host MMU notifier invalidates FPGA TLB entries when host pages change (`mmu_interval_notifier`), and pages migrate on demand between host and card memory (`fpga_migrate_to_{host,card}`).
- **MMU notifiers / invalidation**: not used in the live path. GUP pinning (`FOLL_LONGTERM`) prevents page migration/swap. Consequence: if user space `munmap`s/frees a mapped buffer without `userUnmap`, stale TLB entries remain until the cThread is destroyed; SW (`cThread::freeMem`) always unmaps first.
- **dmabuf / GPU P2P** (kernel >= 6.2): `IOCTL_MAP_DMABUF` -> `p2p_attach_dma_buf` ([vfpga_gup.c:825](../../driver/src/vfpga/vfpga_gup.c)): `dma_buf_get(fd)` -> `dma_buf_dynamic_attach(..., gpu_importer_ops{allow_peer2peer, move_notify})` -> `dma_buf_map_attachment` under `dma_resv_lock` -> fills `hpages[]` from the sg table (4 KB granularity, `huge=false`) -> optional card pages -> TLB map. `p2p_move_notify` (`:774`) re-maps on GPU memory moves (unmap TLB, remap sgt, rewrite hpages, map TLB). `p2p_detach_dma_buf` (`:992`) is the inverse; `tlb_put_user_pages*` also handle dmabuf entries. SW builds: `-DEN_CUDA=1` (`cuMemGetHandleForAddressRange`) or `-DEN_ROCM=1` (`hsa_amd_portable_export_dmabuf`) in `cThread::userMap` ([software.md](software.md)); example [06_gpu_p2p](../../examples/06_gpu_p2p/).

## Locking

| Lock | Type | Protects |
|---|---|---|
| `vfpga_dev.irq_lock` | spinlock (irqsave) | ISR body per vFPGA |
| `vfpga_dev.pid_lock` | mutex | ctid alloc/free, hpid map |
| `vfpga_dev.mmu_lock` | mutex | TLB writes, `user_buff_map`, taken by MAP/UNMAP/DMABUF ioctls **and** page-fault worker |
| `vfpga_dev.offload_lock` / `sync_lock` | mutex | one migration DMA in flight per direction |
| `user_notifier_lock[vfid][ctid]` | mutex | one outstanding notification per cThread (unlocked by ioctl) |
| `bus_driver_data.stat_lock` | spinlock | IP/MAC ioctl setters |
| `bus_driver_data.card_lock` | spinlock | card chunk allocators |
| `reconfig_dev.rcnfg_lock` | mutex | one reconfiguration at a time (also guards shell re-init) |
| `reconfig_dev.mem_lock` / `irq_lock` | spinlock | bitstream buffer alloc/mmap; reconfig ISR |
| hardware | - | `change_tlb_lock` (ISR reg bit 6) guards MMU vs. driver TLB writes |

Completion waits use waitqueue + atomic flag (`wait_offload|sync|invldt|rcnfg`), set in the ISR, cleared by the waiter. Waits use `wait_event_interruptible` without checking the return value (signals can break the handshake).

## Gotchas and known issues

Invariants:
- `ioctl` numbers/args: three copies must agree - [coyote_defs.h](../../driver/include/coyote_defs.h), [cDefs.hpp](../../sw/include/coyote/cDefs.hpp), and any sim stub ([simulation.md](simulation.md)). Arg order is positional in `uint64_t tmp[]`.
- `vfpga_cnfg_regs` / `cyt_*_cnfg_regs` offsets must match RTL; `user_pages.vaddr` is a page number (`vaddr >> 12`), `n_pages` counts 4 KB pages; the hash key is the *start* page, so lookups by an interior address miss (`vfpga_gup.c:525,701,740`).
- `en_avx` is decided by the shell build; SW `EN_AVX` only selects which region SW maps and how it writes (see commit 97b26119, [software.md](software.md)).
- Max 64 cThreads per vFPGA (`N_CTID_MAX`, 6-bit PID field), max 16 vFPGAs (`MAX_N_REGIONS`), 15 with the PR IRQ on vector 15. Small page size must equal the kernel `PAGE_SIZE` (`BUG_ON`).
- Global tables are not per-card (`hpid_ctid_map`, `user_buff_map`, `user_notifier*`); `ref_cnt` is an unlocked `uint32_t`; per-ctid cleanup runs only when the *last* fd closes (a crashed process's pages stay pinned while others hold the device open).
- Security posture: nodes are mode 0666; `ctid`/`hpid` come from user space with no bounds/ownership checks (`pid_array[ctid]`, `user_notifier[vfid][ctid]`, `user_buff_map`; `REGISTER_EVENTFD` with `ctid >= 64` writes out of bounds; `REGISTER_CTID` trusts the given hpid).
- `cRcnfg` passes `getpid()` (TGID) but `reconfig_dev_mmap` compares with `current->pid` (TID, [reconfig_ops.c:233](../../driver/src/reconfig/reconfig_ops.c)): bitstream mmap fails from a non-main thread.
- `en_hmm=1` without `-DHMM_KERNEL`: `OFFLOAD_REQ`, `SYNC_REQ`, `UNMAP_USER_MEM`, `UNMAP_DMABUF` silently become no-ops (guarded by `!en_hmm`).

Bugs and hazards found while reading (not fixed):

| File:line | Symptom |
|---|---|
| [reconfig_ops.c:177](../../driver/src/reconfig/reconfig_ops.c) | app re-couple uses `1 << tmp[3]` (crid) instead of `tmp[4]` (vfid, used at `:163`) |
| [reconfig_ops.c:121,169](../../driver/src/reconfig/reconfig_ops.c) | early `return -1` after `reconfigure_start` failure leaves `rcnfg_lock` held (shell path has already run `shell_pci_remove`) |
| [reconfig_hw.c:46-63,79](../../driver/src/reconfig/reconfig_hw.c) | `cmd_sent` only incremented for the partial last page: throttle dead for full pages |
| [reconfig_mem.c:41-73](../../driver/src/reconfig/reconfig_mem.c) | `vmalloc`/`alloc_pages(GFP_ATOMIC)` under `spin_lock(mem_lock)` (sleeping in atomic context); `:55` returns with the lock held; metadata allocated in mmap never `kfree`d; `hash_del` inside non-`_safe` loop |
| [reconfig_ops.c:234-255](../../driver/src/reconfig/reconfig_ops.c) | `kzalloc(GFP_KERNEL)` under `spin_lock`; `-EIO` path returns with `mem_lock` held |
| [coyote_setup.c:424-428](../../driver/src/coyote_setup.c) | `ctid_chunks[63]` never initialised (id 0, next NULL); `num_free_ctid_chunks` never decremented (guard in `REGISTER_CTID` dead): 64th register returns ctid 0, 65th NULL-derefs `pid_alloc` |
| [coyote_setup.c:568-604](../../driver/src/coyote_setup.c), `:497-499` | shell re-init frees `vfpga_dev` array under open fds (use-after-free), leaks pinned `user_pages`, `hash_init` wipes `user_buff_map` entries |
| [coyote_setup.c:44,60](../../driver/src/coyote_setup.c) | `stlb_meta`/`ltlb_meta` re-`kzalloc`ed on each shell re-init, never freed |
| [vfpga_hw.c:233,248](../../driver/src/vfpga/vfpga_hw.c) | `alloc_card_memory` returns `-ENOMEM` holding `card_lock` |
| [vfpga_hw.c:237-258,291,312](../../driver/src/vfpga/vfpga_hw.c) | allocator ignores `used`, free moves the cursor: double allocation / lost alignment |
| [vfpga_hw.c:90,119](../../driver/src/vfpga/vfpga_hw.c) | `uint64_t entry[2]` uninitialised before `\|=` |
| [vfpga_gup.c:33-35](../../driver/src/vfpga/vfpga_gup.c) | `pid_task(...)->mm` unchecked (process may have exited with a fault queued) |
| `tlb_put_user_pages[_ctid]` | `user_pages` structs never `kfree`d; also `ctid_entry`/`hpid_ctid_pages` never freed; `hash_del` inside non-`_safe` `hash_for_each` (also `vfpga_dev_release`); `tlb_put_user_pages` uses `<=` where other lookups use `<` |
| [vfpga_gup.c:774](../../driver/src/vfpga/vfpga_gup.c) | `p2p_move_notify` runs without `mmu_lock` |
| [vfpga_isr.c:179](../../driver/src/vfpga/vfpga_isr.c) | page faults pass `mem_block=-1`: Versal `en_block_mem` faults dropped unless pre-mapped |
| [vfpga_ops.c:574](../../driver/src/vfpga/vfpga_ops.c) | `GET_NOTIFICATION_VALUE` copies 4 bytes; `MMAP_WB` with `!en_wb` calls `dma_mmap_coherent` on NULL |
| [coyote_sysfs.c:76](../../driver/src/coyote_sysfs.c) | `eost_store` writes the module param `eost`, not `bus_data->eost` |
| [pci_xdma.c:561,736](../../driver/src/platform/pci_xdma.c) | `goto err_alloc` returns 0 on OOM; `kfree` of a `devm_` allocation (also reached from later error paths); error/remove paths use `pci_disable_msix` not `pci_free_irq_vectors` and never `iounmap` `stat_cnfg`/`shell_cnfg` |
| [coyote_setup.c:281](../../driver/src/coyote_setup.c) | `cyt_kobj_type` has no `.release` |
| [coyote_defs.h:381,674,708](../../driver/include/coyote_defs.h) | `IRQ_RCNFG` unused; `hpid_ctid_pages` defined twice (HMM and non-HMM variants) |
| SW cross-ref | `~cThread` calls `SET_NOTIFICATION_PROCESSED` (only when an eventfd exists, [cThread.cpp:244](../../sw/src/cThread.cpp)) even if no notification is pending: unlock of an unlocked mutex |

Also: thesis/paper v1 describe a US+-only XDMA driver with ECI and HMM; the live driver adds Versal/QDMA, card-memory blocks and dmabuf, and has no HMM.

## How to modify / extend

**Add a vFPGA ioctl end-to-end**
1. Define `#define IOCTL_FOO _IOW('F', 20, unsigned long)` in [coyote_defs.h](../../driver/include/coyote_defs.h) **and** [cDefs.hpp](../../sw/include/coyote/cDefs.hpp) (same number/direction/size type).
2. Add `case IOCTL_FOO:` in `vfpga_dev_ioctl` ([vfpga_ops.c](../../driver/src/vfpga/vfpga_ops.c)): `copy_from_user(&tmp, arg, N*sizeof(unsigned long))`, call a helper, `copy_to_user` results; take `mmu_lock`/etc. as appropriate. Put register-level work in `vfpga_hw.c` (+ prototype/docstring in `vfpga_hw.h`).
3. Add the SW wrapper in [cThread.cpp](../../sw/src/cThread.cpp) (+ declaration in [cThread.hpp](../../sw/include/coyote/cThread.hpp)) filling `uint64_t tmp[MAX_USER_ARGS]`; mirror it in [sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp) (stub or implementation).
4. If a new HW register is involved, extend `vfpga_cnfg_regs` (driver) + `CnfgAvxRegs/CnfgLegRegs` (SW) + RTL slave.
For the reconfig device use magic `'P'` and `reconfig_dev_ioctl`.

**Add a new mmap region**: new `MMAP_*` offset in both `coyote_defs.h` and `cDefs.hpp` (SW multiplies by `1<<PAGE_SHIFT`), new branch in `vfpga_dev_mmap` (`remap_pfn_range` for BAR windows, `dma_mmap_coherent` for host buffers; `vm_pgoff` is page index; `MMAP_WB` is 0 because `dma_mmap_coherent` requires it).

**Add an interrupt type**: new `IRQ_*` in `lynx_pkg_tmplt.txt` and `coyote_defs.h`, RTL sets `TYPE_MISS` in `cnfg_slave*.sv`, add a `case` in `vfpga_isr` (fast path inline, slow path via a new workqueue/`work_struct`), remember `clear_irq` happens after the switch.

**New platform/board**: new PCI IDs in `pci_ids[]`; BAR layout must keep `BAR_STAT_CONFIG/DMA_CONFIG/SHELL_CONFIG` order; adjust `MEM_START`/chunk constants in `coyote_defs.h`.
