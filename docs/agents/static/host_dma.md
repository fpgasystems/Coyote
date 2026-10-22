# Host DMA (XDMA / QDMA), channels, writeback, interrupts, PCI driver

**Purpose:** How host memory is reached from the shell: the DMA IP (XDMA on UltraScale+, QDMA on Versal), the wrappers that turn Coyote's `dmaIntf` requests into IP descriptors, channel/queue allocation, writeback, user interrupts, and the kernel PCI code (`pci_xdma.c`, `pci_qdma.c`, `pci_util.c`) that probes and configures the IP.

## Key files

| Path | Role |
|---|---|
| [xdma_wrapper.sv](../../../hw/hdl/static/xdma_wrapper.sv) | `dmaIntf` <-> `xdmaIntf` (descriptor bypass) per channel (US+) |
| [qdma_rd_wrapper.sv](../../../hw/hdl/static/qdma_rd_wrapper.sv) | Round-robin H2C command arbiter, H2C data demux by QID, completion decode (Versal) |
| [qdma_wr_wrapper.sv](../../../hw/hdl/static/qdma_wr_wrapper.sv) | C2H command/data mux, per-channel queue rotation, prefetch-tag table, tlast/mty/ECC (Versal) |
| [qdma_reg_slice.sv](../../../hw/hdl/static/qdma_reg_slice.sv) | Register slices on QDMA H2C/C2H command + data (timing) |
| [qdma_interrupt_wrapper.sv](../../../hw/hdl/static/qdma_interrupt_wrapper.sv) | One-hot IRQ lines -> QDMA `usr_irq` handshake, one outstanding at a time |
| [wback_dma.sv](../../../hw/hdl/static/wback_dma.sv) | Writeback metadata -> 4-byte DMA write (C2H, channel `N_SCHAN`) |
| [dcpl_static.sv](../../../hw/hdl/static/dcpl_static.sv) | Slices/decouplers between shell and these wrappers |
| [static_slave.sv](../../../hw/hdl/static/static_slave.sv) | `QDMA_PFCH_TAG` register; PR descriptor source for the PR channel |
| [lynx_intf.sv](../../../hw/hdl/pkg/lynx_intf.sv) | Interface defs: `dmaIntf` L140, `xdmaIntf` L272, `qdmaH2CS`, `qdmaH2CIntf`, `qdmaH2CSts`, `qdmaC2HS`, `qdmaC2HIntf`, `qdmaC2HSts`, `qdmaH2CDescMM` |
| [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | `dma_req_t`, `dma_rsp_t`, `wback_t`, `qdma_*_t`, `QDMA_*_QUEUE_*`, `N_HCHAN`, `N_SCHAN` |
| [cr_pci.tcl (US+)](../../../hw/bd/ultrascale_plus/cr_pci.tcl), [cr_pci.tcl (Versal)](../../../hw/bd/versal/cr_pci.tcl) | XDMA / CIPS-QDMA IP configuration |
| [pci_xdma.c](../../../driver/src/platform/pci_xdma.c) / [pci_xdma.h](../../../driver/include/platform/pci_xdma.h) | XDMA probe: engines, MSI-X, BARs, IRQ setup (US+) |
| [pci_qdma.c](../../../driver/src/platform/pci_qdma.c) / [pci_qdma.h](../../../driver/include/platform/pci_qdma.h) | QDMA probe: queue contexts, prefetch tags, host profile, MM engine (Versal) |
| [pci_util.c](../../../driver/src/platform/pci_util.c) / [pci_util.h](../../../driver/include/platform/pci_util.h) | `msix_capable`, `pci_enable_capability`, `build_vector_reg`, `build_u32` |
| [coyote_defs.h](../../../driver/include/coyote_defs.h) | XDMA/QDMA constants, register structs, `bus_driver_data`, IRQ masks |
| [coyote_setup.c](../../../driver/src/coyote_setup.c) | vFPGA devices, writeback buffers (`dma_alloc_coherent`), shell config |

**Related:** [static_top.md](static_top.md) | [reconfig.md](reconfig.md) (the PR path shares channel `N_SCHAN` and the QDMA queue 0) | [../shell/shell_top.md](../shell/shell_top.md) | [../services/mmu.md](../services/mmu.md) (page faults / TLB produce the physical addresses fed to `dmaIntf`) | [../services/memory.md](../services/memory.md) (migration channel, card memory) | [../user/user_top.md](../user/user_top.md) | [../driver.md](../driver.md) | [../software.md](../software.md)

## 1. Interface contract with the shell

- Request interface `dmaIntf` ([lynx_intf.sv](../../../hw/hdl/pkg/lynx_intf.sv) L140): `req` = `dma_req_t {paddr[43:0], len[27:0], last, rsrvd}` (96 bits), `valid/ready`, `rsp` = `dma_rsp_t {done}` (one-cycle completion strobe back to the issuer). `PADDR_BITS=44`, `LEN_BITS=28` (max 256 MB per request; software caps at 128 MB, `MAX_TRANSFER_SIZE`).
- Data: 512-bit `AXI4S` per channel. H2C (host read) = `m_axis_dyn_out` (static -> shell); C2H (host write) = `s_axis_dyn_in` (shell -> static).
- `last` marks the last request of a logical transfer (XDMA: sets the EOP/completed/stop bits of the descriptor control word, only then does XDMA report a completion; QDMA: unused, every request is SOP+EOP with `mrkr_req=1`).
- Physical addresses come from the shell MMU (TLB) or, for the PR/WB channel, directly from the driver / writeback metadata.
- Completion semantics differ: on **XDMA** `rsp.done` = status bit 1, which is only raised for descriptors with `ctl[1]` set, i.e. requests with `last=1` -> **one done per logical transfer**, not per request. On **QDMA** `rsp.done` is generated **per request** (H2C/C2H status record matched on QID; `mrkr_req=1`, SOP+EOP on every command).

## 2. Channel allocation

`N_HCHAN = 3` (fixed), `N_SCHAN = N_HCHAN - 1 = 2` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake)).

