# Application layer: vFPGAs, user wrapper, and how to write an app

**Purpose:** Everything a coding agent needs to write, wire, build and drive a vFPGA (user application): the unified hardware interface, the `user_wrapper` that sits between the shell and user logic, the build mechanics (`load_apps`, `vfpga_top.svh`, HLS/SpinalHDL), and the host-side `cThread` API with its driver/RTL linkage.
**Scope:** `N_REGIONS` (<= 15) identical-interface regions per shell; each region has up to `N_CONFIG` interchangeable apps (PR). Code is the source of truth; thesis ch.5 / v2 paper are background only.

## Key files

| Area | File |
|---|---|
| Wrapper (shell-facing, credits, queues) | [user_wrapper_tmplt.txt](../../../hw/templates/common/user_wrapper_tmplt.txt) -> `design_user_wrapper_<vfid>` |
| User-logic shell (port list + `include "vfpga_top.svh"`) | [user_logic_tmplt.txt](../../../hw/templates/common/user_logic_tmplt.txt) -> `design_user_logic_c<cfg>_<vfid>` |
| User clock constraint | [user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt) |
| Types / constants (`req_t`, `ack_t`, `irq_not_t`, `STRM_*`, `N_*_AXI`) | [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) |
| Wrapper sub-modules | [hw/hdl/user/](../../../hw/hdl/user/) (`req/ dreq/ credits/ dest/ axis_mux/ cq/ mux_init/`) |
| Interfaces + macros | [axi_intf.sv](../../../hw/hdl/pkg/axi_intf.sv), [lynx_intf.sv](../../../hw/hdl/pkg/lynx_intf.sv), [axi_macros.svh](../../../hw/hdl/pkg/axi_macros.svh), [lynx_macros.svh](../../../hw/hdl/pkg/lynx_macros.svh) |
| Shell side of the wrapper (CDC, decoupling, CQ/SQ routing) | [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt) |
| Host command/completion registers | [cnfg_slave_avx.sv](../../../hw/hdl/shell/cnfg_slave_avx.sv), [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv) |
| Template rendering per flow | [write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in) |
| User project creation (file copy, HLS IPs, `init_ip.tcl`) | [cr_user.tcl.in](../../../scripts/cr_prjcts/cr_user.tcl.in) |
| HLS / SpinalHDL compilation | [comp_hls.tcl.in](../../../scripts/apps/comp_hls.tcl.in), [comp_spinal.tcl.in](../../../scripts/apps/comp_spinal.tcl.in), [build.sbt](../../../scripts/apps/build.sbt) |
| Debug bridge / hub IP for user ILAs | [user_infrastructure.tcl](../../../scripts/ip_inst/user_infrastructure.tcl) |
| CMake knobs, `load_apps` macro | [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) |
| SW API | [cThread.hpp](../../../sw/include/coyote/cThread.hpp), [cOps.hpp](../../../sw/include/coyote/cOps.hpp), [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp), [cThread.cpp](../../../sw/src/cThread.cpp) |
| Examples | [examples/](../../../examples/) (map below) |

**Related:** [coyote_top.md](../coyote_top.md) | [shell/shell_top.md](../shell/shell_top.md) (CSR address map, xbar) | [services/mmu.md](../services/mmu.md) (translation of `sq_*`) | [services/memory.md](../services/memory.md) | [services/network.md](../services/network.md) (RDMA/TCP) | [driver.md](../driver.md) | [software.md](../software.md) | [simulation.md](../simulation.md) | [build/build_top.md](../build/build_top.md)

## 1. Mental model

```
 host cThread --invoke--> cnfg_slave(_avx) --host_sq--+                 (shell, aclk)
                                                      v
  +--------------- design_user_wrapper_<v> (PR boundary; uclk if EN_UCLK) ---------------+
  | host_req_mux / user_req_mux -> req_arb_2_1 -> req_mux_stream_1_2 (HOST vs CARD)     |
  |   -> local_credits_{host,card}_{rd,wr} (per-dest queue, PMTU parser, credits, data FIFOs)
  |   -> bpss_{rd,wr}_sq (to MMU)          remote: remote_credits_* -> rdma_sq / tcp_sq |
  | cq_arb: bpss_*_cq (+rdma_cq) -> cq_rd/cq_wr                                         |
  |  +------------------- design_user_logic_c<cfg>_<v> ----------------------------+    |
  |  |  axi_ctrl notify sq_rd sq_wr cq_rd cq_wr rq_rd rq_wr axis_* sniffer         |    |
  |  |  `include "vfpga_top.svh"   <- the user's code                             |    |
  |  +-----------------------------------------------------------------------------+    |
  +-------------------------------------------------------------------------------------+
        ^ shell: axis CDC (uclk) + register slices + decouplers (PR) + MMU + services
```
- **Two modules per vFPGA.** `design_user_wrapper_<v>` is fixed Coyote infrastructure; `design_user_logic_c<c>_<v>` contains only ports + the user's `vfpga_top.svh`. User code never touches the wrapper.
- **Build flows ([write_hdl.py.in](../../../scripts/cr_prjcts/write_hdl.py.in)):** in the *shell* flow (`flow='shell'`) the wrapper template renders **only its port list** (black box). In the *user* flow (`flow='user'`, one Vivado project per `(config, vfid)`; synthesised out-of-context on Versal only, see [cr_user.tcl.in](../../../scripts/cr_prjcts/cr_user.tcl.in) L107-111) it renders the full body + `user_logic` + `user_clk.xdc`. Sim flow renders `lynx_pkg` + `user_logic` only (no wrapper/credits; see [simulation.md](../simulation.md)).
- Wrapper ports are the PR boundary: all wrapper ports carry `(* io_buffer_type = "none" *)`; all configs of one vFPGA share identical ports, so every config must use the same `N_STRM_AXI/N_CARD_AXI/N_RDMA_AXI` and `EN_*` shell flags.

## 2. The vFPGA interface (ports of `design_user_logic_c<c>_<v>`)

Present-conditions come from [user_logic_tmplt.txt](../../../hw/templates/common/user_logic_tmplt.txt). "m" = user drives valid/data; "s" = user drives ready.

| Port | Type / modport | Dir | Present if | Meaning |
|---|---|---|---|---|
| `axi_ctrl` | `AXI4L.s` (64-bit addr, 64-bit data) | slave | always | user CSRs; host `setCSR/getCSR` |
| `notify` | `metaIntf.m` of `irq_not_t` | master | always | user interrupt -> host `uisr` |
| `sq_rd`, `sq_wr` | `metaIntf.m` of `req_t` | master | always | vFPGA-initiated read / write requests (send queues) |
| `cq_rd`, `cq_wr` | `metaIntf.s` of `ack_t` | slave | always | completions (for host- *and* vFPGA-initiated requests) |
| `rq_rd` | `metaIntf.s` of `req_t` | slave | `EN_RDMA` | incoming remote READ request (fetch local data for response) |
| `rq_wr` | `metaIntf.s` of `req_t` | slave | `EN_NET` (RDMA, TCP or SNIFFER builds) | incoming remote WRITE/SEND/READ-response (place payload) |
| `axis_host_recv[N_STRM_AXI]` / `axis_host_send[...]` | `AXI4SR.s` / `AXI4SR.m` | host->vFPGA / vFPGA->host | `EN_STRM` | host-memory data |
| `axis_card_recv[N_CARD_AXI]` / `axis_card_send[...]` | `AXI4SR` | card mem <-> vFPGA | `EN_MEM` | HBM/DDR data |
| `axis_rreq_recv/send[N_RDMA_AXI]` | `AXI4SR` | requester side of RDMA | `EN_RDMA` | `rreq_send`: payload of *our* WRITE/SEND; `rreq_recv`: payload of READ responses to *our* READs |
| `axis_rrsp_recv/send[N_RDMA_AXI]` | `AXI4SR` | responder side of RDMA | `EN_RDMA` | `rrsp_recv`: payload of *incoming* WRITE/SEND; `rrsp_send`: payload of READ responses we serve |
| `axis_tcp_recv/send[N_TCP_AXI]` | `AXI4SR` | TCP payload | `EN_TCP` | **not buildable at present** (NET-01) |
| `axis_rx_sniffer`, `axis_tx_sniffer` | `AXI4S.s` (512-bit net) | slave | `EN_SNIFFER` and `SNIFFER_VFPGA_ID == vfid` | raw RX/TX Ethernet frames |
| `filter_config` | `metaIntf.m` of `logic[63:0]` | master | same | sniffer filter word |
| `aclk`, `aresetn` | `input wire` | | always | **`aclk` is `uclk` when `EN_UCLK=1`** |

Interface definitions ([axi_intf.sv](../../../hw/hdl/pkg/axi_intf.sv), [lynx_intf.sv](../../../hw/hdl/pkg/lynx_intf.sv)):
- `metaIntf #(STYPE)`: `valid`, `ready`, `data` (valid/ready handshake; `data` must be stable while `valid && !ready`; asserted in sim).
- `AXI4S`: `tdata[512]`, `tkeep[64]`, `tlast`, `tvalid`, `tready`. `AXI4SR` = `AXI4S` + `tid[PID_BITS=6]` ("routed").
- `AXI4L`: standard AXI4-Lite, `AXI_ADDR_BITS=64`, `AXIL_DATA_BITS=64`.
- All data buses are `AXI_DATA_BITS=512`; network buses `AXI_NET_BITS=512`; `AVX_DATA_BITS=256` (host command register).

