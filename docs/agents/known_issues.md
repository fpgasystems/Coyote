# Known issues (from documentation review)

Found by static code reading while generating the agent docs; nothing here was reproduced on hardware or in simulation. Severity is an estimate (high = wrong results, hang, memory-safety or build failure in a supported configuration; med = wrong behaviour in a corner case or non-default configuration; low = cosmetic, dead code, hygiene).

Status: `confirmed` = the cited file:line was re-opened and the defect seen; `unverified` = reported by a doc agent (see the layer docs), line numbers taken from the docs and not re-opened. Line numbers may have drifted. Layer docs: [coyote_top.md](coyote_top.md), [driver.md](driver.md), [software.md](software.md), [simulation.md](simulation.md), [static/](static/), [shell/shell_top.md](shell/shell_top.md), [services/](services/), [user/user_top.md](user/user_top.md), [build/](build/).

## Static layer & host DMA

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| STA-01 | med | [reconfig_hw.c:46-63,79](../../driver/src/reconfig/reconfig_hw.c) | `cmd_sent` only incremented for the partial last page; `PR_START` write ignores FIFO `ready` (32-deep `axis_data_fifo_static_slave`, `RECONFIG_THRESHOLD`=32). | Bitstreams with >32 outstanding 2 MB chunks can overflow the FIFO and silently lose a descriptor. Increment per descriptor or re-read `reconfig_ctrl` each iteration. | unverified |
| STA-02 | med | [pci_xdma.c](../../driver/src/platform/pci_xdma.c) `probe_engines` | `engines_num < 2 * bd_data->n_fpga_chan` is evaluated before `n_fpga_chan` is read in `read_shell_config()` (still 0). | Missing-engine check never triggers. Move check after shell config read. | unverified |
| STA-03 | low | [pci_xdma.c](../../driver/src/platform/pci_xdma.c) `engine_create` | Writes `!XDMA_CTRL_NON_INCR_ADDR` (= 0) to `ctrl_w1c`. | No-op; probably meant to clear the bit. | unverified |
| STA-04 | med | [pci_xdma.c](../../driver/src/platform/pci_xdma.c) (`pci_check_msix`, `struct xdma_interrupt_regs`) | 22 MSI-X vectors allocated; engine interrupts enabled/declared (`channel_int_enable`, `channel_msi_vector`) but never written and no handlers. | 6 vectors wasted; engine-completion IRQs stay masked. Allocate fewer vectors. | unverified |
| STA-05 | low | [static_slave.sv](../../hw/hdl/static/static_slave.sv) (~L149) | 7-bit address decode aliases every 0x80; regs 8-10 read 0; `PR_ADDR_LOW/HIGH`, `PR_LEN` have no reset value (`'X`); never returns AXI error response. | Reads of unwritten regs give X; aliased accesses. Add reset values / decode full range. | unverified |
| STA-06 | med | [qdma_interrupt_wrapper](../../hw/hdl/static) (Versal) | Interrupts serialised lowest-bit-first: a vFPGA IRQ that is never cleared starves the PR interrupt. `qdma_wr_wrapper` uses fixed priority. | PR (reconfig) hang if a vFPGA keeps asserting; ISRs must always `clear_irq`. Add round-robin. | unverified |
| STA-07 | med | `qdma_rd_wrapper` (Versal, [hw/hdl/static](../../hw/hdl/static)) | err/zero_byte/unexpected-qid beats are never consumed; error statuses never produce `done`. | H2C stall and credit leak after a DMA error. | unverified |
| STA-08 | med | [pci_xdma.c:561,736](../../driver/src/platform/pci_xdma.c), `pci_qdma.c` | `goto err_alloc` after failed `devm_kzalloc` returns 0 (probe "succeeds" on OOM); `err_enable` `kfree`s devm memory; error/remove use `pci_disable_msix` not `pci_free_irq_vectors`; `stat_cnfg`/`shell_cnfg` never `iounmap`ed. | Probe-failure hygiene: false success, double free, leaks. | unverified |
| STA-09 | low | pci_xdma.c `remove_engines`, `irq_setup`; pci_qdma.c `enable_queues` | `remove_engines` loops `i < n_fpga_chan` so channel-2 (PR/WB) engines are never destroyed; `irq_setup` returns uninitialised `ret_val` when `n_fpga_reg==0` and no reconfig IRQ; Versal `enable_queues` returns `-ENODEV` without `disable_queues()`; `disable_queues` also invalidates C2H TIMER context. | Leaks / undefined return values on error paths. | unverified |
| STA-10 | low | [cr_pci.tcl](../../hw/bd/ultrascale_plus/cr_pci.tcl) (US+) | References `perst_n` that is never created. | Likely dead/failing branch for some devices. | unverified |
| STA-11 | low | QDMA H2C/C2H bypass (static) | Bypass commands carry 16-bit `len` (QDMA C2H len also 16-bit). | Keep `PMTU_BYTES` and migration chunks < 64 KiB (documented invariant, no check). | unverified |
| STA-12 | low | [coyote_defs.h:381](../../driver/include/coyote_defs.h) | `IRQ_RCNFG` unused. | Dead define. | unverified |