| Static channel idx | Name | H2C (read) user | C2H (write) user | Decoupled? |
|---|---|---|---|---|
| `0` | host streaming (`STRM_CHAN` when `EN_STRM`) | vFPGA reads from host | vFPGA writes to host | yes |
| `1` | card / migration (`CARD_CHAN` when `EN_MEM`; if streaming is off this becomes channel 0) | offload (host -> card memory) | sync (card memory -> host) | yes |
| `N_SCHAN` (=2) | PR & writeback | **PR bitstream** (`static_slave` -> `m_pr_dma_rd_req`) | **writeback** (`wback_dma`) | no (PR); WB yes (`s_wback` decoupled) |

- Shell channels not enabled by `EN_STRM`/`EN_MEM` are tied off in the shell ([shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt) ~L581-600).
- `dma_rd_req_int[N_SCHAN]` is driven by `static_slave`; `dma_wr_req_int[N_SCHAN]` by `wback_dma` (through `dcpl_static`); `axis_dyn_out_int[N_SCHAN]` is the PR data sink; `axis_dyn_in_int[N_SCHAN]` the writeback data source.
- The PR/WB channel is the only one monitored by `pr_stats` (static registers 11-16; on Versal PR data beats are not countable, the counters see 4 KiB descriptors). Shell-side stats for channels 0..N_SCHAN-1 are in the shell register file (`hdma_debug[12]`, read via `IOCTL_SHELL_HDMA_STATS`).
- Driver channel limits: `XDMA_MAX_NUM_CHANNELS=3`; `QDMA_N_ACTIVE_QUEUES=64` per direction.

## 3. XDMA path (UltraScale+)

IP: `xilinx.com:ip:xdma` 4.1 (Vivado < 2025.1) / 4.2 (>= 2025.1), AXI-Stream mode (`xdma_axi_intf_mm = AXI_Stream`), `xdma_{r,w}num_chnl = N_HCHAN`, `dsc_bypass_{rd,wr}` = bitmask of all channels (every channel in descriptor-bypass mode), `axist_bypass_en` (256 MB AXI bypass BAR for `axi_main`), AXI-Lite master for `axi_cnfg`, `xdma_num_usr_irq=16`, MSI-X (32-entry table), 512-bit data, `xdma_sts_ports` enabled (descriptor status). [cr_pci.tcl](../../../hw/bd/ultrascale_plus/cr_pci.tcl) has per-device blocks (`u250/u200`, `u280/u55c`).

