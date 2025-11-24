# Coyote Example 11: Using TCP/IP Network
Welcome to the eleventh Coyote example!

In this example, we will demonstrate how to use the **TCP/IP stack** integrated into the **Coyote shell**.  
Coyote provides a complete **hardware-accelerated TCP/IP implementation**, enabling data exchange between the **FPGA** and external hosts over standard Ethernet.

This example shows how to establish TCP connections between Linux and the vFPGA and perform data transfers.  
As with all Coyote examples, a brief overview of the main concepts covered in this example is included below.


## Table of contents
[Example Overview](#example-overview)

[TCP/IP Handshake Process](#tcpip-handshake-process)

[Hardware and Software Concepts](#hardware-and-software-concepts)

[Additional Information](#additional-information)

[Troubleshooting](#troubleshooting)


## Example overview
This example measures the **throughput** of TCP data exchange between the following setups:

- Linux as **server**, vFPGA as **client**  
- Linux as **client**, vFPGA as **server**  
- vFPGA as **both client and server** *(to be updated)*  

Each configuration demonstrates how TCP connections can be established and managed entirely in hardware.

## Hardware and Software Concepts

The TCP/IP network example consists of two HLS modules:
- A **TCP server**
- A **TCP client**

Both use the TCP/IP stack provided in the Coyote shell to establish and manage TCP connections directly in hardware.

### Server
The hardware server listens for incoming TCP connections and reads data from the receive stream.  
It receives notifications and metadata from the TCP stack, indicating when a remote endpoint has sent data. Once notified, it issues read requests to retrieve and consume the incoming payload.

At the top level, the server module performs two main functions:

1. **Notification Handling:**  
   When the TCP stack signals that a new packet has arrived (`appNotification`), the module sends a read request for the corresponding session ID and packet length.
2. **Data Consumption:**  
   The received data words (`rxData`) are read from the network stream until the `last` flag is asserted, marking the end of the packet.

### Client

The hardware client is a **TCP traffic generator**.
It actively opens TCP connections to a remote server, transmits payload data, and closes the connections after a configurable duration.

It represents the **active** side of TCP communication, driving the TCP state machine directly in hardware.

The client is driven by a control/status register block accessible from the host over AXI-Lite. The host software programs:
- `runTx`              – start signal for the benchmark
- `numSessions`        – number of parallel TCP connections to open
- `pkgWordCount`       – payload length (in words) per TCP packet
- `serverIpAddress`    – destination IPv4 address
- `userFrequency`      – FPGA clock frequency, used for timing
- `timeInSeconds`      – benchmark duration

The hardware also reports back:
- `state`              – internal FSM state for debugging

Internally, the client consists of several streaming sub-blocks that interface with the TCP/IP stack:
- A connection manager that requests new TCP sessions (`openConnection`) and receives their completion (`openConStatus`).
- A scheduler that advertises outgoing packets by sending transmit metadata (`txMetaData`) and then waits for transmit acknowledgments from the stack (`txStatus`).
- A data generator that pushes the actual payload words into the TCP data channel (`txData`).
- A timer unit that starts when all sessions are established and asserts a stop condition after `timeInSeconds`.

## Additional Information

### How to Run the Examples

This section shows how to run throughput/latency measurements in two directions:
1. Linux as **client**, vFPGA as **server**
2. Linux as **server**, vFPGA as **client**

#### 1. Linux as Client / vFPGA as Server

**On the FPGA side (run the hardware TCP server):**
```
$ cd examples/11_perf_tcp/server/sw/build$
$ bin/test -p 5001
```

**On the CPU side (run the hardware TCP client):**
```
$ iperf -c 10.253.74.88 -P 10
------------------------------------------------------------
Client connecting to 10.253.74.88, TCP port 5001
TCP window size:  165 KByte (default)
------------------------------------------------------------
[ 17] local 10.253.74.82 port 60226 connected with 10.253.74.88 port 5001
[ 15] local 10.253.74.82 port 60198 connected with 10.253.74.88 port 5001
[ 13] local 10.253.74.82 port 60196 connected with 10.253.74.88 port 5001
[ 16] local 10.253.74.82 port 60210 connected with 10.253.74.88 port 5001
[  2] local 10.253.74.82 port 60064 connected with 10.253.74.88 port 5001
[  1] local 10.253.74.82 port 60062 connected with 10.253.74.88 port 5001
[ 19] local 10.253.74.82 port 60240 connected with 10.253.74.88 port 5001
[  3] local 10.253.74.82 port 60076 connected with 10.253.74.88 port 5001
[ 20] local 10.253.74.82 port 60236 connected with 10.253.74.88 port 5001
[ 18] local 10.253.74.82 port 60230 connected with 10.253.74.88 port 5001
[ ID] Interval       Transfer     Bandwidth
[  2] 0.0000-10.0017 sec  4.39 GBytes  3.77 Gbits/sec
[  8] 0.0000-10.0022 sec  4.34 GBytes  3.72 Gbits/sec
[  1] 0.0000-10.0041 sec  7.48 GBytes  6.43 Gbits/sec
[ 16] 0.0000-10.0022 sec  6.82 GBytes  5.86 Gbits/sec
[ 14] 0.0000-10.0013 sec  7.20 GBytes  6.19 Gbits/sec
[  7] 0.0000-10.0020 sec  3.08 GBytes  2.65 Gbits/sec
[ 10] 0.0000-10.0022 sec  3.04 GBytes  2.61 Gbits/sec
[ 19] 0.0000-10.0021 sec  2.93 GBytes  2.52 Gbits/sec
[  4] 0.0000-10.0012 sec  6.32 GBytes  5.43 Gbits/sec
[ 11] 0.0000-10.0010 sec  7.48 GBytes  6.42 Gbits/sec
[ 18] 0.0000-10.0014 sec  6.97 GBytes  5.99 Gbits/sec
[ 13] 0.0000-10.0009 sec  7.09 GBytes  6.09 Gbits/sec
[ 17] 0.0000-10.0021 sec  4.49 GBytes  3.85 Gbits/sec
[  6] 0.0000-10.0018 sec  4.40 GBytes  3.78 Gbits/sec
[  5] 0.0000-10.0013 sec  7.11 GBytes  6.11 Gbits/sec
[ 15] 0.0000-10.0019 sec  4.18 GBytes  3.59 Gbits/sec
[  9] 0.0000-10.0020 sec  7.77 GBytes  6.68 Gbits/sec
[ 20] 0.0000-10.0009 sec  6.95 GBytes  5.97 Gbits/sec
[ 12] 0.0000-10.0016 sec  4.11 GBytes  3.53 Gbits/sec
[  3] 0.0000-10.0019 sec  6.75 GBytes  5.80 Gbits/sec
[SUM] 0.0000-10.0016 sec   113 GBytes  97.0 Gbits/sec
```

#### 2. Linux as Server / vFPGA as Client

**On the CPU side (run the hardware TCP server):**
```
$ iperf -s
```
**On the vFPGA side (run the hardware TCP client):**
```
$ cd examples/11_perf_tcp/client/sw/build$
$ bin/test -i <server ip address> -s 32 -w 128 -t 10
```
```
------------------------------------------------------------
Server listening on TCP port 5001
TCP window size:  128 KByte (default)
------------------------------------------------------------
[  1] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32769
[  2] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32776
[  4] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32777
[  5] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32782
[  7] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32780
[  8] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32779
[  9] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32799
[ 10] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32790
[ 11] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32787
[ 12] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32791
[ 13] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32788
[ 14] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32789
[ 15] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32784
[ 16] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32786
[ 17] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32773
[ 18] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32771
[ 19] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32772
[ 20] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32795
[ 21] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32783
[ 23] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32774
[ 24] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32770
[ 25] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32797
[ 26] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32775
[ 27] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32794
[ 28] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32792
[ 29] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32798
[ 30] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32785
[ 31] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32796
[  3] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32781
[  6] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32778
[ 22] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32768
[ 32] local 10.253.74.82 port 5001 connected with 10.253.74.88 port 32793
[ ID] Interval       Transfer     Bandwidth
[ 30] 0.0000-10.7457 sec  2.73 GBytes  2.18 Gbits/sec
[  1] 0.0000-10.7582 sec  4.41 GBytes  3.52 Gbits/sec
[  3] 0.0000-10.7569 sec  2.79 GBytes  2.22 Gbits/sec
[  6] 0.0000-10.7551 sec  4.26 GBytes  3.40 Gbits/sec
[  5] 0.0000-10.7557 sec  2.67 GBytes  2.13 Gbits/sec
[  9] 0.0000-10.7537 sec  4.42 GBytes  3.53 Gbits/sec
[ 11] 0.0000-10.7532 sec  2.74 GBytes  2.19 Gbits/sec
[ 13] 0.0000-10.7525 sec  4.26 GBytes  3.41 Gbits/sec
[ 15] 0.0000-10.7519 sec  3.88 GBytes  3.10 Gbits/sec
[ 17] 0.0000-10.7516 sec  2.64 GBytes  2.11 Gbits/sec
[ 19] 0.0000-10.7510 sec  2.64 GBytes  2.11 Gbits/sec
[ 21] 0.0000-10.7502 sec  4.70 GBytes  3.76 Gbits/sec
[ 23] 0.0000-10.7494 sec  2.69 GBytes  2.15 Gbits/sec
[ 25] 0.0000-10.7489 sec  2.60 GBytes  2.08 Gbits/sec
[ 27] 0.0000-10.7469 sec  2.58 GBytes  2.06 Gbits/sec
[ 29] 0.0000-10.7462 sec  4.21 GBytes  3.37 Gbits/sec
[ 32] 0.0000-10.7433 sec  4.31 GBytes  3.45 Gbits/sec
[  4] 0.0000-10.7563 sec  5.26 GBytes  4.20 Gbits/sec
[  8] 0.0000-10.7546 sec  4.46 GBytes  3.56 Gbits/sec
[ 12] 0.0000-10.7531 sec  2.70 GBytes  2.16 Gbits/sec
[ 16] 0.0000-10.7518 sec  4.98 GBytes  3.97 Gbits/sec
[ 20] 0.0000-10.7508 sec  5.45 GBytes  4.35 Gbits/sec
[ 24] 0.0000-10.7495 sec  2.47 GBytes  1.98 Gbits/sec
[ 28] 0.0000-10.7465 sec  6.33 GBytes  5.06 Gbits/sec
[  2] 0.0000-10.7578 sec  2.50 GBytes  2.00 Gbits/sec
[ 10] 0.0000-10.7537 sec  3.63 GBytes  2.90 Gbits/sec
[ 18] 0.0000-10.7510 sec  2.72 GBytes  2.17 Gbits/sec
[ 26] 0.0000-10.7472 sec  4.30 GBytes  3.44 Gbits/sec
[  7] 0.0000-10.7554 sec  2.08 GBytes  1.66 Gbits/sec
[ 22] 0.0000-10.7499 sec  2.18 GBytes  1.74 Gbits/sec
[ 14] 0.0000-10.7528 sec  3.14 GBytes  2.51 Gbits/sec
[ 31] 0.0000-10.7457 sec  4.76 GBytes  3.81 Gbits/sec
[SUM] 0.0000-10.7584 sec   115 GBytes  92.2 Gbits/sec
```
### Troubleshootings
Ensure that the **MTU (Maximum Transmission Unit)** size is set large enough to support high throughput.  
In our tests, an **8K MTU** (jumbo frame) was used.

**Example command (HACC cluster):**
```bash
hdev set mtu --device 1 --port 1 --value 9000
```

If the hardware synthesis fails, run
```
git submodule update --init --recursive
```