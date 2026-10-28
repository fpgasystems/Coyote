# Coyote Testbench
The Coyote testbench helps to simplify the usage of Coyote by allowing the user to simulate the interaction of vFPGAs with the different interfaces Coyote provides.
With the simulation target, the exact software code that is used for the hardware can be compiled to use this testbench environment in the background.
If the software code uses the hardware or the simulation in the background is completely transparent.
The testbench currently supports the simulation of the host and card memory, AXI4L control (register), and notify (interrupt) interfaces.
The network (RDMA and TCP/IP) interfaces are not yet supported.

The simulation supports randomization of the valid signal of master interfaces and the ready signal of slave interfaces that go into and out of the vFPGA, which can be enabled by declaring a SystemVerilog define with the name ```EN_RANDOMIZATION```.
Randomization may randomly insert low cycles into the corresponding valid and ready signals which is an established approach to uncover errors with the handshaking logic of valid-ready interfaces.

The test bench consists of three parts:

1. The test bench implementation in SystemVerilog. This implementation provides a wire-protocol, which is used to control the simulation behavior. The protocol mimics the existing Coyote methods from the Coyote client library (e.g. the cThread methods). Data exchange with the simulation is done via files or unix named-pipes. Pipes are used if a interactive simulation is required. A description of the wire protocol is given below.
2. A C++ implementation that implements the wire-protocol. This implementation can be used to run existing C++ code, using the normal Coyote interfaces, against the simulation instead of a real device.
3. A Python implementation that implements the wire protocol and enables the implementation of unit tests for your design.

All three parts are described below.