### 2.1 Types ([lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt))

`req_t` (128 bit, packed, MSB first; widths at default `VADDR_BITS=48`, `DEST_BITS=4`):

| Field | Bits | Set by user? | Meaning |
|---|---|---|---|
| `opcode` | 5 | yes | `LOCAL_READ=1, LOCAL_WRITE=2, LOCAL_TRANSFER=3, LOCAL_OFFLOAD=4, LOCAL_SYNC=5` (lynxTypes consts, equal to SW `CoyoteOper`). For `strm=STRM_RDMA`: `RDMA_READ=0, RDMA_WRITE=1, RDMA_SEND=2, RDMA_IMMED=3`; the shell segments them into `RC_*` wire opcodes |
| `strm` | 2 | yes | `STRM_CARD=0, STRM_HOST=1, STRM_RDMA=2, STRM_TCP=3`; selects data source/sink and local-vs-remote (`is_strm_local()`) |
| `vfid` | 4 (`DEST_BITS`) | no (overwritten) | `user_req_mux` forces `ID_REG` |
| `pid` | 6 | **yes** | Coyote thread id (`ctid`) the request belongs to; selects TLB entries / host process / completion counter. The wrapper does **not** validate it |
| `dest` | 4 (`DATA_DEST_BITS`) | yes | index of the parallel AXI stream (`axis_*_recv/send[dest]`) |
| `last` | 1 | yes | only if set: end-of-request carries `tlast` and a completion (`ack_t`) is produced, completion counters increment |
| `vaddr` | `VADDR_BITS` (48) | yes | virtual address (translated by MMU; process = `pid`) |
| `len` | `LEN_BITS` (28) | yes | bytes, HW max 2^28-1; SW `invoke` caps at 128 MiB (`MAX_TRANSFER_SIZE`) |
| `actv`, `host`, `offs`, `rsrvd` | 1,1,6,22 | no | `user_req_mux` forces `actv=1, host=0` |

`dreq_t` = `{req_t req_1 (rd/local), req_t req_2 (wr/remote)}` = 256 bit: used for host commands (`host_sq`) and remote (RDMA/TCP) requests.

`ack_t` (32 bit): `opcode[5], strm[2], host, dest[4], pid[6], vfid[4], rsrvd[10]`; `opcode` is the `CoyoteOper` value for local completions and the RoCE opcode for RDMA completions. `host=1` means the request came from a host `invoke`, `host=0` from the vFPGA's own `sq_*`. No address/length is returned.

`irq_not_t` (38 bit): `{pid[5:0], value[31:0]}`; `pid` selects the target `ctid`; `value` is delivered to the `uisr` callback.

Constants: `PMTU_BYTES` (default 4096), `N_OUTSTANDING` (default 8), `QUEUE_DEPTH=8`, `AXI_ID_BITS=6`, `PID_BITS=6` (-> 64 ctids/vFPGA), `N_CTID_MAX=64` (SW).

### 2.2 Macros and tie-offs
- Methods on interfaces: `x.tie_off_m()` (drive idle: `valid/tvalid=0`, data 0) and `x.tie_off_s()`. Use `always_comb`.
  - `metaIntf.tie_off_s` -> `ready=1` (drains). `AXI4S/AXI4SR.tie_off_s` -> **`tready=0`** (stalls). `AXI4L.tie_off_s` -> all ready/valid 0 (a host CSR access to a tied-off `axi_ctrl` never completes).
