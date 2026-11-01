# User-space library (`sw/`, libcoyote)

**Purpose**: C++17 shared library `libcoyote.so` (CMake target `Coyote`, namespace `coyote`) that wraps the driver's char devices ([driver.md](driver.md)) into `cThread` (one thread of execution on one vFPGA), `cRcnfg` (shell/app reconfiguration) and higher-level runtime pieces (`cSched`, `cService`, `cConn`, `cFunc`, `cTask`). API *usage* (writing apps, examples) is in [user/user_top.md](user/user_top.md); this file documents internals and the SW -> ioctl/register -> driver -> RTL mapping. The simulation backend ([sim/sw/](../../sim/sw/), see [simulation.md](simulation.md)) re-implements only `cThread.cpp` and reuses these headers and all other `.cpp` files.

## Key files

| Path | Role |
|---|---|
| [sw/CMakeLists.txt](../../sw/CMakeLists.txt) | Library build, options `EN_AVX`/`EN_ROCM`/`EN_CUDA`, install/export |
| [cmake/FindCoyoteSW.cmake](../../cmake/FindCoyoteSW.cmake) | Deprecated shim; only warns and `add_subdirectory(${CYT_DIR}/sw)` |
| [sw/include/coyote/cDefs.hpp](../../sw/include/coyote/cDefs.hpp) | IOCTL numbers, register enums, bit-field constants, `fpgaCnfg`, `ibvQ/ibvQp`, debug macros |
| [sw/include/coyote/cOps.hpp](../../sw/include/coyote/cOps.hpp) | `CoyoteOper`, `CoyoteAllocType`, `CoyoteAlloc`, SG entries (`syncSg/localSg/rdmaSg/tcpSg`) |
| [sw/include/coyote/cThread.hpp](../../sw/include/coyote/cThread.hpp), [sw/src/cThread.cpp](../../sw/src/cThread.cpp) | Core class |
| [sw/include/coyote/cRcnfg.hpp](../../sw/include/coyote/cRcnfg.hpp), [sw/src/cRcnfg.cpp](../../sw/src/cRcnfg.cpp) | Reconfiguration |
| [sw/include/coyote/cSched.hpp](../../sw/include/coyote/cSched.hpp), [sw/src/cSched.cpp](../../sw/src/cSched.cpp) | Per-vFPGA task scheduler (derives from `cRcnfg`) |
| [sw/include/coyote/bFunc.hpp](../../sw/include/coyote/bFunc.hpp), [cFunc.hpp](../../sw/include/coyote/cFunc.hpp), [cTask.hpp](../../sw/include/coyote/cTask.hpp), [sw/src/cTask.cpp](../../sw/src/cTask.cpp) | Function/task abstractions |
| [sw/include/coyote/cService.hpp](../../sw/include/coyote/cService.hpp), [sw/src/cService.cpp](../../sw/src/cService.cpp) | Background daemon (server) |
| [sw/include/coyote/cConn.hpp](../../sw/include/coyote/cConn.hpp), [sw/src/cConn.cpp](../../sw/src/cConn.cpp) | Client of `cService` |
| [sw/include/coyote/cBench.hpp](../../sw/include/coyote/cBench.hpp), [sw/src/cBench.cpp](../../sw/src/cBench.cpp) | Timing helper |
| [sw/README.md](../../sw/README.md), [docs/source/api/sw.rst](../source/api/sw.rst) | Human docs (Doxygen) |

**Related**: [driver.md](driver.md), [simulation.md](simulation.md) (sim `cThread`), examples [03_multitenancy](../../examples/03_multitenancy/) (ctid/vlock), [05_reconfigure_shell](../../examples/05_reconfigure_shell/) (`cRcnfg`), [06_gpu_p2p](../../examples/06_gpu_p2p/) (dmabuf), [10_app_reconfiguration](../../examples/10_app_reconfiguration/) (`cService`/`cConn`/`cSched`), [coyote_top.md](coyote_top.md), [user/user_top.md](user/user_top.md), [build/build_top.md](build/build_top.md), [static/static_top.md](static/static_top.md), [static/host_dma.md](static/host_dma.md), [static/reconfig.md](static/reconfig.md), [shell/shell_top.md](shell/shell_top.md), [services/mmu.md](services/mmu.md), [services/memory.md](services/memory.md), [services/network.md](services/network.md).

## Build

[sw/CMakeLists.txt](../../sw/CMakeLists.txt): `project(Coyote 2.0.0)`, C++17, global `-march=native`, glob `src/*.cpp` -> `add_library(Coyote SHARED)`, `OUTPUT_NAME coyote`, links `Threads`, requires Boost headers (`boost::interprocess::named_mutex`; apps additionally use `program_options`).

| Option (cache var) | Default | Effect |
|---|---|---|
| `EN_AVX` | `1` | `target_compile_definitions(Coyote PUBLIC EN_AVX)` + `-mavx`; enables 256-bit `__m256i` register path in `cThread` and propagates the define to consumers. Must be >= HW: if the shell was built with `EN_AVX=1` the SW must be too (see gotchas) |
| `EN_ROCM` | `0` | AMD GPU dmabuf path; compiler `hipcc`, links `hip::device hsa-runtime64 hsakmt ...`; needs `ROCM_PATH`/`HIP_PATH` |
| `EN_CUDA` | `0` | NVIDIA GPU dmabuf path; `CUDA::cuda_driver CUDA::cudart` |
| `EN_ROCM && EN_CUDA` | - | `FATAL_ERROR` |
| `VERBOSE_DEBUG_1/2/3` | undefined | `DBG1` local ops (also `cConn` submission), `DBG2` reconfig and local QP creation, `DBG3` remote/RDMA/`cConn` socket (`DBG1/2/3` macros in [cDefs.hpp](../../sw/include/coyote/cDefs.hpp)) |
| `EN_SIM` (in example CMakeLists) | `OFF` | `add_subdirectory(sim/sw)` instead of `sw/`: also `project(Coyote)` / target `Coyote`, but `OUTPUT_NAME coyotesim`, installs headers to `include/coyotesim`, exports `CoyoteSimulationTargets`; defines none of `EN_AVX/EN_CUDA/EN_ROCM` |