*Hint: Using Vivado 2023.2 will throw an error about non-parameterized mailboxes that is a regression bug documented in this forum post (https://adaptivesupport.amd.com/s/question/0D54U00007wz0KeSAI/error-xsim-433980-generic-nonparameterized-mailbox?language=en_US). Use a different Vivado version for the simulation.*

# 1. System Verilog test bench

## Structure
The top file of the simulation is **hw/tb_user.sv**, this file creates the neccessary objects for communication between the different simulation drivers and the vFPGA aswell as initializes the simulation and controls the execution of the whole process.
By default, the simulation uses the top level of vFPGA #0 as the device under test (DUT) which is located in `<build_dir>/<proj_name>_config_0/user_c0_0/hdl/wrappers/user_logic_c0_0.sv`.

### Generator
The generators main task is to generate mailbox messages to the different drivers according to work queue entries it reads. 
The stimulus for the testbench is read from a binary file located in `<build_dir>/sim/input.sock` which consists of a arbitrary number of operations which always start with a Byte indicating the type of operation with one of the following values: `CSR = 1, USER_MAP = 2, MEM_WRITE = 3, INVOKE = 4, SLEEP = 5, CHECK_COMPLETED = 6, CLEAR_COMPLETED = 7, USER_UNMAP = 8`.
Multi-byte values are encoded least-significant Byte to most-significant Byte.
The file thus looks like this:

```
+------------+-----+++++++-----+------------+++++
| Op type #0 | LSB | ... | MSB | Op type #1 | ...
+------------+-----+++++++-----+------------+++++
```

In the following, we will describe the binary layout for the different operations:

`SET_CSR` encodes writes `setCSR(...)` to control registers.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  addr (long)  |  data (long)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

`GET_CSR` encodes reads `getCSR(...)` to control registers.
Additionally, there is a polling mode that stalls the dispatching of new operations from the input file until the value of the register with address `addr` matches `data`.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+------------+
|  addr (long)  |  data (long)  | do_polling |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+------------+
```

`USER_MAP` encodes mapping memory to the FPGA but also triggers the allocations in the host and card memory mock through `userMap(...)`.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  vaddr (long) |  size (long)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

`MEM_WRITE` encodes writes to host memory from the host side.
The `data` field is expected to match `len` in length.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
|  vaddr (long) |   len (long)  | data[len] ...
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
```

`INVOKE` encodes calls to `invoke(...)` which trigger memory movements to and from the vFPGA from the CPU side.
The `opcode` field is one of the values of `CoyoteOper`.
At the moment, `LOCAL_WRITE`, `LOCAL_READ`, `LOCAL_TRANSFER`, `LOCAL_OFFLOAD`, and `LOCAL_SYNC` are supported.
The `strm` field is for `STRM_HOST` or `STRM_CARD` and `dest` encodes the index of the stream and has to be smaller than `N_STRM_AXI` and `N_CARD_AXI` respectively.

```
+---------+------+------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+------+
|  opcode | strm | dest |  vaddr (long) |   len (long)  | last |
+---------+------+------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+------+
```

`SLEEP` encodes a number of cycles to sleep before dispatching the next operator.
This can be useful to delay certain operations.

```
+-+-+-+-+-+-+-+-+
|duration (long)|
+-+-+-+-+-+-+-+-+
```

`CHECK_COMPLETED` returns the number of completed requests for the given `opcode`.
If `do_polling` is asserted, stalls dispatching of the next operator until the `CoyoteOper` opcode has finished at least `count` number of times.

```
+--------+-+-+-+-+-+-+-+-+------------+
| opcode |  count (long) | do_polling |
+--------+-+-+-+-+-+-+-+-+------------+
```

`CLEAR_COMPLETED` clears the check completed counters and has no additional data that needs to be passed just the op type.

`USER_UNMAP` passes a vaddr to a memory segment to unmap (and free) in the host and card memory mock.

```
+-+-+-+-+-+-+-+-+
|  vaddr (long) |
+-+-+-+-+-+-+-+-+
```

### Scoreboard
The scoreboard writes back results of control register reads, interrupts, and writes to host memory into a binary output file located at `<build_dir>/sim/output.sock`.
This binary file works similar to the input file but has the following op codes: `GET_CSR = 0, HOST_WRITE = 1, IRQ = 2, CHECK_COMPLETED = 3, HOST_READ = 4`.

`GET_CSR` encodes the result of a `getCSR(...)` call and returns the `value`.

```
+-+-+-+-+-+-+-+-+
|  value (long) |
+-+-+-+-+-+-+-+-+
```

`HOST_WRITE` encodes writes to host memory from the vFPGA side through the `axis_host_send` interface.
The `data` field is expected to match `len` in length.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
|  vaddr (long) |   len (long)  | data[len] ...
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
```

`IRQ` encodes an interrupt through the `notify` interface of the vFPGA.

```
+-----+---+---+---+---+
| pid |  value (int)  |
+-----+---+---+---+---+
```

`CHECK_COMPLETED` encodes the result of a `checkCompleted(...)` call and is thus a result of a `CHECK_COMPLETED` operation in the generator.

```
+-+-+-+-+-+-+-+-+
|  value (int) |
+-+-+-+-+-+-+-+-+
```

`HOST_READ` encodes a read to host memory that was triggered from the vFPGA `sq_rd` interface. 
This is triggered in the read request forwarding logic of the generator and will stall the request until a `MEM_WRITE` to the specified vaddr arrives.
These scoreboard operations are only enabled if the `EN_INTERACTIVE` bit in the `tb_user` is set.
*WARNING: This may deadlock the simulation if the generator is currently waiting inside a polling operation that depends on the result of the `HOST_READ`. 
Polling operations are getCSR and checkCompleted with the polling flag set to true. 
This issue may be solved in the future by adding a second named pipe just for the host read responses.*

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  vaddr (long) |   len (long)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

`RDMA_REMOTE_INIT` writes arbitrary bytes to the remote RDMA memory. This data can then be read by sending requests through the `sq_rd` and `axis_rreq_recv` interfaces.
The `data` field is expected to match `len` in length.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
|  vaddr (long) |   len (long)  | data[len] ...
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
```

`RDMA_LOCAL_READ` simulates an incoming RDMA read request from the network. It carries the `vaddr` at which we want to read at and the amount of bytes in `len`.
The request will be received on the `rq_rd` queue (with remote = 1), and the data to fullfil the request is expected to be provided on the `axis_rrsp_send` interface.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  vaddr (long) |   len (long)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

`RDMA_LOCAL_WRITE` simulates an incoming RDMA write request from the network. It carries the `vaddr` where we want to write along with the data.
The request will be received on the `rq_wr` queue (with remote = 1), and the data to be written will be presented on the `axis_rrsp_recv` interface.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
|  vaddr (long) |   len (long)  | data[len] ...
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
```

### Memory Mock
The `memory_mock` class is instantiated for host and card memory respectively.
The mock does not perfectly implement the Coyote memory model (especially specific timing) but should be sufficient to verify the general functional correctness of the simulated vFPGA.
Memory allocations allocate memory segments in both memory mock instances simultaneously.
Writes to host memory are written into the memory segments in the host memory mock.
A memory request may span multiple adjacent memory segments, but requests outside the allocated memory segments fail.
When the simulation target of the software library invokes an operation on memory that was not mapped with `getMem(...)` or `userMap(...)` before, it emulates the page fault handling of the driver and maps the unmapped page-aligned parts of the requested range.

#### Timing parameters
Each mock reads environment variables when the simulation starts:

| Variable | Default | Meaning |
|---|---|---|
| `COYOTE_SIM_<MOCK>_LATENCY_NS` | `50` | Delay in ns between a request and its first data beat |
| `COYOTE_SIM_<MOCK>_GBPS` | `0` | Data rate per direction in Gbit/s; `0` is one beat per clock cycle (no limit) |
| `COYOTE_SIM_<MOCK>_MTU` | `0` | Bytes between two `tlast` on the data out of the mock (read responses), a multiple of 64; `0` is one `tlast` per request |
| `COYOTE_SIM_<MOCK>_JITTER_NS` | `0` | Extra delay in ns of each request, uniform between 0 and this value, on top of the latency |
| `COYOTE_SIM_<MOCK>_DROP` | `0` | Chance (0 to 1) that one MTU of a transfer is lost and resent; with MTU `0` the unit is the whole transfer |
| `COYOTE_SIM_<MOCK>_RETRANSMIT_NS` | `10000` | Stall in ns of a stream after a loss |
| `COYOTE_SIM_SEED` | `1` | Seed of the random draws of all mocks |

`<MOCK>` is `HOST`, `CARD` or `RDMA`. Both RDMA mocks (remote and local) read the `RDMA` values. The rate limit is a token bucket per direction, shared by all streams of the mock.
The bucket gains `GBPS / 8 * CLK_PERIOD_NS` bytes per clock cycle (50 B at 100 Gbit/s and 4 ns) and holds at most two beats (128 B).
A stream takes one 64 B beat when the bucket holds it.
With an MTU, responses carry `tlast`.
The jitter keeps the order within one stream but changes the order across the streams of a mock.
Assuming reliable transport, dropped data is retransmitted within `RETRANSMIT_NS`.
Each stream and direction has its own random generator (xorshift32), seeded from `COYOTE_SIM_SEED`, the mock name and the stream index.
Xsim and Verilator draw the same numbers.

### Memory Simulation
For work queue entries from sq_rd and sq_wr the memory simulation basically functions as a multiplexer and generates the mailbox message for the correct stream simulation driver.
All transactions from sq_rd and sq_wr require confirmation on cq_rd and cq_wr, for this, the respective drivers will return a mailbox message which will be picked up by the memory simulation to create the completion queue entries.
To support `LOCAL_OFFLOAD` and `LOCAL_SYNC`, the memory simulation implements a relaxed memory model.
Instead of pages, we implement page faults in card memory and the effects of `LOCAL_OFFLOAD` and `LOCAL_SYNC` with buffer faults.
If a card memroy buffer that has not been accessed from the vFPGA side is accessed for the first time, we load the whole buffer to card memory.
In real hardware, this is implemented with pages so be aware that this does not perfectly match hardware behaviour.


### RDMA Support

Beware that the current RDMA support in simulation is barebones. The current implementation is not faithful to the hardware.
Instead of implementing a full two-way communication to simulate networking and the capabilities of a remote device,
we currenty offer just a rudimentary approach where data can be written to the remote memory and events from the remote memory
can be simulated. Notably, there is no support for:

- Host-initiated RDMA requests.
- Custom remote processing: while you can send remote read/write requests and they will be processed as expected against the simulation memory,
  there's currently no support for a custom handling of these requests with arbitrary code.
- Remote reads can be triggered but their output is not assertable (i.e., there is no way to verify that your design is returning the correct data).

In the software simulation target, `cThread::initRDMA` opens no connection.
The first call reads the file named by the environment variable `COYOTE_SIM_RDMA_IMAGE` and writes it with `RDMA_REMOTE_INIT` to the remote memory at vaddr 0, the remote vaddr of the queue pair.
Later calls in the same process only set the local buffer of the queue pair, so one `cThread` serves every RDMA stream of the vFPGA.
`connSync` and `closeConn` do nothing; `invoke` with an `rdmaSg` stays unsupported.

## Setting up the simulation
You set up the simulation build folder the same way as you would for synthesis but instead of running `make project`, you run `make sim` which creates the simulation project and all necessary files.
Thereafter, the simulation can be manually run by opening the simulation project `<build_dir>/sim/<proj_name>.xpr` with Vivado and clicking `Run Simulation` in the GUI.
However, we recommend using either the Python unit test framework located in `sim/unit_test` or the simulation target located in `sim/sw` to interact with the simulation environment.

Passing the defines for randomization and the interactive mode can be done with the TCL command `set_property -name xsim.compile.xvlog.more_options -value {-d EN_RANDOMIZATION -d EN_INTERACTIVE} -objects [get_filesets sim_1]` after opening the project.

# 2. Software Simulation Target
Coyote offers to compile the software code that by default interacts with the hardware through the cThread against the simulation environment and writes a dump of the waveform to `<build_dir>/sim/sim_dump.vcd`.
The dump may be opened in any waveform viewer afterwards. Because the dump makes the simulation considerably slower, you can disable it by setting `COYOTE_SIM_VCD=0`.
To do this, we need to link against the `CoyoteSimulation` library and set the `COYOTE_SIM_DIR` environment variable when running the binary.

In your `CMakeLists.txt` you should have the following `add_subdirectory` or `find_package`:

```cmake
add_subdirectory(path/to/coyote/sim/sw coyote)
# or
find_package(CoyoteSimulation)
```

Then, you can compile your code and, assuming it produces a `test` binary, run it as follows:

```bash
$ cmake .. 
$ make
$ COYOTE_SIM_DIR=path/to/build_hw ./test
```

This switches out the `cThread` implementation that the software code is linked against one that starts Vivado in the background which runs the simulation environment that it communicates with through two named pipes `<build_dir>/sim/input.bin` and `<build_dir>/sim/input.bin`.
The protocol is the one specified above for the generator and scoreboard.
If you need verbose output for debugging purposes, put a `#define VERBOSE` into `sim/sw/include/Common.hpp`.

## Running the simulation with Verilator
The same testbench can run in [Verilator](https://verilator.org) (the release or commit that `sim/vl/verilator.env` pins, or newer) instead of Vivado xsim.
This needs no Vivado at run time and is faster.
After `make sim` has created the simulation project, build the Verilator binary with:

```bash
$ sim/vl/build.sh path/to/build_hw path/to/build_vl
```

The script stops when the Verilator in `PATH` is older than the pin in `sim/vl/verilator.env` (the file says why); `sim/vl/install_verilator.sh <prefix>` builds the pinned one from source without root, and takes another tag or commit as its first argument (usage in its header).
It takes the source list and the include folders from the xsim project that `make sim` wrote, so both simulators compile the same files.
Vivado writes that list at the first xsim run. If xsim has not run on the build yet, the script calls Vivado once to write it (about 40 s, no compile); Vivado must then be in `PATH`.
The list follows the hierarchy of the top in `<build_hw>/sim/vfpga_top.svh`, so the script calls Vivado again when the top is newer than the list (a Python unit test puts its own top there).
Verilator cannot compile encrypted Xilinx IP, for example the floating-point operator that Vitis HLS uses. `sim/vl/models/` holds a simulation model per such IP; Verilator takes it when the module is missing.
It writes `path/to/build_vl/coyote_vl`.
Set `COYOTE_SIM_BIN` to that binary when running the software; `cThread` then starts it instead of Vivado:

```bash
$ COYOTE_SIM_BIN=path/to/build_vl/coyote_vl COYOTE_SIM_DIR=path/to/build_hw ./test
```

The output of the binary goes to `<build_dir>/sim/coyote_vl.log`.
Without `COYOTE_SIM_BIN`, the simulation runs in Vivado as before.

`build.sh` reads `VL_DEFINES`, `VL_MODELS` and `VL_FLAGS` (its header says what each does).

Without Vivado: `sim/vl/configure.sh <app hw dir> <build dir> [cmake args]` makes the build folder in place of `make sim`. It configures the application with `-DSKIP_XILINX=1` (no Vivado, no Vitis HLS, the network stack folder skipped), renders `lynx_pkg.sv` and the user logic wrapper with `write_hdl.py` (needs `jinja2`), copies `vfpga_top.svh`, and writes `files.f` and `incs.f` from the vFPGA folders. HLS kernels are not supported, and Xilinx IP needs a Verilog model (`sim/vl/models/` holds the floating-point core, the ILAs of examples 1, 4, 7 and 12 and the AXI4-Stream register slice of `axisr_reg`).
SpinalHDL kernels (a `spinal/` folder in the vFPGA folder, example 12) are supported: the script runs `comp_spinal.tcl` with `tclsh` and adds the Verilog to `files.f`. This needs `sbt` and Java 11 or newer in `PATH`.
`sim/container/` builds an Apptainer or Docker image of one example this way ([sim/container/README.md](container/README.md)).

The script passes `-Wno-ENUMVALUE`: `'0` and `'X` on enum signals are common in vFPGA code.
Verilator rejects two constructs that xsim accepts: `type()` of an interface array element (`type(in[0].tag)`) and `$bits` of a signal of an interface whose parameter has no default. Pass such types and widths as parameters.
Verilator compiles no VHDL: a project with VHDL sources needs a Verilog model per entity in `VL_MODELS` (the script prints a note when the project has such sources).

# 3. Python unit testing framework

The documentation of the python unit-testing framework can be found in the unit-test subfolder.

# 4. TODO
1. Simulating multiple vFPGAs at once
