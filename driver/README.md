# Coyote driver

## Overview
The Coyote device driver is a vital component of Coyote; it operates within the Linux kernel, serving as an intermediary between the low-level hardware operation implemented on the FPGA and user-facing software API. The driver creates standard Linux char devices and exposes standard system calls, enabling communication between user space and the driver through calls like `open`, `close`, `mmap`, and `ioctl`. Its responsibility is three-fold. First, it sets up the Coyote-enabled FPGA as a PCI device, memory mapping registers, enabling MSI-X interrupts and initializing the (X)DMA core. Second, it manages vFPGAs, handling tasks such as register mappings, interrupts, page faults, TLB states etc. Finally, it manages dynamic reconfiguration. 

## Devices
The Coyote implements two classes of devices, one for virtual FPGAs (```vfpga_device```) and for reconfiguration (```reconfig_device```).

#### Virtual FPGA devices
The driver creates one instance of ```vfpga_device``` for each vFPGA (region) in hardware and implements the following functionality:
- Assign a Coyote thread with a given ID (from the user-facing software API) to a given vFPGA
- Interrupt handlers, which process incoming interrupts for DMA off-loads and sync; TLB invalidations, page faults and user interrupts (notifications)
- Memory management, which can map user pages into the vFPGA's TLBs, attach DMA Buffers for peer-to-peer transfers to GPUs etc.
- State management, by writing to specific memory mapped registers, which trigger the corresponding operations on the FPGA.

#### Reconfiguration device
The driver creates one instance of ```reconfig_dev``` per FPGA, which implements the following functionality:
- Allocating buffers in kernel space that can be used to hold the partial bitstream to be loaded onto the FPGA.
- Triggering reconfiguration by transferrint the parital bitstream buffers to the FPGA and setting the correct control registers
- Interrupt handlers, which process incoming interrupts that indicate a reconfiguration is complete.

## Folder structure & Documentation
Broadly speaking, the following files and folders make up the Coyote driver:
- ```ìnclude```: Contains the header files of the Coyote driver; further broken down into ```vfpga```, ```reconfig``` and ```ìnterconnect```. Each header file includes extensive documentation about the functions and variables in standard Doxygen form. This documentation should be the first point of reference about the driver.
- ```src```: Contains the implementation of the above-defined headers. Harder-to-understand functions and complex code segments include comments, but Coyote's approach is to write smaller, self-contained functions that can be fully explained by the docstring in the accompanying headers.
- ```LEGACY```: Contains previously supported driver features that are no longer supported in Coyote but can act as reference points for advanced users and new features. Currently included are the functions for loading Coyote on Enzian with the Enzian Coherent Interconnect (ECI) and support for implementing unified virtual memory using Linux's Heteregenous Memory Management (HMM) mechanism. Coyote still supports shared virtual memory between the CPU, GPU and FPGA using the paging mechanism (implemented in ```include/vfpga/vfpga_gup.h```and ```src/vfpga/vfpga_gup.c```)

A closer look at the Coyote driver implementation per file:
- ```coyote_driver```: Top-level Coyote driver functions; used for loading and removing the driver
- ```coyote_sysfs```: Coyote sysfs; which can be used for querying device properties (IP, MAC etc.) and run-time characteristics (number of transfers, packet drops). The available sysfs entries can be found in ```/sys/kernel/coyote_sysfs_0/``` and each of these attribtues can be queries using the simple ```cat``` command.
- ```coyote_setup```: Used for allocating and initializing the vFPGA and reconfiguration devices when the driver is first loaded. However, no platform/interconnect-specific functionality is implemented in this file.

- ```platform```: Implements platform/interconnect specific functionality for loading and removing the Coyote driver.
    * ```pci_xdma```: PCI-specific functions for loading a Coyote-enabled FPGA synthesized with the XDMA core. Functions in this file map the XDMA BARs into the OS's  memory space, enable XDMA interrupts and set up the DMA (host-to-card, card-to-host) channels. 
    * ```pci_util```: Implements generic (non-DMA specific) utility functions for PCI systems, for e.g., checking whether MSI-X is available on the system or enabling certain PCI capabilities (e.g., relaxed transaction ordering).

- ```vfpga```: 
    * ```vfpga_gup:```: Implements the paging memory mechanism of vFPGAs, which handles page faults, buffer migrations and interaction with DMA Buffers to peer-to-peer transactions with GPUs.
    * ```vfpga_hw```: Implements low-level hardware operations that set/clear specific memory-mapped registers depending on the target operation 
    * ```vfpga_isr```: Handles all vFPGA-specific interrupts, which include (in order of importance): (1) Notification of off-load/sync completed, (2) TLB invalidation completed, (3) Page fault and (4) User-issued interrupts (notifications). 
    * ```vfpga_ops```: Implements standard device file operations:  `open`, `close`, `mmap`, and `ioctl`. Of particular interest are the IOCTL calls which leverage the other files in this category to implement user-facing functionality. For each IOCTL call, there is a corresponding docstring indicating its purpose, arguments and return variables.
    * ```vfpga_uisr```: Handles user-issued interrupts (notifications) from a vFPGA. For an example of how user interrupts are used in Coyote, check out Example 4.


- ```reconfig```:
    * ```reconfig_mem```: Allocates kernel-space buffers to hold the partial bitstreams to be loaded onto the FPGA
    * ```reconfig_hw```: Functions for trigger the reconfiguration by writing to memory-mapped registers which control the reconfiguration process.
    * ```reconfig_isr```: Interrupt handling for when the reconfiguration has been completed.
    * ```reconfig_ops```: Implements standard device file operations:  `open`, `close`, `mmap`, and `ioctl`. Of particular interest are the IOCTL calls, which include ```ÌOCTL_RECONFIGURE_SHELL``` and ```ÌOCTL_RECONFIGURE_APP```.

## Using the driver
The driver works exclusively with the Linux kernel. While no asssumptions are made about the OS (e.g., Ubuntu, Debian, RHEL), we have tested the Coyote driver extensively on Ubuntu 22.04 and Ubuntu 24.04 with the following Linux kernel versions: 5.4, 5.15, 6.2 and 6.8. Other versions of Linux (>= 5) should also work, though they have not been tested by the Coyote team.

The driver can be compiled using the ```make``` which will generate a loadable driver inside the ```build``` folder called ```coyote_driver.ko```. This driver can be inserted using the ```ìnsmod``` command. Additionally, when loading the driver, users should specify any run-time variables, such as FPGA IP and MAC address. The available variables are documented in ```src/coyote_driver.c```


## Recommended reading
If you are new to programming device drivers, a good resource to get started is "Linux Device Drivers" by Jonathan Corbet, Alessandro Rubini, and Greg Kroah-Hartman. Material covered in that book should give sufficient background to work on the Coyote device driver.

## Licence
The Coyote device driver (and all files within the driver folder) are open-source with a General Purpose Licence (GPL), version 2. A copy of the GPL v2 licence can be found in the COPYING file or online at: https://www.gnu.org/licenses/. All contributions will be accepted under the same license.