# Coyote Example 11: Using TCP/IP Network
Welcome to the eleventh Coyote example! In this example, we will cover how to use the TCP/IP stack integrated into the Coyote shell. Coyote provides a complete hardware-accelerated TCP/IP implementation, allowing data exchange between the FPGA and external hosts over standard Ethernet. This example demonstrates how to establish TCP connections between Linux and the vFPGA, perform data transfers, and measure throughput and latency across different configurations. As with all Coyote examples, a brief description of the core Coyote concepts covered in this example is included below.

## Table of contents
[Example Overview](#example-overview)

[TCP/IP Handshake Process](#tcpip-handshake-process)

[Hardware and Software Concepts](#hardware-and-software-concepts)

[Additional Information](#additional-information)

## Example overview
This example measures throughput and latency of TCP data exchange between
  - Linux as server and vFPGA as clinet
  - Linux as client and vFPGA as server
  - vFPGA as both client and server (To be updated)

Each configuration showcases how TCP connections can be established and managed entirely.

The experiment investigates performance across varying TCP payload sizes and numbers of concurrent connections, identifying when the system saturates the line rate.

## Hardware and Software Concepts
The TCP/IP network example consists of two HLS modules — one implementing a TCP server and one implementing a TCP client. Both use the TCP stack provided in the Coyote shell to establish and manage TCP connections in hardware.

### Server
The hardware server (tcp_perf_server) listens for incoming TCP connections and reads data from the receive stream.
It receives notifications and metadata from the TCP stack, which indicate that a remote endpoint has sent data. Once notified, it issues read requests to retrieve the payload and consumes the incoming data.

At the top level, the server module performs two main functions:
Notification handling: When the TCP stack signals that a new packet has arrived (appNotification), the module sends a read request for the corresponding session ID and length.

Data consumption: The received data words (rxData) are read from the network stream until the last flag is asserted, marking the end of the packet.

### Client
The hardware client (`tcp_perf_client`) is a hardware TCP traffic generator and performance benchmark engine. It actively opens TCP connections to a remote server, transmits payload data, and then closes the connections after a configurable duration.

It demonstrates the active side of TCP communication, driving the TCP state machine in hardware.

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
- A connection manager that requests new TCP sessions (`openConnection`) and monitors their completion (`openConStatus`).
- A transmit scheduler that advertises outgoing packets by sending transmit metadata (`txMetaData`) and then waits for transmit grants/acknowledgments from the stack (`txStatus`).
- A data generator that pushes the actual payload words into the TCP data channel (`txData`), using a known repeating pattern.
- A timer unit that starts when all sessions are established and asserts a stop condition after `timeInSeconds`.

## Additional Information
How to run examples
  - Linux as client and vFPGA as server

In the FPGA side, run
$ cd examples/11_perf_tcp/server/sw/build$
$ bin/test -p 5001

In the CPU side, run
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

To run the example,
  - Linux as server and vFPGA as clinet

In the CPU side, run
$ iperf -s

In the FPGA side, run
$ cd examples/11_perf_tcp/client/sw/build$
$ bin/test -i <server ip address> -s 48 -w 128 -t 10


## Troubleshootings
Set mtu size large enough (in our examples, we used 8k size)
Or you can hdev set mtu --device 1 --port 1 --value 9000 in the hacc cluster