Per-channel datapath:
- Data: `axis_dyn_in_N` -> XDMA `S_AXIS_C2H_N`; XDMA `M_AXIS_H2C_N` -> `axis_dyn_out_N`. No wrapper on data.
- Command ([xdma_wrapper.sv](../../../hw/hdl/static/xdma_wrapper.sv)): `{h2c,c2h}_addr = req.paddr`, `{h2c,c2h}_len = req.len`, `ctl = {11'b0, last, 2'b0, last, last}` (per XDMA bypass control: bit4 = EOP, bit1 = completed, bit0 = stop; all three are set only when `last=1`), `valid = req.valid & xdma ready`, `rsp.done = {h2c,c2h}_status[1]` (descriptor completed; only fires for `last=1` requests).
- Status ports (`dsc_status_{h2c,c2h}_sts<i>`) are 8-bit per channel; only bit 1 is used.
- XDMA channel `i` <-> Coyote channel `i`; the PR/WB channel is XDMA channel `N_SCHAN` (H2C for PR, C2H for writeback).

## 4. QDMA path (Versal)

IP: Versal CIPS CPM5 QDMA (`DMA_INTF = AXI_MM_and_AXI_Stream`, `DSC_BYPASS_RD/WR = 1`, MSI-X table `0x1F`), configured in [cr_pci.tcl](../../../hw/bd/versal/cr_pci.tcl): PCIE0 x16 Gen4 (`dma0_*` pins) or PCIE1 x8 Gen5 (`dma1_*` pins, selected by `PCIE_GEN`). Used ports: ST H2C/C2H data + bypass commands, MM H2C bypass descriptor channel 0 (PR), user-IRQ interface, status interfaces (`h2c_status` always-ready). Tied off: MM H2C ch1, MM C2H ch0/1, `*_byp_out_ready`, `tm_dsc_sts_rdy`, `st_rx_msg_tready`, `cpm_irq0/1`; `intrfc_resetn` tied 1.

### Queue map (hardware = driver constants, [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) / [coyote_defs.h](../../../driver/include/coyote_defs.h))

| QIDs | Direction/type | Used by |
|---|---|---|
| `0` (`QDMA_PR_QUEUE_IDX`) | H2C **memory-mapped**, bypass, MM channel 0 | `pr_ctrl_versal` (PR bitstream -> PMC) |
| `1 .. 64` (`QDMA_RD_QUEUE_START_IDX` + i) | H2C streaming, bypass | `qdma_rd_wrapper`: **one queue per channel** (`qid = 1 + ch`, only `0..N_SCHAN-1` used) |
| `256 .. 319` (`QDMA_WR_QUEUE_START_IDX = 512/2` + i) | C2H streaming, simple bypass with prefetch tags | `qdma_wr_wrapper`: `N_OUTSTANDING` (default 8) queues per channel: `qid = 256 + ch*N_OUTSTANDING + k` |

`QDMA_N_QUEUES=512` is the minimum common to all devices; the driver enables 1 + 64 + 64 = 129 queues. Writes use several queues per channel because write throughput needs multiple outstanding C2H commands (each needs its own prefetch tag); reads use one queue per channel to avoid reordering.

### qdma_rd_wrapper (H2C)
- Command: round-robin over `N_CHAN=N_SCHAN` channels with `valid` (the pointer advances on every grant); emits `addr=paddr`, `len=len[15:0]` (QDMA command only carries 16 bits), `qid = 1 + ch`, `sop=eop=mrkr_req=1`, `func=0`, other fields 0.
- Completion: H2C status record valid, `qid == 1+i`, `port_id==0`, `op==8'h1` (H2C-ST), and `!data[16]` (error) -> `s_dma_rd[i].rsp.done`. A status with the error bit set never produces `done`, so the issuer's credit is never returned (no error path).
- Data: `qdma_out` (H2C stream) routed to `dyn_out[i]` where `qid == 1+i`, `tkeep` rebuilt from `mty` on `tlast`. Beats with `err` or `zero_byte` set (or an unexpected qid) are **not** forwarded and `qdma_out.tready` is only raised when some `dyn_out[i]` is valid and ready, so such a beat is never consumed and the H2C stream stalls.
- Limit: `len[15:0]` truncates requests >= 64 KiB. The real users of this wrapper are the local read channels (the PR path does **not** go through it: `dma_rd_req_int[N_SCHAN]` feeds `pr_ctrl_versal`, which builds its own MM descriptors in 4 KiB pieces). Local transfers are split at `PMTU_BYTES` (default 4096) by the shell `req_parser` and at page boundaries by the TLB FSM, and migrations are issued in 4 KiB chunks (`vfpga_hw.c`), so the limit is not hit in practice.

