# RDMA Benchmark

To run this example, two servers with a U55C-accelerator card each and connected via the same network (both the FPGAs and the servers independently) are required. One of the two FPGAs takes the role of a RDMA-client which initiates transactions and sets the parameters for networking experiment, while the other FPGA acts as a RDMA-server, responding to the initiated transfers. Both sides require the same bitstream `rdma_perf`, which can be built with this name-parameter to the CMakeList exactly as described above. The software-version however is different for the two sides and can be built with the name-parameters `rdma_server` and `rdma_client` respectively. If compiled successfully, the software-build-directory on both machines will hold an executable `bin/test` that can be used as following: 

## Server
The server needs to be initiated first. Since it basically just runs a passive daemon in the background, it's execution can be triggered via

~~~~
$ ./test
~~~~

Furthermore, one needs to find out the IP-address that can be used to exchange meta-information between client and server (CPUs) before initiating RDMA-transfers via FPGAs. The server-IP-address needs to be given to the client as argument and can be figured out via 

~~~~
$ ifconfig
~~~~

## Client
After the background-daemon for the Server is running, the client-software can be started. Different than on the other side, this requires some more arguments: 
* `-t`: IP-address of the Server (-CPU) for meta-exchange (QP-exchange and experiment-parameters). 
* `-w`: Controller to either issue WRITE (=1) or READ (=0) operations. 
* `-n`: Minimum message size for experimentation. 
* `-x`: Maximum message size. The experimentation size will be iterated between these two boundaries. 
* `-r`: Number of throughput-repetitions that are executed per message size. If this value is set to 0, no throughput-experiments will be executed. 
* `-l`: Number of latency-repetitions that are executed per message size. If this value is set to 0, no latency-experiments will be executed. 

Therefore, the software-call has to be
~~~~
$ ./test -t <server-side IP-address> -w <1 for WRITE, 0 for READ> -n <minimum message-size> -x <maximum message-size> -r <# of throughput-exchanges per message-size> -l <# of latency-exchanges per message-size>
~~~~

The server-side IP-address can be queried by running 
~~~~
$ ifconfig
~~~~
on the machine where the `rdma_server` was started. 

It is important to know that latency-measurements are conducted using a ping-pong-style communication (single RDMA-transactions from server and client exchanged in an alternating pattern repeated `l`-times), while throughput is measured with block transfers (`r` transactions from the client, followed by `r` transactions from the server).