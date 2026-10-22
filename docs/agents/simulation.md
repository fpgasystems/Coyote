# Coyote Simulation Environment

**Purpose**: simulate ONE vFPGA's user logic (`vfpga_top.svh`) in Vivado xsim against a SystemVerilog model of the shell-facing interfaces (control AXI4L, `sq/cq/rq` descriptors, host/card/RDMA AXI4-Stream, `notify`), without hardware, driver or static/shell RTL. The same host C++ code (via an alternative `cThread`) or Python unit tests drive it through named pipes.

Scope limits (verified in code): single vFPGA (config 0, region 0), no network (RDMA only as injected remote requests, no TCP), no PR/reconfiguration, no multi-tenancy/scheduling, no real MMU/TLB, no timing fidelity of the shell.

## Key files

| Path | Role |
|---|---|
| [sim/README.md](../../sim/README.md) | Human doc: wire protocol, memory model, RDMA caveats (partly stale, see DOC-01) |
| [sim/hw/tb_user.sv](../../sim/hw/tb_user.sv) | Testbench top: clock/reset, interfaces, drivers, DUT instance `design_user_logic_c0_0`, `$finish` |
| [sim/hw/sim_pkg.sv](../../sim/hw/sim_pkg.sv) | `vaddr_t`, `mem_seg_t` (vaddr, size, data[], `marker`), `mem_t` (segment queue wrapper) |
| [sim/hw/generator.svh](../../sim/hw/generator.svh) | Reads `input.bin` (pipe) via DPI, decodes ops, dispatches to ctrl mailbox / `memory_simulation` |
| [sim/hw/scoreboard.svh](../../sim/hw/scoreboard.svh) | Writes results/events to `output.bin` (GET_CSR, HOST_WRITE, IRQ, CHECK_COMPLETED, HOST_READ) |
| [sim/hw/ctrl_simulation.svh](../../sim/hw/ctrl_simulation.svh) | AXI4L master: CSR writes/reads/polling |
| [sim/hw/memory_simulation.svh](../../sim/hw/memory_simulation.svh) | `sq_rd/sq_wr` monitor, request routing, `cq_rd/cq_wr` generation, completion counters, offload/sync, RDMA injection |
| [sim/hw/stream_simulation.svh](../../sim/hw/stream_simulation.svh) | Per-stream read/write queue runner (drives/consumes AXI4S, checks `keep`/`last`) |
| [sim/hw/mem_mock.svh](../../sim/hw/mem_mock.svh) | Segment-based memory (`malloc/free/get_mem_seg`); instantiated for HOST, CARD, RDMA-REMOTE, RDMA-LOCAL |
| [sim/hw/notify_simulation.svh](../../sim/hw/notify_simulation.svh) | Receives `notify` (`irq_not_t`), forwards to scoreboard as IRQ |
| [sim/hw/c_axil.svh](../../sim/hw/c_axil.svh), [c_axisr.svh](../../sim/hw/c_axisr.svh), [c_meta.svh](../../sim/hw/c_meta.svh) | Clocking-block driver classes for AXI4L / AXI4SR / `metaIntf`; valid/ready randomization (`EN_RANDOMIZATION`) |
| [sim/hw/transactions.svh](../../sim/hw/transactions.svh) | `c_trs_req`, `trs_ctrl`, `c_trs_ack` (classes, not structs; binary-format structs are reversed vs wire order) |
| [sim/hw/log.svh](../../sim/hw/log.svh) | `` `DEBUG/ERROR/FATAL/ASSERT/VERBOSE`` macros (`VERBOSE` needs `EN_VERBOSE`) |
| [sim/hw/dpi/file_io.c](../../sim/hw/dpi/file_io.c), [CMakeLists.txt](../../sim/hw/dpi/CMakeLists.txt), [README.md](../../sim/hw/dpi/README.md) | DPI-C non-blocking pipe reads, compiled with `xsc` to `<SIM_DPI_LIB_NAME>.so` (default `coyote_sim.so`, no `lib` prefix) |
| [sim/sw/CMakeLists.txt](../../sim/sw/CMakeLists.txt) | Builds `libcoyotesim.so` (target `Coyote`): real `sw/src/*.cpp` minus `cThread.cpp`, plus `sim/sw/src/cThread.cpp` |
| [sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp) | Sim `cThread` (same public header [sw/include/coyote/cThread.hpp](../../sw/include/coyote/cThread.hpp)) |
| [sim/sw/include/coyote/](../../sim/sw/include/coyote/) | `BinaryInputWriter`, `BinaryOutputReader`, `VivadoRunner`, `BlockingQueue`, `Broadcast`, `Common` (logging, `VERBOSE`) |
| [sim/unit_test/](../../sim/unit_test/) + [README.md](../../sim/unit_test/README.md) | Python framework (`FPGATestCase`, `FPGAPerformanceTestCase`, `SimulationIOWriter`, `VivadoRunner`) |
| [scripts/unit_test/__init__.in.py](../../scripts/unit_test/__init__.in.py) | Template -> `<build>/coyote_test/__init__.py`; injects CMake values into `constants` |
| [scripts/cr_prjcts/cr_sim.tcl.in](../../scripts/cr_prjcts/cr_sim.tcl.in) | Creates the xsim Vivado project (`<build>/sim/<proj>.xpr`) |
| [cmake/FindCoyoteHW.cmake](../../cmake/FindCoyoteHW.cmake) | `sim` target (`add_custom_target(sim ...)`, `sim_dpi_c` dep), cache vars `UNIT_TEST_DIR`, `SIM_DPI_LIB_NAME`, `SIM_CLOCK_PERIOD` |
| [hw/templates/common/user_logic_tmplt.txt](../../hw/templates/common/user_logic_tmplt.txt), [lynx_pkg_tmplt.txt](../../hw/templates/common/lynx_pkg_tmplt.txt) | Rendered into `<build>/sim/user_logic_c0_0.sv` / `lynx_pkg.sv` (DUT wrapper, `CLK_PERIOD`, `BUILD_DIR`, `N_*_AXI`, `EN_*`) |

**Related**: [user/user_top.md](user/user_top.md) (vFPGA interfaces, cThread API), [software.md](software.md) (real cThread), [driver.md](driver.md), [services/mmu.md](services/mmu.md), [services/memory.md](services/memory.md), [services/network.md](services/network.md), [shell/shell_top.md](shell/shell_top.md), [build/build_top.md](build/build_top.md), [coyote_top.md](coyote_top.md).

## Architecture

```
 sw test (C++ app + sim cThread | Python FPGATestCase)        Vivado xsim, top = tb_user
   BinaryInputWriter / SimulationIOWriter                     generator -> ctrl_sim / memory_simulation
          |  input.bin  (mkfifo, SW -> sim)  ------------->     |            |
          |                                                     v            v
   BinaryOutputReader / output reader                       c_axil      stream_simulation + mem_mock
          ^  output.bin (mkfifo, sim -> SW)  <-------------   |  (scoreboard)  |  c_axisr / c_meta
          |                                                     v            v
   VivadoRunner (pty, `vivado -mode tcl`) --Tcl--> xsim   [ design_user_logic_c0_0 = vfpga_top.svh ]
                                                          notify -> notify_sim -> scoreboard (IRQ)
                                                          waveform: sim_dump.vcd
```

- Two independent front-ends speak the **same binary protocol** to the same testbench: C++ ([BinaryInputWriter.hpp](../../sim/sw/include/coyote/BinaryInputWriter.hpp)/[BinaryOutputReader.hpp](../../sim/sw/include/coyote/BinaryOutputReader.hpp)) and Python ([io_writer.py](../../sim/unit_test/io_writer.py)). Only one front-end at a time.
- Files are **FIFOs** (`mkfifo`): C++ in the `cThread` ctor (`std::filesystem::remove` then `mkfifo`), Python in `SimulationIOWriter._create_named_pipe`. xsim reads `input.bin` through DPI (`open_pipe_for_non_blocking_reads` / `try_read_byte_from_file` return `-2` when empty, `-1` on EOF, `-3` on error) because `$fgetc` would block the whole simulator. Output uses plain `$fopen/$fwrite/$fflush` in the scoreboard.
- Simulation ends when the SW closes `input.bin` (EOF) -> `gen.done` -> `tb_user` waits 10 clock cycles -> `scb.close()` -> `$finish`. SW side then sees EOF on `output.bin`.

## Testbench components (sim/hw)

### tb_user.sv
- `DUT = design_user_logic_c0_0` (generated, includes the user's `vfpga_top.svh`). Ports are `ifdef`-gated on `EN_STRM/EN_MEM/EN_RDMA/EN_NET/EN_TCP` from the generated `lynx_pkg.sv` (i.e. follows the CMake config).
- Clock `CLK_PERIOD` = `SIM_CLOCK_PERIOD` (default `4ns`), reset `RST_PERIOD = 20 * CLK_PERIOD`. Paths come from `BUILD_DIR` (`<build>/sim/input.bin`, `output.bin`).
- Mailboxes: `ctrl_mbx`, `ack_mbx`, per-stream `host_{recv,send}_mbx[N_STRM_AXI]`, `card_*[N_CARD_AXI]`, `rdma_{rrsp,rreq}_{recv,send}_mbx[N_RDMA_AXI]`.
- DUT port wiring: `rq_rd` only under `EN_RDMA`, `rq_wr` only under `EN_NET` (the drivers always exist).
- "recv" = vFPGA receives data (`axis_*_recv`, driven by TB = sq_rd/LOCAL_READ path); "send" = vFPGA sends (`axis_*_send`, consumed by TB = sq_wr/LOCAL_WRITE path).
- `tb_user` has TCP port hooks but no TCP simulation (`//TODO: TCP Simulation`). `EN_VAR_DUMP` define adds `$dumpvars` to `dump.vcd` (separate from the Tcl-driven VCD).
- `env_threads()` forks `ctrl_sim.run`, `notify_sim.run`, `mem_sim.run_sq_rd_recv/run_sq_wr_recv/run_ack`, `gen.run_gen`, and `*_mem_mock.run()` (per-stream `run_read_queue`/`run_write_queue`; `host_mem_mock.run()` only under `EN_STRM`, card under `EN_MEM`, RDMA under `EN_RDMA`).

### generator ([generator.svh](../../sim/hw/generator.svh))
Op codes (0-based enum; first byte of each op; little-endian payloads; **this is the truth, README numbering is stale**):

| Code | Op | Payload (after op byte) | Handling |
|---|---|---|---|
| 0 | SET_CSR | addr u64, data u64 | `ctrl_mbx` |
| 1 | GET_CSR | addr u64, data u64, do_polling u8 | `ctrl_mbx`; polling blocks generator until `ctrl_sim.polling_done` |
| 2 | USER_MAP | vaddr u64, size u64 | `mem_sim.userMap` -> `malloc` in HOST (+CARD if `EN_MEM`) |
| 3 | MEM_WRITE | vaddr, len, data[len] | `mem_sim.write` -> copies into host segment (fires `host_sync_done` in interactive mode) |
| 4 | INVOKE | opcode u8, strm u8, dest u8, vaddr u64, len u64, last u8 | `invokeWrite` (LOCAL_WRITE), `invokeRead` (LOCAL_READ), both (LOCAL_TRANSFER), `invokeOffload/Sync` (`EN_MEM` only); other opcodes -> `done` |
| 5 | SLEEP | cycles u64 | `#(cycles*CLK_PERIOD)` |
| 6 | CHECK_COMPLETED | opcode u8, count u64, do_polling u8 | optional wait until counter >= count, then writes result to scoreboard |
| 7 | CLEAR_COMPLETED | - | zero all counters |
| 8 | USER_UNMAP | vaddr u64 | `free` in HOST/CARD mocks |
| 9/10/11 | RDMA_REMOTE_INIT / RDMA_LOCAL_READ / RDMA_LOCAL_WRITE | vaddr, len (, data) | `EN_RDMA` only, else `$fatal` |

The generator is a **sequential dispatcher**: INVOKE is non-blocking (queues to mailbox), polling ops block subsequent ops.

### scoreboard ([scoreboard.svh](../../sim/hw/scoreboard.svh))
Output ops: `GET_CSR=0 (u64)`, `HOST_WRITE=1 (vaddr u64, len u64, data)`, `IRQ=2 (pid u8, value u32)`, `CHECK_COMPLETED=3 (u32)`, `HOST_READ=4 (vaddr u64, len u64)`. A semaphore serializes multi-part messages (`writeOpCode` takes the lock, `flush` releases). Always `$fflush` after a complete message or the SW blocks forever.
- `HOST_WRITE` is emitted per data beat by the HOST `stream_simulation` write queue and by `invokeSync`. `HOST_READ` only with `EN_INTERACTIVE`.

### memory_simulation + stream_simulation + mem_mock
- `memory_simulation.run_sq_rd_recv/run_sq_wr_recv` monitor `sq_rd`/`sq_wr` (DUT-originated requests) and route them identically to host-invoked ones: `strm` selects HOST / CARD (`EN_MEM`) / RDMA (`EN_RDMA`) mailbox, `dest` selects stream index. Unsupported `strm` -> `$fatal`.
- `stream_simulation` per (mem type, dest): delays each request `REQ_DELAY=50ns` after `req_time`, looks up the covering segment(s) (assert if some byte is unmapped), then drives `axis_*_recv` (reads; `keep` computed for the tail beat, `last` only if request `last`) or consumes `axis_*_send` (writes; asserts full `keep` on non-final beats, exact tail `keep`, and `tlast` when `last` set; allows an extra empty `last`-only beat). Then posts `c_trs_ack` to `ack_mbx`.
- `run_ack` converts acks to `cq_rd`/`cq_wr` entries **only when `last` is set**, bumps `completed_counters[LOCAL_READ]` / `[LOCAL_WRITE]` and `[LOCAL_TRANSFER]` (LOCAL_TRANSFER counts write completions), fires event `ack`.
- Card memory model ("buffer faults", `EN_MEM`): each `userMap` creates a HOST and a CARD segment. `segment.marker==0` means "not resident on card". First CARD read of a non-resident buffer copies the whole host segment to card and sets marker (`is_pagefault`); CARD write sets marker; `LOCAL_OFFLOAD` copies host -> card, sets marker; `LOCAL_SYNC` copies card -> host, emits HOST_WRITE to SW, clears marker. Page-fault copies move the whole `userMap` segment; `OFFLOAD`/`SYNC` copy only `[vaddr, vaddr+len)` yet set/clear the marker for the whole segment. Granularity is never pages.
- `mem_mock.malloc` aborts on overlapping segments; accesses to unmapped bytes abort (`$fatal` / `ASSERT`). A request may span adjacent segments (`mem_t.get_segs`); `stream_simulation` looks up the segment per beat.
- RDMA (`EN_RDMA`): `rdma_mem_mock_remote` (data behind the vFPGA's outgoing requests on `axis_rreq_*`) and `rdma_mem_mock_local` (responses `axis_rrsp_*`). `rdmaLocalRead` issues `rq_rd` opcode `5'h0a` (`strm=STRM_RDMA`), `rdmaLocalWrite` issues `rq_wr` opcode `5'h10` (`strm=STRM_HOST`). See limitations below; host-initiated RDMA is not modeled.

### Drivers and randomization
- [c_axil.svh](../../sim/hw/c_axil.svh): `reset_m/reset_s/write/read`; drives garbage on idle address/data lines (`$urandom`) to catch designs that sample invalid data. It has **no** `EN_RANDOMIZATION` stalls (only `c_axisr` and `c_meta` do).
- [c_axisr.svh](../../sim/hw/c_axisr.svh) / [c_meta.svh](../../sim/hw/c_meta.svh): `send/recv` with clocking blocks `cbm/cbs`; with `EN_RANDOMIZATION` insert idle cycles before asserting valid (`SEND_RAND_THRESHOLD=5`%) or ready (`RECV_RAND_THRESHOLD=10`%), and drive random data when not valid.
- With `EN_RANDOMIZATION`, `ctrl_simulation` also issues dummy burst accesses to the rest of the 8-register-aligned block (writes with `wstrb=0`, reads discarded) to mimic the real shell's burst-style CSR access ([cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv) path). The transaction classes exist (instead of structs) because structs passed through mailboxes share one reference in older Vivado ([transactions.svh](../../sim/hw/transactions.svh)).

### Defines (xvlog `-d`)
| Define | Effect | Set by |
|---|---|---|
| `EN_RANDOMIZATION` | random valid/ready stalls, CSR burst dummies | C++ runner always; Python unless `disable_input_timing_randomization` |
| `EN_INTERACTIVE` | vFPGA reads of host memory generate `HOST_READ` to SW and stall until SW answers with `MEM_WRITE` (needs SW to still be live; deadlock if generator is in a polling op) | C++ runner always. **Python: unsupported** (`ReceiveMessageType` has no `HOST_READ=4`, so the first such message raises `ValueError` in `io_writer.py` `_read_simulation_output_entry`) |
| `EN_VERBOSE` | enable `` `VERBOSE`` logs (RTL side) | Python `verbose_logging=True` (default `True` in `FPGAPerformanceTestCase`, which parses these logs) |
| `EN_VAR_DUMP` | `$dumpfile("dump.vcd")` | manual |
| `EN_STRM/EN_MEM/EN_RDMA/...` | from generated `lynx_pkg.sv` (CMake config) | `write_hdl.py` op 3 |

## DPI layer
- [sim/hw/dpi/file_io.c](../../sim/hw/dpi/file_io.c) exports: `open_pipe_for_non_blocking_reads(path)` (open `O_RDONLY|O_NONBLOCK`, then **blocking** `poll` until the writer produced data, returns fd or -1), `try_read_byte_from_file(fd)` (byte 0..255, `-1` EOF, `-2` no data yet, `-3` error), `close_file(fd)`. Imported in `generator.svh` via `import "DPI-C"`.
- Build: [dpi/CMakeLists.txt](../../sim/hw/dpi/CMakeLists.txt) runs `${XSC_BINARY} --compile file_io.c` then `${XSC_BINARY} --shared --output ${SIM_DPI_LIB_NAME}` in `<build>/sim`; target `sim_dpi_c`, a dependency of `sim` (so it is built before the HLS/Spinal/`cr_sim` steps). Added by `add_subdirectory(.../sim/hw/dpi)` in [FindCoyoteHW.cmake](../../cmake/FindCoyoteHW.cmake).
- Linking: `cr_sim.tcl.in` sets `XELAB.MORE_OPTIONS = -sv_root <build>/sim -sv_lib <SIM_DPI_LIB_NAME>`.
- Rebuild only the DPI lib: `cd <build> && cmake .. && make sim_dpi_c`. To add a DPI function: add to a `.c` file listed in `DPI_FILES`, `import "DPI-C"` it in SV, rerun `make sim`.

## Software side: sim `cThread` ([sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp))
- Same class/header as the real one; the sim variant defines its own `cThread::AdditionalState` (declared as `class AdditionalState; std::unique_ptr<AdditionalState> additional_state;` in the header, pimpl) so the header is layout-compatible across real and sim builds. Holds `BinaryInputWriter`, `BinaryOutputReader`, `VivadoRunner`, `tlb_pages` map (vaddr -> `uint64_t` size, guarded by `tlb_mtx`, used for bounds checks of SIM-originated writes), `map_mtx` (serialises mapping changes), `page_fault_mappings` (ranges mapped by the emulated page fault), threads (`sim_thread`, `out_thread`, `irq_thread`), mutexes for getCSR / checkCompleted ordering, and `Broadcast<return_t>` for crash propagation.
- Build linkage: [sim/sw/CMakeLists.txt](../../sim/sw/CMakeLists.txt) globs `sw/src/*.cpp` except `cThread.cpp` (so `cBench`, `cConn`, `cSched`, `cService`, `cTask`, `cRcnfg` are compiled but only the local-memory/CSR/interrupt subset of `cThread` works), adds sim `cThread.cpp`, compiles with `-march=native`, links `Threads util`, **requires Boost** (`find_package(Boost REQUIRED)`; the ctor creates a named `boost::interprocess` mutex `vpga_mtx_user_<timestamp>`), outputs `libcoyotesim.so`, target name `Coyote` (same as the real lib; apps `target_link_libraries(... Coyote)`). Examples switch with `option(EN_SIM)`: `add_subdirectory(../../../sim/sw ...)` vs `../../../sw` (e.g. [examples/01_hello_world/sw/CMakeLists.txt](../../examples/01_hello_world/sw/CMakeLists.txt)). Install exports package `CoyoteSimulation` (`find_package(CoyoteSimulation)`).
- Constructor flow: read `COYOTE_SIM_DIR` (build dir; relative ok) -> `<dir>/sim/{input,output}.bin` mkfifo -> `VivadoRunner::openProject` (fork a pty, exec `vivado -mode tcl`, find `*.xpr`) -> `compileProject` (sets `-d EN_RANDOMIZATION -d EN_INTERACTIVE`, `xsc.mt_level 16`, compile + elaborate) -> `sim_thread` runs `launch_simulation -step simulate`, `restart`, `open_vcd <dir>/sim/sim_dump.vcd`, `log_vcd /tb_user/inst_DUT/*`, `run -all`, `close_vcd`, `close_sim` -> `out_thread` reads `output.bin` until EOF -> main thread opens `input.bin` for write (blocks until xsim opens it) -> `ctid=0`, optional `irq_thread` calling `uisr(value)` -> `clearCompleted()`.
- Destructor: frees all `mapped_pages`, closes `input.bin` (EOF = end of simulation), joins threads.
- `executeUnlessCrash(lambda)`: runs each op in a helper thread and waits on `Broadcast` for either completion or sim/output-thread exit; on early exit prints only `FATAL: Thread with id <n> crashed` and calls `std::terminate()`; look in `<build>/sim/**/simulate.log` yourself. **There is no timeout**: if the DUT hangs (e.g. never completes a transfer), a blocking call hangs forever (`run -all`).

### cThread feature support in sim

| Feature | Sim behavior |
|---|---|
| `getMem(CoyoteAlloc)` REG/THP/HPF | Allocates host memory (aligned_alloc / posix_memalign / mmap hugetlb), calls `userMap`, then writes byte 0 (SIM-07). Other `CoyoteAllocType` (e.g. GPU) -> FATAL. `alloc.remote` -> assert |
| `userMap/userUnmap` | Sends USER_MAP/USER_UNMAP; `mem_block != -1` ignored with warning. Memory passed to `invoke()` that was not mapped is auto-mapped page-aligned (emulated page fault, `handlePageFaults`; `userMap` replaces such mappings); DUT-originated accesses (`sq_*`) to unmapped memory are still `$fatal` |
| `freeMem` | userUnmap + free/munmap |
| `setCSR/getCSR` | Wire offset = `offs * 8`; blocking getCSR via `csr_queue` |
| `invoke(LOCAL_READ)` | **Copies `sg.len` bytes from `sg.addr` to the sim** (`MEM_WRITE`) then INVOKE LOCAL_READ -> data snapshot at invoke time |
| `invoke(LOCAL_WRITE)` | INVOKE only; results arrive as `HOST_WRITE` messages that the output thread `memcpy`s straight into the user buffer (after bounds check against `tlb_pages`) |
| `invoke(LOCAL_TRANSFER)` | Sent as LOCAL_READ(src) then LOCAL_WRITE(dst); note arg-check is `!(isLocalRead && isLocalWrite)` |
| `invoke(LOCAL_OFFLOAD/SYNC)` | Supported only if the shell config has `EN_MEM`; **without `EN_MEM` the generator's unsupported-opcode branch fires `done` and `tb_user` calls `$finish`** (C++ then reports the sim thread stopped). OFFLOAD first sends `MEM_WRITE` of `[addr, addr+len)`; SYNC data returns as HOST_WRITE for that range only. Blocks via polling `checkCompleted` |
| `checkCompleted/clearCompleted` | Supported for local ops (counters in `memory_simulation`); remote RDMA/TCP -> assert |
| user interrupts (`uisr`) | Supported: `notify` -> IRQ -> `irq_queue` -> `uisr(value)` on `irq_thread`. `pid` is dropped on the C++ side |
| RDMA / TCP (`initRDMA`, `invoke(rdmaSg/tcpSg)`, ARP, QP, `connSync`, `closeConn`) | **Unsupported**: `ASSERT("Networking not implemented...")`. The sim `ASSERT` macro is `LOG + assert(false)`, so with `NDEBUG` (e.g. `CMAKE_BUILD_TYPE=Release`, which examples force) it only logs and execution continues (e.g. `initRDMA` returns `nullptr`) |
| `lock/unlock` (scheduling) | Unsupported (assert) |
| Multiple cThreads / vFPGAs | Not supported: `vfid` ignored, `ctid=0`, one pipe pair & one Vivado per process |
| `printDebug` | stub |
| `invoke` ordering | no per-request completion tracking: use `checkCompleted` polling |

## How to run

### Build the sim project
```bash
mkdir build_sim && cd build_sim
cmake <path/to/app> -DFDEV_NAME=u55c ...   # same configuration as for synthesis, incl. load_apps(VFPGA_C0_0 ...)
make sim                                    # HLS/Spinal gen -> cr_sim.tcl in Vivado -> DPI lib (sim_dpi_c)
```
- `make sim` outputs: `<build>/sim/<proj>.xpr`, `lynx_pkg.sv`, `user_logic_c0_0.sv`, `<SIM_DPI_LIB_NAME>.so` (default `coyote_sim.so`). `<build>/coyote_test/__init__.py` is written by `configure_file` at **cmake** time (not by `make sim`).
- `cr_sim.tcl` adds: `sim/hw`, `hw/hdl/pkg`, `hw/hdl/common`, `<vfpga>/vfpga_top.svh`, the generated files, each source dir's `hdl/`, HLS IPs (`create_ip <krnl>_hls_ip`), SpinalHDL output, plus `scripts/ip_inst/common_infrastructure.tcl` and any `init_ip.tcl`. Top = `tb_user`. It hard-codes vFPGA config 0 region 0 and `write_hdl.py` op 3.
- `make sim` runs `${HLS_SYNTH_CMD}` and `${SPINAL_HDL_GEN_CMD}` before `cr_sim` ([FindCoyoteHW.cmake](../../cmake/FindCoyoteHW.cmake) `add_custom_target(sim ...)`), so rerun `make sim` after changing HLS/Spinal sources (note `cr_sim.tcl.in` itself says Spinal Verilog must be regenerated with each change). Plain `.sv` edits are picked up on the next compile in Vivado. Vivado 2023.2 breaks xsim on non-parameterized mailboxes; use another version.
- The Vivado binary used is baked in at CMake time (`VIVADO_BINARY`, written into `constants.VIVADO_BINARY_PATH`). The C++ runner instead uses `vivado` from `PATH` (`which vivado`).
- CMake knobs: `SIM_CLOCK_PERIOD` (default `4ns`; units fs..sec), `SIM_DPI_LIB_NAME` (default `coyote_sim`), `UNIT_TEST_DIR` (default `${CMAKE_SOURCE_DIR}/unit-tests`, i.e. next to the hardware project's top `CMakeLists.txt`, not the repo root). See [build/build_top.md](build/build_top.md).

### Mode A: run the real C++ app against the simulator
```bash
cd <app>/sw && mkdir build_sim && cd build_sim
cmake .. -DEN_SIM=ON && make          # or add_subdirectory(<coyote>/sim/sw coyote) / find_package(CoyoteSimulation)
COYOTE_SIM_DIR=<path-to>/build_sim ./test
```
- Waveform: `<COYOTE_SIM_DIR>/sim/sim_dump.vcd`. Debug prints: `DEBUG()` is expanded inside `libcoyotesim`, so `#define VERBOSE` in the app has no effect; uncomment/define it in [Common.hpp](../../sim/sw/include/coyote/Common.hpp) (`#ifdef VERBOSE`, line ~53) or add `target_compile_definitions(Coyote PRIVATE VERBOSE)` and rebuild the lib (README's `sim/sw/include/Common.hpp` path is outdated). RTL errors: `<build>/sim/**/simulate.log`.
- Status per example: [examples/README.md](../../examples/README.md) (README table marks 01, 02, 04, 06, 07, 08 as working; not 03, 05, 09, 10, 11). Code disagrees for two: 06 allocates `CoyoteAllocType::GPU` ([main.cpp](../../examples/06_gpu_p2p/sw/src/cuda/main.cpp)) which is FATAL in sim, and 08 creates several `cThread`s in one process ([main.cpp](../../examples/08_multithreading/sw/src/main.cpp)), unsupported (one pipe pair/Vivado per process). 12 (`12_spinal_hdl`) also has an `EN_SIM` option but is not in the README table. Every example has an `EN_SIM` CMake option regardless of whether it works.