## Reconfiguration

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| REC-01 | high | [reconfig_ops.c:163,177](../../driver/src/reconfig/reconfig_ops.c) | `IOCTL_RECONFIGURE_APP` decouples with `1 << tmp[4]` (vfid) but re-couples with `1 << tmp[3]` (crid). | Works only if `crid == vfid`; otherwise target vFPGA stays decoupled and another one is "re-coupled". Use `tmp[4]` at L177. | confirmed |
| REC-02 | high | [reconfig_ops.c:121,169](../../driver/src/reconfig/reconfig_ops.c) | `return -1` after `reconfigure_start` failure while holding `rcnfg_lock` (also when no `(vaddr,pid,crid)` buffer matches, ret 1). Shell path has already torn the shell down and decoupled. | All later reconfigurations deadlock; shell left torn down. Unlock + restore on every error path. | confirmed |
| REC-03 | high | [shell_top_tmplt.txt](../../hw/templates/common/shell_top_tmplt.txt), [shell_slave.sv:49,359](../../hw/hdl/shell/shell_slave.sv) | `m_rst_pr` is generated from `CTRL_DP_REG_SET[32+:N_REGIONS]` but not connected anywhere in the shell templates; driver never writes bits 32+. | Nothing resets a vFPGA after app PR; user logic must tolerate un-reset start or self-reset. Connect to per-region reset and have the driver pulse it. | confirmed |
| REC-04 | med | [reconfig_ops.c](../../driver/src/reconfig/reconfig_ops.c) `IOCTL_RECONFIGURE_SHELL` | `shell_pci_init()` return value ignored. | Failed re-init goes unnoticed. | unverified |
| REC-05 | med | [reconfig_ops.c](../../driver/src/reconfig/reconfig_ops.c) | `wait_event_interruptible` return ignored and no timeout in HW or driver (Versal: no PMC error path). | Bad PDI/bitstream hangs the ioctl forever; a signal ends wait while PR still runs. Use `_timeout`, surface PMC errors. | unverified |
| REC-06 | med | [coyote_setup.c:497-499,568-604](../../driver/src/coyote_setup.c) | Shell re-init frees the `vfpga_dev` array under open fds; leaks pinned `user_pages`; `hash_init` wipes `user_buff_map`. | Use-after-free if any vFPGA fd is open during `reconfigureShell`. Refuse/close fds first. | unverified |
| REC-07 | low | [coyote_setup.c:44,60](../../driver/src/coyote_setup.c) | `stlb_meta`/`ltlb_meta` re-`kzalloc`ed on every shell re-init, never freed. | Small leak per shell reconfiguration. | unverified |
| REC-08 | med | [reconfig_ops.c:233](../../driver/src/reconfig/reconfig_ops.c), [cRcnfg.cpp](../../sw/src/cRcnfg.cpp) | `reconfig_dev_mmap` compares `curr_buff.pid` with `current->pid` (TID) while `cRcnfg` passes `getpid()` (TGID). | Bitstream mmap fails from a non-main thread. Use `current->tgid`. | unverified |
| REC-09 | low | [coyote_sysfs.c:76](../../driver/src/coyote_sysfs.c) | `cyt_attr_eost_store` parses into `bus_data->eost` but writes the module param `eost` to the register. | Setting EOST via sysfs has no effect (old value written). Use `bus_data->eost`. | confirmed |
| REC-10 | low | driver `bus_data->eost` | Only initialised when shell has `EN_PR`; sysfs `cyt_attr_eost` shows 0/stale otherwise. | Cosmetic. | unverified |
| REC-11 | low | [build/constraints.md](build/constraints.md), `IOCTL_PR_WB_STATS` ([vfpga_ops.c](../../driver/src/vfpga/vfpga_ops.c)/reconfig ioctl) | `IOCTL_PR_WB_STATS` copies `N_HDMA_STAT_CH_REGS` (4) of the 6 `N_PR_WB_STAT_REGS`; unused by SW. | Partial stats. | unverified |

## Shell registers (cnfg_slave / shell_slave)

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| REG-01 | high | [cnfg_slave.sv:636-641](../../hw/hdl/shell/cnfg_slave.sv) | `WBACK_LCL_WR_OFFS_REG` write case stores into `slv_reg[WBACK_LCL_RD_OFFS_REG]`. | On non-AVX `EN_WB` shells the RD writeback base is overwritten by the WR value and `WBACK_LCL_WR` (used at L1438) is never set: local-write completions go to the wrong host slot. Fix index. | confirmed |
| REG-02 | high | [cnfg_slave.sv:860,869](../../hw/hdl/shell/cnfg_slave.sv) | Read of `OFFL_CARD_OFFS_REG` / `SYNC_CARD_OFFS_REG` returns the `*_HOST_OFFS_REG` value (write path at L670-693 is correct). | Offload/sync card-offset read-back wrong (non-AVX). | confirmed (write side; read arms per doc) |
| REG-03 | high | [cnfg_slave.sv:857,866](../../hw/hdl/shell/cnfg_slave.sv) | `OFFL_STAT_REG` / `SYNC_STAT_REG` reads use `slv_reg[...][MEM_DONE]`; `MEM_DONE` is not declared anywhere under `hw/hdl/shell`. | Probable compile error for non-AVX + `EN_MEM`; status counters incremented at ~L481/L489 not fully readable. | confirmed |
| REG-04 | high | [cnfg_slave_avx.sv:740-743](../../hw/hdl/shell/cnfg_slave_avx.sv) | `SYNC_CTRL_REG` read returns `offload_queue_used`; `SYNC_STAT_REG` read returns `slv_reg[OFFL_STAT_REG]`; `[REG:REG]` range syntax. | Driver `sync()` throttle ([vfpga_hw.c:180](../../driver/src/vfpga/vfpga_hw.c)) polls the offload queue on AVX shells. | confirmed |
| REG-05 | med | [cnfg_slave.sv:1316](../../hw/hdl/shell/cnfg_slave.sv) | RDMA read counter `a_data_in_rdma_rd` computed from `a_data_out_rdma_wr + 1` (AVX variant ~L1176 uses `_rd`); same value feeds `wback[2]` (~L1446). | With `EN_AVX=0`, READ completion count follows the WRITE counter. | confirmed |
| REG-06 | med | [cnfg_slave_avx.sv](../../hw/hdl/shell/cnfg_slave_avx.sv) (completion counters) | Completion counters lack the `ack_t.host` filter used elsewhere. | Counters may include non-host acks. | unverified |
| REG-07 | med | [cnfg_slave.sv:243-244,754,765](../../hw/hdl/shell/cnfg_slave.sv), [cnfg_slave_avx.sv:258-259,661,666-672](../../hw/hdl/shell/cnfg_slave_avx.sv) | `EN_TCP` branches stale: `open_port_sts` declared twice and both miss `)`; `TCP_OPEN_PORT_CMD_REG` / `TCP_OPEN_CONN_CMD_REG` undeclared (should be `TCP_OPEN_PORT_REG`/`TCP_OPEN_CONN_REG`); `s_axim__ctrl` double underscore (`_avx` only). | `EN_TCP` does not elaborate. See NET-01. | unverified |
| REG-08 | low | [shell_slave.sv](../../hw/hdl/shell/shell_slave.sv) | `PROBE_REG` has no write path; `CTRL_DP_REG_SET/CLR` have no read path (header comment says RW / readable); `slv_reg` reset to X. | Doc/code mismatch; X after reset. | unverified |
| REG-09 | med | `cnfg_slave*` + SW AVX selection ([cThread.cpp](../../sw/src/cThread.cpp)) | AVX shell ties off `axi_ctrl_cnfg` (`wready=0`, `rvalid=0`); SW built without `EN_AVX` maps `MMAP_CNFG` and any access to `+0x30000` hangs the bus. | Build SW with `EN_AVX` (default) or add a runtime guard. | unverified |
| REG-10 | low | [coyote_defs.h:275-295](../../driver/include/coyote_defs.h) | `VFPGA_CTRL_SIZE` is `256 * 1024` and `VFPGA_CTRL_{LTLB,STLB,USER,CNFG}_SIZE` are `VFPGA_CTRL_SIZE / 4`, all unparenthesised. | Precedence bugs when embedded in larger expressions. Parenthesise. | confirmed |
| REG-11 | med | [dynamic_top_tmplt.txt](../../hw/templates/common/dynamic_top_tmplt.txt) ~L1243-1285 | Versal + `EN_PR`: single `s_axi_debug_hub_*` port connected inside the per-region `for` loop. | Multiple drivers for `N_REGIONS > 1`. | unverified |
| REG-12 | med | [shell_top_tmplt.txt](../../hw/templates/common/shell_top_tmplt.txt) | `sys_reset` used for `network_top` and `design_ddr` but never declared (implicit net); only `shell_ctrl_cc.sys_reset` is tied to `1'b0`. | Implicit net, may be 1-bit Z/undriven. | unverified |
| REG-13 | low | [shell_top_tmplt.txt](../../hw/templates/common/shell_top_tmplt.txt) `shell_data_cc`, `shell_split_data` | `shell_data_cc` instance names crossed; `shell_split_data` effectively dead (`N_CHAN == N_SCHAN`). | Confusing names; see DEAD-04. | unverified |
| REG-14 | low | [coyote_defs.h](../../driver/include/coyote_defs.h) vs driver `IOCTL_SHELL_HDMA_STATS` | HDMA stats stride 4 words/channel in driver vs 3 in RTL; `N_NET_STAT_REGS` 10 vs 9. | Misaligned stat read-out. | unverified |
| REG-15 | med | [cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv) | Invalidate `len` truncated to `LEN_BITS` (28). | See MMU-04 (1 GiB pages). | unverified |

