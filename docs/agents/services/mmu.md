# MMU: shared virtual memory (TLBs, page faults, migration, GPU P2P)

**Purpose.** Hardware MMU in the dynamic layer that translates vFPGA virtual addresses (per Coyote thread, `ctid`) to host / card / GPU-bus physical addresses, steers each request to the right DMA engine, and raises IRQs to the driver on TLB misses. Software (driver + `cThread`) populates the TLBs, migrates pages host<->card, and handles invalidation.

**Scope.** `hw/hdl/mmu/*`, the `cnfg_slave` ISR/offload/sync registers it talks to, `driver/src/vfpga/*`, and the memory APIs in `cThread`. Card memory *allocation internals* (HBM/DDR, striping) live in [memory.md](memory.md).

## Key files

| Path | Role |
|---|---|
| [mmu_top.sv](../../../hw/hdl/mmu/mmu_top.sv) | Top: N_REGIONS x `mmu_region_top`, host/card arbiters, `cnfg_slave` per region, ISR (offload/sync) arbiters |
| [mmu_region_top.sv](../../../hw/hdl/mmu/mmu_region_top.sv) | Per-vFPGA: sTLB + lTLB, 2 FSMs (rd, wr), RD/WR mutex, DMA req queues, (optional) credits |
| [tlb_fsm.sv](../../../hw/hdl/mmu/tlb_fsm.sv) | Request FSM (`RDWR` param): lookup, page split, DMA issue, page-fault IRQ + request cache, invalidation drain |
| [tlb_controller.sv](../../../hw/hdl/mmu/tlb_controller.sv) | One set-associative TLB (BRAM): lookup, insert/remove, NRU eviction |
| [tlb_slave_axil.sv](../../../hw/hdl/mmu/tlb_slave_axil.sv) | AXI4-Lite slave (2x64b regs) that pushes a 128b TLB command to `tlb_controller` |
| [mmu_arbiter.sv](../../../hw/hdl/mmu/mmu_arbiter.sv) | RR over vFPGAs for host DMA reqs; emits mux sequence (`mux_host_t`) + completion routing |
| [mmu_arbiter_isr.sv](../../../hw/hdl/mmu/mmu_arbiter_isr.sv) | RR over vFPGAs for offload/sync (migration) requests; fans out to host-DMA + card-DMA |
| [mmu_assign.sv](../../../hw/hdl/mmu/mmu_assign.sv) | Per card-port: forces `last=1` on DMA req, forwards real `last` to the data path |
| [axis_mux_host_src.sv](../../../hw/hdl/mmu/axis_mux_host_src.sv) / [axis_mux_host_sink.sv](../../../hw/hdl/mmu/axis_mux_host_sink.sv) | De-mux host read stream to vFPGAs / mux vFPGA write streams to host DMA, driven by `mux_host_t` {vfid,len,last} |
| [axis_last_rewriter.sv](../../../hw/hdl/mmu/axis_last_rewriter.sv) | Card read path: `tlast = tlast & fwd_last` (restores true `last`) |
| [mmu_credits_rd.sv](../../../hw/hdl/mmu/mmu_credits_rd.sv) / [mmu_credits_wr.sv](../../../hw/hdl/mmu/mmu_credits_wr.sv) | MMU-level credit gating (compiled **out** by default, see Credits) |
| [data_queue_credits_src.sv](../../../hw/hdl/mmu/data_queue_credits_src.sv) / [data_queue_credits_sink.sv](../../../hw/hdl/mmu/data_queue_credits_sink.sv) | 512b data FIFOs that emit `rxfer` / `wxfer` strobes for the credit modules |
| [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv) (+ `cnfg_slave_avx.sv`) | Per-vFPGA config regs: ISR regs, restart/drop, invalidate, offload/sync (instantiated by `mmu_top`) |
| [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | TLB params, `req_t`, `pf_t`, `inv_t`, `irq_pft_t`, `dma_req_t`, `dma_isr_req_t`, IRQ codes |
| [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt) | Instantiates `mmu_top` (~L1017-1019), host mux, card DMA/last-rewriter, migration `cdma` |
| [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) | User-facing TLB knobs (`TLBS_*`, `TLBL_*`, `N_TLB_ACTV`, `VADDR_BITS`) |
| [vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c) | Driver register-level ops: TLB (un)map, restart/drop, invalidate, lock, offload/sync, card alloc |
| [vfpga_isr.c](../../../driver/src/vfpga/vfpga_isr.c) | IRQ handler + page-fault workqueue handler |
| [vfpga_gup.c](../../../driver/src/vfpga/vfpga_gup.c) | Page-fault policy: pin pages, dma_map, card alloc, migration, TLB map/unmap, dma-buf (GPU) |
| [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c) | ioctls: `IOCTL_MAP_USER_MEM`, `..._DMABUF`, `..._OFFLOAD_REQ`, `..._SYNC_REQ` |
| [coyote_defs.h](../../../driver/include/coyote_defs.h) | `tlb_metadata`, `user_pages`, `vfpga_cnfg_regs`, IOCTL / FPGA_CNFG_CTRL_* / IRQ_* defs |
| [coyote_setup.c](../../../driver/src/coyote_setup.c) | Reads TLB geometry from shell config reg (`ctrl_cnfg`) into `stlb_meta`/`ltlb_meta` |
| [cThread.cpp](../../../sw/src/cThread.cpp), [cOps.hpp](../../../sw/include/coyote/cOps.hpp), [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp) | `getMem/freeMem/userMap/userUnmap`, `CoyoteAlloc`, `invoke(LOCAL_SYNC/OFFLOAD)` |
| [examples/06_gpu_p2p](../../../examples/06_gpu_p2p/README.md) | GPU buffers via `CoyoteAllocType::GPU` |

**Related:** [shell_top.md](../shell/shell_top.md) (cnfg reg map, xbar, TLB register windows), [user_top.md](../user/user_top.md) (vFPGA `sq_rd/sq_wr/cq`, local credits), [memory.md](memory.md) (card memory), [host_dma.md](../static/host_dma.md) (XDMA/QDMA, migration channel), [network.md](network.md), [driver.md](../driver.md#mmu-and-page-faults), [software.md](../software.md#mmu-and-page-faults), [coyote_top.md](../coyote_top.md).

## What it does (one paragraph)

Every vFPGA request (`req_t`: `vaddr`, `len`, `pid`=ctid, `strm`, `dest`, `last`) from `sq_rd`/`sq_wr` or from a host-issued `invoke` arrives at `tlb_fsm`. The FSM looks `vaddr` up in both TLBs in parallel, splits the request at page boundaries, and emits `dma_req_t {paddr,len,last}` to the **host** DMA (`strm==STRM_HOST`) or the **card** DMA port selected by `dest`. A miss stalls that direction, sends an IRQ, and waits for the driver to fill the TLB and restart (or drop) the request. There is one MMU per vFPGA (separate rd and wr FSMs), so one vFPGA's fault does not stall another.

## Sub-components

### Hierarchy

```
mmu_top (ID_DYN)                              hw/hdl/mmu/mmu_top.sv
|- mmu_region_top[i]  i < N_REGIONS           per vFPGA
|   |- tlb_slave_axil  x2 (lTLB, sTLB)        AXI4-L (BAR window) -> 128b cmd
|   |- tlb_controller  x2 (lTLB, sTLB)        BRAM, N_ASSOC ways each
|   |- tlb_fsm RDWR=0 (rd) / RDWR=1 (wr)      share TLB lookup port via `mutex`
|   |- dma_req_queue (+ dma_parser, mmu_credits_rd/wr if !EN_CRED_LOCAL)  -> HDMA / DDMA[N_CARD_AXI]
|- mmu_arbiter  rd / wr  (EN_STRM)            RR over regions -> m_{rd,wr}_HDMA_host + m_mux_host_{rd,wr}
|- mmu_assign   rd / wr  (EN_MEM, per N_REGIONS*N_CARD_AXI) -> m_{rd,wr}_CDMA_card + rd_fwd_last_card
|- cnfg_slave[i] (or cnfg_slave_avx if EN_AVX)  ISR regs, offload/sync, user CSR, host sq, completions
|- mmu_arbiter_isr offload (RDWR=0) / sync (RDWR=1)  (EN_MEM) -> migration DMA channel
|- meta_arbiter ARP / RDMA qp+conn / TCP / WB   (service control, not MMU)
```
`usr_irq[i]` = `cnfg_slave.irq_pending` -> static layer MSI-X vector for vFPGA i.

### TLB design (`tlb_controller`)

Two independent TLBs per vFPGA, looked up in parallel; `lTLB` hit wins (`tlb_fsm` ST_CHECK).

| | sTLB ("small") | lTLB ("large/huge") |
|---|---|---|
| Page order (`PG_*_BITS`) | `TLBS_BITS`=12 (4 KiB) | `TLBL_BITS`=21 (2 MiB); 1 GiB (30) is host-only and has issues, see Gotchas |
| Sets (`TLB_*_ORDER`) | `TLBS_S`=10 (1024) | `TLBL_S`=9 (512) |
| Ways (`N_*_ASSOC`) | `TLBS_A`=4 | `TLBL_A`=2 |
| Storage | one `ram_tp_c` (BRAM) per way, + 1-bit ref RAM and 1-bit mod RAM per way | same |
| Index (key) | `vaddr[PG_BITS +: TLB_ORDER]` (low VPN bits, **not hashed**) | same |
| Tag | `vaddr[PG_BITS+TLB_ORDER +: TAG_BITS]`, `TAG_BITS = VADDR_BITS - TLB_ORDER - PG_BITS` (VADDR_BITS=48) | same |
| Phys | `PADDR_BITS(44) - PG_BITS` = page number | same |

Stored entry (`TLB_DATA_BITS`=104-bit RAM word; fields LSB-first, see `tlb_controller` `tlb_data_upd_in` and `tlb_fsm` `PHY_*_OFFS`):

```
[TAG_BITS | PID_BITS=6 | STRM_BITS=2 | V=1 | PHY_BITS | HPID_BITS=32]
  tag        ctid        stream(0=card,1=host)  valid   phys page nr   host pid
```
Hit = `tag == && pid(ctid) == && valid && (strm ==  only if EN_STRM && EN_MEM)`. A stream mismatch is therefore a **miss** -> the driver migrates the data. `hpid` is not compared on lookup; it is used for removal/invalidate matching.

Controller write command (128b = `{reg1, reg0}` from `tlb_slave_axil`; AXI4-L offsets +0x0 / +0x8 in each TLB window; **the write to reg1 triggers the push**, so write reg0 first):

| Word | Bits | Field |
|---|---|---|
| reg0 (+0x0) | `[PHY_BITS-1:0]` | physical page number (`paddr >> page_shift`) |
| reg0 | `[63:32]` | `hpid` |
| reg1 (+0x8) | `[KEY-1:0]` | set index (key) |
| reg1 | `[KEY +: TAG]` | tag |
| reg1 | next 6 / 2 / 1 bits | `ctid` / stream (`host`) / **valid** (1 = insert, 0 = remove) |

Controller FSM (`ST_IDLE->WAIT_1->WAIT_2->COMP`, ~4 cycles after the 128b FIFO):
- **Insert** (`valid=1`): first invalid way (`entry_insert_fe`), else NRU victim (`entry_insert_se`, min of `{ref_r, ref_m}`; ties -> highest way index). No duplicate check: inserting an already-present tag allocates another way.
- **Remove** (`valid=0`): every way whose `tag == && hpid ==` is cleared (also clears its ref/mod). ctid and stream are *not* compared.
- **NRU**: `ref_r` set on any hit, `ref_m` set on write hit (`wr_ext`); every `TLB_TMR_REF_CLR`=100000 cycles a sweep clears `ref_r` of all `2^ORDER` sets (one set per cycle) and restarts. On a hit all ways' ref/mod write-enables are asserted, so non-hit ways at the same address get written with 0/stale data (eviction hints are noisy). (The `EN_NRU` macro guards dead code that references undeclared signals (`addr_C`, `hit_idx_C`, ...): the NRU eviction logic is always built, and setting `EN_NRU=1` would likely break compilation.)
- Lookup latency: 2 cycles BRAM + registered compare; `tlb_fsm` waits `ST_WAIT_1/2` then `ST_CHECK`.

`mmu_region_top` shares one lookup port per TLB between rd and wr FSMs through a 2-bit `mutex` (`[0]`=free, `[1]`=owner is wr). An FSM takes it at `ST_MUTEX` (`lock`), releases it (`unlock_C`) right after `ST_CHECK` hit or when it leaves `ST_MISS_SEND`; DMA issue then proceeds without holding it.

### Request FSM (`tlb_fsm`, one per direction)

Happy path per page chunk: `ST_IDLE -> ST_MUTEX -> ST_WAIT_1 -> ST_WAIT_2 -> ST_CHECK -> ST_HIT_{LARGE|SMALL} -> ST_CALC_{LARGE|SMALL} -> ST_{HOST|CARD}_SEND -> (len left ? ST_MUTEX : ST_IDLE)`.
- `ST_CALC_*`: `paddr = {phys_page, vaddr[PG_BITS-1:0]}`; `plen = min(len, page_size - offset)`; `vaddr += plen`. A long request therefore re-enters `ST_MUTEX` once per page: huge pages materially cut per-request overhead.
- Routing: `strm == STRM_HOST` -> `m_HDMA`; else -> `m_DDMA[dest % N_CARD_AXI]` (ccurr_dest). Without EN_MEM every request is forced to host; without EN_STRM forced to card.
- `dma_req_t.last = (len==0) && req.last`. Each issued request records `{len_C, vaddr_C}` (zero-extended; the `hpid` field is never written, so it is 0) into a circular in-flight RAM (`inst_host_ssn` / `inst_card_ssn`). The record is captured in `ST_*_SEND` *after* `ST_CALC_*` advanced `vaddr_C/len_C`, i.e. it holds the **next chunk's start and remaining length**, not the chunk just sent and an ack token (pid/dest/strm/host/last) into `queue_stream` (depth `N_TLB_ACTV`=16). When the DMA returns `rsp.done`, the ack token produces a completion (`ack_t`, opcode `LOCAL_READ/WRITE`) to `cnfg_slave` (-> `cq`) only if `last`.
- Miss path and invalidation: see flows below.

### Arbitration and data-path support (`EN_STRM` / `EN_MEM`)

- `mmu_arbiter` (host): RR pick among regions' `dma_req_t`, forces `req.last=1` towards the DMA engine (so the engine reports every sub-request), and pushes `{last, vfid, n_beats}` (`mux_host_t`, queue depth `N_OUTSTANDING`) to `m_mux`; a second queue returns `rsp.done` to the right region in issue order. The mux sequence drives `axis_mux_host_src` (rd: single host stream -> per-vFPGA, gated by beat count, `tlast = tlast & last`) and `axis_mux_host_sink` (wr: per-vFPGA -> single host stream) instantiated in `dynamic_top`.
- `mmu_assign` (card, one per vFPGA x card AXI port): same `last=1` forcing, queues real `last` into `rd_fwd_last_card` -> `axis_last_rewriter` on the card read stream. Write completion path needs no forward (`wr_fwd_last_card.ready = 1`).
- `mmu_arbiter_isr`: migration (does not force `last=1`). **Offload** (`RDWR=0`): host **read** + card **write** (`m_rd_HDMA_mig` + `m_wr_CDMA_mig`), done = card write done. **Sync** (`RDWR=1`): card read + host write (`m_wr_HDMA_mig` + `m_rd_CDMA_mig`), done = host write done. Both halves carry the same `len` and `last`; completion queue entries only for `last` requests. The CDMA for migration (`cdma inst_cdma_sync`, AXI port 0 of the card memory) is in `dynamic_top`; per-vFPGA card streams use ports 1..N.

### Credits and fairness

Three layers, only the first two are active in default builds:
1. **Local credits in the vFPGA wrapper** ([local_credits_*](../../../hw/hdl/user/credits/) in `user_wrapper_tmplt.txt`, active when `EN_CRED_LOCAL`, which `FindCoyoteHW.cmake` sets to 1): per-`dest` queues; a read request is released only if the destination data FIFO has room, a write only when enough data has been provided. This stops a stalled vFPGA/stream from back-pressuring the shared DMA. Details in [user_top.md](../user/user_top.md).
2. **Arbitration**: `mmu_arbiter`, `mmu_arbiter_isr` are RR (advance on every granted request), sized by `N_OUTSTANDING` (default 8). Per-region, rd/wr independence plus per-direction request queues (`dma_req_queue`) isolate regions; TLB miss in one region only stalls its own FSM.
3. **MMU-level credits** (`mmu_credits_rd/wr`, `data_queue_credits_*`, `dma_parser`): instantiated only if `EN_CRED_LOCAL` is **undefined**. This path is effectively dead: `dma_parser` has no definition in the repo, and `dynamic_top_tmplt` references `cnfg.en_mem_cred`, which is never set by `scripts/base.tcl.in`. Treat as legacy (rd: up to `N_OUTSTANDING` in-flight reqs tracked by beat counts; wr: only issue when `wxfer` has buffered >= n_beats).

Per-FSM request cache (`cch_buff`, one per region per direction, not shared across regions): while the FSM waits for a page fault (`ST_MISS_IDLE`) further requests on that direction are absorbed into `cch_buff` (admits while `cch_size <= CACHE_MAX_SIZE`=32, i.e. up to 33) and, if they are contiguous with the pending miss (same pid and stream, `vaddr == miss_end`), the fault range is **extended** (`pf_miss.len += len`). This lets one IRQ cover several back-to-back requests; the range goes out on the sideband `m_pfault_rng = pf_rng_C` (the `len` field of `irq_pft_t` is never driven), sampled every cycle by `cnfg_slave`, so `isr_len` is live and can grow while merging in `ST_MISS_IDLE`.

## Data/control flow

### 1. Normal request (TLB hit)

```
vFPGA sq_rd/sq_wr --(user wrapper: local credits, ccross)--> bpss_{rd,wr}_sq  (req_t)
   host invoke --> cnfg_slave m_host_sq ------------------------^ (merged upstream; host=1 in req)
   -> mmu_region_top.tlb_fsm[RDWR]
        ST_MUTEX/WAIT/CHECK : lTLB & sTLB lookup (key=vaddr[PG+:ORDER], tag, ctid, strm)
        hit  -> CALC (paddr,plen) -> HOST_SEND | CARD_SEND
        -> dma_req_queue -> mmu_arbiter (host) | mmu_assign (card) -> HDMA / CDMA
   data: HDMA rd stream -> axis_mux_host_src -> region ; region wr stream -> axis_mux_host_sink -> HDMA
         CDMA rd stream -> axis_last_rewriter -> region  (card)
   done: rsp.done -> ack token (if last) -> cnfg_slave -> bpss_{rd,wr}_cq / host completion counter
```

### 2. Page fault (miss) end to end

```
HW                                              DRIVER                                     SW
tlb_fsm ST_CHECK miss
 -> ST_MISS_CACHE (merge cached reqs)
 -> ST_MISS_SEND: m_pfault <= irq_pft_t{vaddr,strm,pid} (+ range on m_pfault_rng sideband); unlock mutex
 -> ST_MISS_IDLE (wait; caches later reqs)
cnfg_slave: pfault_irq q -> isr regs
  type=IRQ_PFAULT, vaddr, pid(ctid), len=range, stream, wr
  irq_pending=1 -> usr_irq -> MSI-X
                                    vfpga_isr [vfpga_isr.c L24]: read_irq_type (isr_meta_1)
                                      IRQ_PFAULT: read_irq_pfault; queue_work(wqueue_pfault)
                                      clear_irq (isr_ctrl=0x1)           <- IRQ line free again
                                    vfpga_pfault_handler [L156]: mutex_lock(mmu_lock)
                                      hpid = pid_array[ctid]
                                      mmu_handler_gup(vaddr,len,ctid,stream,hpid,mem_block=-1) [vfpga_gup.c L27]
                                        huge VMA? -> ltlb_meta else stlb_meta
                                        map_present? -> yes: migrate if stream != user_pg->host, tlb_map_gup
                                                        no : tlb_get_user_pages (pin_user_pages_remote FOLL_LONGTERM,
                                                             dma_map_single, alloc_card_memory if en_mem)
                                                             -> stream==CARD ? migrate_to_card : -
                                                             -> tlb_map_gup
                                        tlb_map_gup -> create_tlb_mapping -> fpga_{s,l}Tlb[0..1] writes (AXI4-L)
                                      ret!=0 && !=99 -> drop_irq_pfault (isr_ctrl RD/WR_DROP) else restart_mmu
HW: s_pfault (pf_t.success)
  success -> ST_MUTEX (re-lookup, vaddr_C/len_C retained) ; drop -> ST_IDLE (faulting req discarded)
```
Notes: only the first `MAX_N_MAP_PAGES`=256 TLB entries are written per fault; a larger buffer faults again for the rest. `BUFF_NEEDS_EXP_SYNC_RET_CODE` (99) is treated as success (dma_need_sync warning).

### 3. Invalidation / unmap

Current (GUP) driver has **no MMU notifiers**: pages are pinned `FOLL_LONGTERM`, so host-side invalidation never happens behind the driver's back. Invalidation is driver-initiated whenever a mapping is removed or moved (`tlb_unmap_gup`):

```
driver tlb_unmap_gup:
  1. create_tlb_unmapping per (coalesced) page  -> TLB write with valid=0 (removes tag+hpid match)
  2. invalidate_tlb_entry(vaddr,n_pages,hpid,last) per page-group:
       isr_pid=hpid<<32; isr_vaddr; isr_len; isr_ctrl = INVLDT (0x10) | INVLDT_LAST (0x30 on last)
  3. wait_event(waitqueue_invldt) until IRQ_INVLDT sets wait_invldt
HW: cnfg_slave invldt_post -> inv_t{lock,last,hpid,vaddr,len} to BOTH rd and wr tlb_fsm (s_invldt)
    tlb_fsm ST_INVLDT_{HOST,CARD}: walk circular in-flight RAM (tail+1..head); if any in-flight
      req overlaps [vaddr,len) -> in_flight=1 -> loop (ST_INVLDT_EVAL) until DMAs complete
    when drained and inv.last -> m_invldt (irq_inv_t{hpid}); returns to ST_IDLE/ST_LOCKED/ST_MISS_IDLE
cnfg_slave: needs BOTH invldt_irq_rd & _wr -> IRQ_INVLDT, hpid -> driver ISR -> wake_up(waitqueue_invldt)
```
So the HW "invalidate" is a **drain fence** for in-flight DMAs touching the range; the entry removal is the explicit `valid=0` TLB write.

**Lock** (`change_tlb_lock`, `isr_ctrl = 0x50` = INVLDT|LOCK): toggles `tlb_fsm` between `ST_IDLE` and `ST_LOCKED` (new requests not accepted while locked; invalidations still processed). `IOCTL_MAP_USER_MEM`, `IOCTL_UNMAP_USER_MEM`, `IOCTL_MAP/UNMAP_DMABUF` bracket their work with lock/unlock under `mmu_lock`. The page-fault handler does **not** lock.

### 4. Offload / sync (host <-> card migration)

```
SW  cThread::invoke(LOCAL_OFFLOAD|LOCAL_SYNC, syncSg{addr,len})        [cThread.cpp L779]
 -> ioctl IOCTL_OFFLOAD_REQ / IOCTL_SYNC_REQ {vaddr,len,ctid}          [vfpga_ops.c L399/L420]
 -> offload_user_pages / sync_user_pages [vfpga_gup.c L687/L725]
      for each user_pages overlapping: tlb_unmap_gup; user_pg->host = CARD|HOST;
        migrate_to_card / migrate_to_host (mutex offload_lock/sync_lock):
          trigger_dma_offload / trigger_dma_sync [vfpga_hw.c L136/L166]
            per 4K page: offl_host_offs, offl_card_offs, offl_ctrl = (page_size<<32)|START(1) [| CTL|CLR = 0x7 on last]
            throttle: DMA_THRSH=32 outstanding (reads offl_ctrl = queue-used count)
          wait_event(waitqueue_offload|sync)
      tlb_map_gup  (new stream/paddr)
HW  cnfg_slave offload_req (dma_isr_req_t{paddr_host,paddr_card,len,last}) -> FIFO
    -> mmu_arbiter_isr -> HDMA mig + CDMA mig ; last done -> offload_rsp -> IRQ_OFFL / IRQ_SYNC
    -> vfpga_isr: wait_offload / wait_sync = FLAG_SET, wake_up
```
Page-fault-driven migration (`mmu_handler_gup` when `user_pg->host != stream`) uses the same `migrate_to_*` calls. `host==CARD_ACCESS(0)` means the valid copy lives in card memory.

### 5. Unified memory / HMM

HMM-based unified memory (`HMM_KERNEL`, `mmu_handler_hmm`, `mmu_interval_notifier` invalidation) exists only under [driver/LEGACY/hmm](../../../driver/LEGACY/hmm/fpga_hmm.c) and is **not built** by the current Makefile; the `#ifdef HMM_KERNEL` blocks in `vfpga_ops.c`, `vfpga_isr.c`, `coyote_defs.h` are vestigial. However, `en_hmm` is a **live module parameter** ([coyote_driver.c](../../../driver/src/coyote_driver.c) L48-49) that gates `IOCTL_UNMAP_USER_MEM`, `IOCTL_UNMAP_DMABUF`, `IOCTL_OFFLOAD_REQ` and `IOCTL_SYNC_REQ` via `if(!en_hmm)` in `vfpga_ops.c`: loading with `en_hmm=1` on a non-HMM build turns those four into silent no-ops. Keep `en_hmm=0`. "Unified" behaviour today = GUP pinning + explicit/implicit host<->card migration above.

### 6. GPU memory (dma-buf P2P, Linux >= 6.2)

```
cThread::getMem({CoyoteAllocType::GPU,size,false,gpu_id}) -> hipMalloc | cuMemAlloc -> userMap(mem,size)
userMap [cThread.cpp L374]: EN_ROCM: hipPointerGetAttributes==device ; EN_CUDA: cuPointerGetAttribute==DEVICE
   -> export dma-buf fd (hsa_amd_portable_export_dmabuf | cuMemGetHandleForAddressRange DMA_BUF_FD)
   -> ioctl IOCTL_MAP_DMABUF {fd, vaddr, ctid, mem_block}   (ROCm passes vaddr-offset; the driver page-aligns anyway)
 else (host ptr) -> IOCTL_MAP_USER_MEM {vaddr,len,ctid,mem_block}
driver p2p_attach_dma_buf [vfpga_gup.c L825]: dma_buf_dynamic_attach(allow_peer2peer, move_notify=p2p_move_notify)
   dma_buf_map_attachment -> sgt -> bus addrs in hpages[] ; alloc card pages if en_mem ; map in user_buff_map ; tlb_map_gup
GPU access = STRM_HOST stream (PCIe P2P through host DMA); TLB entry phys = GPU bus address
GPU page move -> p2p_move_notify: tlb_unmap_gup, remap sg, tlb_map_gup
userUnmap: IOCTL_UNMAP_DMABUF (p2p_detach_dma_buf) + close fd; freeMem frees GPU memory
```
Auto-detection: `userMap` works on any pointer; only `getMem(GPU)` allocates GPU memory, but a user-allocated GPU pointer passed to `userMap` is detected the same way. Without EN_ROCM/EN_CUDA, `CoyoteAllocType::GPU` throws. DMA bus addresses must fit in `PADDR_BITS`=44. See [examples/06_gpu_p2p](../../../examples/06_gpu_p2p/README.md) ([`src/cuda/main.cpp`](../../../examples/06_gpu_p2p/sw/src/cuda/main.cpp), [`src/rocm/main.cpp`](../../../examples/06_gpu_p2p/sw/src/rocm/main.cpp)).

## Driver & software interaction

### End-to-end SW -> HW

| SW API | ioctl (`_IOW('F',n)`, args in `uint64_t tmp[MAX_USER_ARGS]`) | Driver function | HW write / effect | RTL |
|---|---|---|---|---|
| `getMem(REG/THP/HPF)` -> `userMap` | `IOCTL_MAP_USER_MEM` (5): `{vaddr,len,ctid,mem_block}` -> returns 99 on needs-sync | [vfpga_dev_ioctl](../../../driver/src/vfpga/vfpga_ops.c) -> `mmu_handler_gup(stream=1)` | lock; TLB writes `fpga_sTlb/lTlb[0..1]`; unlock | `tlb_slave_axil` -> `tlb_controller`; `tlb_fsm` ST_LOCKED |
| `getMem(GPU)` / `userMap` on GPU ptr | `IOCTL_MAP_DMABUF` (7): `{fd,vaddr,ctid,mem_block}` | `p2p_attach_dma_buf` | same | same |
| `freeMem` -> `userUnmap` | `IOCTL_UNMAP_USER_MEM` (6): `{vaddr,ctid}` / `IOCTL_UNMAP_DMABUF` (8): `{vaddr,ctid}` | `tlb_put_user_pages` / `p2p_detach_dma_buf` -> `tlb_unmap_gup` | TLB `valid=0` writes + `isr_ctrl` INVLDT[_LAST] | `tlb_controller` remove; `tlb_fsm` INVLDT drain |
| `invoke(LOCAL_OFFLOAD, syncSg)` | `IOCTL_OFFLOAD_REQ` (9): `{vaddr,len,ctid}` | `offload_user_pages` -> `migrate_to_card` | `offl_host_offs/offl_card_offs/offl_ctrl` | `cnfg_slave` -> `mmu_arbiter_isr(RDWR=0)` |
| `invoke(LOCAL_SYNC, syncSg)` | `IOCTL_SYNC_REQ` (10) | `sync_user_pages` -> `migrate_to_host` | `sync_host_offs/sync_card_offs/sync_ctrl` | `mmu_arbiter_isr(RDWR=1)` |
| `invoke(LOCAL_READ/WRITE/TRANSFER, localSg{stream,dest})` | none (MMIO `cnfg_regs` via mmap; see [user_top.md](../user/user_top.md)) | - | `ctrl`, `vaddr_rd/wr`, `ctrl_2` | `cnfg_slave` -> `host_sq` -> `tlb_fsm` (miss -> IRQ) |
| `cThread` ctor / dtor | `IOCTL_REGISTER_CTID` (1) `{hpid}` -> ctid; `IOCTL_UNREGISTER_CTID` (2) | `pid_array[ctid]=hpid` (used by fault handler); `tlb_put_user_pages_ctid` on release | - | TLB `pid` field = ctid |

`stream`/`host`: `HOST_ACCESS=1` (STRM_HOST), `CARD_ACCESS=0` (STRM_CARD). `cThread` mmaps only USER, CNFG, CNFG_AVX and WB windows (`vfpga_dev_mmap`, [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c)); the TLB windows are `ioremap`ed by the driver only ([coyote_setup.c](../../../driver/src/coyote_setup.c) L397-398), so user space cannot write TLBs (isolation). Window offsets in [coyote_defs.h](../../../driver/include/coyote_defs.h): `VFPGA_CTRL_OFFS=0x100000`, lTLB `+0x0`, sTLB `+0x10000`, user `+0x20000`, cnfg `+0x30000` (AVX cnfg at `0x1000000`).

### HW -> driver (IRQs and registers)

Driver struct `vfpga_cnfg_regs` ([coyote_defs.h L572](../../../driver/include/coyote_defs.h)) is byte-compatible with `cnfg_slave` word indices (64-bit) and with `cnfg_slave_avx` for the ISR/offload/sync words.

| Reg (word idx in `cnfg_slave`) | Driver field | Access | Contents / RTL |
|---|---|---|---|
| `ISR_REG` (4), bits `[7:0]` | `isr_ctrl` | W (pulse, auto-clear) | b0 `CLR_IRQ_PENDING`, b1 `RESTART_RD`, b2 `RESTART_WR`, b3 `SUCCESS`, b4 `INVLDT`, b5 `INVLDT_LAST`, b6 `INVLDT_LOCK` |
| `ISR_REG` `[31:16]` | `isr_meta_1` | R | IRQ type: `IRQ_OFFL`=0, `SYNC`=1, `INVLDT`=2, `PFAULT`=3, `NOTIFY`=4, `RCNFG`=5 (ISR priority order in `cnfg_slave`: offl > sync > invldt > pf_rd > pf_wr > notify) |
| `ISR_REG` b32 / b33 | - | R | invldt ctrl / pfault ctrl queue ready |
| `ISR_REG` `[49:48]`, b56 | `isr_meta_3` | R | faulting stream, write-fault flag |
| `ISR_HPID_PID_MISS_REG` (5) | `isr_pid` | R: `[5:0]` ctid; W for invalidate: `[63:32]` hpid | `pid_C`, `hpid_C` |
| `ISR_VADDR_MISS_REG` (6) | `isr_vaddr` | R: miss vaddr; W: invalidate vaddr | |
| `ISR_VAL_LEN_MISS_REG` (7) | `isr_len` | R: `[27:0]` fault range (`pfault_rng_rd/wr`), `[63:32]` notify value; W: invalidate len | |
| `STAT_INVLDT_REG`(12), `STAT_PFAULT_REG`(13) | `stat_irq[]` | R | invalidation / fault counters |
| `OFFL_CTRL_REG` (20) / `SYNC_CTRL_REG` (28) | `offl_ctrl` / `sync_ctrl` | W: b0 START, b1 CTL(=last), b2 CLR, `[59:32]` len; R: queue-used count | -> `dma_isr_req_t.{len,last}` |
| `OFFL_HOST_OFFS_REG` (21) / `OFFL_CARD_OFFS_REG` (22) | `offl_host_offs`, `offl_card_offs` | W | `paddr_host`, `paddr_card` |
| `SYNC_HOST_OFFS_REG` (29) / `SYNC_CARD_OFFS_REG` (30) | `sync_host_offs`, `sync_card_offs` | W | same for sync |
| `OFFL_STAT_REG` (24), `SYNC_STAT_REG` (32) | `offl_stat`, `sync_stat` | R | completion counters |

`FPGA_CNFG_CTRL_IRQ_*` codes written to `isr_ctrl` ([coyote_defs.h L302](../../../driver/include/coyote_defs.h)):

| Code | Value | = bits | Helper in [vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c) | HW effect |
|---|---|---|---|---|
| `CLR_PENDING` | 0x1 | b0 | `clear_irq` | `irq_pending <= 0` |
| `PF_RD_SUCCESS` / `PF_WR_SUCCESS` | 0xa / 0xc | RESTART+SUCCESS | `restart_mmu(write,ctid)` | `s_pfault.data=1` -> FSM retries (`ST_MUTEX`) |
| `PF_RD_DROP` / `PF_WR_DROP` | 0x2 / 0x4 | RESTART, SUCCESS=0 | `drop_irq_pfault` | FSM -> `ST_IDLE`, request discarded |
| `INVLDT` / `INVLDT_LAST` | 0x10 / 0x30 | b4 (+b5) | `invalidate_tlb_entry` | `inv_t` to both FSMs; last -> completion IRQ |
| `LOCK` | 0x50 | b4+b6 | `change_tlb_lock` | toggle `ST_IDLE`<->`ST_LOCKED` |

Interrupt dispatch: [vfpga_isr](../../../driver/src/vfpga/vfpga_isr.c) takes `irq_lock`, switches on `read_irq_type`: `OFFL/SYNC/INVLDT` set an atomic flag + `wake_up_interruptible` (waiters are in `migrate_to_*` / `tlb_unmap_gup`); `PFAULT` and `NOTIFY` are deferred to per-vFPGA single-threaded workqueues (`wqueue_pfault`, `wqueue_notify`, created in [coyote_setup.c](../../../driver/src/coyote_setup.c)) so the TLB programming does not run in IRQ context; then `clear_irq`. Fault handling is serialized per vFPGA by `mmu_lock`. Notifications ([vfpga_uisr.c](../../../driver/src/vfpga/vfpga_uisr.c)) are covered in [driver.md](../driver.md).

TLB geometry hand-off: shell reg `CTRL_CNFG_REG` (see `shell_slave.sv`) -> `coyote_setup.c` fills `tlb_metadata` {`key_size`=TLB order, `assoc`, `page_shift`, masks, `tag_size = TLB_VADDR_RANGE(48) - page_shift - key_size`, `phy_size = TLB_PADDR_RANGE(44) - page_shift`}. `create_tlb_mapping` uses these to build the two words above (VPN in 4 KiB units: `key = (vaddr >> (page_shift-12)) & key_mask`). `cThread` reads `pg_l_bits` from the same register via `IOCTL_READ_SHELL_CONFIG` to choose the `MAP_HUGE_SHIFT` for `HPF`. See [driver.md](../driver.md#mmu-and-page-faults) and [software.md](../software.md#mmu-and-page-faults).

### SW memory types (`CoyoteAllocType`, [cOps.hpp](../../../sw/include/coyote/cOps.hpp))

| Type | Allocation | Notes |
|---|---|---|
| `REG` | `mmap` anon | 4 KiB pages; sTLB entries (driver may coalesce 512 contiguous aligned pages into one lTLB entry in `tlb_map_gup`) |
| `THP` | `posix_memalign(2 MiB)` | relies on kernel THP; same coalescing check |
| `HPF` | `mmap(MAP_HUGETLB \| pg_l_bits<<MAP_HUGE_SHIFT)` | needs reserved hugepages (`nr_hugepages`); VMA flagged hugetlb -> lTLB; `MAP_HUGE_SHIFT` follows the shell's `pg_l_bits`; only 2 MiB is validated (1 GiB: see Gotchas); `THP` alignment is hardcoded 2 MiB (`HUGE_PAGE_SIZE`) |
| `PRM` | reconfig memory | not MMU; see [reconfig.md](../static/reconfig.md) |
| `GPU` | `hipMalloc` / `cuMemAlloc` + dma-buf | see flow 6 |

`CoyoteAlloc.mem_block` selects the card memory block (Versal block-HBM only; `-1` = driver picks / ignored on UltraScale+).

## Config knobs

| Knob (cmake) | Package param | Default | Effect |
|---|---|---|---|
| `TLBS_S` / `TLBS_A` / `TLBS_BITS` | `TLB_S_ORDER` / `N_S_ASSOC` / `PG_S_BITS` | 10 / 4 / 12 | sTLB sets (2^S), ways, page order. Driver asserts `page_shift == PAGE_SHIFT` (`BUG_ON` in `coyote_setup.c`) |
| `TLBL_S` / `TLBL_A` / `TLBL_BITS` | `TLB_L_ORDER` / `N_L_ASSOC` / `PG_L_BITS` | 9 / 2 / 21 | lTLB; 2 MiB validated; 1 GiB (`30`) not usable end to end (see Gotchas) |
| `N_TLB_ACTV` | `N_TLB_ACTV` | 16 | in-flight DMA records / ack depth per FSM per port (invalidation scan length) |
| `N_OUTSTANDING` | `N_OUTSTANDING` | 8 | arbiter sequence/completion queue depths, credit window |
| `VADDR_BITS` | `VADDR_BITS` | 48 | tag width (driver hardcodes 48, see gotchas) |
| `EN_NRU` | `EN_NRU` define | 0 | no functional effect; do not enable (see TLB design) |
| `EN_STRM` / `EN_MEM` | `EN_STRM` / `EN_MEM` | per config | build host path / card path + migration + `strm` compare in TLB |
| `EN_CRED_LOCAL` | `EN_CRED_LOCAL` | 1 | 1 = credits in vFPGA wrapper, MMU credits compiled out |
| `N_CARD_AXI`, `N_STRM_AXI` | same | per config | number of card/host AXI ports (`MULT_CARD_AXI` ifdefs in `tlb_fsm`) |
| `EN_AVX` | `EN_AVX` | 0 | `cnfg_slave_avx` instead of `cnfg_slave` (same ISR layout, wider bus) |
| Driver: `PLATFORM_*`, `en_hmm` | - | - | see UltraScale+ vs Versal; `en_hmm` module param: see flow 5 |

BRAM cost: per TLB `N_ASSOC * 2^ORDER * 104 b` plus 2 x 1-bit RAMs per way.

## UltraScale+ vs Versal

- **`hw/hdl/mmu/*` has no platform ifdefs**; the MMU is identical. Differences are around it:
  - Host DMA: XDMA (US+) vs QDMA (Versal) behind `m_{rd,wr}_HDMA_*` ([host_dma.md](../static/host_dma.md)).
  - Card memory: US+ DDR/HBM presented as one space (`N_MEM_BLOCKS=1`, `MEM_START=256 MiB`); Versal HBM with `HBM_IMPL=unified|block`, `BLOCK_MEM_IMPL_EN` exposed in `MEM_CNFG_REG` bit 14 (`CTRL_CNFG[15:12]` is `TLB_L_ORDER`) -> `bd_data->en_block_mem`; driver `N_MEM_BLOCKS=64`, `MEM_BLOCK_SIZE=512 MiB`, `MEM_START=256 GiB` ([memory.md](memory.md)).
  - Driver `#ifdef PLATFORM_ULTRASCALE_PLUS` / `PLATFORM_VERSAL` in [vfpga_gup.c](../../../driver/src/vfpga/vfpga_gup.c) (`tlb_get_user_pages`, `p2p_attach_dma_buf`): on Versal block-HBM `mem_block == -1` -> `-EINVAL`; user `mem_block` is first made vFPGA-relative (`blk = id*n_card_axi + mem_block`) and then mapped with `DIV_ROUND_CLOSEST(N_MEM_BLOCKS*(blk+1), n_regions*n_card_axi+1)-1`; on US+ `mem_block` ignored. `free_card_memory` derives block from the physical address only on Versal.
  - Versal Gen4/5 PCIe: only affects DMA throughput, not MMU.

## Gotchas / invariants

- **TLB write ordering.** Write sTLB/lTLB entries *before* `restart_mmu`; entry insertion goes through an AXI-S FIFO + 4-cycle FSM and only MMIO ordering/latency keeps the retry lookup behind it.
- **reg1 write triggers the TLB command**; always write reg0 then reg1 (`create_tlb_mapping` does).
- **Removal ignores ctid/stream:** `valid=0` clears every way whose `tag` and `hpid` match. Two ctids of the same process with the same VA share removal.
- **No duplicate suppression** on insert. Migration paths unmap first (`tlb_unmap_gup`), but a refill fault on an already-known buffer with matching stream calls `tlb_map_gup` directly (up to 256 entries, no unmap) -> duplicate ways are possible; hit encoder then picks the highest way.
- **Stream mismatch = fault.** Accessing a host-resident page with `strm=CARD` (or vice versa) page-faults and migrates the *whole* `user_pages` buffer (not only the faulting page).
- **Per-fault mapping limit** `MAX_N_MAP_PAGES`=256 (also for `IOCTL_MAP_USER_MEM`): remaining pages are mapped lazily by later faults.
- **Drop** only discards the faulting request; its AXIS data (writes) is not drained, and cached follow-up requests re-fault. A dropped write can leave the vFPGA stream blocked.
- **ctid <-> hpid** lives in `device->pid_array[ctid]`; faults for an unregistered ctid read a stale hpid. TLB tag includes `ctid` (6 bits, `N_CTID_MAX`=64) so tenants cannot hit each other's entries.
- **IRQ serialization:** one `irq_pending` per vFPGA; types are prioritised, and the ISR clears pending before the page-fault work completes. The fault registers are captured in the ISR (`read_irq_pfault`) before clearing.
- **`last` handling:** DMA engines get `last=1` on every MMU sub-request (arbiters/assign); true `last` travels via `mux_host_t` / `fwd_last` to rewrite `tlast`. Anything bypassing these modules must preserve that.
- **Max transfer** per `invoke`: `MAX_TRANSFER_SIZE` 128 MiB (`LEN_BITS`=28 -> 256 MiB at HW).
- **Pinned pages:** `FOLL_LONGTERM` + `dma_map_single`; IOMMU-translated bus addresses are what the TLB stores (not CPU phys). `dma_need_sync` => warning + return code 99.
- **1 GiB hugepages do not work end to end:** host-only at best. `invalidate_tlb_entry` passes `n_pages=2^18` -> `isr_len=2^30` truncated to `LEN_BITS`=28 -> len 0 (drain fence disabled); with `EN_MEM`, huge card pages are placed at `MEM_START + card_huge_offs + (id << 12)`, not 1 GiB aligned, so lTLB translation of card pages is wrong (Versal `MEM_BLOCK_SIZE`=512 MiB is similar); `THP` alignment is hardcoded 2 MiB.
- **Streams reaching the MMU:** with `EN_NET`, `user_req_mux`/`host_req_mux` split on `is_strm_local()` (HOST|CARD), so RDMA/TCP requests never reach the TLB FSMs; user requests also get `host=0` and `vfid` forced. Without `EN_NET` a stray RDMA/TCP `strm` is routed as card (EN_MEM) or host.
- **Locking:** only `ST_IDLE`/`ST_LOCKED` honour the lock command; the fault handler never locks; offload/sync ioctls bypass `mmu_lock`. Fault and notify work run on per-vFPGA workqueues (`alloc_workqueue(WQ_UNBOUND|WQ_MEM_RECLAIM, max_active=1)`, `coyote_setup.c` L439-445), so faults of one vFPGA are strictly serialized.
- **GPU buffers** are `huge=false`, host-stream, dma-buf must be mapped dynamically (move_notify); requires `CONFIG_PCI_P2PDMA`, `CONFIG_DMABUF_MOVE_NOTIFY`, kernel >= 6.2.

### Code inconsistencies and hazards noticed (not fixed)

| Location | Issue |
|---|---|
| [vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c) `create_tlb_mapping/unmapping` | `uint64_t entry[2]` never zeroed before `|=`; stack garbage can reach TLB words (reg1 also ORs phys above the valid bit; harmless) |
| `vfpga_hw.c` `alloc_card_memory` | `-ENOMEM` returned while holding `card_lock` |
| [vfpga_gup.c](../../../driver/src/vfpga/vfpga_gup.c) `p2p_move_notify` L806 | `cnt = ...` should be `cnt += ...` (multi-segment sg tables overlap in `hpages`); also runs without `mmu_lock` |
| `vfpga_gup.c` `offload_user_pages` / `sync_user_pages` (L700-760) | `user_buff_map` is keyed by start VPN; a non-start `vaddr` finds no entry and `vaddr_tmp` never advances -> infinite loop in kernel. Same start-address-only lookup in `tlb_put_user_pages`, `p2p_detach_dma_buf` |
| [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c) L399-438 | `IOCTL_OFFLOAD_REQ/SYNC_REQ` take neither `mmu_lock` nor the TLB lock, so they can race with page-fault handling |
| [vfpga_isr.c](../../../driver/src/vfpga/vfpga_isr.c) L170-181 (and `IOCTL_MAP_USER_MEM`) | With `HMM_KERNEL` defined the dangling `else` binds to the following `if(ret_val && ...)`: GUP is never called, and with `en_hmm==0` `ret_val=-1` -> every fault is dropped. Only matters if HMM is revived |
| `vfpga_gup.c` `tlb_unmap_gup` | one `invalidate_tlb_entry` (4 MMIO writes + HW scan + IRQ-less step) per 4 KiB page for non-huge buffers: slow unmap/migration |
| [tlb_fsm.sv](../../../hw/hdl/mmu/tlb_fsm.sv) `ST_INVLDT_CMP_*` | `&&`/`||` precedence: the hpid term only qualifies clause B, and clause B (needs hpid==record hpid, which is always 0) effectively never matches; only clause A (`vaddr <= rec.vaddr <= vaddr+len`) works. The record is next-chunk start + remaining len, scan is `[tail, head)` |
| `tlb_fsm.sv` `ST_MISS_IDLE` | any `s_invldt` jumps to `ST_INVLDT_*` without checking `.lock`: stale `invldt_C` scan, deferred restart, lock-parity desync (reachable if `userMap` runs during traffic). Lock honoured only in `ST_IDLE/ST_LOCKED` |
| [mmu_region_top.sv](../../../hw/hdl/mmu/mmu_region_top.sv) mutex (L138-143) | a stray `wr_unlock` while rd holds the mutex sets `2'b11` (frees it); the wr drop path re-pulses `unlock` (`ST_MISS_SEND` then `ST_MISS_IDLE`) |
| `mmu_region_top.sv` vs `tlb_fsm.sv` | `TLB_*_DATA_BITS`: `PID_BITS+2+..` vs `PID_BITS+STRM_BITS+1+..` (1 bit wider); harmless, FSM's computed `hpid` is unused |
| [mmu_assign.sv](../../../hw/hdl/mmu/mmu_assign.sv) | `s_req.ready = m_req.ready` ignores `queue.ready`; with the fwd-last queue full a request is accepted but not forwarded (dropped) |
| [mmu_arbiter_isr.sv](../../../hw/hdl/mmu/mmu_arbiter_isr.sv) | unlike `mmu_arbiter`/`mmu_assign` it does not force `last=1`; relies on the driver's `last` flag (`DMA_CTRL_START_LAST`) |
| [mmu_top.sv](../../../hw/hdl/mmu/mmu_top.sv) L335-338 | four `EN_TCP` instances share the name `inst_tcp_listen_req` |
| [coyote_defs.h](../../../driver/include/coyote_defs.h) | `TLB_VADDR_RANGE`=48 hardcoded while `VADDR_BITS` is a cmake knob; driver IRQ names `IRQ_DMA_OFFL/SYNC` vs RTL `IRQ_OFFL/SYNC` (same values) |
| [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv) | read of `OFFL_CARD_OFFS_REG`/`SYNC_CARD_OFFS_REG` returns the host-offset reg; `WBACK_LCL_WR_OFFS_REG` write targets the RD slot; invalidate `len` truncated to `LEN_BITS`=28 |
| `tlb_controller.sv` | `N_ASSOC=1` gives a degenerate index (`[-1:0]`): use >= 2; `EN_NRU` guards code with undeclared signals |
| `dma_parser`, `cnfg.en_mem_cred` | referenced but undefined: MMU-level credit path cannot build |

## How to modify / extend

- **Resize or retarget TLBs:** change `TLBS_*` / `TLBL_*` in the cmake config (e.g. `-DTLBL_BITS=30`); rebuild shell. Driver/SW pick geometry from the `CTRL_CNFG` register at load, no code change, but Linux must provide matching hugepages (`HPF` uses `pg_l_bits`). Key/ways limited by 4-bit register fields (order <= 15, assoc <= 15; page shift 6 bits).
- **Add a TLB entry field** (e.g. permissions): extend `TLB_DATA_BITS`, offsets `PHY_*_OFFS/HPID_*_OFFS` in `tlb_fsm.sv`, `tlb_data_upd_in` + compare in `tlb_controller.sv`, the packing in `tlb_slave_axil` consumer (`data_C` slices), and `create_tlb_mapping` in `vfpga_hw.c`. Keep driver and RTL bit order in sync.
- **Change replacement policy:** edit "Find second order" in `tlb_controller.sv`; ref/mod RAMs are already available.
- **New fault source / IRQ type:** add `IRQ_*` in `lynx_pkg_tmplt.txt` and `coyote_defs.h`, queue + priority branch in `cnfg_slave.sv` (and `_avx`), `case` in `vfpga_isr`, and a work handler like `vfpga_pfault_handler`.
- **New driver memory policy** (e.g. real MMU notifiers): hook where `user_buff_map` entries are created (`tlb_get_user_pages`) and tear down with `tlb_unmap_gup` (it already does unmap-then-fence); follow `tlb_unmap_gup` order exactly (TLB remove, invalidate fence, wait IRQ).
- **Add a new ioctl for memory:** define `_IOW('F', n, unsigned long)` in both [coyote_defs.h](../../../driver/include/coyote_defs.h) and [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp), add the `case` in `vfpga_dev_ioctl` (take `mmu_lock`; lock/unlock TLB if mutating mappings), call from `cThread`.
- **Add a destination for requests** (new `strm`): extend `strm` handling in `tlb_fsm` routing (`ST_CALC_*` next-state), add DMA port in `mmu_region_top`/`mmu_top`, and an arbiter akin to `mmu_arbiter`.
- **Debug:** ILA hooks: uncomment `` `define DBG_TLB_CONTROLLER `` (tlb_controller.sv) / `DBG_TLB_ARBITER` (mmu_arbiter.sv); driver `dbg_info` logs print every TLB entry written; counters `STAT_PFAULT_REG`, `STAT_INVLDT_REG`.
