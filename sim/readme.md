# Coyote Testbench

## Overview

The Coyote testbench helps to simplify the usage of Coyote by allowing the user to simulate the interaction of the vfpga with the different interfaces.
The Coyote testbench currently supports the simulation of the Host, Card memory and RDMA interfaces, the TCP/IP interface is not yet supported
RDMA transactions have only been tested up to a size of 4KB.

## Structure

The top file of the simulation is **tb_user.sv**, this file creates the neccessary objects for communication between the different simulation drivers and the vfpga aswell as initializes the simulation and controls the execution of the whole process.
In **tb_design_user_logic.sv** the interfaces which are connected to the hardware side are defined.


### Control registers

To simulate the writing and reading of control registers, the simulation contains the class ctrl_simulation which takes a text file as input and can either issue writes to control registers or read from ctrl registers until a certain value is matched.
This communication takes place via the AXI Lite interface called **AXI_CTRL**.
To trace back the actions of the control simulation, every write or read issue will be logged into a file called "ctrl_transfer_output.txt" in /sim_files/output.


### Host Simulation

The interactions with the host are simulated mainly by the host_driver_simulation. The host driver simulation holds a virtual host memory which is initialised by calling the set_data function. Memory is hold in different disjunct segments, if, by calling the set_data function, memory segments overlap or neighbour each other, they will automatically be merged together.
Depending on the simulated hardware, the host driver can either simulate just responding to work queue entries in sq_rd and sq_wr or the transfer of data on **AXI_HOST_SEND** and **AXI_HOST_RECV** without accompanying work queue entries can be simulated.
These actions will be triggered by the generator_simulation via mailbox messages.
When working with sq_rd and sq_wr entries, the host will mutate it's memory accordingly, if a work queue entry refers to an address not currently allocated in the host memory, a message will be displayed and the simulation will be aborted, this is so there won't be any irregularities between the work queues and the axi streams.
Every data transfer on the axi streams will be logged in the "host_transfer_output.txt" file in /sim_files/output. Once the simulation has come to an end, the content of the host memory will be written into the "host_mem_data_output.txt" file in /sim_files/output.


### RDMA Simulation

Similarly to the host simulation, the rdma_driver_simulation holds a virtual memory from which data can be read from or written to.
The RDMA simulation supports outgoing as well as incoming transactions, in case of outgoing RDMA requests, initiated by the vfpga, data will be read from or written to the virtual RDMA memory.
To simulate incoming transactions, the generator simulation will read a file for incoming reads and a file for incoming writes from which it will generate the matching work queue entries in rq_rd and rq_wr and send a request to the RDMA simulation through mailboxes. The RDMA simulation will once again take data from it's virtual memory in case of an incoming write, and write data to it's virtual memory in case of an incoming read.
Data transfers will be continuously written to "rdma_transfer_output.txt" while the content of the virtual memory will be written to "rdma_data_output.txt" once the simulation has been completed.


### Card memory simulation

The card memory simulation works exactly the same as the host simulation but is only able to respond to sq_rd and sq_wr entries, there is no possibility to stream data from or to the card simulation without accompanying work queue entries.
Transfers will be written to "card_transfer_output.txt" and data will be written to "card_data_output.txt".


### Generator simulation

The generators main task is to generate mailbox messages to the different drivers according to work queue entries it reads. For work queue entries from sq_rd and sq_wr the generator basically functions as a multiplexer and generates the mailbox message for the correct driver. Work queue entries in rq_rd and rq_wr will be generated according to the files passed to the generator and mailbox messages will be sent to the rdma simulation to stream the associated data.
If the simulation contains data that is streamed from the host without work queue entries, this will be defined in a file and passed to the generator which will prompt the host simulation with mailbox messages to stream this data.
All transactions from sq_rd and sq_wr require confirmation on cq_rd and cq_wr, for this, the respective drivers will return a mailbox message which will be picked up from the generator to create the completion queue entries.


### tb_user

**tb_user.sv** is the top file of the simulator, it is used to instantiate the needed objects like mailboxes, axi streams etc. and starts the simulator, it also controls when the simulation ends.


## Creating input files
To run a simulation, the user has to create files with input to start the correct execution. These should be located at /sim_files/input.

### ctrl input
The input file is a text file with one instruction per line, consisting of the following parameters, seperated by a space.
- boolean **isWrite**
  - *Defines if the instruction writes a control register or reads from it*
- logic[64] **addr** *in hexadecimal values*
  - *Address of the control register which is written to or read from*
- logic[64] **data** *in hexadecimal values*
  - *Data which is written to the control register, or data which is expected to be read from the control register*
- int **read_start_bit**
  - *In case of a read, this value defines the first bit which is taken into account when comparing the values*
- int **read_en_bit**
  - *In case of a read, this value defines the last bit which is taken into account when comparing the values*
 
The following line would therefore lead to writing *000007fe00000000* at the address *0000000000000018*
~~~~
1 18 000007fe00000000 0 0
~~~~
While the following line would get the ctrl_simulation instance to loop until the last 4 bits from the register at address *0000000000000008* would have the value *1000*
~~~~
0 08 0000000000000008 3 0
~~~~


### rq_rd and rq_wr input
For rq_rd and rq_wr they both get a seperate text file as input with one instruction per line, consisting of the following parameters, seperated by a space.
- int **delay**
  - *delays the enqueing of this request by the specified amount of simulation steps, after the last entry has been enqueued*
- logic[28] **length** *in decimal values*
  - *specifies the length of the incoming RDMA request*
- logic[64] **addr** *in hexadecimal values*
  - *specifies the address of the incoming RDMA request* 

The following line in the input file of rq_rd would lead to an incoming RDMA read request with a length of 128 bytes at address 7fe00000100, 50 simulation steps after the last request has been enqueued.
~~~~
50 80 7fe00000100
~~~~


### host input
The input file is a text file with one instruction per line, consisting of the following parameters, seperated by a space.
- int **delay**
  - *delays the enqueing of this request by the specified amount of simulation steps, after the last entry has been enqueued*
- int **dest**
  - *the number of the destination AXI stream for the transaction*
- logic[6] **pid** *in hexadecimal values*
  - *the pid of the axi transaction*
- logic[64] **keep** *in hexadecimal values*
  - *the keep value of the AXI transaction*
- logic **last**
  - *the last bit of the AXI transaction*
- logic[512] **data** *in hexadecimal values*
  - *the data of the AXI transaction*




## Setting up the simulator