## MMU

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| MMU-01 | high | [tlb_fsm.sv:883-887,911-915](../../hw/hdl/mmu/tlb_fsm.sv) (`ST_INVLDT_CMP_*`) | `A \|\| (B && C) && hpid` precedence: hpid check applies only to the second clause; the second clause needs hpid == record hpid, which is always 0 (hpid never written to in-flight RAM). Only clause A (`vaddr <= rec.vaddr <= vaddr+len`) works. | Invalidation drain fence weak/over-eager; record holds next-chunk start + remaining len. Add parentheses and write hpid. | confirmed |
| MMU-02 | high | [vfpga_gup.c:700-760](../../driver/src/vfpga/vfpga_gup.c) `offload_user_pages` / `sync_user_pages` | `user_buff_map` keyed by start VPN; a non-start `vaddr` finds no entry and `vaddr_tmp` never advances. | Infinite loop in kernel (hang). Also in `tlb_put_user_pages`, `p2p_detach_dma_buf` (interior unmap misses). Advance on miss / use range lookup. | unverified |
| MMU-03 | high | MMU / [vfpga_isr.c](../../driver/src/vfpga/vfpga_isr.c), [coyote_defs.h](../../driver/include/coyote_defs.h) | 1 GiB hugepages broken end to end: `invalidate_tlb_entry` `n_pages=2^18` -> `isr_len=2^30` truncated by `LEN_BITS`=28 -> 0 (fence disabled); card huge pages placed at `MEM_START + card_huge_offs + (id<<12)`, not 1 GiB aligned (Versal `MEM_BLOCK_SIZE`=512 MiB similar); `THP` alignment hardcoded 2 MiB. | lTLB translation of card pages wrong for 1 GiB pages. Restrict to 2 MiB or fix alignment/length width. | unverified |
| MMU-04 | high | [vfpga_hw.c:90,119](../../driver/src/vfpga/vfpga_hw.c) `create_tlb_mapping/unmapping` | `uint64_t entry[2]` not zero-initialised before `\|=`. | Stack garbage can reach TLB words. `= {0}`. | unverified |
| MMU-05 | med | [vfpga_gup.c:806](../../driver/src/vfpga/vfpga_gup.c) `p2p_move_notify` | `cnt = sg_dma_len(...) >> PAGE_SHIFT;` should be `cnt +=`. Function also runs without `mmu_lock` (L774). | Multi-segment sg tables overlap in `hpages` (GPU/dmabuf). | confirmed |
| MMU-06 | med | [vfpga_ops.c:399-438](../../driver/src/vfpga/vfpga_ops.c) | `IOCTL_OFFLOAD_REQ/SYNC_REQ` take neither `mmu_lock` nor the TLB lock. | Race with page-fault handling. | unverified |
| MMU-07 | med | [tlb_fsm.sv](../../hw/hdl/mmu/tlb_fsm.sv) `ST_MISS_IDLE` | Any `s_invldt` jumps to `ST_INVLDT_*` without checking `.lock`; lock honoured only in `ST_IDLE/ST_LOCKED`. | Stale `invldt_C` scan, deferred restart, lock-parity desync (e.g. `userMap` during traffic). | unverified |
| MMU-08 | med | [mmu_region_top.sv](../../hw/hdl/mmu/mmu_region_top.sv) L138-143 | Mutex: stray `wr_unlock` while rd holds sets `2'b11` (frees it); wr drop path re-pulses `unlock`. | Mutex asymmetry. | unverified |
| MMU-09 | med | [mmu_assign.sv](../../hw/hdl/mmu/mmu_assign.sv) | `s_req.ready = m_req.ready` ignores `queue.ready`; with fwd-last queue full a request is accepted but dropped. | Lost request. | unverified |
| MMU-10 | med | TLB refill ([vfpga_gup.c](../../driver/src/vfpga/vfpga_gup.c) `tlb_map_gup`) | Refill on an already-known buffer maps up to 256 entries without unmap. | Duplicate TLB ways (hit encoder picks highest). Also `tlb_map_gup` huge path assumes contiguous 2 MiB card chunks (unchecked). | unverified |
| MMU-11 | med | [tlb_controller.sv](../../hw/hdl/mmu/tlb_controller.sv) | `N_ASSOC=1` gives zero-width index (`[-1:0]`); `EN_NRU` guards code with undeclared signals (NRU ref writes corrupt non-hit ways). | Use `N_ASSOC >= 2`; NRU unusable. | unverified |
| MMU-12 | low | [mmu_region_top.sv](../../hw/hdl/mmu/mmu_region_top.sv) vs [tlb_fsm.sv](../../hw/hdl/mmu/tlb_fsm.sv) | `TLB_*_DATA_BITS`: `PID_BITS+2+..` vs `PID_BITS+STRM_BITS+1+..`; may truncate hpid MSB (doc: harmless, FSM `hpid` unused). Page-fault drop does not drain write data. | Possible stream blockage after dropped write. | unverified |
| MMU-13 | low | [coyote_defs.h:324](../../driver/include/coyote_defs.h) | `TLB_VADDR_RANGE 48` hardcoded while `VADDR_BITS` is a cmake knob; driver `IRQ_DMA_OFFL/SYNC` vs RTL `IRQ_OFFL/SYNC`. | Mismatch if `VADDR_BITS` changed. | confirmed |
| MMU-14 | low | [vfpga_gup.c](../../driver/src/vfpga/vfpga_gup.c) `tlb_unmap_gup` | One `invalidate_tlb_entry` (4 MMIO writes + HW scan) per 4 KiB page. | Slow unmap/migration. | unverified |
| MMU-15 | low | [mmu_arbiter_isr.sv](../../hw/hdl/mmu/mmu_arbiter_isr.sv) | Does not force `last=1` unlike `mmu_arbiter`/`mmu_assign`. | Relies on driver `DMA_CTRL_START_LAST`. | unverified |
| MMU-16 | med | [mmu_top.sv:289](../../hw/hdl/mmu/mmu_top.sv), [dynamic_top_tmplt.txt](../../hw/templates/common/dynamic_top_tmplt.txt) L541/L1064 | Scalar `rdma_host_cq_s1` passed to `mmu_top`, which indexes `s_rdma_cq[i]`. | With `N_REGIONS>1` every region sees the same host completion stream. | unverified |
| MMU-17 | low | [mmu_top.sv:335-338](../../hw/hdl/mmu/mmu_top.sv) | Four `EN_TCP` instances all named `inst_tcp_listen_req`. | Duplicate instance names (TCP build error). | confirmed |