### Mode B: Python unit tests
```bash
export PYTHONPATH=<build_hw>                  # provides coyote_test/; the generated __init__.py appends <coyote>/sim to sys.path itself
                                              # (add <coyote>/sim to PYTHONPATH only for IDE IntelliSense)
cd <hw-project>/unit-tests && python -m unittest    # or pytest / IDE test explorer
```
- Tests run **one at a time**; a singleton `VivadoRunner` keeps one Vivado alive across tests (restarted if the content of `vfpga_top.svh` changes between tests) and skips recompilation if nothing changed (`<build>/sim/.last_change_time`, pickled `CompilationInfo`: latest mtime of `sim/hw`, vfpga top, source folders; vfpga_top path; defines).
- Set `dump_vcd = False` in the test case to skip the VCD dump. Outputs in the unit-test dir: `sim_dump.vcd`, `sim.out` (if `write_simulation_output_to_file()`), `diff/` (actual vs expected per stream, as int32/int64/float views).
- `vfpga_top.svh` is swapped for `<build>/sim/vfpga_top.svh` (copy of your top, or `alternative_vfpga_top_file` relative to the unit-test dir) via `remove_files`/`add_files` in `sim_1`.

## How to write a test

### Python (FPGATestCase)
```python
# <build>/coyote_test/__init__.py only does `from unit_test import *`, so import submodules from coyote_test
from coyote_test import fpga_test_case, fpga_register, fpga_stream, simulation_time
Stream, StreamType = fpga_stream.Stream, fpga_stream.StreamType
SimulationTime, SimulationTimeUnit = simulation_time.SimulationTime, simulation_time.SimulationTimeUnit

class AddOneTest(fpga_test_case.FPGATestCase):
    def test_basic(self):
        self.set_stream_input(0, Stream(StreamType.SIGNED_INT_32, [1, 2, 3]))      # alloc + LOCAL_READ on HOST stream 0
        self.set_expected_output(0, Stream(StreamType.SIGNED_INT_32, [2, 3, 4]))   # alloc + LOCAL_WRITE on HOST stream 0
        self.overwrite_simulation_time(SimulationTime.fixed_time(20, SimulationTimeUnit.MICROSECONDS))  # default 4 us!
        self.simulate_fpga()                # starts Vivado, waits for all expected LOCAL_WRITE completions, closes input
        self.assert_simulation_output()     # reads memory back, bitwise compare, writes diff/ on mismatch
```
- Direction naming in the framework: `CoyoteOperator.LOCAL_READ` = host memory -> vFPGA (`axis_host_recv`); `LOCAL_WRITE` = vFPGA -> host memory (`axis_host_send`). (The unit_test README's prose "LOCAL_WRITE ... sends the input to the FPGA" is inverted; code in [fpga_test_case.py](../../sim/unit_test/fpga_test_case.py) is right.)
- Other helpers: `write_register/read_register` (`vFPGARegister(id, value)`, blocking `read_register` only valid while sim is running), `set_stream_input_batched`, `set_expected_data_at_memory_location`, `set_system_verilog_defines`, `alternative_vfpga_top_file`, `disable_input_timing_randomization`, `test_sim_dump_module` (VCD scope filter), `debug_mode`, `verbose_logging`, `remote_rdma_write/local_rdma_read/local_rdma_write`, `get_io_writer()` for raw protocol (`allocate_sim_memory`, `invoke_transfer`, `check_completed`, `block_till_completed`, `ctrl_poll`, `register_interrupt_handler`, `all_input_done`).
- Non-blocking pattern for interactive tests (CSR reads, interrupts): `simulate_fpga_non_blocking()` -> do blocking IO with the returned end-event -> `io_writer.all_input_done()` -> `finish_fpga_simulation()`. Interrupt callbacks run on the output thread, so spawn a `SafeThread` for blocking calls inside them. Forgetting `all_input_done()` hangs the sim.
- Performance tests: `FPGAPerformanceTestCase` (randomization off, `verbose_logging=True` by default); first and last input batch must each produce output; `set_expected_avg_cycles_per_batch(...)`, `assert_expected_performance()`.
- Python threading: 4 threads (test, Vivado runner, input writer, output reader). `SimulationIOWriter` keeps its own `bytearray` model of sim memory (bounds checked) and never receives `HOST_READ` (no `EN_INTERACTIVE`).
- Fatal detection: a `Fatal: ` line in the Vivado log fails the test even though `launch_simulation` returned success; in VSCode the failing log file is auto-opened.

### C++ (existing app)
No test harness: write a normal Coyote app using `cThread`, compile with `EN_SIM`, assert results yourself (e.g. [examples/01_hello_world](../../examples/01_hello_world/sw/src/main.cpp)). Allocate via `getMem`, use `invoke` / `checkCompleted` / `setCSR` / `getCSR`; avoid unsupported features above.

### Raw protocol (adding a new front-end or op)
1. Add op code to `generator.svh` enum **and** `op_type_size[]` (same order), handler in `case`.
2. Mirror in `BinaryInputWriter.hpp` (`InputOperations`) and Python `SendMessageType`/`_get_*_bytes`. SW->sim ops 9-11 (RDMA) exist in Python only.
3. For sim->SW messages: add to scoreboard (`writeOpCode ... flush`), `BinaryOutputReader::OutputOperations` + `op_type_size[]`, Python `ReceiveMessageType` + `_read_*_output`.

## Relation to hardware, driver & software

| Sim model | Real counterpart | Fidelity / differences |
|---|---|---|
| sim `cThread` ([sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp)) | real [sw/src/cThread.cpp](../../sw/src/cThread.cpp): `/dev/fpga*` fd, ioctls, BAR mmap, eventfd; see [software.md](software.md) | API-compatible subset; no driver, no `mmapFpga`, no scheduler/PID registration (`ctid=0`), no `postCmd` (invoke is a protocol message, not a register write; real path: [user_top.md](user/user_top.md#71-invoke---registers---hardware)) |
| `ctrl_simulation` + `c_axil` -> `axi_ctrl` | `setCSR/getCSR` -> mmap'd user control BAR -> static layer -> shell [cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv)/xbar -> vFPGA `axi_ctrl` ([shell/shell_top.md](shell/shell_top.md), [user/user_top.md](user/user_top.md)) | Only the vFPGA's 64-bit AXI4L slave is exercised; no address decode, no shell/static registers, no AVX path (`EN_AVX` irrelevant). CSR byte address = `offs*8`, as in real `cThread` |
| `memory_simulation` + `mem_mock(HOST)` + `userMap/getMem` | Host DMA + MMU: page-table setup in driver (`vfpga_gup.c`/`vfpga_ops.c`, TLB programming), TLB lookup in [hw/hdl/mmu](../../hw/hdl/mmu/mmu_top.sv), XDMA/QDMA data movement ([services/mmu.md](services/mmu.md), [driver.md](driver.md), [static/host_dma.md](static/host_dma.md)) | Virtual address -> segment lookup replaces TLB; **no invalidations, credits, dest/pid arbitration, or stream multiplexing latency**; sim `cThread::invoke` emulates page faults by auto-mapping, DUT accesses to unmapped memory are a hard error. Fixed 50 ns request latency |
| `LOCAL_OFFLOAD/SYNC` + CARD `mem_mock` marker | Card memory migration through driver + CDMA/HBM/DDR ([services/memory.md](services/memory.md)) | Whole-buffer residency flag, only with `EN_MEM`; no striping/channels |
| `sq_rd/sq_wr` monitors, `cq_rd/cq_wr` driver (`c_meta`) | Request/completion queues between vFPGA and shell dynamic layer ([user/user_top.md](user/user_top.md)) | Acks come only when `last`; completion counters live in TB, whereas real `checkCompleted` reads shell counters via driver/BAR |
| `notify_simulation` -> IRQ message -> `uisr` | `notify` (`irq_not_t{pid,value}`) -> shell -> static IRQ -> driver ISR ([vfpga_uisr.c](../../driver/src/vfpga/vfpga_uisr.c)) -> eventfd -> `cThread` event thread -> `uisr` ([driver.md](driver.md)) | No latency/coalescing/vectors; `pid` discarded in C++ path |
| `rq_rd/rq_wr` + `rdma_mem_mock_*` + `axis_rreq/rrsp` | RoCEv2 stack, QPs, network service ([services/network.md](services/network.md)) | Only injected remote requests; no network stack, no ARP/QP, no host-initiated RDMA, remote-read responses not checkable |
| `EN_RANDOMIZATION` | Real back-pressure from shell/arbiters/DMA | Stochastic only; useful for valid/ready bugs, not for performance |
| `VivadoRunner` + DPI + pipes | `ioctl`/BAR/DMA | Entirely test-infra |
| TCP, sniffer, multiple vFPGAs, PR/`cRcnfg`, `cSched` | see [static/reconfig.md](static/reconfig.md), [services/network.md](services/network.md) | Not simulated |

## Gotchas and limitations
- Unmapped memory access, overlapping `userMap`s, misaligned `keep`, or missing `tlast` produce `$fatal` in xsim. The C++ side sees only "thread stopped", check `simulate.log`.
- `HOST_WRITE` data is written into the user buffer by the output thread as it arrives; since all messages share one ordered pipe, `checkCompleted` result after the data is a valid barrier. Do not read the buffer before completion.
- `LOCAL_READ` snapshot: modifying the buffer after `invoke` has no effect on data already sent to the sim.
- `EN_INTERACTIVE` (C++ mode only): DUT reads of host memory trigger `HOST_READ` -> SW answers with `writeMem` from the **current** user buffer. A vFPGA CARD read that page-faults (`EN_MEM`) also sends `HOST_READ` for the whole segment. Deadlock risk if the generator is in a polling op depending on that read (README warning); RDMA reads are fatal in interactive mode.
- Python default sim time is 4 us (`overwrite_simulation_time`, or `SimulationTime.till_finished()` = `run -all`, requires proper `tlast`).
- `LOCAL_TRANSFER`: the completion counter increments on every LOCAL_WRITE completion. The C++ `cThread` splits it into LOCAL_READ(src)+LOCAL_WRITE(dst); a raw `INVOKE LOCAL_TRANSFER` (Python `io_writer`) makes the generator call `invokeWrite`+`invokeRead` with the same request (same vaddr/strm/dest).
- Large allocations are slow (`mem_mock.malloc` allocates a byte array per segment; warning > 1 MiB).
- Compile time dominates; use `alternative_vfpga_top_file` to test submodules, and `test_sim_dump_module` to shrink VCDs.
- Single Vivado per Python session; Python tests cannot run in parallel (shared build folder).
- Known defects in this area: [known_issues.md](known_issues.md) (`SIM-*`, `DOC-01`, `DOC-02`).

## Recipes
- **Debug a hang in C++ mode**: rebuild the sim lib with `VERBOSE` defined (see Mode A), run, then open `<build>/sim/sim_dump.vcd`; check `sq_rd/sq_wr` handshakes and `cq_*`; check `simulate.log` for `$fatal`. If `getCSR` never returns, the DUT's AXI4L slave isn't asserting `rvalid`/`awready`.
- **Test a single module**: write `unit-tests/my_top.svh` wiring the module to `axi_ctrl`/`axis_host_*` (same signal names as `vfpga_top.svh`), set `alternative_vfpga_top_file = "my_top.svh"`.
- **Parametrize design per test**: `set_system_verilog_defines({"FOO_OVERWRITE": "16"})` and guard with `` `ifdef FOO_OVERWRITE `` (triggers recompile).
- **Check interrupts**: C++: pass `uisr` to `cThread` ctor ([examples/04_user_interrupts](../../examples/04_user_interrupts/sw/CMakeLists.txt) builds with `EN_SIM`); Python: `get_io_writer().register_interrupt_handler(cb(pid, value))`.
- **Change clock period**: `-DSIM_CLOCK_PERIOD=10ns` at CMake time; Python converts cycles using `constants.CLOCK_PERIOD`.
- **Add a new stream type to the TB**: add interface + `c_axisr` drivers + mailboxes in `tb_user.sv`, a `mem_mock` + fork in `env_threads`, routing in `memory_simulation.invokeRead/invokeWrite`, `ifdef` guard from `lynx_pkg`.