Integration: `add_subdirectory(../../../sw ${CMAKE_BINARY_DIR}/coyote)` + `target_link_libraries(app PUBLIC Coyote)`, or `make install` then `find_package(Coyote)`. `install` copies `include/coyote/*.hpp` and exports `CoyoteTargets`. `FindCoyoteSW.cmake` is deprecated. Nothing in the library depends on the driver at link time; at run time it needs `/dev/coyote_fpga_*` nodes. Build-system caveats: only the `EN_AVX` *define* is `PUBLIC`; `-mavx` (set via `CMAKE_CXX_FLAGS`) and `-march=native` (`add_compile_options`) are directory-scoped and not propagated, so consumers using AVX intrinsics add their own flags; `Threads` is `PRIVATE`; for `EN_ROCM`, `CMAKE_CXX_COMPILER` is set to `hipcc` only if not already defined.

## Class overview

| Class | Responsibility | Talks to |
|---|---|---|
| `cThread` | One cThread = one `ctid` on one vFPGA of one card: map memory, post DMA/RDMA commands, completion polling, CSR access, user-interrupt thread, RDMA QP exchange, inter-process vFPGA lock | `/dev/coyote_fpga_<dev>_v<vfid>` (ioctl + 4 mmaps) |
| `cRcnfg` | Load bitstream into driver-allocated, mmap'd 2 MB-page buffer; trigger app (per `vfid`) or shell reconfiguration | `/dev/coyote_fpga_<dev>_reconfig` |
| `bFunc` / `cFunc<ret, args...>` | Type-erased user function bound to an app bitstream path; args/return serialised as `vector<char>` | - |
| `cTask` | One invocation of a function: args, return value, completion state, assigned `cThread*` | - |
| `cSched` | Singleton per `(device,vfid)`; thread executing queued tasks, reconfiguring vFPGA when needed | `cRcnfg` base, `cThread` (via tasks) |
| `cService` | Singleton daemon per `(device,vfid)`; accepts local (AF_UNIX) clients, one `cThread` + 2 threads per client, feeds `cSched` | `cSched`, `cThread` |
| `cConn` | Client side of `cService`: `task<ret>(fid, args...)` (blocking) / `iTask` (async) | UNIX socket `/tmp/<service_id>` |
| `cBench` | warm-up + N timed runs, min/avg/percentiles | - |

## cThread internals

Members ([cThread.hpp](../../sw/include/coyote/cThread.hpp)): `fd`, `vfid`, `ctid`, `hpid`, `fcnfg` (parsed shell config), `qpair` (`unique_ptr<ibvQp>`), `cmd_cnt` (software count of outstanding commands), `efd`/`terminate_efd`/`event_thread`, `cnfg_reg_avx` (**`volatile void*`**), `cnfg_reg` (`uint64_t*`), `ctrl_reg`, `wback`, `mapped_pages` (`void*` -> `CoyoteAlloc`), `gpu_dmabuf_fds`, `connfd`/`sockfd`/`is_connected` (RDMA out-of-band), `vlock` (`boost::interprocess::named_mutex`), `lock_acquired`, `unique_ptr<AdditionalState>`.

