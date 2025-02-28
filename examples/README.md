# Coyote-FAQ: What you always wanted to know about FPGAs, computer systems and life in general 

## Table of Contents
[Coyote Concepts](#coyote-concepts)
[Systems Set-Up & Compatibility](#systems-set-up--compatibility)
[Common Pitfalls](#common-pitfalls)
[Debugging](#debugging)
[Miscellaneous](#miscellaneous)


## Coyote Concepts

#### What is Coyote? 

#### How does multi-tenancy work in Coyote?

#### Can I have more than one vFPGA? 

#### What happens when an application is too big for a vFGPA? 
There is one common misconception that needs to be clarified before answering this question: vFPGAs with strict physical boundaries only exist if Coyote is built for partial reconfiguration on the application-layer. If this is not the case, Coyote will have the shell layer with XDMA and the reconfigurable service layer. All user applications will be placed in this service layer and only limited by the cumulative consumption of the generally available resources in this layer. There are no strictly enforced limites per vFGPAs in this case. 

The situation is different in a scenario where partial reconfigurability on the application layer has been selected as build-parameter for Coyote. In this case, every vFPGA is forced into a restricted area of the FPGA, drawn by the user as a floorplanning "box" in Vivado. Obviously, this can also mean that such a box has not enough ressources for the planned application. Coyote v2 does not offer direct inter-vFPGA connections that would allow to daisy-chain multiple logic blocks. 
However, some design strategies can help to deal with those resource constraints: 
* Plan Coyote with heterogeneous vFPGA-sizings to be able to accomodate various different user applications with different hardware demands: Since the user quite literally "draws" the floorplanning-boxes in Vivado on their own, it's completely possible and supported to have for example two smaller and one larger vFPGA, allowing to maintain capabilities for more and less demanding user apps. 
* Use the virtual memory abstraction in combination with multi-tenancy and / or partial reconfiguration to sequentially execute complicated user applications: Coyote offers powerful memory abstractions for virtualized card memory on the FPGA. This means that any complicated user application can be split up in two or more separate logic blocks, which buffer their intermediate results in the HBM card memory. By either using space division through multi-tenancy in neighboring vFPGAs or time division through partial reconfiguration in the same vFPGA-slot different logic blocks can access these intermediate results in card memory can continue processing. 
* Use the network abstractions of Coyote to scale out applications across multiple nodes: For truly large-scale applications it's probably a good idea to combine the ideas mentioned above with a scale-out approach via the RoCE-v2 network capabilities of the shell design. In such a setup, intermediate results can be transferred via the network to a remote FPGA to continue processing there. 

#### Can my application have more than one input stream? 

#### Where can I find the synthesis and timing reports? 


## Systems Set-Up & Compatibility 

#### What are the system requirements for Coyote? 

#### Does Coyote work with NVIDIA GPUs? 


## Common Pitfalls: 

#### Please help me, my HLS module can't be found! 

#### Can I have single data transfers of buffers larger than 256MB? 

#### I got the following error message: "A LUT3 cell in the design is missing a connection on input pin I0, which is used by the LUT equation. This pin has either been left unconne cted in the design or the connection was removed due to the trimming of unused logic. The LUT cell name is (tie off signals)". What should I do now? 

#### Help me, my SW-compilation is failing! 


## Debugging

#### How can I query run-time statistics? How can I see what went wrong? 

#### What is an ILA? How can I start using ILAs? 
*Integrated Logic Analyzers* (ILAs), also referred to as *ChipScopes*, are a built-in utility that Vivado provides for FPGA-debugging. Speaking generally, these IP-cores can be placed anywhere in a digital design and get connected to signals of interest for debugging via probes. Based on triggering rules, these probed signals are then recorded and written to BRAM-memory. Vivado offers a GUI-interface to examine recorded signals similar to a digital oscilloscope (hence the name *ChipScopes*). It is a very powerful tool to trace FPGA-behaviour in the wild, during run-time, and especially useful if you are dealing with a major source of external non-determinism that can't be simulated in all it's complicatedness (most importantly: network interfaces). 
Placing and using an ILA in your Coyote set-up is a multi-step process that requires action both during build- and run-time: 
1) To begin with, an ILA needs to be instantiated in the suspicious Verilog-module, where it can be connected to all interesting signals via probes. Apart from these probes, it needs to be connected to the respective clock of that domain. A typical example where an ILA is hooked up to an AXI stream could look like the following: 
```Verilog
ila_axi_check inst_ila_axi_check (
    .clk(nclk),                         // Connection to system-clock
    .probe0(axis_host_recv[0].tvalid),  // Bit-Width: 1 
    .probe1(axis_host_recv[0].tready),  // Bit-Width: 1 
    .probe2(axis_host_recv[0].tdata),   // Bit-Width: 512
    .probe3(axis_host_recv[0].tkeep),   // Bit-Width: 64
    .probe4(axis_host_recv[0].tlast)    // Bit-Width: 1
); 
```
2) In a next step, this ILA-design has to be created in Vivado before starting the Coyote build process. There are in general two ways for doing this: 
    * ILAs can be added to the project via the Vivado GUI. For this purpose, open your design in Vivado, then select ``IP Catalog`` in the ``Project Manager``-tab (normally on the left of the window). Search for "ILA" in the now opened user interface, double click on ``ILA (Integrated Logic Analyzer)`` and wait until the configuration interface has loaded. First of all, set the correct ``Component Name`` according to your instantiation - in the example above, *ila_axi_check*. Then, enter the correct ``Number of Probes`` (5 in the example above) and set ``Input Pipe Stages`` to 2 to avoid timing problems. After that, you have to decide on your choice of ``Sample Data Depth``. The higher the value here, the more data (or more accurately: the longer time-stretch of data) you will be able to trace later, on the expense of BRAM-utilization. In a final step, click through the tabs with ``Probe_Ports(X..Y)`` and the correct bitwidth for every port according to your setup (1, 1, 512, 64, 1 accordingly in our example). Finally, click on OK and wait for the next context window. Here, you should select ``Out of context per IP`` as *Synthesis Option* and then click on ``Generate``. The ILA-IP will be built in the next few minutes and should then appear as properly instantiated and existing module in the ``Sources``-overview. 

#### My device is stuck, now what? 


## Miscellaneous

#### Should I *really* use a FPGA for my application? 

#### Do you have some inspiration on what can be done with Coyote? 

#### How can I contribute to Coyote? 

#### How should I cite you guys if I use Coyote in my academic work? 

#### What is the meaning of life, the universe, and everything? 

*42*.