## Card memory

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| MEM-01 | high | [vfpga_hw.c:237-258](../../driver/src/vfpga/vfpga_hw.c), free at [:291,:312](../../driver/src/vfpga/vfpga_hw.c) | `alloc_card_memory` advances `alloc = alloc->next` without checking `used`; `free_card_memory` resets `alloc` to the freed chunk. | After a free/alloc pattern the allocator hands out a chunk already in use (double allocation) and loses ordering. Search for next free chunk or use a bitmap/freelist. | confirmed |
| MEM-02 | high | [vfpga_hw.c:233,248](../../driver/src/vfpga/vfpga_hw.c) (lock at :228, unlock :262) | Returns `-ENOMEM` while holding `card_lock` spinlock. | Deadlock of later callers. Unlock before returning. | confirmed |
| MEM-03 | med | [vfpga_hw.c:210,215](../../driver/src/vfpga/vfpga_hw.c) | Automatic block choice uses `free_chunks > n_pages` (should be `>=`); scan runs before `card_lock` is taken. | Off-by-one, racy block selection. | confirmed |
| MEM-04 | high | [vfpga_hw.c:201](../../driver/src/vfpga/vfpga_hw.c) | Only `mem_block >= N_MEM_BLOCKS` is checked on user value; `< -1` not rejected; nothing checks `mem_block < N_CARD_AXI` (Versal). | One vFPGA can place buffers in another's block (isolation hole). | confirmed (check at L199) |
| MEM-05 | med | [hbm_wide.v:342](../../hw/hdl/shell/hbm_wide.v), :168 | Drives `s_axi_resp` (typo for `s_axi_bresp`; `bresp` left undriven); `rresp` declared 1-bit unpacked while 2-bit values assigned; `s_axi_rlast = rlast[0]` only. | Write response to master undriven (X/implicit net); error codes lost. | confirmed (L342) |
| MEM-06 | med | [axi_stripe_rd.sv](../../hw/hdl/stripe/axi_stripe_rd.sv), [axi_stripe_wr.sv:98](../../hw/hdl/stripe/axi_stripe_wr.sv) | `arid_C` / `awid_C` are 2 bits while `AXI_ID_BITS=6` ([lynx_pkg_tmplt.txt:159](../../hw/templates/common/lynx_pkg_tmplt.txt)). | ID truncation on striped accesses. | unverified |
| MEM-07 | med | [coyote_defs.h:331](../../driver/include/coyote_defs.h) | u280 driver card range = `MEM_START` 0.25 GiB + 4 + 4 GiB = 8.25 GiB > 8 GiB HBM (`HBM_SIZE=33`). | Top 256 MiB of huge-chunk range exceeds device; accesses may alias. | unverified |
| MEM-08 | low | `memory_infrastructure.tcl` / `cr_hbm.tcl` | `axi_toff_in` creation loops do not run for `N_MEM_CHAN > 32` (or `> 16` with `HBM_SPLIT`) but connect loops still reference `SAXI_32+` pins (negative loop). | BD creation fails for large `N_MEM_CHAN`. | unverified |
| MEM-09 | low | cmake / cfg | `en_mem_cred` / `cnfg.en_mem_cred` never defined, `dma_parser` missing: card credit stage never generated (also BLD-03). | MMU-level credit path cannot build; dead. | unverified |
| MEM-10 | low | [FindCoyoteHW.cmake:384](../../cmake/FindCoyoteHW.cmake), `cr_ddr.tcl` | `N_DDR_CHAN` plain `set()` per board, `-DN_DDR_CHAN` ignored; u280 branch of `cr_ddr.tcl` defines only `ddr4_0/1`. | Config knob ineffective. | unverified |
| MEM-11 | low | [vfpga_isr.c:179](../../driver/src/vfpga/vfpga_isr.c) | Page faults pass `mem_block=-1`; Versal `en_block_mem` faults dropped unless pre-mapped. | Block-mem faults unsupported. | unverified |
| MEM-12 | low | `rdma_mux_retrans.sv` L130-140 | RDMA retransmission addresses `{vfid,pid,slot}<<RDMA_MEM_SHIFT` not confined to card-memory window; truncation behaviour of card path unknown. | Possible slot collapse; see NET-10. | unverified |

