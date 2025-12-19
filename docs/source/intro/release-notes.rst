Release notes
=====================================

v0.2.1 - centovalli
------------------------------------

Coyote v0.2.1 includes the following fixes and features:
    - Support for FPGA - GPU DMA without host involvement

    - A fully RoCEv2-compatible, 100G RDMA stack

    - An extensive simulation infrastructure, which allows the verification of vFPGAs with the same code, both on the host and in hardware
    
    - Integration with Python unit tests

    - 10 getting-started examples, including video tutorials, and improved documentation

    - Improved run-time scheduler and a more robust background service

    - Various bug fixes for:

        - User interrupts
        - Memory virtualisation with card memory
        - Partial reconfiguration build flow dependencies
        - Multiple RDMA connections & support for large message size
        - Clock domain crossing between user, networking and static regions
        - HBM splitting for non-U55C platforms