- Macros ([axi_macros.svh](../../../hw/hdl/pkg/axi_macros.svh), [lynx_macros.svh](../../../hw/hdl/pkg/lynx_macros.svh)): `` `AXISR_ASSIGN(s, m) `` (incl. `tid`), `` `AXIS_ASSIGN ``, `` `AXIL_ASSIGN ``, `` `META_ASSIGN(s, m) ``, `` `AXIS_TIE_OFF_M/S ``, `` `AXIS_TIE_ACTIVE_M/S `` (`TIE_OFF_S` sets `tready=1`), `` `AXISR_ASSIGN_FIRST ``. These are **`assign`-based macros** (use at module scope, not inside `always_comb`); `` `AXIS_TIE_OFF_M `` leaves `tid` undriven on an `AXI4SR` (add `assign m.tid = 0`), unlike `x.tie_off_m()` which clears it.
- Helper RTL usable in apps (in project include path): `axisr_reg`, `axis_reg`, `meta_reg`, `queue_meta`, `axisr_arbiter` (see [hw/hdl/common/](../../../hw/hdl/common/)); example 01 uses `axisr_reg`, example 08 `axisr_arbiter`.
- `ifdef` guards from `lynxTypes`: `EN_STRM EN_MEM EN_RDMA EN_TCP EN_NET EN_SNIFFER EN_UCLK EN_PR EN_AVX EN_WB ...` (use e.g. `` `ifdef EN_STRM `` as example 04 does).

## 3. Data streams, `dest`, `tid`

- **Parallel streams:** `N_STRM_AXI` (host), `N_CARD_AXI` (card), `N_RDMA_AXI`, `N_TCP_AXI` independent 512-bit streams *per vFPGA*. Selected per request by `req_t.dest` (SW `localSg.dest`, `rdmaSg.local_dest/remote_dest`). Different `dest` streams back-pressure independently (one queue + data FIFO + credit counter per dest).
- **`dest` semantics:** `dest = i` -> `axis_{host|card}_recv[i]` for reads (data *into* the vFPGA) and `axis_{host|card}_send[i]` for writes (data *out*). `DATA_DEST_BITS=4` bounds streams at 16.
- **`tid` on `*_recv`:** set by the wrapper to the request's `pid` (= `ctid` for host-issued requests). **`tid` on `*_send` is ignored/dropped** by the credit data FIFOs (host/card/RDMA send). Example 08 uses `tid` only to carry the thread id through its own pipeline.
- **Request length vs. beats:** every request of `len` bytes moves `ceil(len/64)` beats; user logic must consume/produce exactly that many beats per request (the beat counter is derived from `len`, not from `tlast`).
- **`tlast` (read path):** `axis_*_recv` carries `tlast` on the final beat of a request **only if `req.last=1`**. **Write path:** shell forwards `tlast_out = user_tlast & req.last`, so for a request with `last=1` the user must assert `tlast` on its final beat; for `last=0` requests user `tlast` is masked. With `last=0` no `ack_t` is produced and `checkCompleted` does not increment.
- **Big requests** are split into `PMTU_BYTES` pieces by `req_parser` (only the final piece keeps `last`).
- **Read credits:** `req_credits_rd` allows at most `N_OUTSTANDING` outstanding read pieces per dest; **write credits** (`req_credits_wr`) only release a write request to the MMU once the user has already pushed enough beats into the dest's data FIFO (so a stalled user cannot block the shell). `req_credits_wr` gates each `PMTU_BYTES` piece on `ceil(len/64)` beats (a partial last beat is charged): the user must be able to stage up to `PMTU_BYTES` (4 KiB) of write data before a piece is released. Hence for writes the **data may need to be produced before/independently of** the write request being forwarded; never make write data depend on the corresponding `cq_wr`.

### 3.1 Remote (RDMA) requests: the responder is the app's job

- Incoming network traffic arrives as **requests on `rq_wr` / `rq_rd`** (`req_t`: `vaddr`, `len`, `pid` decoded from the QPN, `dest` = `remote_dest` of the sender's `rdmaSg`, `opcode` = raw `RC_*` opcode, `last`) plus payload on `axis_rrsp_recv` (WRITE/SEND) or `axis_rreq_recv` (READ response). The shell does **not** move this data to memory by itself: user logic must turn each `rq_wr` into an `sq_wr` and each `rq_rd` into an `sq_rd`, setting `strm` (`STRM_HOST`/`STRM_CARD`) and `dest`, and wire the payload streams to `axis_{host,card}_send/recv[dest]` (`is_opcode_rd_resp(opcode)` separates READ responses from WRITE/SEND). This is the core pattern of [example 09](../../../examples/09_perf_rdma/hw/src/vfpga_top.svh); an undrained `rq_wr` stalls the RX path.
- For READ requests the app must supply the payload on `axis_rrsp_send`; our own outgoing WRITE/SEND payload goes to `axis_rreq_send`.
- Host-initiated `invoke(rdmaSg)` never touches `sq_*`: the local half (payload read) appears on `axis_host_recv[local_dest]` and must be forwarded into `axis_rreq_send` by the app (example 09 comments).

## 4. Control: `axi_ctrl` and `notify`

- **CSRs:** host `setCSR(val, idx)` writes the 64-bit word at byte offset `idx*8` of the vFPGA's 64 KiB user window (`MMAP_CTRL`, `CTRL_REGION_SIZE`); the vFPGA sees it on `axi_ctrl` (address low bits `[ADDR_LSB+:...]` with `ADDR_LSB=3`). BAR2 address = `0x100000 + vfid*0x40000 + 0x20000 + idx*8`; xbar/window details: [shell/shell_top.md](../shell/shell_top.md). Recipes: parse AXI4-Lite manually (see `aes_axi_ctrl_parser.sv` in examples 03/08, `perf_fpga_axi_ctrl_parser.sv` in 07, `packet_sniffer_slv.sv` in 11; all hand-written slaves, 64-bit registers, `wstrb`-aware).
- **Interrupts:** drive `notify.valid`, `notify.data.{pid,value}`; wait for `ready`. `pid` selects which `cThread` (`ctid`) callback fires; `value` is passed to `uisr(int)`. Host-side: section 7 and 8. `cnfg_slave` takes a `notify` only when no other interrupt is pending (`~irq_pending`; shared with page faults), so `notify.ready` can stay low for a while; hold `valid` until `ready`. The wrapper does not rate-limit; the driver serialises per `ctid` (a new interrupt for a ctid blocks until the previous `uisr` returned).

## 5. Wrapper internals ([user_wrapper_tmplt.txt](../../../hw/templates/common/user_wrapper_tmplt.txt), [hw/hdl/user/](../../../hw/hdl/user/))

Order of processing (local data):
1. **Interface conversion** (AXI4S/meta flat ports -> interfaces). Optional `en_user_reg` register stage is hard-disabled (`EN_USER_REG=0` in CMake) and the generated reg-stage code is not wired to the user logic; ignore it.
2. **Request merge:** `host_req_mux` splits `host_sq` (`dreq_t`, from `cnfg_slave`) into local rd/wr (+ remote rd/wr with `EN_NET`); `user_req_mux` takes `sq_rd/sq_wr` (forces `actv=1,host=0,vfid=ID_REG`) and routes by `is_strm_local(strm)`; `req_arb_2_1` round-robins user vs host per direction; `dreq_arb_2_1` same for remote.
3. **Stream split:** `req_mux_stream_1_2` sends `strm==STRM_HOST` to the host path, everything else local to the card path (only when both `EN_STRM` and `EN_MEM`).
4. **Credits (per direction, per target):** `local_credits_{host,card}_{rd,wr}`; internals: `dest_req_mux` (by `dest`) -> `queue_meta` -> `req_parser` (PMTU split) -> `req_credits_{rd,wr}` -> `dest_req_arb` (RR; host variant also drives the `mux` meta telling data muxes which dest/len/pid is next) -> `axis_mux_user_{rd,wr}` (route stream by `mux`; rd attaches `tid=pid`) -> `axisr_data_fifo_512`/`axis_data_fifo_512` per dest. Card variants use `dest_req_arb_ns`/`dest_req_seq_card` and `axis_card_assign_user_rd`. `*_arb_2_1` merges host+card onto `bpss_{rd,wr}_req` (to MMU via [dynamic_top](../../../hw/templates/common/dynamic_top_tmplt.txt)).
5. **Remote (RDMA):** `remote_credits_rd` (`dreq_credits_rd` + `dreq_rdma_parser_rd` + `axis_mux_user_rq`: our READ requests, incoming READ-response / WRITE payload streams `rreq_recv`/`rrsp_recv`), `remote_credits_wr_rdma` (`dreq_credits_wr` + `dreq_rdma_parser_wr` + `dest_dreq_*`: our WRITE/SEND, payload `rreq_send`), `remote_resp_rd` (serves incoming READ requests: `rq_rd` + `rrsp_send`), `dreq_arb_2_1` merges rd/wr into `rdma_sq`; `req_arb_2_1` merges RDMA/TCP `rq` into `rq_wr`; `dreq_mux_net_1_2` splits remote writes between RDMA and TCP.
6. **Completions:** `cq_arb` (RDMA builds only) round-robins `bpss_*_cq` with `rdma_cq` (read-response -> `cq_rd`, ACK -> `cq_wr`); without RDMA `bpss_*_cq` goes straight to `cq_*`. With RDMA, `cq_arb` queues (`QDEPTH=16`) and always accepts input (`ready=1`). **The vFPGA CQ is fire-and-forget:** `cnfg_slave_avx` forwards each ack with `m_bpss_done_*.valid = meta_done_*.valid & meta_done_*.ready` (the vFPGA's `ready` is ignored) and its own input queue is always ready, so an undrained `cq_rd/cq_wr` drops acks (never stalls the shell). Keep `cq_*.ready=1` if unused.
7. **Debug:** `debug_bridge_user` (US+) or `debug_hub_user` (Versal+PR) for ILAs in user logic.

Module roles in [hw/hdl/user/](../../../hw/hdl/user/):

| Dir | Modules | Role |
|---|---|---|
| `mux_init/` | `host_req_mux`, `user_req_mux` | merge host/user requests; local vs remote split |
| `req/` | `req_arb_2_1`, `req_mux_stream_1_2`, `req_parser`, `req_tcp_parser_wr` | arbitration, host/card split, PMTU parsing, TCP cmd parsing |
| `dreq/` | `dreq_arb_2_1`, `dreq_mux_net_1_2`, `dreq_rdma_parser_{rd,wr}` | remote (`dreq_t`) arbitration, RDMA/TCP split, RDMA command build (segmentation into `RC_*` opcodes) |
| `credits/` | `local_credits_*`, `remote_credits_*`, `remote_resp_rd`, `req_credits_{rd,wr}`, `dreq_credits_{rd,wr}` | credit-based flow control: a stalled vFPGA cannot stall shared services |
| `dest/` | `dest_req_{mux,arb,arb_ns,seq,seq_card,card_arb}`, `dest_dreq_{mux,seq,rd_arb,wr_arb}` | per-`dest` demux/arbitration, ordering of requests vs data muxes |
| `axis_mux/` | `axis_mux_user_{rd,wr,rq,tcp,sq,out}`, `axis_mux_join`, `axis_assign_rq`, `axis_card_assign_user_rd` | route 512-bit streams to/from the right `dest`, attach `tid`, join resp/recv |
| `cq/` | `cq_arb` | merge local + RDMA completions |

`EN_CRED_LOCAL`/`EN_CRED_REMOTE` are forced to 1 in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake); the non-credit (`dest_req_seq`) branches are effectively dead. `axis_mux_join`, `dest_req_card_arb`, `axis_mux_user_sq/out`, `axis_assign_rq` are not instantiated by the current wrapper (legacy remnants; also present under `hw/hdl/LEGACY/`).

## 6. Clocks, CDC, partial reconfiguration, multiple configs

- **`aclk` for user logic:** shell `aclk` (default `ACLK_F`=250 MHz) or, with `EN_UCLK=1`, `uclk` at `UCLK_F` (default 250; generated by `shell_ctrl`). The **whole wrapper runs in `uclk`**; CDC happens outside it in [dynamic_top](../../../hw/templates/common/dynamic_top_tmplt.txt): `axis_ccross` (host/card/RDMA streams), `meta_ccross` (sq/cq/notify/host_sq), `axil_ccross` (`axi_ctrl`), followed by `*_reg_array` slices (`N_REG_DYN_*_S1` stages) and **decouplers** (`axis/meta/axil_decoupler`, `decouple_uclk` synchronised into the uclk domain). User code needs no CDC of its own; HLS kernels must be synthesised for the actual clock (`comp_hls.tcl.in` uses `uclk_p` if `EN_UCLK` else `aclk_p`).
- **Constraint:** [user_clk_tmplt.txt](../../../hw/templates/common/user_clk_tmplt.txt) creates `aclk` at `uclk_p`; with `EN_PR` sets `CLOCK_BUFFER_TYPE NONE` on `aclk` (no clock buffers across PR boundary, Vivado 73360). Constraints/floorplans: [../build/constraints.md](../build/constraints.md).
- **PR / configs:** `EN_PR=1`, `N_CONFIG=k`; `load_apps` must receive `N_REGIONS*N_CONFIG` entries named `VFPGA_C<cfg>_<vfid>`. Each `(cfg, vfid)` is synthesised to `user_synthed_c<cfg>_<vfid>.dcp` and a partial bitstream `vfpga_c<cfg>_<vfid>.bit|.pdi`; the shell checkpoint is built from config 0. During a reconfiguration the driver asserts the decouplers (`reconfig_dcpl_app_set`); in-flight transactions to that vFPGA are cut. Runtime: `cRcnfg::reconfigureApp`/`cService` ([software.md](../software.md), example 10; [static/static_top.md](../static/static_top.md) for the PR engine/decouplers).
- `FPLAN_PATH` supplies the vFPGA pblocks (see example 10 `floorplans/`); Versal requires `EN_SHELL_PBLOCK=0` with `EN_PR=1`.

## 7. Software side: `cThread` ([cThread.hpp](../../../sw/include/coyote/cThread.hpp))

```cpp
coyote::cThread t(vfid, getpid() /*hpid*/, device=0, uisr=nullptr /*std::function<void(int)>*/);
void* p = t.getMem({coyote::CoyoteAllocType::HPF, bytes});     // alloc + userMap; freed in dtor
coyote::localSg sg{.addr=p, .len=bytes, .stream=coyote::STRM_HOST, .dest=0};
t.invoke(coyote::CoyoteOper::LOCAL_READ, sg);                   // async
while (t.checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1) {}
t.clearCompleted();
```
Pass `cThread` by reference (copying -> UB; it owns fds/mmaps).

| Call | Behaviour |
|---|---|
| ctor `cThread(vfid, hpid, device, uisr)` | open `/dev/coyote_fpga_<device>_v<vfid>` (`O_RDWR|O_SYNC`); `IOCTL_REGISTER_CTID(hpid)` -> `ctid`; `IOCTL_READ_SHELL_CONFIG` -> `fpgaCnfg` (en_avx/wb/strm/mem/pr/rdma/tcp, TLB page bits); if `uisr`: `eventfd`s + `event_thread` + `IOCTL_REGISTER_EVENTFD`; if `en_rdma`: build local QP (`qpn=(vfid<<6)|ctid`, random PSN, `rkey=0`, IP from driver); `mmapFpga()` (cnfg/ctrl/wback); `clearCompleted()`; opens named mutex `mutex_dev_<device>_vfpa_<vfid>` |
| dtor | unlock if held, `freeMem` all, `munmapFpga`, (if `uisr`) `IOCTL_UNREGISTER_EVENTFD` + write `terminate_efd` + join `event_thread` + close efds, then `IOCTL_UNREGISTER_CTID`, then `closeConn()` if RDMA connected, `close(fd)`; the driver releases a pending notification on unregister |
| `getMem(CoyoteAlloc&&)` / `freeMem(p)` | `REG` (mmap 4 KiB pages), `THP` (`posix_memalign` 2 MiB), `HPF` (`MAP_HUGETLB` with `pg_l_bits` from the shell TLB config), `GPU` (needs `EN_ROCM`/`EN_CUDA`); `PRM` is not handled by `getMem` (returns the null mapping); each -> `userMap` -> `IOCTL_MAP_USER_MEM`. `CoyoteAlloc{alloc,size,remote,gpu_dev_id,gpu_dmabuf_fd,mem_block,mem}`: `remote=true` also stores the buffer in the local QP (used by `initRDMA`); `mem_block` = card memory block (Versal only, `-1`=any) |
| `userMap/userUnmap(vaddr,len[,mem_block])` | map externally allocated buffers (GPU pointers auto-detected -> `IOCTL_MAP_DMABUF`); unmapped addresses still work via page faults (slower) |
| `setCSR(val, idx)` / `getCSR(idx)` | `ctrl_reg[idx]` (`volatile uint64_t*`, `MMAP_CTRL`) -> `axi_ctrl` |
| `invoke(oper, syncSg)` | `LOCAL_OFFLOAD/LOCAL_SYNC` -> `IOCTL_OFFLOAD_REQ/IOCTL_SYNC_REQ`; blocking; requires `en_mem`; not counted by `checkCompleted` |
| `invoke(oper, localSg, last=true)` | `LOCAL_READ`/`LOCAL_WRITE`; async; `postCmd`; throws unless the shell has `en_strm` or `en_mem`, and if len > 128 MiB |
| `invoke(LOCAL_TRANSFER, src, dst, last=true)` | one command with rd half + wr half (src may differ from dst in stream/dest/len) |
| `invoke(oper, rdmaSg, last=true)` | `REMOTE_RDMA_READ/WRITE/SEND`; throws unless shell `en_rdma`; needs `initRDMA` first; if local IP == remote IP does a `memcpy` |
| `invoke(REMOTE_TCP_SEND, tcpSg)` | marked unsupported in `cOps.hpp` |
| `checkCompleted(oper)` | per-`ctid` counter since last `clearCompleted`: LOCAL_WRITE/TRANSFER -> write counter, LOCAL_READ -> read counter, REMOTE_RDMA_READ -> rdma-read, REMOTE_RDMA_WRITE/SEND -> rdma-write (checked in this order; `LOCAL_TRANSFER` therefore polls the *write* side) |
| `clearCompleted()` | zero `wback[ctid + i*64]` (if `en_wb`) and write `CTRL_CLR_STAT|ctid<<10` to the cnfg control register (both rd and wr halves) |
| `lock()/unlock()` | inter-process `boost::named_mutex` per (device, vfid); **`invoke` does not take it implicitly**; use only if several processes/threads must serialise a multi-step sequence |
| `initRDMA(buf, port, server?, mem?)`, `connSync`, `closeConn`, `doArpLookup`, `writeQpContext` | out-of-band TCP QP exchange then `RDMA_CTX_REG/RDMA_CONN_REG/NET_ARP_REG` writes ([services/network.md](../services/network.md)) |
| `getVfid/getCtid/getHpid/getQpair/printDebug` | getters / stats from `STAT_REG_0/1` |

SG structs ([cOps.hpp](../../../sw/include/coyote/cOps.hpp)): `syncSg{addr,len}`, `localSg{addr,len(u32),stream=STRM_HOST,dest=0}`, `rdmaSg{local_offs,local_stream,local_dest,remote_offs,remote_dest,len}` (addresses come from the exchanged QP), `tcpSg{stream=STRM_TCP,dest,len}`. `CoyoteOper`: `NOOP=0, LOCAL_READ=1, LOCAL_WRITE=2, LOCAL_TRANSFER=3, LOCAL_OFFLOAD=4, LOCAL_SYNC=5, REMOTE_RDMA_READ=6, REMOTE_RDMA_WRITE=7, REMOTE_RDMA_SEND=8, REMOTE_TCP_SEND=9`.

### 7.1 `invoke` -> registers -> hardware
Canonical end-to-end path of a host command; other docs link here. `LOCAL_OFFLOAD/SYNC` take the ioctl path instead ([services/mmu.md](../services/mmu.md)).

1. **SW checks** (`invoke`): shell has the needed `en_strm`/`en_mem`/`en_rdma`, `len` <= `MAX_TRANSFER_SIZE` (128 MiB). RDMA with local IP == remote IP is a plain `memcpy`.
2. **Command words:** `invoke` builds up to two control words + two addresses and calls `postCmd(addr_wr, ctrl_wr, addr_rd, ctrl_rd)`. Control word (`cDefs.hpp` `CTRL_*` == `cnfg_slave*.sv` offsets): `[4:0]` opcode (only set for RDMA: `oper - REMOTE_OFFS_OPS` = `RDMA_READ/WRITE/SEND`; local ops leave it 0), `[9:8]` strm, `[15:10]` pid=`ctid`, `[19:16]` dest, `[20]` last, `[21]` START (= HW `actv`), `[22]` CLR_STAT, `[59:32]` len; `[7:5]` unused. Address word = `vaddr`. Local vs remote is decided from `strm`.
   - `LOCAL_READ` fills the rd half, `LOCAL_WRITE` the wr half, `LOCAL_TRANSFER` both (START on each half used).
   - RDMA: only the **remote** half carries START ([cThread.cpp](../../../sw/src/cThread.cpp) `invoke(rdmaSg)`), the local half is descriptor data. READ puts the remote half in the rd slot and the local half in the wr slot; WRITE/SEND the opposite.
3. **Register write (`postCmd`):** with `en_avx` (default) one 256-bit store `[addr_wr, ctrl_wr, addr_rd, ctrl_rd]` to `CnfgAvxRegs::CTRL_REG` (index 0 of `cnfg_reg_avx`, `MMAP_CNFG_AVX`). Non-AVX: four 64-bit stores `VADDR_WR_REG(3), CTRL_REG_2(2), VADDR_RD_REG(1), CTRL_REG(0)` into `cnfg_reg` (`MMAP_CNFG`), `CTRL_REG` last (it triggers the post). The path is chosen at run time from `fcnfg.en_avx` in an `EN_AVX` SW build; a SW build **without** `EN_AVX` only knows the non-AVX registers and breaks on an AVX shell.
4. **Throttle:** `postCmd` tracks `cmd_cnt`; above `CMD_FIFO_DEPTH-CMD_FIFO_THR`=22 it re-reads the used-count from `CTRL_REG` and sleeps `SLEEP_TIME` (100 ns) until the command FIFO drains (HW queue `axis_data_fifo_req_256_used`).
5. **Register decode:** `cnfg_slave*` raises `local_post`/`remote_post` when the `actv` of the rd/wr half is set ([shell/shell_top.md](../shell/shell_top.md) section 4), and pushes a `dreq_t` on `host_sq`.
6. **Split and wrapper:** `host_req_mux` turns it into requests: both halves `actv` -> two local requests; `req_1` alone with remote strm = remote READ; `req_2` alone with remote strm = remote WRITE/SEND **plus** a local read built from `req_1` for the payload. Then the wrapper pipeline (section 5): credits, `dest` streams.
7. **MMU:** `tlb_fsm` translates `vaddr` (per `pid`) and issues host/card DMA; a TLB miss raises a page-fault IRQ, the driver maps the pages and restarts the request ([services/mmu.md](../services/mmu.md)). Data moves on `axis_*_recv/send[dest]`.
8. **Completion:** the MMU emits `ack_t` (only if `last`). `cnfg_slave*` first updates the per-`pid` counter (BRAM, `STAT_DMA_REG + ctid`) or, with `en_wb`, writes it to host memory (`wback[ctid + blk*64]`, blk 0=RD, 1=WR, 2=RD_RDMA, 3=WR_RDMA), and **then** forwards the ack (`m_bpss_done_*`) via `bpss_*_cq` to the vFPGA `cq_rd/cq_wr` (serial, not parallel). No IRQ is raised.
9. **Polling:** `checkCompleted` reads the 32-bit lanes of `STAT_DMA_REG+ctid` (`_mm256_extract_epi32`: 0 local rd, 1 local wr, 2 rdma rd, 3 rdma wr; non-AVX: two 32-bit halves of `STAT_DMA_REG`/`STAT_RDMA_REG`+ctid) or the writeback region. The counters are per `ctid` and per type and count every acked request with that `pid` -- including requests issued by the vFPGA's own `sq_*` (no `ack_t.host` filter). `clearCompleted` zeroes `wback[]` and writes `CTRL_CLR_STAT | ctid<<10` to both halves (AVX: both 64-bit lanes of one 256-bit store; non-AVX: `CTRL_REG_2` then `CTRL_REG`), which zeroes the HW counters of that `pid`.

### 7.2 `ctid`, threads, multiple apps
- `ctid` (0..63) = driver-allocated id per `cThread` per vFPGA (`IOCTL_REGISTER_CTID`); it is the `pid` in every request, the key for TLB ownership, completion counters, user interrupts and the RDMA QPN. Distinct `cThread`s on the same vFPGA run concurrently with independent counters (example 08: 4 threads, `dest=i`, `N_STRM_AXI=4`). Hardware does **not** isolate threads from each other beyond `pid` tagging: sharing one stream between threads requires arbitration in user logic (`axisr_arbiter`, `tid`).
- A vFPGA is shared across processes: each process gets its own `ctid`. `getCtid()` is what user logic needs for `sq_*` requests (`setCSR(ctid, reg)` as in example 07).
- Different vFPGAs: construct one `cThread(i, ...)` per region (example 03).

## 8. Driver & software interaction

Full ioctl/mmap tables: [driver.md](../driver.md#device-nodes-ioctls-and-mmap). Per vFPGA interface:

| vFPGA interface / feature | RTL counterpart (shell side) | SW API | Register / ioctl | Driver function |
|---|---|---|---|---|
| `axi_ctrl` (CSRs) | `axil_ccross`/`axil_decoupler` -> wrapper -> user slave; xbar in `dynamic_xbar` | `setCSR/getCSR` | `mmap` off `MMAP_CTRL` (page 3), 64 KiB | `vfpga_dev_mmap` ([vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c)), no per-access driver involvement |
| `sq_rd/sq_wr` (vFPGA-initiated) | `user_req_mux` -> wrapper -> MMU; **bypasses `cnfg_slave`** | none (user logic issues them; SW only supplies `ctid`/addresses via CSRs) | `axi_ctrl` CSRs defined by the app | none; page faults as below |
| host `invoke` local | `cnfg_slave_avx` `CTRL_REG` -> `host_sq` -> `host_req_mux` -> wrapper | `invoke(localSg/...)` ([software.md#cthread-internals](../software.md#cthread-internals)) | `cnfg_reg_avx[CTRL_REG]` 256-bit store (`MMAP_CNFG_AVX`) or `cnfg_reg[...]` | `vfpga_dev_mmap` only; translation by MMU ([services/mmu.md](../services/mmu.md)) |
| TLB mappings used by `sq_*`/streams | `mmu_top` TLBs ([mmu.md](../services/mmu.md)) | `getMem/userMap/freeMem/userUnmap` | `IOCTL_MAP_USER_MEM`(5) / `UNMAP_USER_MEM`(6) / `MAP_DMABUF`(7) / `UNMAP_DMABUF`(8) | `mmu_handler_gup`, `tlb_put_user_pages`, `p2p_attach_dma_buf` ([vfpga_gup.c](../../../driver/src/vfpga/vfpga_gup.c)) |
| Missing mapping (page fault) | MMU raises `IRQ_PFAULT`, stalls that `pid` until restart | transparent | MSI-X -> ISR regs (`isr_vaddr/len/pid`) | `vfpga_pfault_handler` -> `mmu_handler_gup` -> `restart_mmu` / `drop_irq_pfault` ([vfpga_isr.c](../../../driver/src/vfpga/vfpga_isr.c)); [driver.md#mmu-and-page-faults](../driver.md#mmu-and-page-faults), [software.md#mmu-and-page-faults](../software.md#mmu-and-page-faults), [driver.md#interrupt-flow](../driver.md#interrupt-flow) |
| `cq_rd/cq_wr` + completion counters | `cnfg_slave_avx` (`inst_rd_stat`/`inst_wr_stat` BRAMs, `m_wback`), `wback_dma` (static) | `checkCompleted/clearCompleted` | `STAT_DMA_REG+ctid` lanes (AVX) or `mmap` `MMAP_WB` (page 0) | none at runtime (`vfpga_dev_mmap` maps `MMAP_WB` via `dma_mmap_coherent`) |
| `notify` (user interrupt) | `cnfg_slave_avx` `s_notify` queue -> ISR regs (`isr_pid`, `isr_len` high) -> MSI-X | ctor `uisr` callback; `event_thread` `eventHandler` | `IOCTL_REGISTER_EVENTFD`(3), `IOCTL_GET_NOTIFICATION_VALUE`(19), `IOCTL_SET_NOTIFICATION_PROCESSED`(18), `IOCTL_UNREGISTER_EVENTFD`(4) | `vfpga_isr` -> `read_irq_notify` ([vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c)) -> `vfpga_notify_handler` (locks `user_notifier_lock`, stores `interrupt_value`, `eventfd_signal`) -> [vfpga_uisr.c](../../../driver/src/vfpga/vfpga_uisr.c) `vfpga_register_eventfd`; see [driver.md#user-interrupts](../driver.md#user-interrupts), [software.md#user-interrupts](../software.md#user-interrupts) |
| `rq_rd/rq_wr`, `axis_rreq/rrsp_*`, `rdma_sq/cq` | RDMA stack, `remote_credits_*` | `initRDMA`, `invoke(rdmaSg)`, `doArpLookup`, `writeQpContext` | `RDMA_CTX_REG`, `RDMA_CONN_REG`, `NET_ARP_REG`; `IOCTL_GET_IP_ADDRESS`(13) | `vfpga_dev_ioctl` get/set IP/MAC; see [services/network.md](../services/network.md), [driver.md#networking](../driver.md#networking), [software.md#networking](../software.md#networking) |
| `axis_card_*` / card memory | HBM/DDR, striping, MMU card path | `getMem(...mem_block)`, `invoke(syncSg)` | `IOCTL_OFFLOAD_REQ`(9) / `IOCTL_SYNC_REQ`(10) | `offload_user_pages`/`sync_user_pages` -> `trigger_dma_offload/sync`, `alloc_card_memory` ([vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c)); [driver.md#card-memory](../driver.md#card-memory), [software.md#card-memory](../software.md#card-memory) |
| ctid / process identity (`pid` field) | TLB tag, counters, QPN | `cThread` ctor/dtor, `getCtid` | `IOCTL_REGISTER_CTID`(1) / `UNREGISTER_CTID`(2) | `vfpga_dev_ioctl` (`pid_alloc` list, `hpid_ctid_map`); `pid_array[ctid]=hpid` is what page faults use |
| Shell capabilities seen by SW | `shell_slave`/cnfg regs | `fpgaCnfg` (`en_avx/wb/strm/mem/pr/rdma/tcp`, TLB bits) | `IOCTL_READ_SHELL_CONFIG`(15) | `vfpga_dev_ioctl` |
| Reconfiguration of the app | decouplers around the wrapper | `cRcnfg`, `cService` | `/dev/coyote_fpga_<d>_reconfig` ioctls `RECONFIGURE_APP` | [driver.md](../driver.md#reconfiguration) |
| Sniffer `filter_config`, `axis_*_sniffer` | `packet_sniffer` service (network) | CSRs defined by the app (example 11 `SnifferCSRs`) | `axi_ctrl` | none |

User-interrupt chain in one line: `notify` -> `cnfg_slave*` ISR regs -> MSI-X -> `vfpga_isr`/`vfpga_notify_handler` -> `eventfd_signal(user_notifier[vfid][ctid])` -> `epoll` in `cThread::eventHandler` (`event_thread`) -> `IOCTL_GET_NOTIFICATION_VALUE` -> `uisr(value)` -> `IOCTL_SET_NOTIFICATION_PROCESSED` (releases the per-ctid lock).

## 9. Writing an app (build mechanics)

**Source layout** (one directory per `(cfg, vfid)`; `load_apps` takes a **space-separated list**, first entry is the primary):
```
src/
  vfpga_top.svh        # REQUIRED in the first dir: body of design_user_logic_c*_*
  hdl/*.sv|*.v|*.svh   # copied to <proj>/hdl/ext/raw (extra dirs -> raw/lib<k>/ to avoid name clashes)
  hls/<krnl>/<krnl>.cpp|.hpp   # Vitis HLS; top function name = <krnl>; instantiate as <krnl>_hls_ip
  spinal/<krnl>/*.scala        # SpinalHDL; generated by `sbt "runMain <krnl>Verilog"`; Verilog added from hdl/ext/spinal
  init_ip.tcl          # sourced after project creation (create ILAs/FIFOs/DWCs; has $cfg(...) incl. fpga_arch)
```
- `vfpga_top.svh` is `include`d at the end of the user_logic module: ports (table in section 2) are in scope under their template names; `import lynxTypes::*;` goes at the top by convention. Every port must be driven/tied off.
- Always-needed tie-offs for unused ports (examples copy these verbatim): `notify.tie_off_m(); sq_rd.tie_off_m(); sq_wr.tie_off_m(); cq_rd.tie_off_s(); cq_wr.tie_off_s(); axi_ctrl.tie_off_s();` plus per-stream `axis_*_recv[i].tie_off_s()` (note `tready=0`; use `` `AXIS_TIE_OFF_S `` or `assign ...tready = 1` if data may arrive) / `axis_*_send[i].tie_off_m()`, `rq_rd/rq_wr.tie_off_s()`, RDMA/TCP streams.
- **CMake (hw/CMakeLists.txt)** skeleton: `find_package(CoyoteHW REQUIRED)`; `project(...)`; `set(EN_STRM 1) set(N_REGIONS 1) ...`; `validation_checks_hw()`; `load_apps(VFPGA_C<c>_<v> "<dir> [<lib dirs>]" ...)`; `create_hw()`. Paths are relative to `CMAKE_SOURCE_DIR`. `load_apps` requires exactly `N_REGIONS*N_CONFIG` pairs. Targets: `make project && make bitgen` (see [build/build_top.md](../build/build_top.md)); with `EN_PR` also per-config bitstreams.
- **HLS kernels:** `#pragma HLS INTERFACE axis register port=<p> name=s_axi_<p>`/`m_axi_<p>`, `ap_ctrl_none`; ports `s_axi_in1_TDATA/TKEEP/TLAST/TSTRB/TVALID/TREADY`, `ap_clk`, `ap_rst_n`; tie `TSTRB` to 0. `ap_axiu<512,0,0,0>` carries no `tid` (add one yourself if needed). The IP is `<krnl>_hls_ip` (vendor `user.org`, library `hls`), exported to `iprepo`, instantiated by name (example 02).
- **SpinalHDL:** module must `setDefinitionName(...)`, clock named `aclk`, reset `aresetn`; requires `sbt` + JDK >= 11; one `object <krnl>Verilog extends App` per kernel; the object name minus `Verilog` must equal the `spinal/<krnl>/` folder name ([vector_adder.scala](../../../examples/12_spinal_hdl/hw/src/spinal/VectorAdder/vector_adder.scala) L105); it must call `generateVerilog` with `targetDirectory="gen"` (example 12).

### 9.1 Recipe: first vFPGA (mirrors [examples/01_hello_world](../../../examples/01_hello_world/))
`hw/CMakeLists.txt`
```cmake
cmake_minimum_required(VERSION 3.16)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)            # path to Coyote root
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)
project(my_app)
set(EN_STRM 1)            # host streams
set(EN_MEM 0)             # card streams (set 1 + use axis_card_*)
set(N_REGIONS 1)
validation_checks_hw()
load_apps(VFPGA_C0_0 "src")
create_hw()
```
`hw/src/vfpga_top.svh` (host loopback, +1 on every 32-bit word)
```systemverilog
import lynxTypes::*;
always_comb begin
    for (int i = 0; i < 16; i++) axis_host_send[0].tdata[i*32+:32] = axis_host_recv[0].tdata[i*32+:32] + 1;
    axis_host_send[0].tvalid = axis_host_recv[0].tvalid;
    axis_host_recv[0].tready = axis_host_send[0].tready;
    axis_host_send[0].tkeep  = axis_host_recv[0].tkeep;
    axis_host_send[0].tlast  = axis_host_recv[0].tlast;
    axis_host_send[0].tid    = axis_host_recv[0].tid;
end
always_comb notify.tie_off_m();  always_comb sq_rd.tie_off_m();  always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();   always_comb cq_wr.tie_off_s();  always_comb axi_ctrl.tie_off_s();
```
(Example 01 additionally puts registered stages in `hdl/perf_local.sv` via `axisr_reg` and an ILA from `init_ip.tcl`; `init_ip.tcl` is optional, `hdl/` optional.)

`sw/CMakeLists.txt`: `add_subdirectory(<coyote>/sw ${CMAKE_BINARY_DIR}/coyote)` (or `.../sim/sw` when `EN_SIM`), `add_executable`, `target_link_libraries(<exe> PUBLIC Coyote)`; optional `EN_AVX` (default 1), `EN_CUDA|EN_ROCM` (example 06).
`sw/src/main.cpp`
```cpp
#include <coyote/cThread.hpp>
int main() {
    coyote::cThread t(/*vfid*/0, getpid());
    // REG (4 KiB pages) for a first test: HPF would consume a whole 2 MiB hugepage per 4 KiB buffer
    int *src = (int*) t.getMem({coyote::CoyoteAllocType::REG, 4096});
    int *dst = (int*) t.getMem({coyote::CoyoteAllocType::REG, 4096});
    for (int i = 0; i < 1024; i++) { src[i] = i; dst[i] = 0; }
    coyote::localSg s = {.addr = src, .len = 4096};   // stream=HOST, dest=0 (designated initializers must follow member order; ex. 01 compiles them the same way)
    coyote::localSg d = {.addr = dst, .len = 4096};
    t.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, s, d);
    while (t.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != 1) {}
    // dst[i] == src[i] + 1
}
```
Deploy: program bitstream, `insmod coyote_driver.ko`, run (see [examples/README.md](../../../examples/README.md)).

## 10. Config knobs affecting the user layer ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake))

| Variable (default) | Effect on user interface |
|---|---|
| `N_REGIONS` (1, max 15) | number of vFPGAs; one `cThread vfid` per region |
| `EN_STRM` (1), `N_STRM_AXI` (1) | host streams `axis_host_*[N_STRM_AXI]` |
| `EN_MEM` (0), `N_CARD_AXI` (1) | card streams `axis_card_*[N_CARD_AXI]`, enables sync/offload |
| `EN_RDMA` (0), `N_RDMA_AXI` (1) | `rq_rd`, `rq_wr`, `axis_rreq_*`, `axis_rrsp_*` (US+ only) |
| `EN_TCP` (0), `N_TCP_AXI` (1) | `axis_tcp_*` (broken in current templates) |
| `EN_SNIFFER` (0), `SNIFFER_VFPGA_ID` (0) | sniffer ports on that vFPGA only; setting it forces `EN_NET=1` (cmake: `EN_RDMA OR EN_TCP OR EN_SNIFFER`), which exposes `rq_wr`. Sniffer-only builds (no RDMA/TCP) leave the wrapper's remote sinks/`user_rq_wr_int` undriven (NET-07); example 11 sets `EN_RDMA=1` |
| `DATA_DEST_BITS` (4) | width of `dest`/`vfid` fields |
| `VADDR_BITS` (48) | `vaddr` width |
| `EN_UCLK` (0), `UCLK_F` (250), `ACLK_F` (250) | user clock |
| `EN_PR` (0), `N_CONFIG` (1), `FPLAN_PATH`, `EOS_TIME` | app reconfiguration |
| `EN_SHELL_PBLOCK` (1) | shell floorplan/reconfigurability; must be 0 on Versal with `EN_PR=1` |
| `PMTU_BYTES` (4096), `N_OUTSTANDING` (8) | request split size, outstanding reads (sizes the data FIFOs) |
| `EN_WB` (1), `EN_AVX` (1) | completion via host writeback vs. register polling; AVX command interface |
| `HBM_IMPL` (`unified`) | Versal HBM mapping; with `block`, `dest` MUST equal the `mem_block` of the buffer or the transfer stalls ([v80-notes](../../source/intro/v80-notes.rst)) |
| `LOAD_APPS` | internal, set by `load_apps` |

## 11. UltraScale+ vs Versal

Summary table: [../coyote_top.md#ultrascale-vs-versal-summary](../coyote_top.md#ultrascale-vs-versal-summary). The vFPGA logical interface is identical; user-layer differences:

| Aspect | UltraScale+ | Versal |
|---|---|---|
| `mem_block` / `HBM_IMPL=block` | ignored (`mem_block` not used) | per-pseudo-channel allocation; `dest` must match block in `block` mode; `BLOCK_MEM_IMPL_EN` in `lynxTypes` |
| User debug in wrapper | `debug_bridge_user` + BSCAN ports (`S_BSCAN_*`, `dclk`) | `debug_hub_user` + AXI debug-hub ports only if `EN_PR` |
| User synthesis | normal | `-mode out_of_context` (set only for Versal in [cr_user.tcl.in](../../../scripts/cr_prjcts/cr_user.tcl.in)); resource reports may show black boxes |
| `user_clk` xdc | `dclk` 100 MHz + debug-core properties | only if `EN_PR`: `dclk` at `sclk_p`, `CLOCK_BUFFER_TYPE NONE`; otherwise only the `aclk` clock |
| App PR flow | nested DFX (shell pblock + vFPGA pblocks) | app flow incomplete (TODO in cmake) |

## 12. Examples map (`examples/`)

| # | Demonstrates | vFPGA ifaces / features | Key files | CMake flags (hw) |
|---|---|---|---|---|
| 01 hello_world | host/card loopback, `cThread`, `LOCAL_TRANSFER`, sync, benchmarking | `axis_host_*[0]`, `axis_card_*[0]`; all else tied off | [vfpga_top.svh](../../../examples/01_hello_world/hw/src/vfpga_top.svh), [perf_local.sv](../../../examples/01_hello_world/hw/src/hdl/perf_local.sv), [main.cpp](../../../examples/01_hello_world/sw/src/main.cpp) | `EN_STRM=1 EN_MEM=1 N_REGIONS=1 BUILD_OPT=1` |
| 02 hls_vadd | HLS kernel, 2 parallel host streams (`dest`) | `axis_host_recv[0..1]`, `axis_host_send[0]` | [vector_add.cpp](../../../examples/02_hls_vadd/hw/src/hls/vector_add/vector_add.cpp), [vfpga_top.svh](../../../examples/02_hls_vadd/hw/src/vfpga_top.svh) | `EN_STRM=1 N_STRM_AXI=2 EN_MEM=0` |
| 03 multitenancy | 4 vFPGAs, per-region CSRs (`setCSR`), AES | `axi_ctrl`, `axis_host_*[0]` | [aes_axi_ctrl_parser.sv](../../../examples/03_multitenancy/hw/src/hdl/aes_axi_ctrl_parser.sv), [main.cpp](../../../examples/03_multitenancy/sw/src/main.cpp) | `N_REGIONS=4 EN_STRM=1 BUILD_OPT=1`, `load_apps` x4 |
| 04 user_interrupts | `notify` -> `uisr` callback | `notify`, `axis_host_recv[0]` | [vfpga_top.svh](../../../examples/04_user_interrupts/hw/src/vfpga_top.svh), [main.cpp](../../../examples/04_user_interrupts/sw/src/main.cpp) | `EN_STRM=1` |
| 05 reconfigure_shell | run-time **shell** reconfiguration (`cRcnfg`) | starts from ex. 04's full bitstream (`cyt_top`), loads ex. 02's partial `shell_top.bin|pdi` | [sw/src/main.cpp](../../../examples/05_reconfigure_shell/sw/src/main.cpp) | SW only (hw from other examples; shell pblock; static checkpoint must match) |
| 06 gpu_p2p | GPU dmabuf <-> FPGA | `CoyoteAllocType::GPU` | [cuda/main.cpp](../../../examples/06_gpu_p2p/sw/src/cuda/main.cpp), [rocm/main.cpp](../../../examples/06_gpu_p2p/sw/src/rocm/main.cpp) | SW only: `-DEN_CUDA=1` or `-DEN_ROCM=1`; hw from example 01 |
| 07 perf_fpga | FPGA-initiated DMA via `sq_rd/sq_wr`, `cq_*`, CSR control | `sq_*`, `cq_*`, `axi_ctrl`, `axis_host_*` | [vfpga_top.svh](../../../examples/07_perf_fpga/hw/src/vfpga_top.svh), [perf_fpga_axi_ctrl_parser.sv](../../../examples/07_perf_fpga/hw/src/hdl/perf_fpga_axi_ctrl_parser.sv) | `EN_STRM=1` |
| 08 multithreading | N `cThread`s -> one vFPGA, `dest=i`, `tid`, arbiter, AES-CBC | `axis_host_*[0..3]`, `axi_ctrl` | [vfpga_top.svh](../../../examples/08_multithreading/hw/src/vfpga_top.svh), [main.cpp](../../../examples/08_multithreading/sw/src/main.cpp) | `EN_STRM=1 N_STRM_AXI=4` |
| 09 perf_rdma | RDMA WRITE/READ, `rq_*` -> `sq_*` reflection, `initRDMA` | `rq_rd`, `rq_wr`, `sq_*`, `axis_rreq_*`, `axis_rrsp_*`, `axis_host_*[0..1]` | [vfpga_top.svh](../../../examples/09_perf_rdma/hw/src/vfpga_top.svh), [client/main.cpp](../../../examples/09_perf_rdma/sw/src/client/main.cpp), [server/main.cpp](../../../examples/09_perf_rdma/sw/src/server/main.cpp) | `EN_STRM=1 N_STRM_AXI=2 EN_RDMA=1 BUILD_OPT=1` (US+ only) |
| 10 app_reconfiguration | `N_CONFIG=2` apps per region, scheduler service (`cService`, `cFunc`), HLS apps | `axis_host_*[0..1]` | [apps/*/vfpga_top.svh](../../../examples/10_app_reconfiguration/hw/apps/), [floorplans/](../../../examples/10_app_reconfiguration/hw/floorplans/), [server/main.cpp](../../../examples/10_app_reconfiguration/sw/src/server/main.cpp) | `EN_PR=1 N_CONFIG=2 FPLAN_PATH=... N_STRM_AXI=2`; `load_apps(VFPGA_C0_0 ".../euclidean_distance" VFPGA_C1_0 ".../cosine_similarity")` |
| 11 packet_sniffer | network sniffer service + user app; writes captures with `sq_wr` (`strm=STRM_CARD`); `sq_rd` held invalid, `cq_*` drained | `axis_rx/tx_sniffer`, `filter_config`, `sq_wr`, `axis_card_*`, `axi_ctrl` | [vfpga_top.svh](../../../examples/11_packet_sniffer/hw/src/vfpga_top.svh), [packet_sniffer_slv.sv](../../../examples/11_packet_sniffer/hw/src/hdl/packet_sniffer_slv.sv), [main.cpp](../../../examples/11_packet_sniffer/sw/src/main.cpp) | `EN_STRM=0 EN_MEM=1 EN_RDMA=1 EN_SNIFFER=1 SNIFFER_VFPGA_ID=0` (US+ only) |
| 12 spinal_hdl | SpinalHDL kernel (Scala -> Verilog) | like 02 | [vector_adder.scala](../../../examples/12_spinal_hdl/hw/src/spinal/VectorAdder/vector_adder.scala), [vfpga_top.svh](../../../examples/12_spinal_hdl/hw/src/vfpga_top.svh) | `EN_STRM=1 N_STRM_AXI=2`; `sbt` + JDK >= 11 |

All SW example CMake files accept `-DEN_SIM=ON` to build against the simulator ([simulation.md](../simulation.md)); examples 01-12 SW also need Boost `program_options`.

## 13. Gotchas and invariants

- **Tie everything off.** Undriven ports break synthesis; examples use `always_comb x.tie_off_*()`. `AXI4S*.tie_off_s()` leaves `tready=0`: a host transfer targeting a tied-off recv stream hangs (use `` `AXIS_TIE_OFF_S `` / `tready=1` to sink). `axi_ctrl.tie_off_s()` means CSR access never completes -- do not `getCSR/setCSR` on apps that tie it off.
- **Drain `cq_rd/cq_wr`** (`ready=1`). The CQ is fire-and-forget in every build (path `mmu_top` -> `cnfg_slave_avx` -> `m_bpss_*_cq` -> wrapper -> `cq_*`; with RDMA also through the 16-deep `cq_arb` queues): a slow or non-ready consumer **loses** acks, it never back-pressures the shell. If user logic relies on acks, consume them every cycle (or queue them yourself).
- **Beat accounting:** produce/consume exactly `ceil(len/64)` beats per request per `dest`; set `tkeep` correctly on the final beat; assert `tlast` on the final write beat of `last=1` requests.
- **`last=false`** (SW `invoke(..., false)` or `req.last=0`): no `tlast`, no ack, no counter increment; the *last* request of a sequence must have `last=1`.
- **Request limits:** HW `len` 28 bit; SW throws above 128 MiB; requests are split at `PMTU_BYTES`. SW `localSg.len` is `uint32_t`.
- **`pid`/`ctid`:** vFPGA-issued requests must carry a registered `ctid` (pass it via CSR, example 07); invalid `pid` -> page fault resolved against wrong/none host process. The wrapper does not enforce isolation.
- **`dest` range:** keep `dest < N_*_AXI`. `dest_req_mux` forwards a request only to the queue whose index equals `dest`; for an out-of-range `dest` no queue's `valid` is set and `req_ready[dest]` indexes out of bounds (X in simulation; the request may stall or alias, behaviour undefined). Still unguarded. In Versal `block` HBM mode `dest` must equal `mem_block`.
- **Fixed interface per shell:** all vFPGAs/configs share `EN_*`/`N_*_AXI`; apps must declare the same ports.
- **`EN_AVX` (one-directional rule):** an `EN_AVX` SW build (default) adapts to either shell at run time; a SW build without `EN_AVX` fails against an AVX shell ([driver.md](../driver.md#device-nodes-ioctls-and-mmap)).
- **Completion counters mix sources:** counters are per `ctid` and include vFPGA-initiated requests with the same `pid`; call `clearCompleted()` between phases. `checkCompleted(LOCAL_TRANSFER)` reports writes only.
- **Remote reads:** the intrinsic counter for `REMOTE_RDMA_READ` is the RDMA-read counter, incremented by READ-response acks (`rdma_done_rd`, [cnfg_slave_avx.sv](../../../hw/hdl/shell/cnfg_slave_avx.sv) L1145-1170). Example 09 instead polls `LOCAL_WRITE` because its `vfpga_top.svh` reflects `rq_wr` into `sq_wr`, which yields local-write acks; that is app-specific.
- **uclk:** set `EN_UCLK` to run user logic at `UCLK_F`; HLS clock constraint follows (`uclk_p`). No manual CDC in user code.
- **`ap_axiu` HLS streams have no `tid`:** use `AXISR` signals only if you need it; otherwise leave `tid` 0 on `*_send` (ignored anyway).
- **Simulation:** [simulation.md](../simulation.md) drives `design_user_logic_c0_0` directly (no wrapper, no credits, no CDC); timing/back-pressure behaviour differs from hardware.

## 14. Known defects

Known defects in this area: [known_issues.md](../known_issues.md) (`USR-*`, `NET-01`, `NET-04`, `NET-07`, `DEAD-03`).
