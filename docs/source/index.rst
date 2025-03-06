.. cyt_docs documentation master file, created by
   sphinx-quickstart on Mon Apr 15 23:25:28 2024.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to Coyote, *the* open-source Operating System for FPGAs!
====================================

**Introduction: An OS for FPGAs**
------------------------------------

.. figure:: ../../img/Coyote_System_Overview.svg

``Coyote`` is our attempt to make the full potential of Field Programmable Gate Arrays (FPGAs) as accelerators in data processing available to all interested developers, no matter how much previous experience they have with digital design or computer architecture. One should think about Coyote as the Operating System for reconfigurable hardware: By taking care of the relevant system abstractions for networking (*100G RoCE v2*, *100G TCP / IP*), virtualized memory (*DRAM*, *HBM*) and PCIe-interaction with the host system (*CPU*, *GPU*) we strive to ease the mind of the developer and let them focus on the actual application logic. Coyote provides very clear and simple-to-use interfaces for both hardware and software, allowing everyone to leverage the mentioned abstractions for customized acceleration offloads.
Our central goal is to position Coyote as academic playground and empty canvas, yet deployment-ready platform alike for datacenters and cloud computing environments, focusing on the assembly of heterogeneous systems for efficient data processing in large scale, distributed applications. For this, Coyote can be whatever you as the developer want it to be: From a simple PCIe-accelerator card for stream offloads to a powerful AI-NIC with data preprocessing for LLM-serving to state-of-the-art GPUs - the only limiting factor is your creativity. 

Besides this concept of application acceleration plugged into standardized interfaces, we also like to promoto Coyote as a platform for detailed systems research: As mentioned above, the shell comes with many mechanisms known from commercial off-the-shelf hardware - from network to memory management. However, Coyote is open-source and there for you to play with all these components in order to evaluate new concepts of systems organization and management. If you're out there thinking about AI-enhanced page table walks or Quantum-encrypted network interfaces, Coyote is probably the place where your dreams become reality (or at least turn into a nice paper about why these late-night visions *did not* work as intended...). 

Finally, we are all in for open-source and community-driven development - that's why we are happy to share Coyote with you and hope that you will contribute to the project with your ideas, code and feedback. We are looking forward to see what you will make out of it!


**Motivation and Philosophy**
--------------------------------
The inspiration for ``Coyote`` comes from the drastic changes in the hardware landscape in large-scale computing: With the inevitable end of Moore's Law and Dennard Scaling, new generations of hardware do not promise the same performance improvements as before. Instead, the industry is moving towards domain-specific accelerators (DSA) that offer customize computing architectures for highly specialized tasks (https://dl.acm.org/doi/10.1145/3282307). FPGAs are key in this development, both as prototyping platforms for sophisticated ASIC-based accelerators and as highly-versatile and reconfigurable acceleration platforms for direct deployment. A crucial moment for this trend was reached when Microsoft made its *Project Catapult* (https://www.microsoft.com/en-us/research/project/project-catapult/) public, showcasing the potential of FPGAs as network accelerators for real-world usecases at hyperscale in their Azure-datacenters. 
While this general sentiment towards specialized hardware is shared by many academic and industrial observers of the field, working with such platforms still remains a major challenge for many developers: Due to many reasons, including the considerably smaller size of the community, FPGA-tooling is not up to the standard of modern software development, most relevant mechanisms are provided only as proprietary IP-cores by few major vendors and thus, many projects tend to "reinvent the wheel" when it comes to basic system abstractions. This obviously hinders the speed of innovation and adaption of new FPGA-based solutions in academic and industrial research. 
``Coyote`` aims directly at these well-known weaknesses of the ecosystem, providing a comprehensive, open-source and community-driven approach to hardware engineering for FPGA-based datacenter-accelerators. When using Coyote, developers can fully concentrate on the implementation of their application logic, leveraging the infrastructure abstractions provided by the shell. At the same time, all these abstractions are open-source and can be fully optimized and performance-tuned if deemed necessary, offering additional chances for new insights in computer systems composition. 
Finally, the community-focus of ``Coyote`` is chosen to create a modern townsquare, where FPGA-developers, system researchers and cloud computing engineers can gather to commonly contribute to the platform that can serve all their various purposes. As demonstrated by the striking success of other open-source projects, most notably obviously the Linux-kernel, open-source community projects can a decisive force in the development of future technologies and trends in the computing world.


.. toctree::
   :maxdepth: 2
   :caption: Quick Start

   quickstart/index

.. toctree::
   :maxdepth: 2
   :caption: Deploying Coyote in HACC

   hacc/index

.. toctree::
   :maxdepth: 2
   :caption: System Architecture

   system/static/index
   system/dynamic/index
   system/application/index
   system/vms/index

.. toctree::
   :maxdepth: 2
   :caption: Developer Guide

   developer/index

.. toctree::
   :maxdepth: 2
   :caption: Additional Info

   addinfo/index

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
