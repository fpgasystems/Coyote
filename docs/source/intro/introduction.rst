Introduction
=====================================

Coyote is an open-source shell which aims to facilitate the deployment of FPGAs in datacenters and cloud systems. 
One could think of Coyote as an OS for FPGAs, taking care of standard system abstractions for multi-tenancy, multi-threading, reconfiguration, networking (*100G RoCE v2*, *100G TCP/IP*), virtualized memory (*DRAM*, *HBM*) and PCIe interaction with other hardware (*CPU*, *GPU*). 
Generally speaking, Coyote strives to simplify the application deployment process and enable developers to solely focus on their application logic and its performance, rather than infrastructure plumbing.
By providing clear and simple-to-use interfaces in both hardware and software, Coyote allows everyone to leverage the mentioned abstractions for customized acceleration offloads and 
build distributed and heterogeneous computer systems, consisting of many FPGAs, GPUs and CPUs. Some examples of such systems would be AI SmartNICs or heterogeneous database engines. 

Motivation
---------------
The inspiration for Coyote comes from the drastic changes in the hardware landscape of datacenter and cloud computing.
With the inevitable end of Moore's Law and Dennard Scaling, new generations of hardware do not promise the same performance improvements as before. 
Instead, computer systems are moving towards domain-specific accelerators (DSA) that offer customized computing architectures for highly specialized tasks `(1) <https://dl.acm.org/doi/10.1145/3282307>`_. 
FPGAs, in particular, were key in this development, both as prototyping platforms for sophisticated ASIC-based accelerators and as highly versatile and reconfigurable accelerators for direct deployment. 
A great example of this trend was Microsoft's `Project Catapult <https://www.microsoft.com/en-us/research/project/project-catapult/>`_, showcasing the potential of FPGAs as network accelerators for real-world usecases at hyperscale in their Azure datacenters. 


However, FPGA tooling and infrastructure is not up to the standard of modern software development, leading many projects to "reinvent the wheel" when it comes to basic system abstractions and infrastructure. 
Coyote aims directly at these well-known weaknesses of the ecosystem, providing a comprehensive, open-source and community-driven approach to abstractions on FPGAs. 
When using Coyote, developers can fully concentrate on the implementation of their application logic, leveraging the infrastructure abstractions provided by the shell. 
At the same time, all these abstractions are open-source and can be optimized if deemed necessary, offering new insights in computer systems. 