### qdma_wr_wrapper (C2H)
- FSM `ST_IDLE` / `ST_WRITING`: one command + its data at a time; command and data are never issued in the same cycle.
- Arbitration: **writeback channel (`N_CHAN-1`) first**, otherwise lowest-index valid channel (fixed priority, not round-robin).
- Queue: `qid = 256 + ch*N_QUEUES_PER_CHAN + chan_qid[ch]`, rotating `chan_qid` after each completed transfer. `pfch_tag = pfch_tags[ch*N_QUEUES_PER_CHAN + chan_qid]`.
- `pfch_tags[0..255]` table is loaded from `static_slave.QDMA_PFCH_TAG` (`valid`, `qid[7:0]` relative to 256, `tag`) when `pfch_tag_valid`.
- Data: length is not part of the command; it is buffered and sent in the C2H data sideband (`payload.len`, `qid`). `tlast` is asserted at the last beat of **every** request (required by QDMA, unlike XDMA); `mty` = number of empty bytes from `tkeep` on the last beat; ECC computed by IP `qdma_ecc` over `{qid,len,...}`; `has_cmpt=0` (no completion entries to host), `marker=0`.
- Completion: C2H status valid, `qid` within the channel's queue range, `!drop && !error` -> `s_dma_wr[i].rsp.done`; `drop`/`error` statuses never produce `done` (credit leak, no error path). C2H length is also 16-bit (`curr_dma_wr_len[15:0]`, 11-bit beat counter).

### qdma_reg_slice
One `register_slice_qdma_{h2c_cmd,c2h_cmd,data}` stage (`N_STAGES=1`) on all four QDMA streams; the command path is otherwise a long combinational chain.

### Prefetch tags (C2H simple bypass)
QDMA requires a prefetch tag per C2H command in bypass mode. For each C2H queue `enable_queue()` writes `QDMA_C2H_PFCH_BYP_QID_REG (0x1408) = qid`, reads `QDMA_C2H_PFCH_BYP_TAG_REG (0x140c)` (`[6:0]` tag, `[19:8]` qid), subtracts `QDMA_WR_QUEUE_START_IDX`, writes `stat_cnfg->qdma_pfch_tag = (1<<31)|(qid<<8)|tag`, then clears it. Max 64 queues: the hardware port is 7-bit (`pfch_tag[6:0]`, driver masks `0x7F`), the 64 limit comes from comments/guards in the driver (`coyote_defs.h` ~L169, `enable_queues`).

## 5. Writeback

- Purpose: let SW poll host memory for completion counters instead of PCIe MMIO. Per vFPGA the driver `dma_alloc_coherent`s `WB_SIZE = WB_BLOCKS(4) * N_CTID_MAX(64) * 4 B = 1 KiB` (`set_memory_uc`), and programs `cnfg_regs->wback[j] = wb_phys_addr + j*256` for j in {local RD, local WR, RDMA RD, RDMA WR} ([coyote_setup.c](../../../driver/src/coyote_setup.c) ~L478-483).
- HW (shell `cnfg_slave`, and `cnfg_slave_avx`): on every completed transfer (`meta_done_*`, keyed by ctid; [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv) ~L1432-1452) it emits `wback_t {paddr = base[j] + (ctid<<2), value = counter+1}` (also a clearing write of 0 on `rd_clear/wr_clear`).
- Static path: `s_wback` -> `meta_decoupler_static` -> `wback_dma` -> 4-byte write on channel `N_SCHAN` (`len=4`, `last=1`) with the 32-bit value on `axis_dyn_in_int[N_SCHAN]` -> XDMA C2H ch2 / QDMA writes (priority queue range of channel `N_CHAN-1`).
- SW: `cThread::mmapFpga` maps `MMAP_WB` -> `wback`; `checkCompleted()` reads `wback[ctid + {RD,WR,...}_WBACK*N_CTID_MAX]`; `clearCompleted()` zeroes them ([cThread.cpp](../../../sw/src/cThread.cpp) L1011-1076).
- Disabled by `EN_WB=0` (`WB_FLOW`), in which case `m_wback` is tied off in the shell and SW polls registers.