## Networking (RDMA / TCP / sniffer)

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| NET-01 | high | [dynamic_top_tmplt.txt](../../hw/templates/common/dynamic_top_tmplt.txt), [user_wrapper_tmplt.txt](../../hw/templates/common/user_wrapper_tmplt.txt) (~L896-1050), [lynx_pkg_tmplt.txt](../../hw/templates/common/lynx_pkg_tmplt.txt) | TCP does not build: `dynamic_top` connects `.tcp_cq_*` ports missing in `user_wrapper`; `N_TCP_AXI` undefined in `lynxTypes`; `axis_tcp_send_int/recv_int` undeclared; missing comma after `.m_rq(tcp_rq_wr_int)`; `axis_mux_user_tcp` takes `muxIntf` but gets `metaIntf`; non-uclk branch uses stale `tcp_0_*` names; only `tcp_mem_*[0]` of `N_TCP_CHANNELS=2` wired; no SW drives `TCP_OPEN_*`. | `EN_TCP=1` unusable as shipped. Do not enable; SW also marks `REMOTE_TCP_SEND` unsupported ([cOps.hpp:71](../../sw/include/coyote/cOps.hpp)). | unverified (`N_TCP_AXI` grep in lynx_pkg returned nothing) |
| NET-02 | high | [tcp_port_table.sv:62](../../hw/hdl/network/tcp/tcp_port_table.sv) | `logic [TCP_RSESSION_BITS-1:0:0] rsid_C, rsid_N;` invalid SystemVerilog. | Syntax error under `EN_TCP`. Should be `[...-1:0]`. | confirmed |
| NET-03 | high | [network_packet_sniffer.sv](../../hw/hdl/network/stack/network_packet_sniffer.sv) | `packet_filter` RX branch for filter bit 31 tests `tx_rocev2_ipv4_aeth/reth` instead of `rx_*`. | Wrong RX RoCE strip decision. | unverified |
| NET-04 | high | [user_wrapper_tmplt.txt:483-492](../../hw/templates/common/user_wrapper_tmplt.txt) | `assign {rx,tx}_sniffer.tready = ..._tready` and `filter_config.data/.valid = filter_config_data/valid` drive in the opposite direction to the ports (`notify` pattern at L294-296 is the reference). | Back-pressure and filter mask never reach shell (filter stays 0 = capture all). Doc marks "likely, verify in synthesis". | confirmed (lines); direction unverified in synthesis |
| NET-05 | high | sniffer streams / `filter_config` ([dynamic_top_tmplt.txt](../../hw/templates/common/dynamic_top_tmplt.txt), [user_wrapper_tmplt.txt](../../hw/templates/common/user_wrapper_tmplt.txt)) | No CDC or decoupler on sniffer streams and `filter_config` (nclk -> aclk). | Works only when `NCLK_F == ACLK_F`. Add `axis_ccross`/`meta_ccross`. | unverified |
| NET-06 | med | [crc.cpp](../../hw/services/network/hls/crc/crc.cpp) | `drop_invalid_crc` counts mismatches but forwards bad packets ("hack"); `crc_drop` counter not exported to `net_stat_t`. | RX ICRC not enforced. | unverified |
| NET-07 | med | `hw/services/network` HLS build vs `network_stack.sv` | Sniffer-only build (`EN_SNIFFER` without RDMA/TCP): HLS gated on `EN_TCP\|EN_RDMA` but `network_stack` instantiated on `EN_NET`; wrapper leaves `remote_sq_*`/`user_rq_wr_int` undriven (no branch in if/elif chain); driver `en_net = en_rdma \| en_tcp`, so IP/MAC cannot be set. | Sniffer-only shell fails; use `EN_RDMA=1` (example 11). | unverified |
| NET-08 | low | [rocev2_config.hpp.in:4](../../hw/services/network/hls/rocev2/rocev2_config.hpp.in) | `RETRANS_EN` always `#define`d; CMake option of the same name has no effect. `retryCounter` init `0xF` vs `RETRANS_RETRY_CNT=12`. | Config knob ineffective. | confirmed |
| NET-09 | low | `ROCE_STACK_MAX_QPS=500` | QPN = `vfid*64+ctid` indexes 500-entry tables, unchecked. | Effectively <= 7 vFPGAs x 64 ctids; out-of-range QPN undefined. | unverified |
| NET-10 | low | `state_table.hpp` (submodule `hw/services/network`) | QP state assignment commented out. | No QP state tracking. | unverified |
| NET-11 | low | [cyt_attr_nstats](../../driver/src/coyote_sysfs.c) | Prints QSFP0 stats always; `RDMA_OFFS_REG`/`TCP_OFFS_REG` never written. | Misleading output; dead regs. | unverified |
| NET-12 | low | `ack_gap_enforcer`, `read_request_trimmer` | Match hard-coded header bytes (`tdata[15:0]==0x0245`, opcode 0x11 / 0x0C). | Peers with other TOS/ECN bypass the gap enforcer. | unverified |
| NET-13 | low | `rdma_flow` | Reads limited by the *write* constant (16) while vFPGA side uses `RDMA_N_RD_OUTSTANDING` (8). | Inconsistent limits. | unverified |
| NET-14 | low | [cThread.cpp:1348](../../sw/src/cThread.cpp) | Server-side `closeConn` (from `~cThread`) blocks in `read()` until client sends `DEF_OP_CLOSE_CONN`; RDMA handshake only synchronised by `usleep`. | Destructor hang if client dies. | unverified |

## User layer / templates

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| USR-01 | high | [lynx_pkg_tmplt.txt:194,513](../../hw/templates/common/lynx_pkg_tmplt.txt), [dynamic_top_tmplt.txt:923,958,966](../../hw/templates/common/dynamic_top_tmplt.txt) | `NOTIFY_BITS = 32` but `irq_not_t` = `{pid[PID_BITS=6], value[31:0]}` = 38 bits; `notify` `meta_ccross` / `meta_reg_array` use `DATA_BITS(NOTIFY_BITS)`. | `pid` truncated, `cnfg_slave` sees `pid=0`; all user interrupts go to ctid 0. Use `$bits(irq_not_t)`. | confirmed |
| USR-02 | med | [axi_intf.sv:134-142](../../hw/hdl/pkg/axi_intf.sv) | `AXI4S/AXI4SR/AXI4L` `tie_off_s()` sets `tready`/`ready` = 0, unlike the `AXIS_TIE_OFF_S` macro (`tready=1`). Also `axi_ctrl.tie_off_s()` never completes CSR access. | Host transfer to tied-off recv stream hangs. Use macro or `assign tready=1`. | confirmed (arready/awready=0 in AXI4 variant; others per doc) |
| USR-03 | med | [dest_req_mux.sv](../../hw/hdl/user/dest/dest_req_mux.sv) | `req_ready[s_req.data.dest]` indexed without bounds guard; `req_credits_wr` `n_beats` floor. | `dest >= N_*_AXI`: X/stall/alias. Guard index. | unverified |
| USR-04 | med | [user_wrapper_tmplt.txt](../../hw/templates/common/user_wrapper_tmplt.txt) ~L870-1050 | No remote-credits branch for `EN_NET` without RDMA/TCP. | See NET-07. | unverified |
| USR-05 | low | [user_wrapper_tmplt.txt](../../hw/templates/common/user_wrapper_tmplt.txt) ~L495-557 | `en_user_reg` block mis-wired; always disabled (`EN_USER_REG=0`). | Dead; see DEAD-03. | unverified |
| USR-06 | med | `cq_rd`/`cq_wr` path (`mmu_top` -> `cnfg_slave_avx` -> wrapper) | vFPGA CQ is fire-and-forget: undrained `cq_*` drops acks silently. | Documented invariant; consider back-pressure. | unverified |
| USR-07 | low | `notify` path (`cnfg_slave*`, `vfpga_isr.c`) | Notify blocked while `irq_pending` (shared with page faults); notification delivery on single-thread workqueue (head-of-line blocking). | Latency / lost notifies under fault storm. | unverified |
| USR-08 | low | [cThread.cpp](../../sw/src/cThread.cpp) ctor; [cThread.hpp](../../sw/include/coyote/cThread.hpp) | Named mutex spelled `..._vfpa_...`; `getMem(PRM)` falls to `default` and registers null mapping; comments say `RDMA_WRITE` vs `REMOTE_RDMA_*`. | Typo / stale comments. | unverified |

