<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="img/cyt_logo_dark.png" width = 450>
    <source media="(prefers-color-scheme: light)" srcset="img/cyt_logo_light.png" width = 450>
    <img src="img/cyt_logo_light.png" width = 600>
  </picture>
</p>

[![Documentation Status](https://github.com/fpgasystems/Coyote/actions/workflows/build_docs.yaml/badge.svg?branch=master)](https://fpgasystems.github.io/Coyote/)
[![Build benchmarks](https://github.com/fpgasystems/Coyote/actions/workflows/build_hls.yaml/badge.svg?branch=master)](https://github.com/fpgasystems/Coyote/actions/workflows/build_hls.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# _An operating system for FPGAs_
Coyote is an open-source shell which aims to facilitate the deployment of FPGAs in datacenters and cloud systems. One could think of Coyote as an OS for FPGAs, taking care of standard system abstractions for multi-tenancy, multi-threading, reconfiguration, networking (RDMA, TCP/IP), virtualized memory (DRAM, HBM) and PCIe interaction with other hardware (CPU, GPU). Generally speaking, Coyote aims to simplify the application deployment process and enable developers to solely focus on their application and its performance, rather than infrastructure development. By providing clear and simple-to-use interfaces in both hardware and software, Coyote allows everyone to leverage the mentioned abstractions for customized acceleration offloads and build distributed and heterogeneous computer systems, consisting of many FPGAs, GPUs and CPUs. Some examples of such systems would be [distributed recommender systems](https://www.usenix.org/conference/osdi24/presentation/he), [AI SmartNICs](https://arxiv.org/pdf/2501.12032) or [heterogeneous database engines](https://www.research-collection.ethz.ch/bitstream/handle/20.500.11850/586069/3/p11-korolija.pdf).

## Motivation
The inspiration for Coyote comes from the drastic changes in the hardware landscape of datacenter and cloud computing. With the inevitable end of Moore’s Law and Dennard Scaling, new generations of hardware do not promise the same performance improvements as before. Instead, computer systems are moving towards domain-specific accelerators that offer customized computing architectures for highly specialized tasks. FPGAs, in particular, were key in this development, both as prototyping platforms for sophisticated ASIC-based accelerators and as highly versatile and reconfigurable accelerators for direct deployment. 

However, FPGA tooling and infrastructure is not up to the standard of modern software development, leading many projects to “reinvent the wheel” when it comes to basic system abstractions and infrastructure. Coyote aims directly at these well-known weaknesses of the ecosystem, providing a comprehensive, open-source and community-driven approach to abstractions on FPGAs. When using Coyote, developers can fully concentrate on the implementation of their applications, leveraging the infrastructure abstractions provided by the shell. At the same time, all these abstractions are open-source and can be optimized if deemed necessary, offering insights in future computer systems.

## Features
Some of Coyote's features include:
 * Support for both RTL and HLS user applications
 * Easy-to-use software API in C++
 * Python run-time with [pyCoyote](https://github.com/fpgasystems/pyCoyote)
 * Multiple isolated, virtualized user applications (vFPGAs)
 * Shared virtual memory between the FPGA, host CPU and other accelerators (e.g. GPUs)
 * Networking services: 100G RoCE-v2 compatible RDMA, TCP/IP and collectives
 * Automatic instantiation of card memory controllers (HBM/DDR) and memory striping
 * Dynamic run-time reconfiguration of user applications and services
 * Simulation environment with seamless simulation target for software code and Python unit test framework

<p align="center"
 <picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/cyt_ov_dark.png" width = 620>
  <source media="(prefers-color-scheme: light)" srcset="img/cyt_ov_light.png" width = 620>
  <img src="img/cyt_ov_light.png" width = 620>
</picture>
</p>

# Documentation & Examples

The recommended way to get started with Coyote is by going through the various [examples and tutorials](https://github.com/fpgasystems/Coyote/tree/master/examples), which cover hardware design, the software API, data movement, reconfiguration, networking etc. 

For video recordings covering Coyote's features, walk-through tutorials and live demos, check out our [tutorial at ASPLOS 2025](https://systems.ethz.ch/research/data-processing-on-modern-hardware/hacc/asplos25-tutorial-fpgas.html).

Examples on Coyote's Python run-time, pyCoyote, can be found in the [corresponding repository](https://github.com/fpgasystems/pyCoyote).

Additional details on Coyote's features and internals can be found in the [documentation](https://fpgasystems.github.io/Coyote/).

# Getting started
## Prerequisites
- **Linux**: For the basic Coyote functionality, Linux >= 5 is sufficient. Coyote has been extensively tested with Linux 5.4, Linux 5.15, Linux 6.2 and Linux 6.8.
- **CMake**: CMake >= 3.5 with support for C++17.
- **Vivado & Vitis**: Coyote has to be built with the full Vivado suite, including Vitis HLS. Coyote supports Vivado/Vitis HLS >= 2022.1. We have conducted extensive testing with Vivado 2024.1 and 2022.1, though others should work as well. All network-related Coyote configurations are built using the UltraScale+ Integrated 100G Ethernet Subsystem, for which a valid license must be obtained.
- **FPGA**: The main target platform for the current Coyote release is the AMD Alveo U55C accelerator card, Additionally, Coyote also supports and has extensively been tested on Alveo U250 and Alveo U280.

Additional requirements for certain features (e.g. GPU peer-to-peer) are covered in the respective example covering the feature.

## Download
Clone the repo and all its submodules:
```bash
git clone --recurse-submodules https://github.com/fpgasystems/Coyote
```

## Getting-started examples
The various Coyote examples can be found [here](https://github.com/fpgasystems/Coyote/tree/master/examples), which cover hardware design, the software API, data movement, reconfiguration, networking etc. 

# FAQ & Discussions

List of frequently asked questions and answers to common issues can be found on the [FAQ page](https://fpgasystems.github.io/Coyote/intro/faq.html).

If you have any questions, comments, or ideas regarding Coyote or just want to show us how you use Coyote, don't hesitate to reach us through the [discussions tab](https://github.com/fpgasystems/Coyote/discussions).

# Citation

If you use Coyote, please cite us:

```bibtex
@inproceedings{coyote_v2,
    author = {Ramhorst, Benjamin and Korolija, Dario and Heer, Maximilian Jakob and Dann, Jonas and Liu, Luhao and Alonso, Gustavo},
    title = {Coyote v2: Raising the Level of Abstraction for Data Center FPGAs},
    year = {2025},
    isbn = {9798400718700},
    publisher = {Association for Computing Machinery},
    address = {New York, NY, USA},
    url = {https://doi.org/10.1145/3731569.3764845},
    doi = {10.1145/3731569.3764845},
    booktitle = {Proceedings of the ACM SIGOPS 31st Symposium on Operating Systems Principles},
    pages = {639–654},
    numpages = {16},
    keywords = {FPGA, shell, heterogeneous systems},
    location = {Lotte Hotel World, Seoul, Republic of Korea},
    series = {SOSP '25}
}

@inproceedings{coyote,
    author = {Dario Korolija and Timothy Roscoe and Gustavo Alonso},
    title = {Do {OS} abstractions make sense on FPGAs?},
    booktitle = {14th {USENIX} Symposium on Operating Systems Design and Implementation ({OSDI} 20)},
    year = {2020},
    pages = {991--1010},
    url = {https://www.usenix.org/conference/osdi20/presentation/roscoe},
    publisher = {{USENIX} Association}
}
```

and if you use Coyote's networking stack, BALBOA, please cite the following work:
```bibtex
@misc{balboa,
    title={RoCE BALBOA: Service-enhanced Data Center RDMA for SmartNICs}, 
    author={Maximilian Jakob Heer and Benjamin Ramhorst and Yu Zhu and Luhao Liu and Zhiyi Hu and Jonas Dann and Gustavo Alonso},
    year={2025},
    eprint={2507.20412},
    archivePrefix={arXiv},
    primaryClass={cs.AR},
    url={https://arxiv.org/abs/2507.20412}, 
}
```
# License
Most of Coyote code is licensed under the terms in [LICENSE](https://github.com/fpgasystems/Coyote/blob/master/LICENSE.md), which corresponds to the MIT Licence.
An exception to this is the Coyote device driver, which is open-sourced with the GPL v2 license. 
Any contributions to Coyote will be accepted under the same terms of license.
