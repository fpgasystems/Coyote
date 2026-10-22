# Card Memory Service (HBM / DDR)

**Purpose:** gives each vFPGA (and the shell's own migration/network engines) AXI4 access to FPGA-attached memory: HBM (u55c, u280, v80) or DDR4 (u200, u250). Covers the memory controllers/BDs, card DMA engines (CDMA), striping, channel numbering, and the driver's card-memory allocator. TLB/page-fault/migration *mechanics* live in [mmu.md](mmu.md); this file owns everything on the memory side of the MMU.

## Key files
| Path | Role |
|---|---|
| [hw/bd/ultrascale_plus/cr_hbm.tcl](../../../hw/bd/ultrascale_plus/cr_hbm.tcl) | US+ HBM BD (`cr_bd_design_hbm`:189, per-channel `create_hier_cell_path`:91, `create_hier_cell_init_logic`:28) |
| [hw/bd/ultrascale_plus/cr_hbm_split.tcl](../../../hw/bd/ultrascale_plus/cr_hbm_split.tcl) | US+ HBM BD variant for `HBM_SPLIT=1` (2 HBM ports per channel via `hbm_wide`) |
| [hw/hdl/shell/hbm_wide.v](../../../hw/hdl/shell/hbm_wide.v) | 512b channel -> 2x256b HBM ports (stack 0 / stack 1), used only by `cr_hbm_split.tcl` |
| [hw/bd/versal/cr_hbm.tcl](../../../hw/bd/versal/cr_hbm.tcl) | Versal HBM: `cr_bd_hbm_cc_dwc`:29 (SmartConnect CDC + 512->256 DWC), `cr_bd_design_hbm`:238 (`axi_noc` with HBM NMUs) |
| [hw/bd/ultrascale_plus/cr_ddr.tcl](../../../hw/bd/ultrascale_plus/cr_ddr.tcl) | DDR4 BD `cr_bd_design_ddr`:28; per-board DDR4 configs (u200/u250:108, u280:297), `axi_interconnect_0`:724, address map:806 |
| [scripts/ip_inst/memory_infrastructure.tcl](../../../scripts/ip_inst/memory_infrastructure.tcl) | Creates standalone IPs: Versal `clk_gen_hbm` (:6), `ddr4_0..3` for u200/u250/u280 |
| [scripts/ip_inst/shell_infrastructure.tcl](../../../scripts/ip_inst/shell_infrastructure.tcl) | `axis_data_fifo_hbm_{r,w,b}` IPs (:15-22) used by `hbm_wide.v` |
| [scripts/cr_prjcts/cr_shell.tcl.in](../../../scripts/cr_prjcts/cr_shell.tcl.in) | Decides which BDs/HDL get built (`en_dcard`/`en_hcard`/`hbm_split`, :93, :150-170) |
| [hw/hdl/stripe/axi_stripe.sv](../../../hw/hdl/stripe/axi_stripe.sv), [axi_stripe_rd.sv](../../../hw/hdl/stripe/axi_stripe_rd.sv), [axi_stripe_wr.sv](../../../hw/hdl/stripe/axi_stripe_wr.sv) | Fragment-and-interleave across memory controllers (`EN_MEM_STRIPE`) |
| [hw/hdl/cdma/cdma_u/cdma.sv](../../../hw/hdl/cdma/cdma_u/cdma.sv) (+ `axi_dma_rd.sv`, `axi_dma_wr.sv`) | The CDMA actually built (unaligned) |
| [hw/hdl/cdma/cdma_a/](../../../hw/hdl/cdma/cdma_a/), [hw/hdl/cdma/cdma_x/cdma.sv](../../../hw/hdl/cdma/cdma_x/cdma.sv) | Unused alternatives (aligned; Xilinx DataMover wrapper) |
| [hw/templates/common/shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt) | Instantiates `design_ddr`/`design_hbm`/`hbm_cc_dwc`, `axi_mem[N_MEM_CHAN]` (:881), network `axi_stripe`s (:883-892), HBM clocks/`hbm_cc_dwc` (:1322-1427) |
| [hw/templates/common/dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt) | Sync/offload `cdma` + `axi_stripe` (:344-354), per-vFPGA `cdma` + `axi_stripe` (:372-388) |
| [hw/templates/common/lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt) | `MEM_OFFSET`, `MC_SIZE`, `N_STRIPE_CHAN[_BITS]`, `STRIPE_FRAG_SIZE`, `N_MEM_CHAN`, `N_CARD_AXI`, `BLOCK_MEM_IMPL_EN` (:372-405) |
| [cmake/FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake) | Memory options and per-board constants (:79-98, :350-454, :468-486, :570-611, :657-722) |
| [driver/src/vfpga/vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c) | `alloc_card_memory`:203, `free_card_memory`:278, `trigger_dma_offload`:136, `trigger_dma_sync`:171 |
| [driver/src/vfpga/vfpga_gup.c](../../../driver/src/vfpga/vfpga_gup.c) | `tlb_get_user_pages`:299 (card alloc + `mem_block` -> block), `migrate_to_card/host`:713/728, `offload_user_pages`:743, `sync_user_pages`:783 |
| [driver/include/coyote_defs.h](../../../driver/include/coyote_defs.h) | `N_MEM_BLOCKS`, `MEM_BLOCK_SIZE`, `MEM_START`, `N_SMALL/LARGE_CHUNKS` (:340-359), card block fields (:1201-1204) |

**Related:** [mmu.md](mmu.md) (TLB, page faults, sync/offload) · [network.md](network.md) (RDMA/TCP buffers use memory channels 0..N_NET_CHAN-1) · [../shell/shell_top.md](../shell/shell_top.md) · [../user/user_top.md](../user/user_top.md) (`axis_card_recv/send`) · [../driver.md](../driver.md) · [../software.md](../software.md) · [../build/build_top.md](../build/build_top.md) · [../simulation.md](../simulation.md) · [../coyote_top.md](../coyote_top.md)

---

## 1. What it does
- Provides **N_MEM_CHAN** 512-bit AXI4 master channels (`axi_mem[N_MEM_CHAN]`, `AXI_DDR_BITS=512`) at `aclk` into the memory BD (`design_ddr` or `design_hbm`).
- The vFPGA never sees addresses on these buses directly: user logic uses `axis_card_{recv,send}[i]` streams; vFPGA requests carry **virtual** addresses, the MMU translates them to **card physical addresses** (TLB entry with `host=0`), and a CDMA turns `{paddr, len}` into AXI bursts.
- Memory is only instantiated when `EN_MEM=1` **or** a network stack is on (RDMA/TCP need buffers): `EN_CARD = EN_DCARD | EN_HCARD` ([FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake):570-611, :657-662).
  - `AV_DDR` (u200/u250) -> `EN_DCARD=1, EN_HCARD=0`; `AV_HBM` (u55c/u280/v80) -> `EN_HCARD=1`. u280 therefore **always uses HBM**; its DDR path in `cr_ddr.tcl` is dormant unless `DDR_DEV`/`HBM_DEV` lists in CMake are edited (:471-472).

## 2. Memory channel numbering (important)
`N_MEM_CHAN = N_NET_CHAN + (EN_MEM ? N_REGIONS*N_CARD_AXI + 1 : 0)` (CMake :669-676), `N_NET_CHAN = N_TCP_CHAN + N_RDMA_CHAN`.

| `axi_mem[]` index | Owner | Source |
|---|---|---|
| `0 .. N_NET_CHAN-1` | TCP (`axi_ddr_tcp`) then RDMA (`axi_ddr_rdma`), each through its own `axi_stripe` | [shell_top_tmplt.txt](../../../hw/templates/common/shell_top_tmplt.txt):883-892 |
| `N_NET_CHAN` | **Sync/offload channel** (`inst_cdma_sync` + `inst_strp_sync`) | [dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt):344-354 |
| `N_NET_CHAN + 1 + i*N_CARD_AXI + j` | vFPGA `i`, card stream `j` (`inst_cdma` + `inst_strp`) | dynamic_top_tmplt.txt:372-388 |

The shell hands `axi_mem[N_NET_CHAN +: 1+N_REGIONS*N_CARD_AXI]` to `design_dynamic_top.m_axi_ddr` (shell_top_tmplt.txt:1486).
- Versal has no networking (CMake :622 fatal), so channel 0 is always the sync/offload channel; it is the only NoC **PL** port (see 5.2). vFPGA channel `k` (0-based, over all regions) is `axi_hbm_in_{k+1}` -> HBM NMU `HBM{k}_AXI`.
- vFPGA-side mapping: `dest` field of `localSg` (SW) -> `axis_card_recv/send[dest]` and `m_rd/wr_CDMA_card[i*N_CARD_AXI+dest]` in [mmu_top.sv](../../../hw/hdl/mmu/mmu_top.sv):219-220. `CTRL_DEST_MASK=0xf` caps `dest` at 16.
- `N_CARD_AXI > 1` sets `MULT_CARD_AXI` (more card streams per vFPGA).

## 3. Data flow
```
vFPGA axis_card_send/recv[j]  (uclk, 512b AXI4S)
  -> dynamic_top: axis_decoupler -> axis_reg_array(S1) -> [axis_ccross uclk<->aclk] -> credits (gated by `en_mem_cred`, see note below)
     -> axis_last_rewriter (read side) -> axis_reg_array(S0)           (dynamic_top_tmplt.txt:358-480)
  -> cdma_u  (dmaIntf rd_CDMA/wr_CDMA from MMU: {paddr,len,last}; m_axi_ddr 512b)
  -> axi_stripe (EN_MEM_STRIPE ? fragment+interleave : passthrough)
  -> axi_mem[k]  (shell_top, aclk)
  -> US+ DDR : design_ddr.axi_ddr_in_k -> axi_interconnect_0 -> ddr4_N (ui_clk)
  -> US+ HBM : design_hbm.axi_hbm_in_k -> path_k [slice, CDC aclk->hclk, slice, DWC 512->256, slice, RAMA] -> hbm_inst SAXI_k
  -> Versal  : hbm_cc_dwc (SmartConnect CDC+DWC) -> axi_noc HBM NMU -> HBM PC
```
Note: the card credit stage is wrapped in `{% if cnfg.en_mem_cred %}` ([dynamic_top_tmplt.txt](../../../hw/templates/common/dynamic_top_tmplt.txt):411), but `en_mem_cred` is not defined anywhere in `cmake/`/`scripts/`, so the stage is **never generated** (plain `AXIS_ASSIGN` pass-through, :424-426).

Request side: `sq_rd/sq_wr` (STRM_CARD=0) -> MMU TLB lookup -> `mmu_assign` -> `rd/wr_CDMA_card[i*N_CARD_AXI+j]`. Read data returns on `axis_card_recv`, writes are consumed from `axis_card_send` (direction naming from the vFPGA's perspective; `cdma.m_axis_ddr` = memory->vFPGA, `cdma.s_axis_ddr` = vFPGA->memory).

Sync/offload data path (no vFPGA involved): `mmu_arbiter_isr` pairs a host DMA request with a card CDMA request ([mmu_top.sv](../../../hw/hdl/mmu/mmu_top.sv):321-322):
- **Offload** (host -> card): `m_rd_HDMA_mig` + `m_wr_CDMA_mig`; **Sync** (card -> host): `m_wr_HDMA_mig` + `m_rd_CDMA_mig`. Data goes through `s_axis_card/m_axis_card` of `design_dynamic_top` and `inst_cdma_sync`. See [mmu.md](mmu.md).

## 4. Sub-components

### 4.1 Card DMA engines (`hw/hdl/cdma/`)
All expose the same module name `cdma` and ports (`aclk, aresetn, dmaIntf.s rd_CDMA/wr_CDMA, AXI4.m m_axi_ddr, AXI4S.s s_axis_ddr, AXI4S.m m_axis_ddr`); exactly one directory is added to the project.

| Variant | Used? | Notes |
|---|---|---|
| `cdma_u` | **Yes** - `add_files .../cdma/cdma_u` in [cr_shell.tcl.in](../../../scripts/cr_prjcts/cr_shell.tcl.in):93 (only if `en_card`) | Unaligned (byte-granular start/len) read/write engines (`axi_dma_rd.sv`, `axi_dma_wr.sv`, AXI-DMA style), `BURST_LEN=64`, request queue + CTL sequencing queue of depth `N_OUTSTANDING`; `last` tracking so `rd_CDMA.rsp.done` fires only on the request's final fragment. Higher resource cost. |
| `cdma_a` | No | Aligned engines + `krnl_counter.sv`; lower resources, requires aligned transfers. |
| `cdma_x` | No (and not buildable as-is) | Wraps the Xilinx AXI DataMover IP `cdma_datamover`, which no script instantiates. |

- `dmaIntf` req fields used: `paddr`, `len` (`LEN_BITS=28`, so max 256 MiB per request; SW further caps at 128 MiB = `MAX_TRANSFER_SIZE`), `last`; response `rsp.done`.
- Instances: one per `(vFPGA, card stream)` plus one sync CDMA. A CDMA sits **before** the stripe module and runs on `aclk`.

### 4.2 Striping (`hw/hdl/stripe/`)
- `axi_stripe` splits each AXI request into **`STRIPE_FRAG_SIZE`-byte fragments** (default 1024 B, CMake `STRIPE_FRAG_SIZE`) and sends consecutive fragments to consecutive memory controllers/pseudo-channels so that one stream (or many tenants) uses all channels.
- Address remap (identical in `axi_stripe_rd.sv`:199/220 and `axi_stripe_wr.sv`:220/241), with `a = addr - MEM_OFFSET`:
  `paddr = (a[FRAG_LOG +: N_STRIPE_CHAN_BITS] << MC_SIZE) | (a & (FRAG-1)) | (((a & (~(FRAG-1) << N_STRIPE_CHAN_BITS)) >> N_STRIPE_CHAN_BITS) + MEM_OFFSET)` (three terms OR'd; in SV `+` binds tighter than `|`, so `MEM_OFFSET` is added to the compacted high part only)
  i.e. fragment index bits pick the controller (placed at bit `MC_SIZE` = per-controller window), the rest are compacted.
- Read: response `rlast` is regenerated from a sequencing queue (`N_OUTSTANDING_STRIPE = 8*N_OUTSTANDING`) so only the last fragment asserts `rlast`. Write: `wlast` is re-asserted every `FRAG_BEATS`; only the last fragment's `bresp` is forwarded (`axi_stripe_wr.sv`:272-289).
- `axi_stripe` is compiled as **passthrough** (`AXI_ASSIGN`) unless `EN_MEM_STRIPE` is defined ([axi_stripe.sv](../../../hw/hdl/stripe/axi_stripe.sv)). `EN_MEM_STRIPE` is set by CMake (:708-717):
  - US+ DDR with `N_DDR_CHAN > 1`  -> 1 (`MC_SIZE=DDR_SIZE=34`, `N_STRIPE_CHAN=N_DDR_CHAN`);
  - US+ HBM -> **0** (striping done by RAMA in the BD, see 5.1);
  - Versal + `HBM_IMPL=unified` -> 1 (`MC_SIZE=30`, `N_STRIPE_CHAN=32`, `MEM_OFFSET=2^38`); Versal + `block` -> 0.
- `N_STRIPE_CHAN` must be a power of two (`N_STRIPE_CHAN_BITS = clog2s`); 3 DDR channels is rejected by CMake (`DDR_AUTO` sets ddr_2 *and* ddr_3 -> "DDRs have not been configured properly").
- The network channels also go through `axi_stripe` (shell_top_tmplt.txt:883-892).

### 4.3 `hbm_wide.v` (only `HBM_SPLIT=1`, US+)
- One 512-bit channel -> two 256-bit HBM AXI ports: low 256 b to port `path_i` (stack 0), high 256 b to `path_{i+N_MEM_CHAN}` (stack 1, connected to `SAXI_{i+16}`). Both ports get the same address `addr >> 1` (`m_axi_1` ORs in `1 << (HBM_SIZE-1)`), `arsize` forced to 256 b, and handshakes are joined (`arready = ready0 & ready1`, etc.). `HBM_SIZE` module parameter default 33; set from `cfg(hbm_size)` in the BD.
- Removes the 512->256 DWC and the 2:1 clock-ratio throughput limit at the cost of consuming 2 HBM ports per channel (max `N_MEM_CHAN <= 16`; tie-offs `axi_toff_in` become `2*(16-N_MEM_CHAN)`).
- Uses `axis_data_fifo_hbm_{r,w,b}` (depth 128) as skid FIFOs.

## 5. UltraScale+ vs Versal

Cross-layer summary: [UltraScale+ vs Versal](../coyote_top.md#ultrascale-vs-versal-summary). Memory-specific details:

### 5.1 UltraScale+ HBM (u55c, u280) - [cr_hbm.tcl](../../../hw/bd/ultrascale_plus/cr_hbm.tcl)
- **IP:** `xilinx.com:ip:hbm:1.0` (`hbm_inst`, :432), 2 stacks, 16 MCs enabled (`USER_MC_ENABLE_00..15`), ECC correction + scrubbing on, `USER_SWITCH_ENABLE_01`. Density from `hbm_size`: **33 -> "8GB" (u280), else "16GB" (u55c, `HBM_SIZE=34`)** (:426-430). Total 32 AXI slave ports (`SAXI_00..31`, 256 b, AXI3).
- **Ports:** `axi_hbm_in_0..N_MEM_CHAN-1` (512 b, AXI4, 6-bit ID) at `aclk`; `32-N_MEM_CHAN` unused HBM ports are tied to **`axi_toff_in_*`** dummy slave ports (256 b AXI3) so the BD validates; `shell_top_tmplt.txt` leaves them (and `S_AXI_CTRL`, `DRAM_*_STAT_*`, `hbm_mc_init_seq_complete`) unconnected.
- **u55c naming:** on u55c the HBM pins are `SAXI_%02d_8HI`; other boards use `SAXI_%02d` (`if {$cnfg(fdev) eq "u55c"}`, :602-622).
- **Per-channel `path_i`** (`create_hier_cell_path`:91): `axi_register_slice(slice_0)` -> `axi_clock_converter(aclk->hclk)` -> `slice_1` -> `axi_dwidth_converter 512->256` -> `slice_2` (all-5-channel regslice) -> **`rama:1.1`** (`G_MEM_INTERLEAVE_TYPE=per_memory`, `G_MEM_COUNT=32`, `G_REORDER_QUEUE_DEPTH=512`) -> `M_AXI` to `SAXI_k`. **RAMA is what stripes across all 32 pseudo-channels**; `STRIPE_FRAG_SIZE` has no effect here.
- **Clocking:** `hclk` = differential `hbm_clk` (100 MHz, `IBUFDS` in shell_top_tmplt.txt:1322-1327; `hresetn = lckresetn`). `clk_wiz_0` (MMCM, `CLKOUT1_REQUESTED_OUT_FREQ 450`, literal `MMCM_DIVCLK_DIVIDE 2`, `CLKFBOUT_MULT_F 23.625`, `CLKOUT0_DIVIDE_F 2.625`: 100 x 23.625 / 2 / 2.625 = **450 MHz**) generates `hclk_int` which clocks `path_i` (hclk side), all `AXI_xx_ACLK`. The `hbm` IP's `USER_AXI_CLK_FREQ` and port `FREQ_HZ` come from `HCLK_F` (450 for u55c/u280), but the MMCM values are literal in `cr_hbm.tcl`:578 (only `cr_hbm_split.tcl` uses `HCLK_F` for the MMCM request).
- **APB/init:** `S_AXI_CTRL` (AXI-Lite, 23-bit) -> `axi_apb_bridge` -> `SAPB_0/1` (0x0 / 0x400000, 4 MiB each); `dclk`/`dresetn` is the APB clock. `init_logic` ANDs `apb_complete_0/1` -> `hbm_mc_init_seq_complete`.
- **Temperature/CATTRIP:** `DRAM_{0,1}_STAT_TEMP[6:0]` exported; `DRAM_{0,1}_STAT_CATTRIP` OR-ed -> `DRAM_STAT_CATTRIP` **and** into `hbm_reset_sync_SLR0.aux_reset_in`, so an over-temperature trip resets all `path_i` hclk-side logic (`interconnect_aresetn` = `hresetn` of the paths).
- **Split variant:** [cr_hbm_split.tcl](../../../hw/bd/ultrascale_plus/cr_hbm_split.tcl) drops `slice_1/2` + DWC (`path` = slice -> CDC -> RAMA with `G_MEM_COUNT=16`; the `axi_hbm_in_*` BD ports use `ID_WIDTH=1`, cr_hbm_split.tcl:265), instantiates `hbm_wide_i` per channel (`create_bd_cell -type module -reference hbm_wide`) and uses `2*N_MEM_CHAN` paths. Enabled with CMake `HBM_SPLIT=1` (ignored with a warning on Versal, :663-665).

### 5.2 Versal HBM (v80) - [cr_hbm.tcl](../../../hw/bd/versal/cr_hbm.tcl)
- **Two BDs.** `hbm_cc_dwc` (`cr_bd_hbm_cc_dwc`:29; a SmartConnect, `NUM_CLKS=2`, S_AXI 512 b `aclk` -> M_AXI 256 b `hclk`) is instantiated **once per memory channel** in `shell_top_tmplt.txt`:1352-1427 (`inst_hbm_cc_dwc_i`; `clk_gen_hbm` at :1344) and `design_hbm` (`cr_bd_design_hbm`:238) holds `axi_noc:1.1` `inst_hbm_noc` with 256-bit inputs. They are kept separate because both the NoC and SmartConnect need address assignment. Created in [cr_shell.tcl.in](../../../scripts/cr_prjcts/cr_shell.tcl.in):158-171.
- **Size:** only `HBM_SIZE == 35` (32 GiB = 16 HBM channels x 2 PCs = **32 PCs x 1 GiB**, each PC exposing two 512 MB AXI ports (`PORT0/1` or `PORT2/3`) = **64 ports/blocks of 512 MB**, `HBM_NUM_CHNL=16`; hence `HBM{loc/4}_PORT{loc%4}` below) is accepted; anything else exits (:385-395).
- **Channel 0 = sync/offload:** `axi_hbm_in_0` -> `S00_AXI` (NoC category `pl`, i.e. through the PL NoC interface, lower performance), connected to **all 32 PCs** (via PORT0 and PORT2 of each of the 16 MCs, 250 MB/s placeholders; cr_hbm.tcl:451). vFPGA channels `1..N_MEM_CHAN-1` -> `HBM%02d_AXI` NMUs (category `pl_hbm`); `NUM_HBM_BLI = N_MEM_CHAN-1`.
- **`HBM_IMPL`** (CMake, default `unified`; only on Versal):
  | | `unified` | `block` |
  |---|---|---|
  | NMU connections | each NMU lists 32 `CONNECTIONS` (`HBM{0..15}_PORT0` and `_PORT2`, i.e. one port of each of the 32 PCs, cr_hbm.tcl:464), which still gives it the whole 32 GiB ("uniform random") | each NMU reaches exactly 1 port (`HBM%d_PORT%d`, point-to-point), `PHYSICAL_LOC NOC_NMU_HBM2E_X<loc>Y0` |
  | Striping | `EN_MEM_STRIPE=1` (`axi_stripe`, `STRIPE_FRAG_SIZE`) to reduce PC collisions | none |
  | Address map | `ROW_BANK_COLUMN_BGO` | user-defined `1BG-15RA-1SID-2BA-5CA-1BG` |
  | `NUM_*_OUTSTANDING` (:100-107) | `N_OUTSTANDING * PMTU_BYTES / STRIPE_FRAG_SIZE` | `N_OUTSTANDING` |
  | `avg_burst` (:437-442) | `STRIPE_FRAG_SIZE/256*8` | `PMTU_BYTES*8/256` |
  | Per-NMU BW hint | 250 | 12000 |
  | SW | `mem_block` optional (selects a 512 MB window, then striped) | `mem_block` **required**, and `dest` must equal it, else the transfer stalls |
- **NMU placement (block):** vFPGA channels are spread evenly: `gap = 64/(N_vfpga_chan+1)`, `loc = round(i*gap)-1` for `i=1..N_vfpga_chan`; `MC = loc/4`, `port = loc%4` (:478-491). The driver re-derives the same formula to turn a `mem_block` into a physical block (vfpga_gup.c:447/459: `DIV_ROUND_CLOSEST(N_MEM_BLOCKS*(t+1), N_REGIONS*N_CARD_AXI+1) - 1`, `t = vfid*N_CARD_AXI + mem_block`). **Both must stay in sync.**
- **Clocking:** `hclk` comes from Clocking Wizard `clk_gen_hbm` (memory_infrastructure.tcl:6; input `aclk`, output `HCLK_F` = **400 MHz** for v80; recommended `HCLK_F = 2*ACLK_F`). Only `hclk` is passed to the NoC (`aclk0`); no `hresetn`, no APB/CATTRIP plumbing in the BD (NoC handles HBM init).
- **Addresses** start at `0x40_0000_0000` (256 GiB) = `MEM_OFFSET` in HW = `MEM_START` in driver.

### 5.3 DDR (u200/u250; DDR path for others dormant) - [cr_ddr.tcl](../../../hw/bd/ultrascale_plus/cr_ddr.tcl)
- `cr_bd_design_ddr` branches on `$cnfg(fdev)`; each instantiates `ddr4_N` (N in 0..3) for every `ddr_N=1` flag (`DDR_AUTO` sets them from `N_DDR_CHAN`: 1->ddr_0, 2->ddr_0,1, >2->all four).
- `axi_interconnect_0`: `NUM_SI=N_MEM_CHAN` (512 b, `axi_ddr_in_k`, `aclk`), `NUM_MI=N_DDR_CHAN`, `STRATEGY=2`, M-side data FIFOs + regslices (:724-735). Each MI has its own `ui_clk` and `rst_ddr4_N_300M`.
- Address map: each `axi_ddr_in_k` sees controller `j` at `offset = j * 2^DDR_SIZE` (:806-822). With `EN_MEM_STRIPE`, `axi_stripe` places the controller-select bits at `MC_SIZE=DDR_SIZE`, so the two views agree.
- ECC: `set ecc 1` for u200/u250/u280 -> `axi_ctrl_ddr_N` AXI-Lite port per controller (segment 0x8000), but `shell_top_tmplt.txt` ties them off (`axi_ctrl_ddr_*` valid=0), so ECC status is not software-visible.

### 5.4 Summary: US+ vs Versal
| Aspect | UltraScale+ | Versal (v80) |
|---|---|---|
| Controller | `hbm` IP (HBM) / `ddr4` MIG (DDR) in fabric | `axi_noc` hard HBM NMUs |
| Width/clock conversion | per-channel regslice+CC+DWC inside `design_hbm` (`path_i`) | `hbm_cc_dwc` SmartConnect per channel |
| Striping | RAMA (HBM) / `axi_stripe` (multi-DDR) | `axi_stripe` (`unified` only) / none (`block`) |
| Memory-block selection | none; driver `N_MEM_BLOCKS=1`, `mem_block` ignored | 64 blocks of 512 MB; `mem_block` honored (`block`: required) |
| Sync/offload path | normal channel (index `N_NET_CHAN`) via same HBM/DDR | NoC PL port (`S00_AXI`), channel 0 |

## 6. Configuration knobs
CMake (defaults in [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake); `cfg(...)` in [base.tcl.in](../../../scripts/base.tcl.in); SV params in [lynx_pkg_tmplt.txt](../../../hw/templates/common/lynx_pkg_tmplt.txt)); see [build_top.md](../build/build_top.md):

| CMake var | Default | `cfg(...)` / SV | Effect |
|---|---|---|---|
| `EN_MEM` | 0 | `en_mem` / `EN_MEM` | vFPGA card streams + sync channel; HBM/DDR instantiated if also set by network |
| `N_CARD_AXI` | 1 | `n_card_axi` / `N_CARD_AXI` | card streams per vFPGA (= memory channels per vFPGA) |
| `N_REGIONS` | 1 | | `N_MEM_CHAN` scales with it |
| `DDR_AUTO` | 1 | `ddr_0..3` | auto-place DDR controllers from `N_DDR_CHAN` |
| `STRIPE_FRAG_SIZE` | 1024 | `stripe_frag_size` / `STRIPE_FRAG_SIZE` | stripe granularity (not used by RAMA) |
| `HBM_SPLIT` | 0 | `hbm_split` | US+ HBM only: 2 HBM ports per channel (`hbm_wide`) |
| `HBM_IMPL` | `unified` | `hbm_impl` / `BLOCK_MEM_IMPL_EN` | Versal only: `unified`/`block` |
| `N_OUTSTANDING` | 8 | `n_outs` / `N_OUTSTANDING` | CDMA/stripe queue depths, NoC outstanding |
| `PMTU_BYTES` | 4096 | `pmtu` | request size; NoC `avg_burst` |
| `ACLK_F` | 250 | `aclk_f` | CDMA/stripe/memory-interface clock |
| *(board-set, not user-overridable)* `HCLK_F`, `HBM_SIZE`, `DDR_SIZE`, `N_DDR_CHAN`, `MC_SIZE`, `N_STRIPE_CHAN`, `MEM_OFFSET` | see table 7 | `hclk_f`, `hbm_size`, `ddr_size`, `n_ddr_chan`, `mc_size`, `n_stripe_chan`, `mem_offset` | set in the per-board `if(FDEV_NAME ...)` block (:350-454) |
| `EN_MEM_STRIPE`, `N_MEM_CHAN`, `N_NET_CHAN`, `CARD_CHAN`, `EN_DCARD`, `EN_HCARD` | derived | | see sections 2/4.2 |

Runtime (HW-reported to SW): `MEM_CNFG_REG` bits (`shell_slave.sv`:274-279): `[1] MEM_FLOW (EN_MEM)`, `[13:8] N_CARD_AXI`, `[14] BLOCK_MEM_IMPL_EN`.

## 7. Per-board table
Values from [FindCoyoteHW.cmake](../../../cmake/FindCoyoteHW.cmake):355-454.

| Board | Arch | Card memory used | Size (`HBM_SIZE`/`DDR_SIZE`) | Controllers / ports | `HCLK_F` | Striping | `MEM_OFFSET` |
|---|---|---|---|---|---|---|---|
| u55c | US+ | HBM2 | 16 GiB (34) | 32 AXI ports, 2 stacks (`SAXI_xx_8HI`) | 450 | RAMA (`MC_SIZE=29`, `N_STRIPE_CHAN=32` unused) | 0 |
| u280 | US+ | HBM2 (DDR4 disabled by default) | 8 GiB (33); DDR 16 GiB (34) | 32 HBM ports; 1 DDR (dormant) | 450 | RAMA (HBM) | 0 |
| u200, u250 | US+ | DDR4 (4 channels possible, 1 default) | 16 GiB/ch (34) | `N_DDR_CHAN` fixed to 1 in CMake (code paths for up to 4; 3 fails the `N_DDRS` check) | 1 (dummy) | `axi_stripe` if `N_DDR_CHAN>1` | 0 |
| v80 | Versal | HBM2e via NoC (DDR not supported yet) | 32 GiB (35) | 16 MCs x 2 PC x 2 ports = 64 blocks of 512 MB | 400 | `axi_stripe` (`unified`) / none (`block`); `MC_SIZE=30`, 32 stripe channels | `0x40_0000_0000` |

## 8. Driver & software interaction
**Card allocation is driver-side and happens at mapping time**, not in SW: every buffer mapped to a vFPGA of a shell with `en_mem` gets a card-side twin allocated in the same call.

Flow (see [../software.md](../software.md), [../driver.md](../driver.md), [mmu.md](mmu.md)):
1. SW: `cThread::getMem({CoyoteAllocType::HPF|REG|THP|GPU, size, mem_block})` ([cThread.cpp](../../../sw/src/cThread.cpp):485; `CoyoteAlloc.mem_block` in [cOps.hpp](../../../sw/include/coyote/cOps.hpp):138, default -1) allocates host pages then calls `userMap(vaddr, len, mem_block)` (:373).
2. ioctl `IOCTL_MAP_USER_MEM` (args `{vaddr, len, ctid, mem_block}`, [vfpga_ops.c](../../../driver/src/vfpga/vfpga_ops.c):316) -> `mmu_handler_gup(..., stream=true, mem_block)` (:335; vfpga_gup.c:27) -> `tlb_get_user_pages` (:299). Because `stream=true` (host), the card twin is allocated but the TLB is mapped to the **host** pages; data only moves to the card on the first card access or an explicit offload (vfpga_gup.c:~78-110). GPU buffers use `IOCTL_MAP_DMABUF` (args `{dmabuf_fd, vaddr, ctid, mem_block}`, :374) -> `p2p_attach_dma_buf` (vfpga_gup.c:887), which has its own copy of the block transform (:987-1005) and always allocates regular (`huge=false`) card pages (:1010); it does not go through `mmu_handler_gup`.
3. `tlb_get_user_pages` pins host pages, then, if `bd_data->en_mem`, picks `target_block` (:436-465):
   - US+: `mem_block` ignored (`target_block=-1`);
   - Versal `en_block_mem` (`BLOCK_MEM_IMPL_EN`): `mem_block==-1` -> `-EINVAL`; else block = `DIV_ROUND_CLOSEST(N_MEM_BLOCKS*(vfid*N_CARD_AXI+mem_block+1), N_REGIONS*N_CARD_AXI+1)-1`;
   - Versal unified: same transform if `mem_block != -1`, else `-1` (first block with space).
   then `alloc_card_memory(device, cpages, n_pages, huge, target_block)` ([vfpga_hw.c](../../../driver/src/vfpga/vfpga_hw.c):203).
4. `alloc_card_memory`: `card_sblocks[]`/`card_lblocks[]` (arrays of `struct memory_partition`, one per block, circular free lists of `struct chunk`, built in [coyote_setup.c](../../../driver/src/coyote_setup.c):145-198). Chunk = **4 KiB** (`stlb_meta->page_shift`) for both regular and huge buffers (`n_pages` counts 4 KiB units; a 2 MiB page consumes 512 chunks that are *assumed* to be consecutive and 2 MiB-aligned: `tlb_map_gup`'s huge-page path, vfpga_gup.c:171-181, maps `cpages[i]` as one lTLB entry without checking, whereas the regular-page path verifies contiguity/alignment before coalescing, :184-204). Address:
   `card_paddr = (chunk_id << page_shift) + (huge ? card_huge_offs : card_reg_offs) + target_block*MEM_BLOCK_SIZE + MEM_START`.
5. TLB: `tlb_map_gup` (vfpga_gup.c:160) writes `cpages[]` (card) or `hpages[]` (host) into the vFPGA's sTLB/lTLB via `create_tlb_mapping` (vfpga_hw.c:80), tagged `host`/`CARD_ACCESS=0|HOST_ACCESS=1`. The MMU later issues `paddr` to `cdma`. See [mmu.md](mmu.md).
6. Free: SW `cThread::freeMem` (cThread.cpp:679) / `userUnmap` (:455) -> `IOCTL_UNMAP_USER_MEM` (vfpga_ops.c:350) -> `tlb_put_user_pages`, or `IOCTL_UNMAP_DMABUF` (:406) -> `p2p_detach_dma_buf` -> `free_card_memory` (vfpga_hw.c:278; inverts the formula, Versal derives the block from `(paddr-MEM_START)/MEM_BLOCK_SIZE`; call sites vfpga_gup.c:572, :653, :1077).
7. Migration: `invoke(LOCAL_OFFLOAD|LOCAL_SYNC, syncSg)` ([cThread.cpp](../../../sw/src/cThread.cpp):778; requires `fcnfg.en_mem`) -> `IOCTL_OFFLOAD_REQ`/`IOCTL_SYNC_REQ` (vfpga_ops.c:434/:461) -> `offload_user_pages`/`sync_user_pages` (vfpga_gup.c:743/:783) -> `tlb_unmap_gup`, `migrate_to_card/host` -> `trigger_dma_offload/sync` (vfpga_hw.c:136/:171) -> writes `{offl,sync}_host_offs`, `{offl,sync}_card_offs`, then `{offl,sync}_ctrl` (`stlb page_size << 32 | START_{MIDDLE,LAST}`; the `huge` argument of both `trigger_dma_*` functions is unused - every entry is a 4 KiB transfer; `trigger_dma_offload` skips entries whose host or card address is 0 (:147), `trigger_dma_sync` has no such skip; throttled to `DMA_THRSH=32` outstanding by polling `*_ctrl`, which gives up after `CYT_POLL_TIMEOUT_MS`=2000; `migrate_to_*` wait at most `CYT_DMA_TIMEOUT_MS`=5000) -> `cnfg_slave` posts `offload_req`/`sync_req` -> `dma_offload/dma_sync` -> `mmu_arbiter_isr` -> host DMA + sync `cdma` -> completion IRQ `IRQ_OFFL`/`IRQ_SYNC` ([vfpga_isr.c](../../../driver/src/vfpga/vfpga_isr.c):37/44) sets `wait_offload/wait_sync`, waking the `migrate_to_*` waiter. An access to a buffer whose location doesn't match (`user_pg->host`) triggers the same migration implicitly from the page-fault handler (vfpga_gup.c:~78-110). Copy semantics are in [mmu.md](mmu.md).
8. SG commands to card streams: `localSg{.stream = STRM_CARD, .dest = j}` -> `CTRL_DEST` -> card channel `j` of that vFPGA (**in block mode `dest` must equal `mem_block`**, v80-notes.rst).

| HW/driver/SW item | RTL counterpart | Driver accessor | SW accessor |
|---|---|---|---|
| Card present, #card AXI, block impl | `MEM_CNFG_REG` ([shell_slave.sv](../../../hw/hdl/shell/shell_slave.sv):274) | `en_mem`, `n_card_axi`, `en_block_mem` ([coyote_setup.c](../../../driver/src/coyote_setup.c):80-93, masks `EN_MEM_MASK`, `N_CARD_AXI_MASK`, `EN_BLOCK_MEM_MASK` in coyote_defs.h:256-262) | `fcnfg.en_mem` (cDefs.hpp:408; no `n_card_axi` field in SW). Path: HW bit 1 of `MEM_CNFG_REG` -> driver `en_mem` -> `IOCTL_READ_SHELL_CONFIG` repacks it to bit 3 (vfpga_ops.c:550-554) -> `parseCnfg` `(cnfg >> 3) & 1` (cDefs.hpp:435) |
| Card physical address of a page | TLB entry (`host=0`), `mmu_*`, `cdma` `paddr` | `alloc_card_memory`, `card_{s,l}blocks`, `MEM_START`/`MEM_BLOCK_SIZE`/`N_MEM_BLOCKS` | `CoyoteAlloc.mem_block`, `userMap(..., mem_block)` |
| Offload/sync registers `OFFL_*`, `SYNC_*` | non-AVX: [cnfg_slave.sv](../../../hw/hdl/shell/cnfg_slave.sv):316-335 (64-bit word idx `OFFL_CTRL/HOST/CARD`=20/21/22, `SYNC_*`=28/29/30). AVX (`EN_AVX`): [cnfg_slave_avx.sv](../../../hw/hdl/shell/cnfg_slave_avx.sv):329-344 (`OFFL_CTRL_REG=5`, `SYNC_CTRL_REG=7`; host/card offsets packed in the same 512-bit word at bits 64/128) | `cnfg_regs->offl_*`/`sync_*` (coyote_defs.h:600-610; `cnfg_regs` is ioremapped onto the AVX window when `en_avx`, coyote_setup.c:399-403, same word offsets 20-22/28-30) | `invoke(LOCAL_OFFLOAD/SYNC)` |
| Sync/offload CDMA | `inst_cdma_sync`, `mmu_arbiter_isr` | `trigger_dma_offload/sync`, ISR flags | - |
| Card stream index | `axis_card_*[dest]`, `rd/wr_CDMA_card[i*N_CARD_AXI+dest]` | - | `localSg.dest` |
| Memory block placement (Versal) | NMU location formula (`cr_hbm.tcl`:478-491) | `tlb_get_user_pages` DIV_ROUND_CLOSEST (:447/:459) | `mem_block` |

Driver constants (coyote_defs.h:340-359):
| | US+ | Versal |
|---|---|---|
| `N_MEM_BLOCKS` | 1 | 64 |
| `MEM_BLOCK_SIZE` | unused (0) | 512 MiB |
| `MEM_START` | 256 MiB (first 256 MiB never handed out; being non-zero guarantees no page has card address 0, which `trigger_dma_offload` treats as "skip") | 256 GiB (= HW `MEM_OFFSET`) |
| `N_SMALL_CHUNKS` / `N_LARGE_CHUNKS` | 1 Mi x 4 KiB = 4 GiB each | 64 Ki x 4 KiB = 256 MiB each per block |
| `card_reg_offs` / `card_huge_offs` | 0 / `N_SMALL_CHUNKS*4KiB` (4 GiB) | 0 / 256 MiB (within each 512 MiB block) |

## 9. Gotchas
- **Channel 0 is not always sync/offload.** With RDMA/TCP on a US+ board, `axi_mem[0..N_NET_CHAN-1]` are network channels and sync/offload is `axi_mem[N_NET_CHAN]`. The statement "channel 0 = sync/offload" holds on Versal only (no net).
- **`mem_block` semantics differ by arch:** ignored on US+; on Versal `block` it is mandatory and indexes *per-vFPGA* card streams (0..`N_CARD_AXI-1`), not global PCs; mismatching `.dest` stalls the transfer.
- **`MEM_START` is only a driver-side offset on US+** (not programmed in HW): the first 256 MiB are never allocated to user buffers.
- **Stripe fragment must divide transfers sensibly:** requests are split at `STRIPE_FRAG_SIZE`-aligned boundaries; very small `STRIPE_FRAG_SIZE` raises outstanding counts (`NUM_*_OUTSTANDING = N_OUTSTANDING*PMTU/FRAG` on Versal) and FIFO depth.
- **Striped address != contiguous physical address.** Block-mode `mem_block` windows are only meaningful without striping; under `unified` the "block" is just an address window that `axi_stripe` then spreads over all PCs.
- **Block mode capacity:** each card stream owns exactly one 512 MiB block (256 MiB regular + 256 MiB huge-page chunks, `N_SMALL/LARGE_CHUNKS=64Ki`); allocations beyond that fail with `-ENOMEM` even if other blocks are free.
- Sim: card memory is mocked in simulation (`EN_MEM`), see [../simulation.md](../simulation.md).

Known defects in this area: [known_issues.md](../known_issues.md) (`MEM-*`, `DOC-05`, `BLD-04`, `DEAD-01`).

## 10. How to modify / extend
- **Change stripe granularity:** `-DSTRIPE_FRAG_SIZE=<pow2>` (affects DDR multi-channel and Versal unified only); re-synthesize shell.
- **Add a DDR channel / board:** add board block in `FindCoyoteHW.cmake` (`DDR_SIZE`, `N_DDR_CHAN`, `MC_SIZE`, `N_STRIPE_CHAN`, add to `DDR_DEV`), a `ddr4_N` IP in `memory_infrastructure.tcl`, a board branch in `cr_ddr.tcl` (ports + MIG config), and top-level DDR pins in `cyt_top_tmplt.txt`/`shell_top_tmplt.txt`; keep `N_STRIPE_CHAN` a power of two.
- **Support another HBM size on Versal:** extend the `hbm_size` check in `cr_hbm.tcl`:385 (`n_hbm_chan`, `n_hbm_ports`), driver `N_MEM_BLOCKS`/`MEM_BLOCK_SIZE`, and CMake `HBM_SIZE`/`MC_SIZE`.
- **Change NMU placement:** edit the `hbm_nmu_gap` formula (`cr_hbm.tcl`:478-483) **and** the identical formula in `tlb_get_user_pages` / `p2p_attach_dma_buf` (vfpga_gup.c:447/:459, :991/:1003).
- **Use a different CDMA:** swap the directory in `cr_shell.tcl.in`:93; keep the `cdma` port list and `rsp.done` semantics.
- **Increase card capacity in driver:** edit `N_SMALL_CHUNKS`/`N_LARGE_CHUNKS`/`MEM_START` in `coyote_defs.h`, rebuild driver (`make TARGET_PLATFORM=...`).
- **More than 16 vFPGA card channels on v80:** possible only by lowering `ACLK_F`/`HCLK_F`, `N_OUTSTANDING`, `PMTU_BYTES` (tested to 32 NMUs; [v80-notes.rst](../../source/intro/v80-notes.rst)).
