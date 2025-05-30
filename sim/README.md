# Coyote Testbench

## Overview
The Coyote testbench helps to simplify the usage of Coyote by allowing the user to simulate the interaction of vFPGAs with the different interfaces Coyote provides.
The testbench currently supports the simulation of the host and card memory, AXI4L control (register), and notify (interrupt) interfaces.
The network (RDMA and TCP/IP) interfaces are not yet supported.

## Structure
The top file of the simulation is **hw/tb_user.sv**, this file creates the neccessary objects for communication between the different simulation drivers and the vFPGA aswell as initializes the simulation and controls the execution of the whole process.
By default, the simulation uses the top level of vFPGA #0 as the device under test (DUT) which is located in `<build_dir>/<proj_name>_config_0/user_c0_0/hdl/wrappers/user_logic_c0_0.sv`.

### Generator
The generators main task is to generate mailbox messages to the different drivers according to work queue entries it reads. 
For work queue entries from sq_rd and sq_wr the generator basically functions as a multiplexer and generates the mailbox message for the correct driver.
All transactions from sq_rd and sq_wr require confirmation on cq_rd and cq_wr, for this, the respective drivers will return a mailbox message which will be picked up from the generator to create the completion queue entries.
The stimulus for the testbench is read from a binary file located in `<build_dir>/sim/input.sock` which consists of a arbitrary number of operations which always start with a Byte indicating the type of operation with one of the following values: `CSR = 1, GET_MEM = 2, MEM_WRITE = 3, INVOKE = 4, SLEEP = 5, CHECK_COMPLETED = 6`.
Multi-byte values are encoded least-significant Byte to most-significant Byte.
The file thus looks like this:

```
+------------+-----+++++++-----+------------+++++
| Op type #0 | LSB | ... | MSB | Op type #1 | ...
+------------+-----+++++++-----+------------+++++
```

In the following, we will describe the binary layout for the different operations:

`CSR` encodes writes `setCSR(...)` and reads `getCSR(...)` to control registers.
Additionally, for reads it has a polling mode that stalls the dispatching of new operations from the input file until the value of the register with address `addr` matches `data`.

```
+----------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+------------+
| is_write |  addr (long)  |  data (long)  | do_polling |
+----------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+------------+
```

`GET_MEM` encodes memory allocations through `getMem(...)`.

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
At the moment, `LOCAL_WRITE`, `LOCAL_READ`, and `LOCAL_TRANSFER` are supported.
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

`CHECK_COMPLETED` stalls dispatching of the next operator until the `CoyoteOper` opcode has finished at least `count` number of times.

```
+--------+-+-+-+-+-+-+-+-+
| opcode |  count (long) |
+--------+-+-+-+-+-+-+-+-+
```

### Scoreboard
The scoreboard writes back results of control register reads, interrupts, and writes to host memory into a binary output file located at `<build_dir>/sim/output.sock`.
This binary file works similar to the input file but has the following op codes: `GET_CSR = 0, HOST_WRITE = 1, IRQ = 2`.

`GET_CSR` encodes the result of a `getCSR(...)` call and returns the `value`.

```
+-+-+-+-+-+-+-+-+
|  value (long) |
+-+-+-+-+-+-+-+-+
```

`HOST_WRITE` encodes writes to host memory from the vFPGA side.
The `data` field is expected to match `len` in length.

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
|  vaddr (long) |   len (long)  | data[len] ...
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+++++++++++++++
```

`IRQ` encodes an interrupt through the notify interface.

```
+-----+---+---+---+---+
| pid |  value (int)  |
+-----+---+---+---+---+
```

### Memory Mock
The `memory_mock` class is instantiated for host and card memory respectively.
The behavior does not model the Coyote memory model perfectly but should be sufficient to verify the general functional correctness of the design in simulation.
Memory allocations allocate memory segments in both memory mock instances simultaneously.
Writes to host memory are written into the memory segments in the host memory mock.
Since `LOCAL_OFFLOAD` and `LOCAL_SYNC` are currently not supported and we do not model page faults, the card memory can only be written from the vFPGA side.
Memory requests outside the allocated memory segments fail.

## Setting up the simulation
You set up the simulation build folder the same way as you would for synthesis but instead of running `make project`, you run `make sim` which creates the simulation project and all necessary files.
Thereafter, the simulation can be run by opening the simulation project `<build_dir>/sim/<proj_name>.xpr` with Vivado and clicking `Run Simulation` in the GUI.

## TODO
1. Check hardware details
   1. cq acknowledgements for host initiated transfers?
   2. cq acknowledgements for requests where req.last == 0?
   3. What does checkCompleted on LOCAL_TRANSFER do? Does it return completed reads or writes?
2. RDMA support
3. Simulation target for software that communicated with simulation through sockets
