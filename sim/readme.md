<h1>Coyote Testbench</h1>

<h2>Overview</h2>

The Coyote testbench helps to simplify the usage of Coyote by allowing the user to simulate the interaction of the vfpga with the different interfaces.
The Coyote testbench currently supports the simulation of the Host, Card memory and RDMA interfaces, the TCP/IP interface is not yet supported
RDMA transactions have only been tested up to a size of 4KB.

<h2>Structure</h2>

The top file of the simulation is **tb_user.sv**, this file creates the neccessary objects for communication between the different simulation drivers and the vfpga aswell as initializes the simulation and controls the execution of the whole process.
In **tb_design_user_logic.sv** the interfaces which are connected to the hardware side are defined.

<h3>Control registers</h3>

To simulate the writing and reading of control registers, the simulation contains the class ctrl_simulation which takes a text file as input and can either issue writes to control registers or read from ctrl registers until a certain value is matched.
This communication takes place via the AXI Lite interface called **AXI_CTRL**.

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
- **1 18 000007fe00000000 0 0**

While the following line would get the ctrl_simulation instance to loop until the last 4 bits from the register at address *0000000000000008* would have the value *1000*
- **0 08 0000000000000008 3 0**