## 6. User interrupts

| Bit | Source | Notes |
|---|---|---|
| `usr_irq[0..N_REGIONS-1]` | vFPGA `i` (`cnfg_slave.irq_pending`, aggregated: offload/sync/invalidate/page-fault/notify types, see `IRQ_*` in [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt)) | `s_usr_irq[14:0]` passes `dcpl_static` (decoupled) |
| `usr_irq[15]` | `static_slave.pr_irq` (PR done) | `FPGA_RECONFIG_IRQ_VECTOR = 15`, mask `0x8000`; vFPGA mask `FPGA_USER_IRQ_MASK = 0x7fff` |

- US+ (XDMA): `usr_irq[15:0]` -> XDMA `usr_irq_req`. Driver: `vfpga_interrupts_enable` writes `user_int_enable_w1s = 0x7fff`, `reconfig_interrupt_enable` writes `0x8000` (XDMA IRQ block at `BAR_DMA_CONFIG + XDMA_OFS_INT_CTRL (0x2000)`); `write_msix_vectors()` programs `user_msi_vector[0..3]` so user IRQ `i` -> MSI-X vector `i` (done once, at probe).
- Versal (QDMA): [qdma_interrupt_wrapper.sv](../../../hw/hdl/static/qdma_interrupt_wrapper.sv): FSM `IDLE -> SEND -> WAIT -> DONE`. Picks the **lowest-index** asserted bit `idx`, drives `usr_irq_valid`, `usr_irq_vec = idx`, `usr_irq_fnc = 0` until `usr_irq_ack` (or retries on `usr_irq_fail`), then waits until the driver clears the source bit (`usr_irq[idx]==0`) before servicing the next. Consequence: **interrupts are serialized**, and an uncleared vFPGA IRQ blocks all others including PR (bit 15). Vector number = bit index; there is no enable register on QDMA.
- Linux side (both): `pci_check_msix()` allocates MSI-X vectors (`XDMA_MAX_NUM_ENGINES + XDMA_N_MAX_IRQ = 22` on US+, `QDMA_N_MAX_IRQ = 16` on Versal); `irq_setup()` does `request_irq(pci_irq_vector(pdev, i), vfpga_isr, ..., &vfpga_dev[i])` for `i < n_fpga_reg` and, with `enable_reconfig_irq`, `request_irq(pci_irq_vector(pdev, 15), reconfig_isr, ..., reconfig_dev)`.
- ISR flows: `vfpga_isr` ([vfpga_isr.c](../../../driver/src/vfpga/vfpga_isr.c)): reads the IRQ type from the vFPGA's config registers (`read_irq_type`) -> wakes waitqueues (offload/sync/invalidate) or queues work (`vfpga_pfault_handler`, `vfpga_notify_handler`), then `clear_irq` (`isr_ctrl = FPGA_CNFG_CTRL_IRQ_CLR_PENDING`). `reconfig_isr`: see [reconfig.md](reconfig.md). Notifications reach SW via the `eventfd` registered by `IOCTL_REGISTER_EVENTFD` and the `uisr` callback in `cThread::eventHandler`. Details: [../driver.md](../driver.md#interrupt-flow), [../user/user_top.md](../user/user_top.md).

## 7. XDMA vs QDMA