## Driver

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| DRV-01 | high | [vfpga_uisr.c:34-47](../../driver/src/vfpga/vfpga_uisr.c), [vfpga_ops.c:264-285](../../driver/src/vfpga/vfpga_ops.c) | No bounds/ownership check on user `ctid`: `user_notifier[vfid][ctid]` / `user_notifier_lock[..][ctid]` indexed directly; `REGISTER_EVENTFD` with `ctid >= 64` writes out of bounds. Device nodes are mode 0666; `REGISTER_CTID` trusts user `hpid`; `pid_array[ctid]`, `user_buff_map` same. | Kernel memory corruption from any user. Validate `ctid < N_CTID_MAX` and ownership in every ioctl. | confirmed |
| DRV-02 | high | [coyote_setup.c:424-428](../../driver/src/coyote_setup.c) | Init loop `j < N_CTID_MAX - 1` leaves `ctid_chunks[63]` uninitialised (`next` NULL); `num_free_ctid_chunks` never decremented, so the guard at [vfpga_ops.c:136](../../driver/src/vfpga/vfpga_ops.c) is dead. | 64th register returns ctid 0, 65th NULL-derefs `pid_alloc`. Init all chunks, decrement counter. | confirmed |
| DRV-03 | high | [coyote_setup.c:568-604](../../driver/src/coyote_setup.c) | See REC-06 (shell re-init with open vFPGA fds). | Use-after-free + pinned page leak. | unverified |
| DRV-04 | high | [reconfig_mem.c:41-73](../../driver/src/reconfig/reconfig_mem.c), [reconfig_ops.c:234-255](../../driver/src/reconfig/reconfig_ops.c) | `vmalloc` / `alloc_pages(GFP_ATOMIC)` / `kzalloc(GFP_KERNEL)` under `spin_lock(mem_lock)` (sleeping in atomic context). | BUG/lockup on debug kernels. Use mutex or allocate before locking. | unverified (vmalloc at reconfig_mem.c:52 seen) |
| DRV-05 | high | [reconfig_mem.c:55](../../driver/src/reconfig/reconfig_mem.c), reconfig_ops.c `-EIO` path | `alloc_reconfig_buffer` returns `-ENOMEM` after `vmalloc` failure and `reconfig_dev_mmap` returns `-EIO` while holding `mem_lock`. | Permanent lock leak on error. | confirmed (L55) |
| DRV-06 | med | [reconfig_mem.c](../../driver/src/reconfig/reconfig_mem.c) | Metadata allocated in mmap never `kfree`d; `hash_del` inside non-`_safe` loop. | Leak / list corruption. | unverified |
| DRV-07 | med | [vfpga_ops.c:49-79](../../driver/src/vfpga/vfpga_ops.c) (`vfpga_dev_release`), `tlb_put_user_pages[_ctid]` | `hash_del` inside non-`_safe` `hash_for_each`; `user_pages` / `ctid_entry` / `hpid_ctid_pages` never freed; `tlb_put_user_pages` uses `<=` where other lookups use `<`. | Use-after-free in iteration; leaks. Use `hash_for_each_safe`, kfree. | unverified |
| DRV-08 | med | [vfpga_gup.c:33-35](../../driver/src/vfpga/vfpga_gup.c) | `pid_task(...)->mm` unchecked. | NULL deref if process exited with fault queued. | unverified |
| DRV-09 | med | [vfpga_isr.c:170-181](../../driver/src/vfpga/vfpga_isr.c), [vfpga_ops.c](../../driver/src/vfpga/vfpga_ops.c) (`IOCTL_MAP_USER_MEM`) | With `HMM_KERNEL` defined, declaration after brace-less `else` binds the dangling `else` to the following `if`: GUP skipped; `en_hmm==0` -> every fault dropped. | Only if HMM revived. Add braces. | unverified |
| DRV-10 | med | [coyote_defs.h](../../driver/include/coyote_defs.h) / driver | `en_hmm=1` without `-DHMM_KERNEL`: `OFFLOAD_REQ`, `SYNC_REQ`, `UNMAP_USER_MEM`, `UNMAP_DMABUF` silently no-op; `hpid_ctid_pages` defined twice (HMM / non-HMM). | Silent failure of migration/unmap. Reject `en_hmm=1` at load. | unverified |
| DRV-11 | med | global tables ([vfpga_ops.c:24-25](../../driver/src/vfpga/vfpga_ops.c), `user_buff_map`, `user_notifier*`) | Tables shared across cards; `ref_cnt` unlocked `uint32_t`; per-ctid cleanup only when last fd closes. | Multi-card interference; crashed process's pages stay pinned. | unverified |
| DRV-12 | low | [vfpga_ops.c:574](../../driver/src/vfpga/vfpga_ops.c) | `GET_NOTIFICATION_VALUE` copies 4 bytes; `MMAP_WB` with `!en_wb` calls `dma_mmap_coherent` on NULL. | Possible NULL deref via mmap. | unverified |
| DRV-13 | low | [coyote_setup.c:281](../../driver/src/coyote_setup.c) | `cyt_kobj_type` has no `.release`. | Kernel warning on kobject put. | unverified |
| DRV-14 | low | driver notifications | Single-thread workqueue head-of-line blocking; `SET_NOTIFICATION_PROCESSED` unlocks possibly-unlocked mutex (see SW-02). | Latency; undefined unlock. | unverified |
| DRV-15 | med | driver / sysfs | Tracking of pinned pages: interior-address unmap misses (key = start VPN, see MMU-02); leaks of `user_pages`, `ctid_entry`, `hpid_ctid_pages`, `stlb/ltlb_meta`. | Memory leak over time. | unverified |