**Layout independence of `EN_AVX`** (commit 97b26119): `cnfg_reg_avx` used to exist only under `#ifdef EN_AVX`, making `sizeof(cThread)` differ between translation units compiled with/without it. It is now always present as `void*` and the typed `__m256i` view is the `#ifdef EN_AVX`-guarded inline `avxRegs()` accessor. Rule: **never add/remove/reorder data members or change their types under `#ifdef`s in `cThread.hpp`** (or other public headers); only guard member *functions* / includes. The same header is compiled into the sim library and into user binaries. Motivation: `std::make_shared`/`allocate_shared` in app code (compiled with a different `EN_AVX` than `libcoyote.so`) allocated a smaller block than the library constructor wrote (fpgasystems/Coyote#139). **Known remaining violation**: `CoyoteAlloc` ([cOps.hpp](../../sw/include/coyote/cOps.hpp), `cu_dev_ptr` under `#ifdef EN_CUDA`, SW-14); `EN_CUDA` must match between app and library (sim defines none).

**`AdditionalState` pimpl** (`additional_state` in [cThread.hpp](../../sw/include/coyote/cThread.hpp)): forward-declared nested class. HW build defines it empty at the end of [cThread.cpp](../../sw/src/cThread.cpp) (`class cThread::AdditionalState {}`); the simulation build defines it with the Vivado runner, pipe reader/writer threads, TLB page map etc. ([sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp), `class cThread::AdditionalState`) - lets sim keep state without new members in the shared header.

**Constructor** `cThread(vfid, hpid, device=0, uisr=nullptr)` ([cThread.cpp](../../sw/src/cThread.cpp)):
1. Construct `vlock = named_mutex(open_or_create, "mutex_dev_<device>_vfpa_<vfid>")` (note the `vfpa` spelling).
2. `open("/dev/coyote_fpga_<device>_v<vfid>", O_RDWR|O_SYNC)`.
3. `IOCTL_REGISTER_CTID{hpid}` -> `ctid`.
4. `IOCTL_READ_SHELL_CONFIG` -> `fcnfg.parseCnfg(tmp[0])`, `fcnfg.parseCtrlReg(tmp[1])` (TLB geometry, `pg_l_bits` used for hugepage allocs).
5. If `uisr` given: create two `eventfd`s, start `event_thread(eventHandler,...)`, `IOCTL_REGISTER_EVENTFD{ctid, efd}`.
6. If `fcnfg.en_rdma`: `IOCTL_GET_IP_ADDRESS`; init local `ibvQ`: GID from IP, `qpn = ((vfid & 0xf) << 6) | (ctid & 0x3f)`, random 24-bit `psn`, `rkey = 0`.
7. `mmapFpga()`, `clearCompleted()`.

**Destructor** ([cThread.cpp](../../sw/src/cThread.cpp), `cThread::~cThread`): unlock `vlock` if held; `freeMem` every mapped buffer; `munmapFpga`; if event thread (`efd != -1`): `IOCTL_UNREGISTER_EVENTFD`, write `terminate_efd`, join, close fds; then `IOCTL_UNREGISTER_CTID` (after the event thread, as another cThread could otherwise reuse the `ctid`); `closeConn()` if RDMA connected; `close(fd)`.

**Access levels** ([cThread.hpp](../../sw/include/coyote/cThread.hpp)): all members, `mmapFpga/munmapFpga`, `postCmd`, `sendAck/readAck`, `avxRegs` are `protected`; from the `public:` section: ctor/dtor, `doArpLookup`, `writeQpContext`, `userMap/userUnmap`, `getMem/freeMem`, `setCSR/getCSR`, `invoke` x5, `checkCompleted/clearCompleted`, `connSync`, `initRDMA/closeConn`, `lock/unlock`, getters `getVfid/getCtid/getHpid/getQpair`, `printDebug`. Registers can only be reached through these (subclass to access more).

**`mmapFpga`** ([cThread.cpp](../../sw/src/cThread.cpp)) - offsets are `index << PAGE_SHIFT` ([cDefs.hpp](../../sw/include/coyote/cDefs.hpp), `MMAP_*` constants) -> driver `vm_pgoff` ([driver.md](driver.md#device-nodes-ioctls-and-mmap)):

| Pointer | Condition | mmap offset | Size |
|---|---|---|---|
| `cnfg_reg_avx` | `EN_AVX` build and `fcnfg.en_avx` | `MMAP_CNFG_AVX` (2) | 256 KB |
| `cnfg_reg` | otherwise | `MMAP_CNFG` (1) | 64 KB |
| `ctrl_reg` | always | `MMAP_CTRL` (3) | 64 KB |
| `wback` | `fcnfg.en_wb` | `MMAP_WB` (0) | `4*64*4` B |

**Register indices** (`CnfgAvxRegs` / `CnfgLegRegs` in [cDefs.hpp](../../sw/include/coyote/cDefs.hpp)): `CnfgAvxRegs` index = 256-bit register number (byte `32*n`); `CnfgLegRegs` index = 64-bit register number (byte `8*n`). For registers 0-15 they address the **same byte layout** (`vfpga_cnfg_regs` in [driver.md](driver.md#core-data-structures); AVX reg `n` = legacy reg `4n`): e.g. `CTRL_REG`: Avx 0 / Leg 0; `ISR_REG`: 1 / 4; `STAT_REG_0`: 2 / 8-11; `OFFLOAD_CTRL_REG`: 5 / 20; `NET_ARP_REG`: 9 / 36; `RDMA_CTX_REG`: 10 / 40-42; `RDMA_CONN_REG`: 11 / 44-46; `TCP_*`: 12-15 / 48,52,56,60. **The completion-counter windows do not share a layout**: AVX `STAT_DMA_REG`=64 is 256-bit reg `64+ctid` at byte `2048+32*ctid` (4 lanes: local rd/wr, remote rd/wr); legacy `STAT_DMA_REG`=64 is at byte `512+8*ctid` (local rd low32 / wr high32) and `STAT_RDMA_REG`=128 at byte `1024+8*ctid` (remote rd/wr) (`STAT_DMA_REG` in [cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv), [cnfg_slave_avx.sv](../../hw/hdl/shell/cnfg_slave_avx.sv)). RTL: [cnfg_slave_avx.sv](../../hw/hdl/shell/cnfg_slave_avx.sv), [cnfg_slave.sv](../../hw/hdl/shell/cnfg_slave.sv).

**Command post** `postCmd(offs_3, offs_2, offs_1, offs_0)` ([cThread.cpp](../../sw/src/cThread.cpp)): register stores (AVX vs legacy), command-FIFO throttle, control word layout and the hardware path are described in [user/user_top.md](user/user_top.md#71-invoke---registers---hardware). SW-side details: callers pass `offs_0 = read ctrl`, `offs_1 = read vaddr`, `offs_2 = write ctrl`, `offs_3 = write vaddr`; `cmd_cnt` is a SW estimate, refreshed from the HW outstanding count (`CTRL_USED_OFFS`=0) only when above the threshold; control-word constants are the `CTRL_*` macros in [cDefs.hpp](../../sw/include/coyote/cDefs.hpp).

**invoke()** overloads (all check shell features via `fcnfg`, throw `runtime_error` on misuse):

| Call | Checks | Action |
|---|---|---|
| `invoke(LOCAL_OFFLOAD\|LOCAL_SYNC, syncSg)` | `en_mem` | ioctl `OFFLOAD_REQ`/`SYNC_REQ{addr,len,ctid}` (not a register write) |
| `invoke(LOCAL_READ\|LOCAL_WRITE, localSg, last)` | `en_strm\|\|en_mem` | READ: `postCmd(0,0,vaddr,ctrl)`; WRITE: `postCmd(vaddr,ctrl,0,0)` |
| `invoke(LOCAL_TRANSFER, src, dst, last)` | same | `postCmd(dst.addr, dst.ctrl, src.addr, src.ctrl)` |
| `invoke(REMOTE_RDMA_{READ,WRITE,SEND}, rdmaSg, last)` | `en_rdma` | if local IP == remote IP: `memcpy(remote, local)` **in every case** (wrong direction for `REMOTE_RDMA_READ`, SW-03); else builds a local and a remote command (opcode `oper - REMOTE_OFFS_OPS`(6): READ 0, WRITE 1, SEND 2; remote uses `STRM_RDMA`), swaps src/dst for READ, `postCmd`. Only the *remote* half carries `CTRL_START` (`ctrl_cmd_r` in [cThread.cpp](../../sw/src/cThread.cpp)); the local half is a descriptor without START |
| `invoke(REMOTE_TCP_SEND, tcpSg, last)` | `en_tcp` | write-only command on `STRM_TCP` (documented as unsupported/buggy in [cOps.hpp](../../sw/include/coyote/cOps.hpp)) |

`invoke` is asynchronous: it returns after the command is queued. Completion: `checkCompleted(oper)` ([cThread.cpp](../../sw/src/cThread.cpp)) returns a monotonically increasing per-ctid counter; check order is **write -> read -> remote read -> remote write/send** because `LOCAL_TRANSFER` satisfies both `isLocalRead` and `isLocalWrite`. Counter locations (writeback / AVX lanes): [user_top.md](user/user_top.md#71-invoke---registers---hardware).

`clearCompleted()` zeroes the writeback slots and writes `CTRL_CLR_STAT | ctid<<10` to both command words (AVX: lanes 0 and 2 in one store). **Not** safe to call while operations are outstanding.

**CSRs**: `setCSR(val, offs)` / `getCSR(offs)` -> `ctrl_reg[offs]` (64-bit slots = vFPGA `axi_ctrl`; direct mmap access, no ioctl; offset is a register *index*).

**Event thread** (`eventHandler` in [cThread.cpp](../../sw/src/cThread.cpp)): `epoll` on `efd` and `terminate_efd` (`MAX_EVENTS`=1). On `efd`: `eventfd_read` -> `IOCTL_GET_NOTIFICATION_VALUE{ctid}` -> `uisr(value)` -> `IOCTL_SET_NOTIFICATION_PROCESSED{ctid}`. `uisr` runs on the event thread (must be thread-safe); an exception there terminates the process.

**vFPGA lock**: `lock()`/`unlock()` ([cThread.cpp](../../sw/src/cThread.cpp); idempotent per cThread via `lock_acquired`, released in the dtor) take the named inter-process mutex of `(device,vfid)` so cThreads from different processes can serialise use of one vFPGA (e.g. while a bitstream is loaded). Not taken automatically by `invoke`; `cSched` takes it around task execution. The named object persists after a crash (typically under `/dev/shm`) and can wedge later runs; `cRcnfg`'s destructor removes `"reconfig_mtx"`, `cThread` never removes its mutex.

**Memory** `getMem(CoyoteAlloc&&)` ([cThread.cpp](../../sw/src/cThread.cpp)) allocates then `userMap`; `freeMem` unmaps then frees; destructor frees leftovers.

| `CoyoteAllocType` | Allocation | `freeMem` |
|---|---|---|
| `REG` | anonymous `mmap` | `userUnmap` + `munmap` |
| `THP` | `posix_memalign(2 MB)` (relies on kernel THP; driver sees regular pages and coalesces contiguous 2 MB-aligned runs into large-TLB entries) | `userUnmap` + `free` |
| `HPF` | `mmap(MAP_HUGETLB \| pg_l_bits << MAP_HUGE_SHIFT)`, page size = shell large-TLB page | `userUnmap` + `munmap` |
| `GPU` | `hipMalloc` / `cuMemAlloc` (EN_ROCM / EN_CUDA, else throws) | `userUnmap` + hipFree/cuMemFree |
| `PRM` | not for `cThread`; used by `cRcnfg` | - |

`userMap(vaddr,len,mem_block)`: if EN_ROCM/EN_CUDA and the pointer is device memory (CUDA detection via `cuPointerGetAttribute` needs an active CUDA context, `cThread::userMap` in [cThread.cpp](../../sw/src/cThread.cpp)) -> export dmabuf fd -> `IOCTL_MAP_DMABUF{fd, vaddr, ctid, mem_block}` (ROCm passes the page-aligned base), remember fd in `gpu_dmabuf_fds`; else `IOCTL_MAP_USER_MEM{vaddr,len,ctid,mem_block}`; return `99` -> warn only. `userUnmap` picks `UNMAP_DMABUF` vs `UNMAP_USER_MEM` by `gpu_dmabuf_fds` membership. Users may also `userMap` externally allocated memory (e.g. RDMA staging buffer passed to `initRDMA`).

**RDMA/out-of-band** (`initRDMA`, `connSync`, `closeConn`, `writeQpContext`, `doArpLookup`; [cThread.cpp](../../sw/src/cThread.cpp)): see [Networking](#networking).

`ibvQ`/`ibvQp` ([cDefs.hpp](../../sw/include/coyote/cDefs.hpp)): `{ip_addr, qpn, psn, rkey, vaddr, size, gid[33]}`; sent raw over TCP (host byte order, same-architecture peers assumed).

## cRcnfg, cSched, cFunc/cTask, cService, cConn, cBench

**cRcnfg** ([cRcnfg.cpp](../../sw/src/cRcnfg.cpp)): ctor opens `/dev/coyote_fpga_<device>_reconfig`, `pid=getpid()`, `crid = crid_gen++` (static atomic), named mutex `"reconfig_mtx"`. `readBitstream(ifstream)` -> `getMem({PRM, n_pages})` (`n_pages = ceil(len/2MB)`; passes *page count* in `alloc.size`) -> `IOCTL_ALLOC_HOST_RECONFIG_MEM{n_pages,pid,crid}` -> `mmap(MMAP_RECONFIG, (n_pages+1)*2MB)` -> align up to 2 MB -> byte-wise `ifstream.read` copy. `reconfigureBase(bitstream, vfid=-1)`: `vfid!=-1` -> `IOCTL_RECONFIGURE_APP{vaddr,len,pid,crid,vfid}`, else `IOCTL_RECONFIGURE_SHELL{vaddr,len,pid,crid}`; blocking until the driver's reconfig IRQ. Public: `reconfigureShell(path)`, `reconfigureApp(path, vfid)`. `cThread`s on a vFPGA being reconfigured must be idle; after *shell* reconfiguration old `cThread` fds are stale (driver re-creates device nodes).

**bFunc / cFunc<ret, args...>**: `cFunc(fid, app_bitstream_path, std::function<ret(cThread*, args...)>)` stores the absolute path; `run(cThread*, vector<vector<char>>)` `memcpy`-deserialises each argument (so arguments and the return type must be trivially copyable; `ret` must be non-void since `sizeof(ret)` bytes are sent; sizes from `getArgumentSizes()`/`getReturnSize()`; bitstream size is `uint32_t`, see `getBitstreamPointer` in [bFunc.hpp](../../sw/include/coyote/bFunc.hpp)), applies the function, serialises the return. Pointers passed as `uint64_t` refer to the **client's** address space (see cService).

**cTask**: `{tid, fid, cthread*, fn_args, ret_val, ret_val_size, ret_code(-1 until done), is_completed}`.

**cSched** (singleton per `"<device>-<vfid>"` via `getInstance(vfid, device=0, reorder=true, current_bitstream="")`; derives `cRcnfg`): ctor queries `IOCTL_PR_CNFG` -> `fcnfg.en_pr`. `addFunction(unique_ptr<bFunc>)` (inline in the header): rejects duplicate fid (returns 2), loads the function's bitstream into driver memory immediately via `readBitstream` (1 on failure, 0 ok). `start()` spawns `schedule()`; loop under `tlock`: pick next non-completed task - FIFO if `!reorder`, else the first whose function bitstream path equals `current_bitstream`, falling back to the oldest; if the bitstream differs: `reconfigureBase(bitstream_ptr, vfid)` (only if `en_pr`, else fail the task with `ret_code=1`); then `cthread->lock(); fn->run(); cthread->unlock();` store result (`ret_code=0`). Tasks are never removed from the vector. Tasks failing reconfiguration get `ret_code=1` here (but see SW-10). Logging via `syslog`. (Thesis ch.3.3.3 describes priority queues + load balancer; the code has only FIFO / bitstream-affinity ordering.)

**cService** (daemon; `getInstance(name, remote, vfid, device=0, reorder=true, port=DEF_PORT)`; `addFunction` forwards to its `cSched`): `service_id = "coyote-daemon-dev-<device>-vfid-<vfid>-<name>"`, socket `/tmp/<service_id>`. `start()`: `initDaemon()` (double `fork` + `setsid`, closes std fds, syslog; **the calling process exits**, so register functions *before* `start()`), `initSocket()` (AF_UNIX; `remote=true` branch creates TCP socket but `acceptConnectionRemote` is a stub), cleanup thread (`cleanConns`), `scheduler->start()`, then accept loop. Per accepted client: read client `pid` -> create `cThread(vfid, rpid, device)` (**driver `hpid` = client pid**, so page faults pin the *client's* memory) -> two threads `processRequests` / `sendResponses`. Wire format: request `int32[3] = {DEF_OP_SUBMIT_TASK(1)|DEF_OP_CLOSE_CONN(0), fid, client_tid}` followed by raw args; response `{int32 ret_code, int32 client_tid}` (+ raw return value if `ret_code==0`). `sendResponses` ignores `task->getRetCode()` (SW-10). `SIGTERM` handler deletes all `cService` singletons (unlinks the socket) and `exit`s.

**cConn** ([cConn.cpp](../../sw/src/cConn.cpp)): connect AF_UNIX to the socket path, send `getpid()`, start completion thread (`checkCompletedTasks`). `task<ret>(fid, args...)` (blocks, polling every `SLEEP_INTERVAL_CLIENT_CONN_MANAGER`=500 us; throws on non-zero return code) and `iTask<ret>(...)` returning a tid, + `isTaskCompleted(tid)` / `getTaskReturnValue<ret>(tid)`. Arguments sent with `write(sockfd, &x, sizeof(arg_type))` - sizes must match the server's `cFunc` signature exactly. Destructor sends close request.

**cBench**: `execute(bench_fn, prep_fn)` (the variadic `BenchArgs` are not deducible in practice; examples call it with two callables, e.g. [01_hello_world](../../examples/01_hello_world/sw/src/main.cpp)): `n_warmups` (default 100) + `n_runs` (default 1000) runs, `prep_fn` outside the timed region, times in ns, sorted; getters `getAvg/Min/Max/P25/P50/P75/P95/P99/getAll`.

## Threading and locking model

| Resource | Mechanism / caveat |
|---|---|
| One vFPGA across processes | `cThread::lock()` named mutex `mutex_dev_<d>_vfpa_<v>` (opt-in) |
| Reconfig buffer allocation across processes | `cRcnfg::mlock` named mutex `reconfig_mtx` |
| Reconfig execution | driver `rcnfg_lock` ([driver.md](driver.md#locking)) |
| cThread internals | **no internal locking** (`cmd_cnt`, `mapped_pages`); one `cThread` per application thread (example 08) |
| Event/uisr | dedicated thread per cThread with a `uisr` |
| `cSched` queue | `tlock` guards `tasks`/`task_id_map`, but is held for the whole `schedule()` iteration including reconfiguration and `fn->run()` ([cSched.cpp](../../sw/src/cSched.cpp)), so `addTask/isTaskCompleted/getTask` block during task execution; `functions` map is read without a lock (register functions before `start()`) |
| `cService` | per-client `task_locks[connfd]` only protects `tasks[connfd]`; the maps `tasks`, `task_locks`, `coyote_threads`, `connection_threads`, `conns_to_clean` are mutated from accept/connection/cleanup threads **without** a lock |
| `cConn` | `tasks` map shared between caller threads and `checkCompletedTasks` without a lock ([cConn.cpp](../../sw/src/cConn.cpp)) |
| Notifications | `IOCTL_SET_NOTIFICATION_PROCESSED` releases the driver's per-ctid semaphore, only for a pending notification (`vfpga_release_notification`) |

## Static layer & host DMA

RTL: [static/static_top.md](static/static_top.md), [static/host_dma.md](static/host_dma.md); driver: [driver.md#static-layer--host-dma](driver.md#static-layer--host-dma).

| SW | Ioctl / register | Driver | RTL |
|---|---|---|---|
| `invoke(LOCAL_READ/WRITE/TRANSFER, localSg)` -> `postCmd` | mmap `CTRL_REG` (AVX 256-bit store / 4x64-bit legacy) | none (direct MMIO; driver only mapped the window) | `cnfg_slave*.sv`, then [user_top.md](user/user_top.md#71-invoke---registers---hardware) |
| `checkCompleted` / `clearCompleted` | `wback[]` (mmap off 0) or `STAT_DMA_REG+ctid` / `CTRL_CLR_STAT` | writeback buffer allocated + base programmed in `setup_vfpga_devices` | `wback_dma.sv` / `cnfg_slave*.sv` |
| `cThread` ctor (`parseCnfg`) | `IOCTL_READ_SHELL_CONFIG` | `vfpga_dev_ioctl` reading `bus_driver_data` | `shell_slave.sv` config regs |
| `printDebug` | `STAT_REG_0/1` (sent rd/wr local/remote, invalidations, page faults, notifications) | - | `cnfg_slave*.sv` |

No SW wrapper (use sysfs or add one): `IOCTL_SHELL_HDMA_STATS`, `IOCTL_PR_WB_STATS` ([driver.md](driver.md#static-layer--host-dma); RTL `dma_stats.sv`, `pr_stats.sv`).

## Reconfiguration

RTL: [static/reconfig.md](static/reconfig.md); driver: [driver.md#reconfiguration](driver.md#reconfiguration).

| SW | Ioctl | Driver | RTL |
|---|---|---|---|
| `cRcnfg::readBitstream/getMem` | `ALLOC_HOST_RECONFIG_MEM` + `mmap(0x100<<12)` | `alloc_reconfig_buffer`, `reconfig_dev_mmap` | host memory only |
| `reconfigureApp(path, vfid)` | `RECONFIGURE_APP` | `reconfig_dev_ioctl` -> `reconfigure_start`, `reconfig_isr` | `static_slave.sv` PR regs, ICAP/PMC, `shell_slave.sv` app decouple |
| `reconfigureShell(path)` | `RECONFIGURE_SHELL` | + `shell_pci_remove/init` | `dcpl_static.sv`, EOS reset |
| `cRcnfg::freeMem` | `FREE_HOST_RECONFIG_MEM` | `free_reconfig_buffer` | - |
| `cSched` ctor | `PR_CNFG` | returns `en_pr` | `PR_CNFG_REG` |
| `cSched::schedule` -> `reconfigureBase` | `RECONFIGURE_APP` | as above | as above |

## Shell registers

RTL: [shell/shell_top.md](shell/shell_top.md); driver: [driver.md#shell-registers](driver.md#shell-registers).
- `fpgaCnfg::parseCnfg/parseCtrlReg` ([cDefs.hpp](../../sw/include/coyote/cDefs.hpp)) decode the two words from `IOCTL_READ_SHELL_CONFIG`; `ctrl_cnfg_reg_bits` mirrors `CTRL_CNFG_REG` of [shell_slave.sv](../../hw/hdl/shell/shell_slave.sv).
- User CSRs: `setCSR/getCSR` -> `MMAP_CTRL` region -> the vFPGA's `axi_ctrl` ([user/user_top.md](user/user_top.md)).
- Per-vFPGA config registers via `CnfgAvxRegs`/`CnfgLegRegs` as above. The SW never touches the TLB or `isr_*` registers (driver-only).

## MMU and page faults

RTL: [services/mmu.md](services/mmu.md); driver: [driver.md#mmu-and-page-faults](driver.md#mmu-and-page-faults).

| SW | Ioctl | Driver | Notes |
|---|---|---|---|
| `getMem(REG/THP/HPF)`, `userMap` | `MAP_USER_MEM{vaddr,len,ctid,mem_block}` | `mmu_handler_gup` -> pin + TLB write | pre-mapping avoids runtime faults; unmapped buffers are mapped lazily by the page-fault path when HW touches them |
| `userMap` on GPU pointer | `MAP_DMABUF{fd,vaddr,ctid,mem_block}` | `p2p_attach_dma_buf` | needs EN_CUDA/EN_ROCM + kernel >= 6.2 |
| `userUnmap`, `freeMem` | `UNMAP_USER_MEM` / `UNMAP_DMABUF{vaddr,ctid}` | `tlb_put_user_pages`, `p2p_detach_dma_buf` | blocks on TLB invalidation IRQ |
| `invoke(LOCAL_OFFLOAD/SYNC, syncSg)` | `OFFLOAD_REQ` / `SYNC_REQ` | `offload_user_pages` / `sync_user_pages` | host <-> card migration |
| cThread ctor/dtor | `REGISTER_CTID{hpid}` / `UNREGISTER_CTID{ctid}` | `ctid` alloc, per-ctid cleanup | `ctid` is the TLB tag and the command `pid` field |

## Card memory

RTL: [services/memory.md](services/memory.md); driver: [driver.md#card-memory](driver.md#card-memory).

| SW | Ioctl / field | Driver | RTL path |
|---|---|---|---|
| `CoyoteAlloc.mem_block` (Versal HBM pseudo-channel selector; `-1` = any; ignored on US+) | `userMap` `tmp[3]` | `alloc_card_memory` ([vfpga_hw.c](../../driver/src/vfpga/vfpga_hw.c)), `mem_block` remap in `tlb_get_user_pages` | HBM/DDR ports per vFPGA |
| `invoke(LOCAL_OFFLOAD/LOCAL_SYNC, syncSg)` | `OFFLOAD_REQ` / `SYNC_REQ` | `offload_user_pages` / `sync_user_pages` -> `trigger_dma_{offload,sync}` (`offl_*`/`sync_*` regs) | card DMA (`hw/hdl/cdma`) between host and card memory |
| `localSg.stream = STRM_CARD` (0) in `invoke(LOCAL_READ/WRITE/TRANSFER)` | command `strm` field | page fault with CARD access: driver migrates to card and maps with `host=0` | vFPGA `axis_card_*` streams via striping |

Requires `fcnfg.en_mem`. SW never sees card addresses.

## Networking

RTL: [services/network.md](services/network.md); driver: [driver.md#networking](driver.md#networking).

| SW | Mechanism | Driver / RTL |
|---|---|---|
| `cThread` ctor (RDMA) | `IOCTL_GET_IP_ADDRESS` | cached IP loaded by driver from `ip_addr` param |
| `initRDMA(buffer_size, port, server_addr?, mem?)` | TCP out-of-band. Client: connect -> allocate (`getMem({HPF, size, remote=true})`) unless `mem` given -> send local `ibvQ` -> read remote `ibvQ`. Server: bind (`SO_REUSEADDR`)/listen/accept **one** client -> read remote `ibvQ` -> allocate -> reply; failures call `releaseConn()`. Then `writeQpContext` + `doArpLookup`. Each server cThread opens its own listening socket | none; buffer mapped via `MAP_USER_MEM` |
| `writeQpContext(port)` | `RDMA_CTX_REG`: `[0]` = qpn(24b)@0 \| remote rkey@32; `[1]` = local psn(24b)@0 \| remote psn(24b)@24; `[2]` = remote vaddr(48b)@0. `RDMA_CONN_REG`: `[0]` = local qpn(16b)@0 \| remote qpn(24b)@16 \| port@40; `[1]`,`[2]` = remote GID words via `gidToUint` + `htols` | `cnfg_slave*.sv` -> RoCE stack |
| `doArpLookup(ip)` | writes `NET_ARP_REG`, then `usleep(SLEEP_TIME)` | ARP module |
| `invoke(rdmaSg)` | as table above | RDMA stack |
| `connSync(client)`, `closeConn()` | ack ints / `DEF_OP_CLOSE_CONN` over the OOB socket | none |

No SW wrapper: `IOCTL_SET_IP_ADDRESS`, `IOCTL_SET_MAC_ADDRESS`, `IOCTL_GET_MAC_ADDRESS`, `IOCTL_NET_STATS` (named `IOCTL_SHELL_NET_STATS` in the driver) - use sysfs/insmod params; the `TCP_OPEN_PORT/CONN(_STAT)_REG` registers also have no `cThread` wrapper (TCP send is unsupported).

Both register writes end with `usleep(SLEEP_TIME)` = **100 us** (`usleep` takes microseconds although `SLEEP_TIME` is documented in ns). IP/MAC registers (`NET_IPADDR_REG`=32, `NET_MACADDR_REG`=33 in `shell_slave.sv`) are driver-only. Local QP number = `(vfid & 0xf) << 6 | (ctid & 0x3f)`; local `rkey` fixed to 0; one OOB connection per `cThread` (`connfd`, `sockfd`); see [examples/09_perf_rdma](../../examples/09_perf_rdma/).

## User interrupts

RTL: `notify` interface ([user/user_top.md](user/user_top.md)); driver: [driver.md#user-interrupts](driver.md#user-interrupts).
- `cThread(vfid, hpid, device, uisr)` with non-null `uisr` (`std::function<void(int)>`) -> eventfd + epoll thread + `IOCTL_REGISTER_EVENTFD`. Per notification: `eventfd_read` -> `GET_NOTIFICATION_VALUE` -> `uisr(value)` -> `SET_NOTIFICATION_PROCESSED`. Example: [examples/04_user_interrupts](../../examples/04_user_interrupts/).
- Path: vFPGA `notify` -> `cnfg_slave*.sv` (`IRQ_NOTIFY`, counted in `STAT_NOTIFY`; pid/value in `ISR_PID`/`ISR_VAL` fields, legacy regs `ISR_HPID_PID_MISS_REG`=5, `ISR_VAL_LEN_MISS_REG`=7, AVX `ISR_REG` fields) -> MSI-X -> [vfpga_isr.c](../../driver/src/vfpga/vfpga_isr.c) `vfpga_notify_handler` -> eventfd registered by [vfpga_uisr.c](../../driver/src/vfpga/vfpga_uisr.c) -> `eventHandler` (value fetched with `IOCTL_GET_NOTIFICATION_VALUE`, [cThread.cpp](../../sw/src/cThread.cpp)).
- The simulation backend feeds `uisr` from the Vivado output pipe (`irq_thread`, [sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp)); `ctid` is hard-coded to 0 there.

## Gotchas and known issues

- **EN_AVX must agree with the shell**: SW built without `EN_AVX` on an AVX shell maps the non-AVX window (`MMAP_CNFG`) that shell does not implement (HW instantiates exactly one of `cnfg_slave`/`cnfg_slave_avx`, [mmu_top.sv](../../hw/hdl/mmu/mmu_top.sv), `inst_cnfg_slave` under `ifdef EN_AVX`). SW with `EN_AVX` (default) works for both.
- No `#ifdef`-dependent data members in `cThread.hpp`/public headers.
- `IOCTL_*`/`MMAP_*`/register enums must be mirrored in [coyote_defs.h](../../driver/include/coyote_defs.h) and the sim `cThread`.
- `MAX_TRANSFER_SIZE` (128 MB) is SW-only; `PAGE_SIZE`/`HUGE_PAGE_SIZE` are constants (only `pg_l_bits` is read from the shell for `HPF`); positive `ioctl` returns other than `99` (`MAP_USER_MEM`) are errors.
- Korolija's PhD thesis (Coyote v1) and the OSDI'20 paper describe a priority-queue/load-balancing runtime; the code has only FIFO / bitstream-affinity ordering.

Known defects in this area: [known_issues.md](known_issues.md) (`SW-*`, `NET-14`, `REC-08`).

## How to modify / extend

**Add a cThread method that writes a new register**
1. RTL: add the register in `cnfg_slave_avx.sv` **and** `cnfg_slave.sv` with the same byte offset (AVX reg `n` = legacy reg `4n`, **valid only for regs 0-15**; the `STAT_DMA` windows differ, see above).
2. Driver: if the driver needs it, extend `struct vfpga_cnfg_regs` ([coyote_defs.h](../../driver/include/coyote_defs.h)) - otherwise no driver change (the whole window is mmapped).
3. SW: add entries to `CnfgAvxRegs` and `CnfgLegRegs` in [cDefs.hpp](../../sw/include/coyote/cDefs.hpp).
4. Add the method to [cThread.hpp](../../sw/include/coyote/cThread.hpp) / [cThread.cpp](../../sw/src/cThread.cpp) following `doArpLookup` (AVX: `avxRegs()[CnfgAvxRegs::X] = _mm256_set_epi64x(...)` inside `#ifdef EN_AVX`/`fcnfg.en_avx`; else `cnfg_reg[CnfgLegRegs::X]`). Only add *member functions* under `#ifdef`.
5. Add a stub/implementation in [sim/sw/src/cThread.cpp](../../sim/sw/src/cThread.cpp) (and the testbench protocol if observable, [simulation.md](simulation.md)).

**Add an ioctl-backed method**: see [driver.md#how-to-modify--extend](driver.md#how-to-modify--extend); SW side: `uint64_t tmp[MAX_USER_ARGS]; tmp[i]=...; if (ioctl(fd, IOCTL_X, &tmp)) throw ...;`.

**Add a new allocation type**: extend `CoyoteAllocType` ([cOps.hpp](../../sw/include/coyote/cOps.hpp)), add cases to `getMem`/`freeMem`; if memory is not host-pinnable, add a new driver path like dmabuf.

**Add a scheduling policy**: modify `cSched::schedule()` selection loop (tasks vector under `tlock`); new `getInstance` parameters need the singleton key (`device-vfid`) kept.

**Expose a driver stat**: add `ioctl` wrapper in `cThread` (e.g. around `IOCTL_SHELL_HDMA_STATS`, currently no SW wrapper).