Platform-level differences: [UltraScale+ vs Versal](../coyote_top.md#ultrascale-vs-versal-summary).

| | XDMA | QDMA |
|---|---|---|
| Command model | Per-channel descriptor bypass (`addr,len,ctl`) | Single bypass stream for H2C and for C2H, tagged by `qid`; per-request SOP/EOP |
| Channel separation | Hardware channel `i` | Queue IDs (`1+ch`, `256+ch*N_OUT+k`) |
| Completion | Channel status bit, once per transfer (`last=1`) | Status stream with `qid`, `op`, error/drop bits, once per request |
| Write fan-out | One engine per channel | `N_OUTSTANDING` queues per channel + prefetch tags |
| Max cmd length | 28 bits | 16 bits in the bypass command (`len[15:0]`) |
| Arbitration | None (IP internal) | `qdma_rd_wrapper` RR; `qdma_wr_wrapper` WB-first then fixed priority |
| tlast | Only on last request of a transfer | Every request |
| IRQ | Parallel, XDMA IRQ block + MSI-X table | Serialized by `qdma_interrupt_wrapper` |
| Driver init | `probe_engines`: engines ID `0x1fc0` (H2C) / `0x1fc1` (C2H), `engine_create` sets `ctrl` RUN | `enable_queues`: FMAP, host profile, steering, PR queue, 64 H2C + 64 C2H queues, `0xab0` C2H buffer = `PAGE_SIZE`, H2C MM engine run (`0x1204`) |
| Limits | 3 channels | `QDMA_N_ACTIVE_QUEUES=64` (prefetch tags: 7-bit port, 64 assumed) |

## 8. Driver platform code

Common probe skeleton (both): `devm_kzalloc(bus_driver_data)` -> `pci_enable_device` -> `assign_device_id` (names `coyote_fpga_<id>`, `coyote_fpga_<id>_reconfig`) -> PCIe tweaks (relaxed ordering, extended tag, `pcie_set_readrq(512)`, `pci_set_master`) -> `pci_check_msix` -> `pci_request_regions` -> `map_bars` (first `CYT_BARS=3` non-empty BARs, `pci_iomap`) -> `dma_set_mask_and_coherent(DMA_BIT_MASK(44))` -> platform DMA init (US+: `probe_engines`; Versal: `ioremap` stat/shell BARs then `enable_queues`) -> shell reset pulse (`reconfig_eost_reset` 0 -> 1) -> `read_shell_config` -> sysfs -> card memory -> reconfig device -> vFPGA devices -> `irq_setup(.., true)` (+ US+ interrupt enables). `pci_remove` reverses. `shell_pci_init/remove` (called from `IOCTL_RECONFIGURE_SHELL`) redo only the shell-dependent part (config read, sysfs, card memory, vFPGA devices, vFPGA IRQs).

### pci_xdma.c
- `probe_for_engine(c2h, channel)`: offset = `c2h*0x1000 + channel*0x100` in `BAR_DMA_CONFIG`; checks `id[31:16] == 0x1fc0/0x1fc1` and channel id `id[11:8]`.
- `engine_create`: `ctrl_w1c`, read `alignments`, then `ctrl = IE_DESC_STOPPED | IE_DESC_COMPLETED | RUN_STOP`.
- Registers declared in `struct xdma_engine_regs`, `struct xdma_interrupt_regs` ([coyote_defs.h](../../../driver/include/coyote_defs.h) L466-515). SGDMA registers are mapped but unused: Coyote uses **only descriptor bypass**, the driver never submits XDMA descriptors.
- `read_interrupts()` just logs `user_int_request` / `channel_int_request`.

### pci_qdma.c
- `enable_queue(qid, c2h, is_mm, mm_chn)`: clear SW/HW/credit contexts -> program SW context (`0x80040001` for MM ch0, `0x00040001` for ST; bypass bit set) through the indirect context interface (`QDMA_CTX_CMD_REG 0x844`, data `0x804..`, mask `0x824..`) -> verify `idl_stp_b` -> clear prefetch + completion contexts -> for C2H: prefetch context (`0x1`, valid bit) and prefetch tag hand-off to `static_slave` -> write completion context (`dir_c2h` for C2H).
- `enable_queues`: FMAP (QID base 0, max `QDMA_N_QUEUES-1`), host profile, **steering**: H2C MM data goes via `CPM_PCIE_NOC_1` (QDMA_CTXT_SELC_HOST_PROFILE), queues: PR (MM), H2C ST 1..64, `0xab0 = PAGE_SIZE`, C2H ST 256..319, then `iowrite32(1, QDMA_H2C_MM_CTRL_REG)`. C2H MM is not enabled (commented).
- `disable_queues`: invalidate contexts (prefetch, completion, SW) per queue, free structs.
- `wait_until_busy_cleared` polls `QDMA_CTX_CMD_REG` bit0 (`usleep_range` per poll), bounded to `DMA_CTX_BUSY_POLLS`=10000: `-ENODEV` if the register reads all ones, `-ETIMEDOUT` otherwise.
- Debug: `cyt_attr_qdma_debug_regs` sysfs dumps QDMA error status registers (`0xAF0`, `0xAF8`, `0xF4`, `0xFC`, `0x1058`, `0x1258`, `0x264`, `0x254`, `0x248`).

### pci_util.c
`msix_capable()`, `pci_enable_capability()` (PCIe DEVCTL), `build_vector_reg(a,b,c,d)` (4x5-bit MSI-X vector fields, 8-bit stride) and `build_u32`.

## Driver & software interaction

**Data-transfer path (the host DMA is not driven directly by SW or the driver; the shell issues descriptors):**

1. `invoke` -> registers -> shell (`cnfg_slave`, MMU/TLB translation, `dmaIntf` request on static channel 0/1): [user_top.md section 7.1](../user/user_top.md#71-invoke---registers---hardware).
2. Static: `dcpl_static` -> `xdma_wrapper` (US+) or `qdma_{rd,wr}_wrapper` (Versal) -> XDMA/QDMA -> PCIe -> host memory; data on the 512-bit AXI-Stream.
3. Completion: `rsp.done` back to the shell, which bumps counters and (WB) emits `s_wback` -> `wback_dma` -> C2H 4-byte write into the per-vFPGA writeback page; `cThread::checkCompleted()` polls it. No interrupt and no driver involvement in the common path.
4. Migration (`cThread::invoke(LOCAL_OFFLOAD|LOCAL_SYNC, syncSg)` ([cThread.cpp](../../../sw/src/cThread.cpp) L778) -> `IOCTL_OFFLOAD_REQ` / `IOCTL_SYNC_REQ` -> [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c)) programs `offl_*` / `sync_*` registers of the vFPGA config space; the shell then uses static channel 1; completion IRQ type `IRQ_DMA_OFFL`/`IRQ_DMA_SYNC` -> `vfpga_isr` -> wakes the ioctl.

**Interrupt path (reverse):** vFPGA `irq_pending` -> `s_usr_irq[i]` -> `dcpl_static` -> (US+) `usr_irq[i]` / (Versal) `qdma_interrupt_wrapper` -> MSI-X vector `i` -> `vfpga_isr` (reads the type from the vFPGA config registers, wakes waitqueue or `queue_work` `vfpga_pfault_handler` / `vfpga_notify_handler`) -> `clear_irq` writes `isr_ctrl` -> line drops (Versal: wrapper advances). Notifications -> `eventfd` -> `cThread` epoll thread -> `IOCTL_GET_NOTIFICATION_VALUE` -> user `uisr` -> `IOCTL_SET_NOTIFICATION_PROCESSED`. Page faults: `vfpga_pfault_handler` pins pages, updates TLB, `restart_mmu` writes `isr_ctrl = FPGA_CNFG_CTRL_IRQ_PF_{RD,WR}_SUCCESS`.

| Register / ioctl | RTL | Driver | SW |
|---|---|---|---|
| vFPGA `ctrl/vaddr_rd/vaddr_wr` | `cnfg_slave` (shell) | none (mmap'd) | `cThread::postCmd`, `invoke` |
| `wback[0..3]` | `cnfg_slave` -> `s_wback` -> `wback_dma` | `coyote_setup.c` (alloc + program) | `mmap(MMAP_WB)`, `checkCompleted/clearCompleted` |
| `isr_ctrl`, `isr_*` | `cnfg_slave` irq mux | `vfpga_isr.c`, `vfpga_hw.c` (`read_irq_type`, `clear_irq`) | eventfd, `IOCTL_{GET,SET}_NOTIFICATION_*` |
| `QDMA_PFCH_TAG` (static 0x44) | `static_slave` -> `qdma_wr_wrapper` | `enable_queue` | none |
| XDMA `user_int_enable_*`, `user_msi_vector[]` | XDMA IP | `pci_xdma.c` | none |
| QDMA context regs `0x804-0x844`, `0x1204`, `0xab0`, `0x1408/0x140c` | QDMA IP | `pci_qdma.c` | none |
| `IOCTL_SHELL_HDMA_STATS` | shell `hdma_debug[]` (`shell_slave` exposes 3 regs/channel; the driver copies `N_HDMA_STAT_CH_REGS`=4 per channel) | [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c) L566 | macro in [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp) only, no SW wrapper |
| `IOCTL_PR_WB_STATS` / sysfs `cyt_attr_prstats` | `pr_stats` via `static_slave` | [reconfig_ops.c](../../../driver/src/reconfig/reconfig_ops.c), [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c) | none |

See also [../driver.md](../driver.md#static-layer--host-dma), [../driver.md](../driver.md#interrupt-flow), [../driver.md](../driver.md#user-interrupts), [../software.md](../software.md#cthread-internals) and [../software.md](../software.md#user-interrupts).

## Config knobs

| Knob | Effect |
|---|---|
| `N_HCHAN` (3), `N_SCHAN` | channel count (XDMA channels, QDMA read channels) |
| `N_OUTSTANDING` | QDMA write queues per channel (and shell outstanding requests); `N_OUTSTANDING * N_HCHAN <= 64` required by `QDMA_N_ACTIVE_QUEUES` (64 prefetch tags assumed in the driver) |
| `PCIE_GEN` (4/5), `SCLK_F` | Versal link config / static clock (throughput) |
| `EN_WB` | writeback on/off |
| `EN_STRM`, `EN_MEM` | which of channel 0/1 are live |
| `NR_ST_S0/S1` | slice depths |
| `NR_HST` | `HDMA_STATS_DELAY` (stats register delay, not a slice depth) |
| Driver: `TARGET_PLATFORM`, `QDMA_N_ACTIVE_QUEUES`, `DMA_BIT_MASK(44)` | platform build and limits |

## Gotchas and invariants

- Never change channel/queue constants in only one place: `QDMA_*_QUEUE_*` exist in both [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) and [coyote_defs.h](../../../driver/include/coyote_defs.h); mismatch silently routes data to disabled queues.
- QDMA C2H needs a valid prefetch tag per queue **before** hardware issues commands to it; tags are only learned in `enable_queue` at probe. Reloading the shell does not re-run this (static layer persists), but a QDMA reset would require reloading the driver.
- QDMA H2C/C2H bypass commands carry 16-bit `len`; keep shell packetization (`PMTU_BYTES`) and migration chunks below 64 KiB.
- `eos_pmc`/PR data on Versal share the QDMA but use MM queue 0 and NoC_1; do not enable C2H MM or MM channel 1 without changing `cr_pci.tcl` (driver warns in `enable_queue`).
- `usr_irq` width is 15 for vFPGAs; `N_REGIONS <= 15` is enforced by CMake ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) ~L497).
- Known defects in this area: [known_issues.md](../known_issues.md) (`STA-*`).

## How to modify / extend

- **Add a DMA channel (XDMA):** raise `N_HCHAN`, update `xdma_{r,w}num_chnl`/`dsc_bypass` in `cr_pci.tcl`, `XDMA_MAX_NUM_CHANNELS`, `N_HDMA_STAT_CH_REGS`, shell channel mapping; rebuild static checkpoint ([static_top.md](static_top.md#8-routed-locked-checkpoints)).
- **Add a QDMA channel/queue range:** update `N_SCHAN`/`N_OUTSTANDING`, ensure `QDMA_RD_QUEUE_START_IDX + N_SCHAN <= QDMA_WR_QUEUE_START_IDX`, `N_OUTSTANDING*N_HCHAN <= QDMA_N_ACTIVE_QUEUES`; the driver enables all `QDMA_N_ACTIVE_QUEUES` automatically.
- **Change write parallelism on Versal:** `N_OUTSTANDING` (CMake). `qdma_wr_wrapper.N_QUEUES_PER_CHAN` follows.
- **Add an interrupt source:** extend shell IRQ aggregation (bits 0..14); on US+ nothing else; on Versal nothing else (vector = bit index, serialized). Add `request_irq` in `irq_setup` if it needs its own handler (`FPGA_RECONFIG_IRQ_VECTOR` style).
- **Enable C2H MM / MM channel 1 on Versal:** tie the corresponding `byp_in_mm_*_valid` in `cr_pci.tcl` to logic instead of `const_0`, set `QDMA_C2H_MM_CTRL_REG` run bit, add queue via `enable_queue(.., is_mm=true, mm_chn)`.
- **New platform ID:** add the PCI device ID to `pci_ids` in the platform file.