## Software (libcoyote)

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| SW-01 | med | [cThread.hpp:131](../../sw/include/coyote/cThread.hpp) | `bool is_connected;` uninitialised; dtor reads it when `en_rdma`. | UB / spurious `closeConn`. Initialise to false. | confirmed |
| SW-02 | med | [cThread.cpp:244](../../sw/src/cThread.cpp) | Dtor calls `IOCTL_SET_NOTIFICATION_PROCESSED` whenever an eventfd exists, even with no pending notification. | Driver unlocks an unlocked mutex. | unverified |
| SW-03 | med | [cThread.cpp:942](../../sw/src/cThread.cpp) | Same-IP RDMA shortcut always `memcpy(remote_addr, local_addr, len)`. | Wrong direction for `REMOTE_RDMA_READ`. | confirmed |
| SW-04 | med | [cThread.cpp:122-176](../../sw/src/cThread.cpp) | Ctor throws after `event_thread` started -> `std::terminate`; fd and ctid leak on any later throw. | Crash on constructor failure. | unverified |
| SW-05 | low | [cThread.cpp:496](../../sw/src/cThread.cpp) | `getMem(REG)` does not check `MAP_FAILED`. | Silent bad pointer. | unverified |
| SW-06 | low | [cThread.cpp:1105,1159](../../sw/src/cThread.cpp), `DAEMON_PROCESS_REQUESTS_SLEEP` | `usleep(SLEEP_TIME)` (100 us) vs documented ns; `DAEMON_PROCESS_REQUESTS_SLEEP` documented us but used as ns in `cSched`/`cService`. | Wrong sleep durations / doc. | unverified |
| SW-07 | med | [cRcnfg.cpp:64-79,103-119](../../sw/src/cRcnfg.cpp) | `getMem/freeMem` throw while holding named `reconfig_mtx`; `~cRcnfg` removes the global mutex while possibly in use. | Wedges later reconfigs (stale `/dev/shm`). | unverified |
| SW-08 | low | [cRcnfg.cpp](../../sw/src/cRcnfg.cpp) | `reconfigureApp/Shell` never free bitstream buffer until dtor (new allocation per call); byte-by-byte copy to uncached mapping. | Memory growth; slow PR (~850 ms vs ~50 ms). | unverified |
| SW-09 | med | [cService.cpp:274-275](../../sw/src/cService.cpp), [cConn.cpp:98,108](../../sw/src/cConn.cpp) | `recv_buff[RECV_BUFF_SIZE=1024]`: args/returns > 1024 B overflow or short-read. | Buffer overflow on large args. | unverified |
| SW-10 | med | [cService.cpp:391](../../sw/src/cService.cpp) | `sendResponses` hard-codes `int32_t ret_code = 0`. | Failed tasks reported as success. | confirmed |
| SW-11 | med | [cService.cpp](../../sw/src/cService.cpp) | `processRequests` spins forever if client dies (`read` returns 0); `sendResponses` erases then `tmp++` (skips entry); `start()` shadows member `cleanup_thread`; remote mode (`acceptConnectionRemote`) is a stub; maps unlocked across threads; `cSched` holds `tlock` during run; `cTask`s never removed. | Races, spin, lost responses. | unverified |
| SW-12 | low | `cService`/`cSched` singletons | Keyed `"<device>-<vfid>"`, ignoring `name`. | Name ignored. | unverified |
| SW-13 | low | [cDefs.hpp](../../sw/include/coyote/cDefs.hpp) vs [coyote_defs.h](../../driver/include/coyote_defs.h) | SW `IOCTL_NET_STATS` vs driver `IOCTL_SHELL_NET_STATS`; no SW wrappers for `SET_IP/MAC` etc. and `IOCTL_SHELL_HDMA_STATS`. | Naming / API gap. | unverified |
| SW-14 | low | `CoyoteAlloc` (EN_CUDA member) | `EN_CUDA` introduces `#ifdef`-dependent data member, violating layout independence (commit 97b26119 rule). | ABI mismatch between lib and apps when `EN_CUDA` differs. | unverified |
| SW-15 | low | [cThread.cpp:244-1348](../../sw/src/cThread.cpp) | Server `closeConn` blocks in `read` (see NET-14). | Hang in dtor. | unverified |

## Simulation

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| SIM-01 | med | [sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp) | `uisr` handler drops `pid`. | Interrupt handler cannot see source ctid. | unverified |
| SIM-02 | low | [sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp) | `userUnmap` sends `USER_UNMAP` for unknown vaddr. | Unexpected generator behaviour. | unverified |
| SIM-03 | med | sim C++ runner | No timeout on `run -all` in C++ mode; unsupported INVOKE opcodes terminate sim with `$finish` (SW sees exit only); deadlock risk in `EN_INTERACTIVE` polling ops. | Hung or opaque simulation. | unverified |
| SIM-04 | med | [process_runner.py](../../sim/unit_test/process_runner.py) | C++ runner always compiles with `EN_INTERACTIVE`, Python without; Python `.last_change_time` not updated by C++ runs; `_open_project` replaces `vfpga_top.svh`. | Stale builds when switching flows; rerun `make sim`. | unverified |
| SIM-05 | low | sim | Multi-vFPGA simulation TODO; `cr_sim` hard-codes config 0 / region 0; sim does not model wrapper credits/CDC. | Feature gap. | unverified |
| SIM-06 | low | sim C++ | `VivadoRunner.compileProject` always re-runs compile/elaborate (`-noclean_dir`). | Slow app start. | unverified |

## Build & constraints

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| BLD-01 | med | [FindCoyoteHW.cmake](../../cmake/FindCoyoteHW.cmake) | No `compile` target (PnR = `make shell`); bitgen `OUTPUT` lists name files that are never created. | bitgen always reruns. | unverified |
| BLD-02 | low | [pnr_shell.tcl.in](../../scripts/impl/pnr_shell.tcl.in) | Message tells user to floorplan `shell_subdivided.dcp`, created only later by `flow_dyn`. | Stale/misleading text (see [constraints.md](build/constraints.md) workaround). | unverified |
| BLD-03 | low | cmake / [lynx_pkg_tmplt.txt](../../hw/templates/common/lynx_pkg_tmplt.txt) | `NR_CC` unused; `EN_GP_*` read undefined `N_GP_*`; lynx_pkg tests `cnfg.en_uc`/`en_xch_2`/`en_mem_cred` that are never defined. | Dead / always-false conditionals. | unverified |
| BLD-04 | low | cmake | `HCLK_F` user value overwritten (hard-set per board); `EOS_TIME` only resets the default (driver `eost` parameter overrides). | Config knobs ineffective. | unverified |
| BLD-05 | med | [bitgen.tcl.in](../../scripts/impl/bitgen.tcl.in) | Calls bare `python` for `fix_bif.py` (Versal). | Fails on hosts with only `python3`. | unverified |
| BLD-06 | med | cmake (Versal) | `QDMA_N_ACTIVE_QUEUES(64) >= 3*N_OUTSTANDING` caps `N_OUTSTANDING` at 21; Versal `BUILD_APP` flow appears unsupported (TODO in `gen_targets`). | Limits / unsupported flow. | unverified |
| BLD-07 | med | [u280_shell_base.xdc](../../hw/constraints/u280/shell/synth/u280_shell_base.xdc), `static/impl/u280_static_base.xdc` L12-13 | CMAC refclk period 3.103 ns (shell synth) vs 6.206 ns (static); enabled pins in `u280_shell_net_{0,1}.xdc` are 156.25 MHz (6.4 ns). | Wrong CMAC clock timing on U280, likely copy/paste from U55C. | unverified |
| BLD-08 | low | [hw/constraints/](../../hw/constraints) u55c vs u280 | U55C and U280 shell floorplans are byte-identical; u280 `c0_sys_clk` pins equal `hbm_clk` pins (BJ43/BJ44). | Copy/paste risk; possible pin overlap. | unverified |
| BLD-09 | low | [FindCoyoteHW.cmake](../../cmake/FindCoyoteHW.cmake) vs `link.tcl.in` | Comment "Versal static always re-synthesized" contradicts `link.tcl.in`. | Stale comment. | unverified |
| BLD-10 | low | [example_fplan_u55c.xdc](../../examples/10_app_reconfiguration/hw/floorplans/example_fplan_u55c.xdc) (uncommitted edit) | Comment refers to removed `resize_pblock` lines. | Stale comment. | unverified |
| BLD-11 | low | `flow_dyn_ultrascale_plus.tcl.in` L76 | Re-adds `fplan/` (second `create_pblock pblock_inst_shell`) if checkpoint already has it. | Flagged by constraints doc as unverified behaviour. | unverified |
| BLD-12 | low | [FindCoyoteHW.cmake](../../cmake/FindCoyoteHW.cmake) `validation_checks_hw` | V80 messages mention `BUILD_APP` for 333 MHz override, branch only reached for static/shell flows. | Misleading message. | unverified |

