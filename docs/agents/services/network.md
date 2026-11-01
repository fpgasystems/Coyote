# Network services (CMAC, network stack, RoCEv2 RDMA, TCP/IP, packet sniffer)

**Purpose**: everything between the QSFP cage and the per-vFPGA network interfaces (`rq_rd`/`rq_wr`, `axis_rreq_*`/`axis_rrsp_*`, `axis_tcp_*`, sniffer streams), plus the host-side control path (IP/MAC, ARP prefetch, QP context, statistics). UltraScale+ only (CMAC, [summary](../coyote_top.md#ultrascale-vs-versal-summary)), 100G, 512-bit datapath, HLS cores + SystemVerilog glue.
RDMA is the maintained path (RoCEv2, "BALBOA"). TCP/IP is present in RTL but is **not currently usable end to end** (see [Gotchas](#gotchas-and-known-issues)).

## Key files

| Path | Role |
|---|---|
| [network_top.sv](../../../hw/hdl/network/stack/network_top.sv) | Top of the network service: CMAC + early CDC + stack + late CDC (nclk -> aclk) + slicing + card-memory AXI masters |
| [network_module.sv](../../../hw/hdl/network/stack/network_module.sv) | CMAC wrapper + RX FIFO, TX frame padding (HLS) + packet FIFO |
| [cmac_uplus_axis_wrapper.sv](../../../hw/hdl/network/cmac/cmac_uplus_axis_wrapper.sv) | Module `cmac_axis_wrapper`: UltraScale+ CMAC (`cmac_usplus_axis_0`) bring-up FSMs, GT ports, `usr_clk` = `gt_txusrclk2` (322 MHz) |
| [network_stack.sv](../../../hw/hdl/network/stack/network_stack.sv) | L2/L3 plumbing: sniffer, `ip_handler`, ARP, ICMP, `mac_ip_encode`, merge of TX streams, instantiates `roce_stack` / `tcp_stack`, stats counters, IP/MAC registers |
| [network_packet_sniffer.sv](../../../hw/hdl/network/stack/network_packet_sniffer.sv) | `packet_filter` + `packet_sniffer` (RX/TX tap, header-only truncation) |
| [network_ccross_early.sv](../../../hw/hdl/network/stack/network_ccross_early.sv), [common/network_ccross_late.sv](../../../hw/hdl/network/stack/common/network_ccross_late.sv) | CDC 322 MHz -> nclk (early) and nclk -> aclk (late, control/stats) |
| [net_mem_intf.sv](../../../hw/hdl/network/stack/net_mem_intf.sv) | AXI datamover wrapper: stack mem cmds -> AXI4 to card memory (adds `ddr_offset_addr_*`) |
| [roce_stack.sv](../../../hw/hdl/network/rdma/roce_stack.sv) | RoCE wrapper: `rdma_flow`, `rocev2_ip` (HLS), ICRC, read-request trimmer, ACK gap enforcer, retransmission mux |
| [rdma_flow.sv](../../../hw/hdl/network/rdma/rdma_flow.sv), [rdma_mux_retrans.sv](../../../hw/hdl/network/rdma/rdma_mux_retrans.sv), [icrc.sv](../../../hw/hdl/network/rdma/icrc.sv), [read_request_trimmer.sv](../../../hw/hdl/network/rdma/read_request_trimmer.sv), [ack_gap_enforcer.sv](../../../hw/hdl/network/rdma/ack_gap_enforcer.sv) | RDMA sub-blocks (see below) |
| [rdma_arbiter.sv](../../../hw/hdl/network/rdma/rdma_arbiter.sv), [rdma_meta_tx_arbiter.sv](../../../hw/hdl/network/rdma/rdma_meta_tx_arbiter.sv), [rdma_meta_rx_arbiter.sv](../../../hw/hdl/network/rdma/rdma_meta_rx_arbiter.sv), [rdma_mux_cmd_rd.sv](../../../hw/hdl/network/rdma/rdma_mux_cmd_rd.sv), [rdma_mux_cmd_wr.sv](../../../hw/hdl/network/rdma/rdma_mux_cmd_wr.sv) | Per-vFPGA multiplexing (instantiated from `dynamic_top`) |
| [rdma/common/](../../../hw/hdl/network/rdma/common/), [tcp/common/](../../../hw/hdl/network/tcp/common/), [stack/common/](../../../hw/hdl/network/stack/common/) | CDC (`*_ccross_*`) and register-slice (`*_slice*`) wrappers per interface bundle |
| [tcp_stack.sv](../../../hw/hdl/network/tcp/tcp_stack.sv), [tcp_arbiter.sv](../../../hw/hdl/network/tcp/tcp_arbiter.sv), [tcp_conn_table.sv](../../../hw/hdl/network/tcp/tcp_conn_table.sv), [tcp_port_table.sv](../../../hw/hdl/network/tcp/tcp_port_table.sv) | TOE wrapper, listen-port/session tables, per-vFPGA RX/TX arbiters |
| [hw/services/network/](../../../hw/services/network/) (git submodule) | HLS sources of all protocol cores; [CMakeLists.txt](../../../hw/services/network/CMakeLists.txt) selects what is built |
| [network_infrastructure.tcl](../../../scripts/ip_inst/network_infrastructure.tcl) | Vivado `create_ip` for CMAC (per board), FIFOs, CDC, HLS IPs (versions are pinned here) |
| [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | Network constants/structs: `rdma_qp_ctx_t`, `rdma_qp_conn_t`, `net_stat_t`, `RDMA_*`, `TCP_*`, `DEF_IP/MAC_ADDRESS` |
| [shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt) / [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt) / [user_wrapper_tmplt.txt](../../../hw/templates/common/user_wrapper_tmplt.txt) | Instantiate `network_top`; per-vFPGA arbitration, CDC to uclk, decoupling, credits |
| [shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv), [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv) (+ [`_avx`](../../../hw/hdl/shell/cnfg_slave_avx.sv)) | Registers: IP/MAC/stats (shell-level), ARP/QP ctx/conn/RDMA completions (per-vFPGA) |
| [cThread.cpp](../../../sw/src/cThread.cpp), [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp), [cOps.hpp](../../../sw/include/coyote/cOps.hpp) | SW: `initRDMA`, `writeQpContext`, `doArpLookup`, `invoke(rdmaSg)`, `ibvQ`/`ibvQp` |
| [coyote_driver.c](../../../driver/src/coyote_driver.c) (`ip_addr`/`mac_addr` module params), [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c), [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c), [coyote_setup.c](../../../driver/src/coyote_setup.c) | Driver: `ip_addr`/`mac_addr` params, IP/MAC ioctls, `cyt_attr_nstats` |
| [09_perf_rdma](../../../examples/09_perf_rdma/), [11_packet_sniffer](../../../examples/11_packet_sniffer/) | Reference designs |

**Related**: [../coyote_top.md](../coyote_top.md), [../shell/shell_top.md](../shell/shell_top.md) (clocks, shell/vFPGA register map), [memory.md](memory.md) (card memory used as retransmission/TOE buffer), [mmu.md](mmu.md) (translation of RDMA-triggered DMA), [../user/user_top.md](../user/user_top.md) (vFPGA ports), [../driver.md#networking](../driver.md#networking), [../software.md#networking](../software.md#networking), [../build/build_top.md](../build/build_top.md), [../build/constraints.md](../build/constraints.md) (QSFP pins/floorplan), [../simulation.md](../simulation.md) (no networking in sim).

## 1. What it does

- Terminates one 100G Ethernet port (QSFP0 **or** QSFP1, never both) and exposes it to **all vFPGAs** of the shell through arbiters.
- Protocols on the wire: ARP, ICMP(v4), IPv4, UDP (RoCEv2 on UDP port 4791 = 0x12B7), TCP (TOE). IPv6/ICMPv6 outputs of `ip_handler` are tied off (`tready=1`, dropped) in [network_stack.sv](../../../hw/hdl/network/stack/network_stack.sv).
- Services selected at build time: `EN_RDMA`, `EN_TCP`, `EN_SNIFFER` (any of them sets `EN_NET`, see [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), `EN_NET`). The IP/MAC/ARP/ICMP infrastructure is always present when `EN_NET=1`.
- Both RDMA and TCP need **card memory** (HBM/DDR): RDMA for the retransmission buffer, TCP for TX/RX buffers. `EN_TCP`/`EN_RDMA` force-enable the card-memory subsystem and add one memory channel each (`N_NET_CHAN`); see [memory.md](memory.md).

## 2. Hierarchy and datapath

```
QSFP -- GT/CMAC (322 MHz usr_clk = rclk) ----------------------------------------- hw/hdl/network/cmac
   |  network_module: 2-stage regs -> axis_data_fifo_512_cc_rx (RX)
   |                  TX: ethernet_frame_padding_512 (HLS) -> axis_pkg_fifo_512 (store&fwd) -> axis_data_fifo_512_cc_tx
   v
network_ccross_early (rclk -> nclk; only if EN_NCLK=1, else n_clk = rclk)  ---------- stack/network_top.sv
   v                                                          nclk domain
network_stack
   RX: axis_reg -> [packet_sniffer RX tap] -> ip_handler_ip (HLS) -+-> ARP -> arp_server_subnet_ip
                                                                   +-> ICMP -> 512->64 -> icmp_server_ip -> 64->512
                                                                   +-> UDP  -> sink (tready=1, dropped)
                                                                   +-> TCP  -> tcp_stack (EN_TCP)  [toe_ip + hash_table_ip]
                                                                   +-> RoCE -> roce_stack (EN_RDMA) [rocev2_ip]
   TX: icmp / udp(unused) / tcp / roce -> axis_interconnect_512_4to1 -> mac_ip_encode_ip (ARP lookup, IP->Eth)
         -> axis_interconnect_512_2to1 (mac_merger: ARP replies + IP frames) -> [packet_sniffer TX tap] -> m_axis_net
   v
network_ccross_late + rdma/tcp_ccross_late_net + *_slice_array_net (nclk -> aclk; N_REG_NET_S0 stages)
   v                                                           aclk domain (shell clock)
net_mem_intf (RDMA, TCP) -> AXI4 -> axi_stripe -> card memory (shell_top)
   v
dynamic_top: rdma_slice_array_dyn -> rdma_arbiter / tcp_arbiter (N_REGIONS) -> rdma_ccross_ul / tcp_ccross_ul (aclk->uclk, if EN_UCLK)
          -> *_slice_array_ul -> decouplers -> design_user_wrapper_i -> credits/muxes -> vFPGA (rq_rd, rq_wr, axis_rreq_*, axis_rrsp_*, axis_tcp_*)
```

Instantiation: `inst_network_top` in [shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt) (`CROSS_EARLY = EN_NCLK`, `CROSS_LATE = 1`). Generic `network_top` ports are guarded by `` `ifdef EN_RDMA/EN_TCP/EN_SNIFFER/EN_STATS ``.

### 2.1 CMAC (`network_module`, `cmac_axis_wrapper`)
- One CMAC IP instance `cmac_usplus_axis_0`, 4x25G (CAUI4), AXIS user interface, flow control off, `ADD_GT_CNRL_STS_PORTS=1`. Created per board and per port in [network_infrastructure.tcl](../../../scripts/ip_inst/network_infrastructure.tcl): u55c (`CMACE4_X0Y5`, GT `X0Y24..27`/`X0Y28..31`), u250/u200 (`X0Y7`), u280 (`X0Y6`). There is no v80 branch.
- Wrapper handles RX/TX bring-up: waits for `stat_rx_aligned`, then enables RX/TX (`ctl_rx_enable`, `ctl_tx_enable`), sends LFI/RFI while link is down. `tx_rst` -> `rresetn` (BUFG) is the reset of the whole stack at `rclk`. Optional `CMAC_DEBUG` (ILA/counters), `POLARITY_INV`.
- `init_clk` = `dclk`, `sys_reset` from shell top. GT reference clock 156.25 MHz (u250/u280/u200) or 161.1328125 MHz (u55c).
- TX path pads to the 64 B Ethernet minimum (HLS [ethernet_frame_padding_512](../../../hw/services/network/hls/ethernet_frame_padding_512/)) and then uses a **packet FIFO** (`axis_pkg_fifo_512`, `FIFO_MODE=2`) so that a frame is presented to the CMAC without bubbles.

### 2.2 `network_stack` details
- IP/MAC registers: reset to `DEF_IP_ADDRESS` (`0xD1D4010B`) / `DEF_MAC_ADDRESS` (`0xE59D02350A00`), updated by `s_set_ip_addr`/`s_set_mac_addr` with **byte reversal** (register value `0B01D4D1` -> internal `D1D4010B`; i.e. the driver parameter is the natural-order hex of the dotted quad, 11.1.212.209). Subnet mask is fixed `IP_SUBNET_MASK=0x00FFFFFF` (as seen by HLS, i.e. /24), default gateway = `{ip[31:28], 8'h01, ip[23:0]}`; DHCP is compiled out (`DHCP_EN=0`).
- ARP: `arp_server_subnet_ip` answers requests and keeps a cache; `mac_ip_encode_ip` issues lookups for TX packets. Host side `s_arp_lookup_request` (from `NET_ARP_REG`) is a **prefetch**: its reply output (`m_axis_host_arp_lookup_reply`) is left unconnected, so SW cannot read back the MAC.
- Stats: counters in `net_stat_t` ([lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt)) incremented at stream boundaries (`rx/tx_pkg`, `arp`, `icmp`, `tcp`, `roce`; `ibv_*`, `psn_drop`, `retrans` come from `rocev2_ip`; `axis_stream_down` is high while `s_axis_net.tvalid && !tready` has persisted for `NET_STRM_DOWN_THRS=256` cycles; the counter restarts whenever `tready` is seen high, so it is a live indicator, but in practice it means the RX path is stuck). Delayed by `NET_STATS_DELAY` stages, crossed to aclk. Only built with `EN_STATS`.
- Unused leftover: `rdma_mux_cmd_sink.sv` is an empty file.

## 3. HLS service cores and how they are built

Sources in the submodule [hw/services/network/hls](../../../hw/services/network/hls/) (ETH Zurich Systems Group stack). Each core has a `CMakeLists.txt` + `make.tcl.in` that runs Vitis HLS `csynth_design` + `export_design -format ip_catalog` into `${IPREPO_DIR}` (= `<build>/iprepo`, [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), `IPREPO_DIR`).

| HLS dir | Vivado IP / instance name | Built when | Function |
|---|---|---|---|
| [ethernet_frame_padding_512](../../../hw/services/network/hls/ethernet_frame_padding_512/) | `ethernet_frame_padding_512_ip` v0.1 | `EN_TCP or EN_RDMA` | Pads frames < 60/64 B |
| [ip_handler](../../../hw/services/network/hls/ip_handler/) | `ip_handler_ip` v2.0 | same | Ethernet RX: demux ARP / ICMP / ICMPv6 / UDP / TCP / RoCE (UDP port 4791), checks dst MAC/IP |
| [arp_server_subnet](../../../hw/services/network/hls/arp_server_subnet/) | `arp_server_subnet_ip` v1.1 | same | ARP request/reply + cache, host lookup interface, request/reply counters |
| [icmp_server](../../../hw/services/network/hls/icmp_server/) | `icmp_server_ip` v1.67 (vendor `xilinx.labs`) | same | Ping responder (64-bit datapath, hence 512<->64 converters) |
| [mac_ip_encode](../../../hw/services/network/hls/mac_ip_encode/) | `mac_ip_encode_ip` v2.0 | same | Prepend Ethernet header using ARP lookup (subnet/gateway aware) |
| [udp](../../../hw/services/network/hls/udp/), [crc](../../../hw/services/network/hls/crc/), [ipv6](../../../hw/services/network/hls/ipv6/) | **not separate IPs**: compiled into `rocev2` | `EN_RDMA` | UDP framing, ICRC for RoCE; ipv6 unused (`IP_VERSION 4`) |
| [ipv4](../../../hw/services/network/hls/ipv4/) | built as its own HLS IP (`EN_TCP or EN_RDMA`) but its `create_ip` is commented out in `network_infrastructure.tcl` (`ipv4_ip`) -> built, not instantiated; `rocev2` compiles `ipv4.cpp` in | - | IPv4 framing for RoCE |
| [rocev2](../../../hw/services/network/hls/rocev2/) + [ib_transport_protocol](../../../hw/services/network/hls/ib_transport_protocol/) | `rocev2_ip` v0.82 | `EN_RDMA` | RoCEv2 endpoint (`rocev2_top`): crc -> ipv4 -> udp -> IB transport |
| [toe](../../../hw/services/network/hls/toe/) | `toe_ip` v1.6 | `EN_TCP` | TCP offload engine |
| [hash_table](../../../hw/services/network/hls/hash_table/) | `hash_table_ip` v1.0 | `EN_TCP` | Session lookup (tabulation hashing) for the TOE |
| [ethernet](../../../hw/services/network/hls/ethernet/) | header only (`ethernet.hpp`) | - | Shared types |

Build flow:
1. [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) `gen_targets`: `if(EN_NET) add_subdirectory(hw/services/network)` and adds `make services` to the shell/static build commands.
2. [hw/services/network/CMakeLists.txt](../../../hw/services/network/CMakeLists.txt): `add_subdirectory` for the common cores if `EN_TCP OR EN_RDMA`; `toe`+`hash_table` if `EN_TCP`; `rocev2` if `EN_RDMA`. Parameters: `CLOCK_PERIOD=4` ns (250 MHz), `CLOCK_UNCERTAINTY=25%`, `DATA_WIDTH=64` bytes, `TCP_STACK_MSS=4096`, `TCP_STACK_WINDOW_SCALING_EN=1`; rocev2 also `PMTU_BYTES` (shared with Coyote), `ROCE_STACK_MAX_QPS=500`, `RETRANS_EN` (define is hard-wired, NET-08). `FPGA_PART` is inherited from the Coyote cache.
3. [network_infrastructure.tcl](../../../scripts/ip_inst/network_infrastructure.tcl) (sourced by [cr_shell.tcl.in](../../../scripts/cr_prjcts/cr_shell.tcl.in)) instantiates the exported IPs by `-version`; **bump the version there if you change `export_design -version`**. HLS cores with `VITIS_HLS` define use the Vitis port names (`m_axis_*_TDATA`, `s_axis_sq_meta_TDATA`) while the non-`VITIS_HLS` branch uses `*_V_V_*`; the Vitis branch is the one exercised.
4. **A sniffer-only build (`EN_SNIFFER=1`, `EN_RDMA=0`, `EN_TCP=0`) would not build `ip_handler`, `arp_server_subnet`, ... because of the `EN_TCP OR EN_RDMA` guard, while `network_stack` instantiates them unconditionally.** [11_packet_sniffer](../../../examples/11_packet_sniffer/hw/CMakeLists.txt) therefore sets `EN_RDMA=1`.

## 4. RoCEv2 (RDMA) in detail

### 4.1 Supported
- Reliable Connection (RC) only. Operations: `RDMA WRITE` (FIRST/MIDDLE/LAST/ONLY, + `WITH_IMM` opcodes exist in the HLS enum), `RDMA READ` (request + READ RESPONSE FIRST/MIDDLE/LAST/ONLY), `SEND` (FIRST/MIDDLE/LAST/ONLY), RC ACK. IB opcodes: `ibOpCode` in [ib_transport_protocol.hpp](../../../hw/services/network/hls/ib_transport_protocol/ib_transport_protocol.hpp), SV mirror `RC_*` in [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt).
- Interoperates with commodity NICs (tested with ConnectX-5 per [dynamic.rst](../../../docs/source/system/dynamic.rst)). That doc's field widths are stale; trust RTL.
- Not supported: IPv6 RoCE, UD/UC, atomics, multiple PKeys, RX ICRC enforcement (NET-06).

### 4.2 `roce_stack` pipeline
```
RX: s_axis_rx(IP pkts, no Ethernet) -> axis_data_fifo_512_cc_tx ("incoming_traffic_fifo") -> ack_gap_enforcer -> rocev2_ip
TX: rocev2_ip -> read_request_trimmer -> icrc -> m_axis_tx
Ctrl: s_rdma_sq -> rdma_flow -> rocev2_ip.s_axis_sq_meta ; rocev2_ip.m_axis_rx_ack_meta -> rdma_flow -> m_rdma_ack
Mem : rocev2_ip.m_axis_mem_{write,read}_cmd -> rdma_wr_req (to user) / rdma_rd_req -> rdma_mux_retrans
```
- `rocev2_ip` internals ([rocev2.cpp](../../../hw/services/network/hls/rocev2/rocev2.cpp)): `crc` (strip/compute) -> `ipv4` -> `udp` -> `ib_transport_protocol`. IB core ([ib_transport_protocol.cpp](../../../hw/services/network/hls/ib_transport_protocol/ib_transport_protocol.cpp), 2.8k lines): RX `rx_process_ibh/exh`, `rx_ibh_fsm`, `rx_exh_fsm`, `drop_ooo_ibh`, `handle_read_requests`; TX `local_req_handler`, `generate_ibh/exh`, `append_payload`, `prepend_ibh_header`, `tx_pkg_arbiter`.
- State tables (all BRAM, indexed by QPN, size `MAX_QPS`=500): [state_table.hpp](../../../hw/services/network/hls/ib_transport_protocol/state_table.hpp) (PSNs, retry counter; the `qpState` enum exists but the state field is not written), [msn_table.hpp](../../../hw/services/network/hls/ib_transport_protocol/msn_table.hpp) (MSN, vaddr, r_key), [conn_table.hpp](../../../hw/services/network/hls/ib_transport_protocol/conn_table.hpp) (remote QPN, remote IP (128 b), UDP port), [read_req_table.hpp](../../../hw/services/network/hls/ib_transport_protocol/read_req_table.hpp), [flow_control.hpp](../../../hw/services/network/hls/ib_transport_protocol/flow_control.hpp) (32-entry outstanding window per QP), [transport_timer.hpp](../../../hw/services/network/hls/ib_transport_protocol/transport_timer.hpp) (one timer per QP, retry counter, `RETRANS_RETRY_CNT=12`), [retransmitter/](../../../hw/services/network/hls/ib_transport_protocol/retransmitter/) (linked-list of in-flight requests, free list, triggered by the timer or a NAK, [retransmitter.md](../../../hw/services/network/hls/ib_transport_protocol/retransmitter/retransmitter.md)).
- QP setup interfaces of `rocev2_ip` (see [4.3](#43-qp-context-and-connection-table)): `s_axis_qp_interface` (`qpContext`), `s_axis_qp_conn_interface` (`ifConnReq`).
- **QP = per (vFPGA, cThread)**: `QPN = (vfid << 6) | ctid` (10 significant bits; RTL carries 16, [roce_stack.sv](../../../hw/hdl/network/rdma/roce_stack.sv) packs `{vfid, pid}` into `RDMA_QPN_BITS=16`). One cThread has exactly one QP (`ibvQp` with local/remote `ibvQ`). Consequence: **QPN must be < `ROCE_STACK_MAX_QPS` (500)** or table indices overflow (not checked in RTL; `vfid*64+ctid` reaches 500 at vfid 7, ctid 52).
- Remote side address of payload: `vaddr` exchanged at QP setup is the base of the registered buffer; `rdmaSg.local_offs/remote_offs` add offsets. The **remote destination stream** (`remote_dest`, 4 b) and stream type (`strm`, 2 b) travel in bits `[51:48]` / `[53:52]` of the remote vaddr field of the SQ descriptor (see `rdma_sq_data` packing in `roce_stack.sv`) and come back in `memCmd.dst/strm` on the responder.

### 4.3 QP context and connection table
SV types ([lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt), `rdma_qp_ctx_t`/`rdma_qp_conn_t`):

| Struct | Fields (MSB..LSB order as packed) | Written from SW (`writeQpContext`) |
|---|---|---|
| `rdma_qp_ctx_t` (184 b) | `vaddr[47:0]`, `r_key[31:0]`, `local_psn[23:0]`, `remote_psn[23:0]`, `qp_num[23:0]`, `new_state[31:0]` | `qp_num`=local QPN, `r_key`=**remote** rkey, PSNs, `vaddr`=**remote** buffer vaddr; `new_state` tied to 0 and ignored: the `state_table.hpp` assignment is commented out, a context write only sets PSNs and `retryCounter` (3 bit, reset to 7), so HLS has no QP state machine |
| `rdma_qp_conn_t` (184 b) | `remote_udp_port[15:0]`, `remote_ip_address[127:0]`, `remote_qpn[23:0]`, `local_qpn[15:0]` | local/remote QPN, `port` (the TCP port passed to `initRDMA`, **used as UDP port field**), remote GID (IP repeated 4x) |

Both are posted by writing the last of three 64-bit registers (`RDMA_CTX_REG_2`, `RDMA_CONN_REG_2`): the RTL raises `valid` on that write ([cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv), `RDMA_CTX_REG_2`/`RDMA_CONN_REG_2` cases). Order matters: write REG_0, REG_1, then REG_2. Per-vFPGA `meta_arbiter`s in [mmu_top.sv](../../../hw/hdl/mmu/mmu_top.sv) serialise ctx/conn/ARP writes from all vFPGAs into the single network-side interface.

### 4.4 Request path (requester)
1. A request comes either from the host (`cThread::invoke` -> `cnfg_slave` -> `host_sq`) or from the vFPGA (`sq_rd/sq_wr` with `strm=STRM_RDMA`). [host_req_mux.sv](../../../hw/hdl/user/mux_init/host_req_mux.sv) / `user_req_mux` classify as remote when `strm` is not host/card.
2. `dreq_t` = `{req_1 (rd/local), req_2 (wr/remote)}`. For remote WRITE/SEND, [dreq_rdma_parser_wr.sv](../../../hw/hdl/user/dreq/dreq_rdma_parser_wr.sv) splits into PMTU-sized segments; [remote_credits_wr_rdma.sv](../../../hw/hdl/user/credits/remote_credits_wr_rdma.sv) / [remote_credits_rd.sv](../../../hw/hdl/user/credits/remote_credits_rd.sv) apply per-destination credits and pair descriptors with the data stream `axis_rreq_send[dest]` (payload for WRITE/SEND).
3. [rdma_meta_tx_arbiter.sv](../../../hw/hdl/network/rdma/rdma_meta_tx_arbiter.sv) round-robins across vFPGAs (`MULT_REGIONS`) and muxes the payload stream in descriptor order (sequence queue of `{vfid,len}`).
4. [rdma_flow.sv](../../../hw/hdl/network/rdma/rdma_flow.sv): per `(is_read, vfid, pid)` window of `RDMA_N_WR_OUTSTANDING=16` (used for reads too; `RDMA_N_RD_OUTSTANDING=8` is used by the vFPGA-side [dreq_credits_rd.sv](../../../hw/hdl/user/credits/dreq_credits_rd.sv)). Tags the descriptor with `offs = head` = retransmission-buffer slot, and queues ACKs (`ack_que_in`) so the vFPGA/host see completions only for `last` ACKs.
5. `rocev2_ip` builds BTH (+RETH/AETH/IMM), emits packets; payload comes from `m_axis_mem_read_data` <- `rdma_mux_retrans.m_axis_net`.
6. [rdma_mux_retrans.sv](../../../hw/hdl/network/rdma/rdma_mux_retrans.sv): for `actv=1` WRITE/SEND data it **copies the payload to card memory** (`m_req_ddr_wr` + `m_axis_ddr`) while forwarding to the stack; for `actv=0` read commands (= retransmission) it **reads payload back from card memory** (`m_req_ddr_rd`). READ RESPONSE payloads (`actv=1`, read-response opcodes) come from the responder-side vFPGA stream `axis_rrsp_send` and are *not* buffered. Buffer address = `{vfid, pid, slot(offs)}` (each field shifted by the preceding widths, zeros below `offs << log2(PMTU)`) then `<< RDMA_MEM_SHIFT(27)`, + `ddr_offset_addr_rdma` (shell reg `RDMA_OFFS_REG`, default 0).
7. TX: [read_request_trimmer.sv](../../../hw/hdl/network/rdma/read_request_trimmer.sv) shortens READ_REQUEST (opcode `0x0C`) to a single 56 B beat; [icrc.sv](../../../hw/hdl/network/rdma/icrc.sv) (16-stage CRC32 pipeline, masking of variable fields) appends the real ICRC.

### 4.5 Response path (responder) and ACKs
- RX: [ack_gap_enforcer.sv](../../../hw/hdl/network/rdma/ack_gap_enforcer.sv) inserts 85 cycles (`8'h55`) of back-pressure after an ACK packet so the HLS ACK handling (tables) is not overrun. `rocev2_ip` validates QPN/PSN (`drop_ooo_ibh`, `roce_psn_drop_counter`), then:
  - WRITE/SEND payload -> `m_axis_mem_write_data` + `m_axis_mem_write_cmd` -> `rdma_wr_req` (to vFPGA as `rq_wr`) and `m_axis_rdma_wr`;
  - READ request -> `m_axis_mem_read_cmd` -> `rdma_rd_req` -> `rdma_mux_retrans` -> `rq_rd` to the vFPGA (the vFPGA must answer with payload on `axis_rrsp_send`);
  - READ RESPONSE payload -> as WRITE (`rq_wr`, to the *requester* vFPGA, `axis_rreq_recv`).
- ACK generation/NAK is inside the IB core; incoming ACKs/READ-response completions are reported as `ackMeta` -> `rdma_ack` -> `rdma_flow` -> `m_rdma_ack`.
- [rdma_mux_cmd_rd.sv](../../../hw/hdl/network/rdma/rdma_mux_cmd_rd.sv), [rdma_mux_cmd_wr.sv](../../../hw/hdl/network/rdma/rdma_mux_cmd_wr.sv): route `rq_rd`/`rq_wr` + payload to the vFPGA given by `req.vfid` (decoded from QPN); [rdma_meta_rx_arbiter.sv](../../../hw/hdl/network/rdma/rdma_meta_rx_arbiter.sv) routes ACKs by `ack.vfid`, plus a copy to the host completion path (`m_rdma_host_cq_user`).

### 4.6 PMTU, flow control, retransmission summary
| Topic | Mechanism | Where |
|---|---|---|
| PMTU | `PMTU_BYTES` (CMake, default 4096) = HLS `PMTU` = split size of `dreq_rdma_parser_wr` = retrans slot size. Peer QP MTU/jumbo frames must match | [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), [rocev2_config.hpp.in](../../../hw/services/network/hls/rocev2/rocev2_config.hpp.in) |
| Outstanding window | 16 requests per `(vfid,pid)` and direction in `rdma_flow`; 32 per QP in HLS `flow_control` | `rdma_flow.sv`, `flow_control.hpp` |
| Credits (vFPGA side) | per `axis_*[dest]` credit counters before a descriptor is issued/data accepted | `hw/hdl/user/credits/remote_*.sv` |
| Retransmission | timer per QP (up to 12 retries) + NAK; payload re-read from card memory; counter `retrans_count` (`Retrans cnt`) | `transport_timer.hpp`, `retransmitter/`, `rdma_mux_retrans.sv` |
| Completion to SW | per-pid counters in `cnfg_slave` (separate RD/WR RDMA counters, optional writeback blocks `RD_RDMA_WBACK=2`, `WR_RDMA_WBACK=3`) | `cnfg_slave.sv` (`inst_cmplt_rdma_q`) |

### 4.7 Message flow: `REMOTE_RDMA_WRITE` from `cThread::invoke` to the wire and back
The shared local part (`invoke` -> `postCmd` -> `cnfg_slave` -> `host_sq` -> `host_req_mux`) is in [user_top.md](../user/user_top.md#71-invoke---registers---hardware); this adds the remote half.
```
SW (client)                          client FPGA                                            server FPGA / SW (server)
invoke(REMOTE_RDMA_WRITE, rdmaSg)
 -> postCmd: writes CTRL_REG/VADDR regs
    (remote cmd: STRM_RDMA, START)
                         cnfg_slave: remote_post -> host_sq (dreq_t)
                         user_wrapper: host_req_mux -> remote_sq_wr -> remote_credits_wr_rdma
                           [also a local READ of the buffer -> axis_host_recv[local_dest] -> vFPGA kernel -> axis_rreq_send[local_dest]]
                         rdma_arbiter/meta_tx_arbiter -> (CDC) -> rdma_flow -> rocev2_ip
                         rdma_mux_retrans: payload -> network AND copy -> card memory
                         icrc -> mac_ip_encode -> CMAC  ========= RoCEv2 WRITE FIRST/MIDDLE/LAST|ONLY =========>  CMAC -> ip_handler -> roce_stack
                                                                                                                  rocev2_ip: QP/PSN check
                                                                                                                  rq_wr (+payload) -> vFPGA
                                                                                                                  vFPGA: sq_wr -> LOCAL_WRITE to host
                                                                                                                  (examples: rq_wr -> sq_wr)
                         <============================== RC ACK =============================================== ack from rocev2_ip
                         rocev2_ip -> m_rdma_ack -> rdma_flow(queue) -> rdma_meta_rx_arbiter
                         -> cnfg_slave RDMA completion counter (pid) [and vFPGA cq_wr via cq_arb]
checkCompleted(REMOTE_RDMA_WRITE) polls the counter: AVX `STAT_DMA_REG+ctid` word field 3 (READ: field 2); legacy `STAT_RDMA_REG`(128)+ctid, READ = low 32 b, WRITE = high 32 b; or writeback block 3 (READ: 2)
```
For `REMOTE_RDMA_READ` the SW swaps source/destination roles in `invoke`; only the descriptor leaves the FPGA, the remote vFPGA must serve `rq_rd` with `axis_rrsp_send`, and data returns as READ RESPONSE through `rq_wr`/`axis_rreq_recv` into a local write (`checkCompleted(REMOTE_RDMA_READ)` counts `rd_resp` ACKs).

## 5. Per-vFPGA multiplexing and IDs

| vFPGA port | Meaning (from the vFPGA's view) | Internal name | Reference |
|---|---|---|---|
| `sq_rd`, `sq_wr` (+ `cq_rd/wr`) | Issue local/remote commands; `req_t.strm=STRM_RDMA`(2) / `STRM_TCP`(3) selects network | `user_sq_*`, `user_remote_sq_*` | [user_top.md](../user/user_top.md) |
| `rq_wr` | **Incoming** payload is arriving (remote WRITE/SEND, or READ RESPONSE for our READ); descriptor only | `rdma_rq_wr`, `user_rq_wr_int` | [user_wrapper_tmplt.txt](../../../hw/templates/common/user_wrapper_tmplt.txt) |
| `rq_rd` | Remote READ request arrived; vFPGA must supply payload | `user_rq_rd_int` | same |
| `axis_rreq_send[N_RDMA_AXI]` | Payload for our outgoing WRITE/SEND (requester) | `axis_rdma_send_req_int` -> `axis_rdma_src_req` | `remote_credits_wr_rdma` |
| `axis_rreq_recv[N_RDMA_AXI]` | Payload of READ RESPONSEs to our READs | `axis_rdma_resp_int` | `remote_credits_rd` (`m_axis_resp`) |
| `axis_rrsp_recv[N_RDMA_AXI]` | Payload of incoming remote WRITE/SEND | `axis_rdma_recv_int` | `remote_credits_rd` (`m_axis_recv`) |
| `axis_rrsp_send[N_RDMA_AXI]` | Payload we send as READ RESPONSE | `axis_rdma_send_rsp_int` -> `axis_rdma_src_rsp` | [remote_resp_rd.sv](../../../hw/hdl/user/credits/remote_resp_rd.sv) |
| `axis_tcp_recv/send[N_TCP_AXI]`, `rq_wr` (TCP) | TCP payload; `rq_wr` carries `{sid,len}` | `axis_tcp_*_int`, `tcp_rq_*` | `axis_mux_user_tcp`, `remote_credits_wr_tcp` |
| `axis_rx_sniffer`, `axis_tx_sniffer`, `filter_config` | Only on vFPGA `SNIFFER_VFPGA_ID` | `rx_sniffer`, `tx_sniffer`, `filter_config` | [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt) (`cnfg.sniffer_vfpga_id` block) |

- `N_RDMA_AXI` = number of destination streams per vFPGA (indexed by `dest`; example 09 keeps `N_RDMA_AXI=1`; its 0/1 convention is on the *host* streams (`N_STRM_AXI=2`: index 0 = requester side, 1 = responder side, see its [vfpga_top.svh](../../../examples/09_perf_rdma/hw/src/vfpga_top.svh)). `N_RDMA_AXI>1` sets `MULT_RDMA_AXI`.
- **ID encoding**: `req_t`/`ack_t` carry `vfid` (`DEST_BITS`=4 = CMake `DATA_DEST_BITS`), `pid` (`PID_BITS`=6, = ctid), `dest`, `strm`, `host`. QPN = `{vfid, pid}`. The HLS stack only sees QPN; vfid/pid are recovered from the same bits in the memory command / ACK metadata (`roce_stack.sv` unpack: `pid = [32+:PID_BITS]`, `vfid = [32+PID_BITS+:DEST_BITS]`). `ack_t.host` distinguishes host-initiated from vFPGA-initiated commands (for completion routing).
- Per-vFPGA register paths (ARP, QP ctx/conn) are *not* multiplexed by ID: arbitrated round-robin ([mmu_top.sv](../../../hw/hdl/mmu/mmu_top.sv) `meta_arbiter`), so all vFPGAs share one QP table and one ARP cache.
- TCP: `tcp_arbiter` + `tcp_port_table` (listen ports, `TCP_PORT_ORDER=10` -> 1024 ports at `TCP_PORT_OFFS=49152`) + `tcp_conn_table` (session -> `{vfid,pid,dest}`), RX/TX arbiters per vFPGA ([tcp_rx_arbiter.sv](../../../hw/hdl/network/tcp/tcp_rx_arbiter.sv), [tcp_tx_arbiter.sv](../../../hw/hdl/network/tcp/tcp_tx_arbiter.sv)).

## 6. Clocks, CDC and slicing
- Three relevant clocks ([shell_ctrl_tmplt.txt](../../../hw/templates/common/shell_ctrl_tmplt.txt), `clk_wiz_0` in [cr_ctrl.tcl](../../../hw/bd/ultrascale_plus/cr_ctrl.tcl): aclk/nclk/uclk are outputs of one MMCM with phase alignment): `rclk` (CMAC `usr_clk`, 322 MHz), `nclk` (`NCLK_F`, default 250 MHz), `aclk` (shell, `ACLK_F`), plus `uclk` for user logic. Details: [shell_top.md](../shell/shell_top.md).
- `EN_NCLK=1` (default): `CROSS_EARLY=1`, stack and HLS cores run at `nclk` (`axis_data_fifo_net_ccross_early_512` async FIFOs, depth 512). `EN_NCLK=0`: the stack runs directly at 322 MHz (`n_clk = r_clk`); HLS cores were synthesized for 4 ns, so 322 MHz timing is likely not met.
- Late crossing nclk -> aclk is always instantiated (`CROSS_LATE=1`): control and data of RDMA/TCP (`rdma_ccross_net_late`, `tcp_ccross_late_net`, `network_ccross_late`) via `axis_clock_converter_*`/async `axis_data_fifo_*_ccross_*`; `ENABLED=0` would just wire through. Stats/IP/MAC/ARP also cross here.
- **The sniffer streams and `s_filter_config` are NOT crossed and not decoupled**: they leave `network_stack` at `n_clk` and are wired straight into the user wrapper ([dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt), `cnfg.sniffer_vfpga_id` block): no nclk->aclk CDC, no aclk->uclk CDC, no PR decoupler. It works by default only because `NCLK_F == ACLK_F == 250` come from the same phase-aligned MMCM; changing `NCLK_F`/`UCLK_F` or reconfiguring the sniffer vFPGA needs extra logic.
- Pipeline/slice depths (CMake `NR_*`): `NR_N_S0` (6, aclk-side slices in network_top), `NR_N_S1` (4, early CDC), `NR_N_S2` (5, CMAC side), `NR_DN_S0/S1` (3/3, dynamic layer), `NR_NST` (4, stats). Increase if timing fails on SLR crossings.
- vFPGA side: `rdma_ccross_ul` / `tcp_ccross_ul` cross aclk -> uclk only if `EN_UCLK`; decouplers (`meta_decoupler`, `axis_decoupler`) sit at the PR boundary on all RDMA/TCP interfaces, including the completion path (`rdma_meta_rx_arbiter` -> `rdma_cq_s1..s3` -> decoupler) ([dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt)).

## 7. Packet sniffer
- Enable: `EN_SNIFFER=1`, `SNIFFER_VFPGA_ID=<i>` (only that vFPGA gets the ports). Example 11 builds with `EN_RDMA=1`, `EN_MEM=1`, `EN_STRM=0`, `N_REGIONS=1`.
- RTL: `packet_sniffer` in [network_packet_sniffer.sv](../../../hw/hdl/network/stack/network_packet_sniffer.sv) taps `s_axis_net` (RX, before `ip_handler`) and the TX stream after `mac_merger` (before early CDC, frame padding and CMAC, so captured TX frames can be shorter than 64 B). Traffic passes through unchanged (pass-through wires, filter never back-pressures the link); filtered copies go to `rx_filtered_axis`/`tx_filtered_axis` through 3-stage slices. `filter_config` (64 b, `metaIntf`) is latched in a register.
- Filter bits (`local_filter_config`, bit set = ignore): 8 IPv4, 9 IPv6, 16 ARP, 18 ICMPv4, 20 ICMPv6, 22 UDPv4, 23 UDPv4 payload (keep 42 B header), 24 UDPv6, 25 UDPv6 payload (62 B), 26 TCPv4, 27 TCPv4 payload (54 B, options dropped), 30 RoCEv4, 31 RoCEv4 payload (54 B BTH; +RETH 16 B for WRITE/READ-request opcodes -> 70 B, +AETH 4 B -> 58 B). Protocol detect assumes a 20 B IPv4 header (no options).
- vFPGA ([vfpga_top.svh](../../../examples/11_packet_sniffer/hw/src/vfpga_top.svh), [packet_scheduler.sv](../../../examples/11_packet_sniffer/hw/src/hdl/packet_scheduler.sv)): merges RX/TX preserving packet order, writes 32 KiB chunks (`SIZE_PER_REQ`) as `LOCAL_WRITE` to **card memory** (`STRM_CARD`) at the host-buffer vaddr; SW afterwards `LOCAL_SYNC`s to host. CSRs ([packet_sniffer_slv.sv](../../../examples/11_packet_sniffer/hw/src/hdl/packet_sniffer_slv.sv), SW enum `SnifferCSRs` in [main.cpp](../../../examples/11_packet_sniffer/sw/src/main.cpp)): 0 `CTRL_0` start/stop, 1 `CTRL_1` host-mem info ready, 2 `CTRL_FILTER`, 3 `SNIFFER_STATE` (0 idle, 1 sniffing, 3 finishing), 4 size, 5 timer, 6 `HOST_VADDR`, 7 `HOST_LEN`, 8 `SNIFFER_CTID`, 9 `HOST_DEST`. Flow: `getMem(HPF)` -> `LOCAL_OFFLOAD` -> set CSRs -> `CTRL_FILTER`, `CTRL_0=1` -> ... -> `CTRL_0=0` -> wait idle -> `LOCAL_SYNC` -> convert to pcap ([conversion.cpp](../../../examples/11_packet_sniffer/sw/src/conversion.cpp)).
- Known limits: timestamp insertion is a commented-out stub; sniffer tready in the vFPGA must stay 1 (overflow silently loses data; `sniffer_size` vs `wrote_len` mismatch indicates insufficient memory bandwidth).

## 8. Config knobs

Set before `find_package(CoyoteHW)`/`validation_checks_hw()` in the example `CMakeLists.txt` (defaults in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake), NETWORKING section). See [build_top.md](../build/build_top.md).

| Knob | Default | Effect |
|---|---|---|
| `EN_RDMA` | 0 | Build `rocev2`, `roce_stack`, per-vFPGA RDMA ports, 4 writeback blocks (`N_WBS=4`), adds card-memory channel |
| `EN_TCP` | 0 | Build `toe`+`hash_table`, TCP ports. **Broken in current templates** (NET-01) |
| `EN_SNIFFER`, `SNIFFER_VFPGA_ID` | 0, 0 | Sniffer RTL and ports on one vFPGA |
| `EN_NET_0` / `EN_NET_1` | 1 / 0 | QSFP port (GT quad) for the single CMAC; both set = fatal error. Reported to SW via `rdma_cnfg[1]`/`tcp_cnfg[1]` -> `qsfp` |
| `N_RDMA_AXI`, `N_TCP_AXI` | 1, 1 | Network data streams per vFPGA |
| `PMTU_BYTES` | 4096 | RoCE MTU / packetisation (also host/card packetisation) |
| `ROCE_STACK_MAX_QPS` | 500 (rocev2 CMake cache, pass with `-D`) | QP table depth in HLS |
| `EN_NCLK`, `NCLK_F` | 1, 250 | Early CDC and network clock |
| `EN_STATS` | 1 | Network counters (shell regs + sysfs `nstats`) |
| `NR_N_S0/S1/S2`, `NR_DN_S0/S1`, `NR_NST` | 6/4/5, 3/3, 4 | Pipeline stages (timing) |
| `N_OUTSTANDING` (`n_outs`) | see [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) | Depth of sequence queues in muxes |
| `CLOCK_PERIOD`, `TCP_STACK_MSS`, `TCP_STACK_WINDOW_SCALING_EN`, `NETWORK_BANDWIDTH` | 4, 4096, 1, 100 | HLS-side ([network CMakeLists](../../../hw/services/network/CMakeLists.txt)) |
| Driver `ip_addr`, `mac_addr` | `0B01D4D1`, `000A35029DE5` | Runtime, `insmod` params (natural-order hex) |

Runtime IP/MAC must differ per node and the peer must be on the same /24 (subnet mask is constant in RTL).

## 9. Registers

### 9.1 Shell-level ([shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv); 64-bit register index, byte offset = idx*8 from the shell config BAR region; C view `cyt_shell_cnfg_regs` in [coyote_defs.h](../../../driver/include/coyote_defs.h))
| Idx | Name | Acc | Fields / use |
|---|---|---|---|
| 7 | `RDMA_CNFG_REG` | RO | `[0]` RDMA_FLOW, `[1]` QSFP |
| 8 | `TCP_CNFG_REG` | RO | `[0]` TCP_FLOW, `[1]` QSFP |
| 32 | `NET_IPADDR_REG` | W | `[31:0]` IP (-> `s_set_ip_addr` pulse on write, byte-wise strobes). Reads back 0 (driver keeps a cached copy) |
| 33 | `NET_MACADDR_REG` | W | `[47:0]` MAC (-> `s_set_mac_addr`) |
| 34 / 35 | `TCP_OFFS_REG` / `RDMA_OFFS_REG` | RW | 64-bit card-memory base offset added by `net_mem_intf`; no driver/SW writer exists (stays 0) |
| 96 | `NET_STAT_PKG` | RO | `{tx_pkg, rx_pkg}` |
| 97, 98, 99, 100, 101 | `NET_STAT_ARP/ICMP/TCP/RDMA(roce)/IBV` | RO | `{tx, rx}` pairs |
| 102 | `NET_STAT_DROP` | RO | `{retrans, psn_drop}` |
| 103 / 104 | `NET_STAT_SESS` / `NET_STAT_DOWN` | RO | `[31:0]` TCP sessions / `[0]` stream-down |

### 9.2 Per-vFPGA ([cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv); SW enum `CnfgLegRegs` / `CnfgAvxRegs` in [cDefs.hpp](../../../sw/include/coyote/cDefs.hpp); idx = 64-bit word (legacy) or 256-bit word (AVX))
| Legacy idx | AVX idx | Name | Fields |
|---|---|---|---|
| 36 | 9 | `NET_ARP_REG` | W: `[31:0]` IP to look up (byte-reversed into the request); R: `[0]` request ready |
| 40,41,42 | 10 | `RDMA_CTX_REG_0..2` | `0`: `[23:0]` qpn, `[63:32]` rkey; `1`: `[23:0]` local PSN, `[47:24]` remote PSN; `2`: `[47:0]` remote vaddr (**write triggers post**; R `[0]` ready) |
| 44,45,46 | 11 | `RDMA_CONN_REG_0..2` | `0`: `[15:0]` local QPN, `[39:16]` remote QPN, `[55:40]` port; `1`,`2`: remote GID 128 b (**write of 2 triggers post**) |
| 48/52/56/60 | 12-15 | `TCP_OPEN_PORT/STAT`, `TCP_OPEN_CONN/STAT` | TCP listen/open; **no SW API uses them** |
| 64+ctid | 64+ctid | `STAT_DMA_REG` | completion counters per ctid; RDMA RD/WR counters in AVX word fields 2/3 (legacy: `STAT_RDMA_REG` 128+ctid) |
| 0,1,2,3 | 0 | `CTRL_REG`, `VADDR_RD`, `CTRL_REG_2`, `VADDR_WR` | Command post; bit 21 (`CTRL_START` in SW = `CTRL_ACTV_OFFS` in RTL) triggers; `strm` field selects local vs remote (`is_strm_local`) |

### 9.3 Driver-visible
Sysfs `cyt_attr_ip`, `cyt_attr_mac` (rw), `cyt_attr_nstats` (ro) and `IOCTL_SHELL_NET_STATS`; see [driver.md#sysfs](../driver.md#sysfs). `nstats` always prints the header "QSFP0" regardless of the configured port.

## Driver & software interaction

End to end for RDMA bring-up and operation:

```
cThread ctor (en_rdma): IOCTL_GET_IP_ADDRESS -> qpair->local.{ip,gid}; qpn=(vfid<<6)|ctid; psn=rand24; rkey=0
cThread::initRDMA(size, port, server_ip?)               [out-of-band TCP socket inside cThread, NOT sw/src/cConn.cpp]
  client: connect(); getMem(HPF,size); write(ibvQ local) ; read(ibvQ remote)
  server: bind/listen/accept; read(remote ibvQ); getMem(); write(local ibvQ)
  both  : writeQpContext(port)  -> 3x CTX regs, 3x CONN regs   (mmapped cnfg_slave, no ioctl)
          doArpLookup(remote.ip) -> NET_ARP_REG
cThread::connSync(client)       -> sendAck/readAck over the same socket (barrier; uint32 payload)
invoke(REMOTE_RDMA_{WRITE,READ,SEND}, rdmaSg) -> postCmd -> CTRL/VADDR regs -> RTL (4.7)
checkCompleted(REMOTE_RDMA_*)   -> STAT_DMA_REG / writeback region
~cThread / closeConn()          -> DEF_OP_CLOSE_CONN message on the socket
```

| SW API / mechanism | Out-of-band or kernel step | Driver function / register path | RTL counterpart |
|---|---|---|---|
| `cThread::cThread` -> `ioctl(IOCTL_GET_IP_ADDRESS)` | - | [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c) `case IOCTL_GET_IP_ADDRESS` returns cached `net_ip_addr` | none (value was written at probe) |
| `insmod ... ip_addr= mac_addr=` | - | [coyote_setup.c](../../../driver/src/coyote_setup.c) `read_shell_config` -> `shell_cnfg->net_ip/net_mac` (only if `en_net`) | `shell_slave` `NET_IPADDR_REG`/`NET_MACADDR_REG` -> `network_stack` regs |
| `IOCTL_SET_IP_ADDRESS` / `_MAC_` (no cThread wrapper; raw `ioctl`) or sysfs `cyt_attr_ip/mac` | - | `vfpga_ops.c`, [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c) write `shell_cnfg->net_ip/mac` | same |
| `initRDMA` socket exchange of `ibvQ` | TCP, `DEF_PORT=18488`, struct `ibvQ` raw (`sizeof(ibvQ)`), client sends first | none | none |
| `writeQpContext` | - | direct MMIO to mmapped CNFG region (`MMAP_CNFG`/`MMAP_CNFG_AVX`); driver not involved | `cnfg_slave` `RDMA_CTX_REG_*`, `RDMA_CONN_REG_*` -> `mmu_top` arbiter -> `network_top` ccross -> `rocev2_ip` `s_axis_qp_interface`/`_conn_interface` |
| `doArpLookup` | `usleep(100)` only; no readback | direct MMIO | `NET_ARP_REG` -> `s_arp_lookup_request` -> `arp_server_subnet_ip` host port |
| `invoke(rdmaSg)` -> `postCmd` | local-IP == remote-IP short-circuits to `memcpy` | direct MMIO (no ioctl); page faults handled by [MMU path](mmu.md) | `cnfg_slave` -> `host_sq` -> sections 4.4/4.7 |
| `checkCompleted(REMOTE_*)`, `clearCompleted` | - | writeback buffer (`MMAP_WB`, blocks `RD_RDMA_WBACK`/`WR_RDMA_WBACK`) allocated by the driver, filled by `wback_dma`; or MMIO `STAT_DMA_REG` | `cnfg_slave` RDMA BRAM counters (`inst_rdma_ack_rd/wr`) fed by `s_rdma_done` |
| `cat cyt_attr_nstats` | - | [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c) `cyt_attr_nstats_show` reads `shell_cnfg->net_debug[0..8]` | `shell_slave` regs 96-104 <- `net_stats` |
| `IOCTL_READ_SHELL_CONFIG` -> `fpgaCnfg.en_rdma/en_tcp` | - | `vfpga_ops.c` packs bits 16/17 | `shell_slave` `RDMA_CNFG_REG`/`TCP_CNFG_REG` |
| `sendAck` / `readAck` / `connSync` | TCP socket, 4-byte payload | none | none |

Reverse path: ACKs/READ-RESPONSE completions travel stack -> `rdma_flow` -> `rdma_arbiter` -> (a) host completion queue -> per-pid counters in `cnfg_slave` (polled by SW or pushed by writeback DMA) and (b) vFPGA `cq_wr`/`cq_rd` via `cq_arb`. There are no network interrupts; `axis_stream_down` is only visible in `nstats`.

Notes:
- [sw/src/cConn.cpp](../../../sw/src/cConn.cpp) is **unrelated to RDMA**: it is the AF_UNIX client of the cService/cSched daemon (task submission). The out-of-band RDMA channel lives in `cThread` (`connfd`, `sockfd`, `is_connected`).
- The simulation target stubs all network functions (`ASSERT("Networking not implemented in simulation target")`, [sim/sw/src/cThread.cpp](../../../sim/sw/src/cThread.cpp)).
- `initRDMA(size, port, server_ip, mem)`: optional `mem` is a user buffer (skips `getMem`). `invoke(rdmaSg)` throws for `len > MAX_TRANSFER_SIZE` (128 MB) and sends RTL opcode `oper - REMOTE_OFFS_OPS(6)` (READ=0, WRITE=1, SEND=2 = `RDMA_*`; HLS expands to `RC_*`). `IOCTL_GET_MAC_ADDRESS` exists ([coyote_defs.h](../../../driver/include/coyote_defs.h)) but cThread only uses the IP getter.
- Details of the SW side: [../software.md#networking](../software.md#networking); driver side: [../driver.md#networking](../driver.md#networking).

## UltraScale+ vs Versal

Cross-layer summary: [coyote_top.md](../coyote_top.md#ultrascale-vs-versal-summary). Networking-specific details:

| | UltraScale+ | Versal (V80) |
|---|---|---|
| MAC | `cmac_usplus` 4x25G, licensed "UltraScale+ Integrated 100G Ethernet" | none; placeholders for **DCMAC** in [shell_clk_tmplt.txt](../../../hw/templates/versal/shell_clk_tmplt.txt) and [v80_static_synth.xdc](../../../hw/constraints/v80/static/synth/v80_static_synth.xdc) ("TODO ... when adding network support") |
| Debug IPs | `vio_link`, `vio_ip`, `vio_shell_nstats` are instantiated | n/a |
| HLS cores | arch-independent (HLS part from `FPGA_PART`) | would be reusable; the CMAC wrapper, GT pins, `network_infrastructure.tcl`, clocking would need a DCMAC/MRMAC port |

See also [v80-notes.rst](../../../docs/source/intro/v80-notes.rst) ("Networking support will be added shortly"). No MRMAC/DCMAC logic exists, only MRMAC sites reserved in the shell pblock ([v80_static_floorplan.xdc](../../../hw/constraints/v80/fplan/v80_static_floorplan.xdc), `resize_pblock` for `pblock_inst_shell`).

## Gotchas and known issues

- Fixed /24 subnet mask; gateway derived as `{ip[31:28],0x01,ip[23:0]}`. `PMTU_BYTES=4096` needs jumbo frames end to end and a peer path MTU of 4096.
- The vFPGA must drain `rq_wr`/`axis_rrsp_recv` (examples wire `rq_wr -> sq_wr`), otherwise RX FIFOs fill and the link stalls (`axis_stream_down` goes high; the README advises reprogramming). In example 09 the server counts incoming RDMA writes as `LOCAL_WRITE` completions for that reason ([server/main.cpp](../../../examples/09_perf_rdma/sw/src/server/main.cpp), `checkCompleted(LOCAL_WRITE)`).
- SW handshake: `usleep` after `writeQpContext`/`doArpLookup` is the only synchronisation (`ready` bits are not polled); the server must start first and accepts one connection per `initRDMA` (a server can call `initRDMA` again on the same port, `SO_REUSEADDR`). Server `closeConn` blocks in `read()` until the client sends `DEF_OP_CLOSE_CONN` or disconnects (NET-14).
- Change HLS sources by committing in the `hw/services/network` submodule and bumping the pointer in the parent repo.

Known defects in this area: [known_issues.md](../known_issues.md) (`NET-*`, `MMU-16`, `MMU-17`, `MEM-12`, `REG-05`, `REG-07`, `DOC-03`).

## How to modify / extend

**Change RoCE behaviour (HLS)**: edit the submodule sources ([ib_transport_protocol.cpp](../../../hw/services/network/hls/ib_transport_protocol/ib_transport_protocol.cpp) etc.), bump `export_design -version` in [rocev2/make.tcl.in](../../../hw/services/network/hls/rocev2/make.tcl.in) and the `-version` in [network_infrastructure.tcl](../../../scripts/ip_inst/network_infrastructure.tcl); if you add/rename ports update `roce_stack.sv` (both `VITIS_HLS` and legacy branches). C simulation: `test_rocev2.cpp`/`test_ib_transport.cpp` in the same dirs.

**Change QP table size / PMTU**: `-DROCE_STACK_MAX_QPS=N`, `-DPMTU_BYTES=N` at CMake configure (`PMTU_BYTES` is shared with the shell). Re-run `make services`.

**Add a new L4 protocol or service core** (e.g. a second UDP service): add an HLS dir + `CMakeLists.txt` under `hls/`, `add_subdirectory` in the network `CMakeLists.txt`, `create_ip` in `network_infrastructure.tcl`; in [network_stack.sv](../../../hw/hdl/network/stack/network_stack.sv) tap `axis_iph_to_udp_slice` (currently sunk) and drive an additional input of `axis_interconnect_512_4to1 ip_merger` (S01 UDP input is tied off with `tvalid=0`); expose to vFPGAs by copying the `rdma_*` pattern (`*_ccross_*`, `*_slice_array_*`, arbiter in `dynamic_top_tmplt.txt`, ports in `user_wrapper_tmplt.txt`, SV `ifdef`/CMake flag through `lynx_pkg_tmplt.txt`, `base.tcl.in`, `export.cmake.in`).

**Add a new per-vFPGA network register/command**: add the register in `cnfg_slave.sv` **and** `cnfg_slave_avx.sv`, an index in `CnfgLegRegs`/`CnfgAvxRegs` ([cDefs.hpp](../../../sw/include/coyote/cDefs.hpp)), the SW access in `cThread.cpp` (and a stub in [sim/sw/src/cThread.cpp](../../../sim/sw/src/cThread.cpp)), and an arbiter in `mmu_top.sv` if it leaves the vFPGA scope.

**Add network statistics**: extend `net_stat_t` (`lynx_pkg_tmplt.txt`; padded to 512 b), increment in `network_stack.sv`, expose in `shell_slave.sv` (idx 105+), add to `net_debug[]` handling in [coyote_sysfs.c](../../../driver/src/coyote_sysfs.c)/`vfpga_ops.c` (`N_NET_STAT_REGS=10` fixed).

**Use the sniffer**: build with `EN_SNIFFER=1 SNIFFER_VFPGA_ID=i` (+`EN_RDMA=1` or `EN_TCP=1`, `EN_MEM=1`), reuse [packet_sniffer_sched](../../../examples/11_packet_sniffer/hw/src/hdl/packet_scheduler.sv) in the vFPGA to merge `axis_rx_sniffer`/`axis_tx_sniffer`, drive `filter_config` (64-bit mask above; `valid=1` constant is fine), and store to card memory; keep clocks equal or add a CDC. To add a filter rule extend `packet_filter` ([network_packet_sniffer.sv](../../../hw/hdl/network/stack/network_packet_sniffer.sv)): decode at the first beat, set `*_filtered_axis.tkeep/tlast` to truncate, or `tvalid=0` plus `*_filter_dropped` to drop the packet.

**Run the RDMA example**: build [09_perf_rdma](../../../examples/09_perf_rdma/) (`EN_RDMA=1`, `EN_STRM=1`, `N_STRM_AXI=2`), program both nodes with the same bitstream, load the driver with distinct `ip_addr`/`mac_addr`, start the server binary first (`-DINSTANCE=server`), then the client with the **server CPU's** address (`-i`). Check `cat /sys/kernel/coyote_sysfs_0/cyt_attr_nstats` (`IBV RX/TX`, `PSN drop`, `Retrans`, `STRM down`).