## Documentation drift

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| DOC-01 | med | [sim/README.md](../../sim/README.md) | Stale: file names are `input.bin`/`output.bin` (README says `.sock`, and "input.bin and input.bin"); op codes start at 0 (README: `CSR = 1,...`, split `SET_CSR/GET_CSR`); DUT path is `<build>/sim/user_logic_c0_0.sv` (not `user_c0_0/hdl/wrappers/`); verbose define in `sim/sw/include/coyote/Common.hpp`; RDMA ops not in C++ runner. | Misleads users of the simulator. Rewrite. | unverified |
| DOC-02 | med | [sim/unit_test/README.md](../../sim/unit_test/README.md) | `LOCAL_READ`/`LOCAL_WRITE` direction reversed. | Misleads test authors. | unverified |
| DOC-03 | low | [docs/source/system/dynamic.rst](../source/system/dynamic.rst) | RDMA field layouts (12-bit qpn, 16-bit rkey) outdated. | Trust RTL. | unverified |
| DOC-04 | low | [docs/source/system/static.rst](../source/system/static.rst) | Empty stubs. | Missing docs. | unverified |
| DOC-05 | low | [docs/source/intro/v80-notes.rst](../source/intro/v80-notes.rst) | Documents tuning `HCLK_F` (not a user CMake option) and `mem_block` `0..N_CARD_AXI-1` (not enforced, see MEM-04). | Doc/code mismatch. | unverified |
| DOC-06 | low | [shell_slave.sv](../../hw/hdl/shell/shell_slave.sv) header | Comment says `PROBE_REG` RW and `CTRL_DP_REG_SET/CLR` readable; neither implemented. | Stale comment. | unverified |
| DOC-07 | low | [cThread.hpp](../../sw/include/coyote/cThread.hpp), [cOps.hpp](../../sw/include/coyote/cOps.hpp) | Comments use `RDMA_WRITE` vs enum `REMOTE_RDMA_*`; `SLEEP_TIME` documented ns, used as us. | Stale comments. | unverified |
| DOC-08 | low | [coyote_top.md](coyote_top.md) glossary | Credits pointer should name `hw/hdl/user` local credits, not `mmu_credits_*` (legacy, dead). Example 09 QP exchange lives in `cThread::initRDMA` (not `cConn`); op names are `REMOTE_RDMA_*`. | Fix during integration. | unverified |

## Dead code

| ID | Severity | Location | Issue | Impact / suggested fix | Status |
|---|---|---|---|---|---|
| DEAD-01 | low | `cdma_a` / `cdma_x` (hw/hdl, see `cr_shell.tcl.in`:93) | Not instantiated in the build; changing them does nothing. | Remove or document. | unverified |
| DEAD-02 | low | [mmu_credits_*](../../hw/hdl/mmu), `dma_parser` (missing), `EN_NRU` guards | MMU-level credits dead since `EN_CRED_LOCAL` always 1; `EN_NRU` guards broken. | Delete or repair. | unverified |
| DEAD-03 | low | [user_wrapper_tmplt.txt](../../hw/templates/common/user_wrapper_tmplt.txt) | `EN_USER_REG` block; non-credit branches; `axis_mux_join`, `dest_req_card_arb`, `axis_mux_user_sq/out`, `axis_assign_rq`. | Unused modules/branches. | unverified |
| DEAD-04 | low | `shell_split_data` | Dead while `N_CHAN == N_SCHAN`. | Remove or document. | unverified |
| DEAD-05 | low | network | `network_dropper`, `network_bp_drop`, `rdma_mux_cmd_user`, `rdma_req_parser`, `rdma_mux_cmd_sink` (empty). | Unused. | unverified |
| DEAD-06 | low | [coyote_defs.h:381](../../driver/include/coyote_defs.h) | `IRQ_RCNFG` unused. | Unused define. | unverified |

## Summary by severity

Counts (rows per table; see tables for IDs):

| Area | high | med | low | total |
|---|---|---|---|---|
| Static layer & host DMA | 0 | 6 | 6 | 12 |
| Reconfiguration | 3 | 4 | 4 | 11 |
| Shell registers | 4 | 7 | 4 | 15 |
| MMU | 4 | 8 | 5 | 17 |
| Card memory | 3 | 4 | 5 | 12 |
| Networking | 5 | 2 | 7 | 14 |
| User layer / templates | 1 | 4 | 3 | 8 |
| Driver | 5 | 7 | 3 | 15 |
| Software | 0 | 8 | 7 | 15 |
| Simulation | 0 | 3 | 3 | 6 |
| Build & constraints | 0 | 4 | 8 | 12 |
| Documentation drift | 0 | 2 | 6 | 8 |
| Dead code | 0 | 0 | 6 | 6 |

Totals: 151 items (25 high, 59 med, 67 low); 30 confirmed, 121 unverified.

Items marked `confirmed` were re-opened in the source on this pass; all others are `unverified` (taken from the layer docs / doc-agent log with their line numbers). Several rows cross-reference each other (REC-06/DRV-03, SW-15/NET-14, MEM-09/BLD-03, DEAD-06/STA-12) because the same defect was reported by more than one source.
