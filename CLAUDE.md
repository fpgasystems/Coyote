# Coyote

## Introduction & motivation
Open-source FPGA shell/run-time for AMD Alveo U55C/U280/U250/U200 (UltraScale+) and V80 (Versal) FPGAs. It has three layers: static, dynamic (services) and application (vFPGAs), plus a Linux kernel driver and the C++ library libcoyote. 

Coyote simplifies the deployment of applications on FPGAs and the integration of FPGAs in complex computer systems by providing high-level abstractions: (1) a set of standard interfaces in so-called vFPGAs that can host arbitrary user applications; these interfaces allow user applications to interact with the host, memory and network, expose memory-mapped registers and raise interrupts, (2) a high-level, easy to use C++ runtime which allows host software to control user applications, (3) complete networking stacks in FPGA fabric (RoCEv2 RDMA, TCP/IP), which the apps can use to communicate with other nodes, (4) a memory virtualization layer that abstracts access to host, GPU and FPGA-side HBM memory, (5) the necessary functionality to reconfigure the FPGA on the fly and (6) low-level infrastructure plumbing (e.g, DMA logic).

## Start here
- Agent docs: @docs/agents/coyote_top.md. It maps every layer to its own doc (static, shell, MMU, memory, network, user, driver, software, sim, build, constraints).
- Known bugs: docs/agents/known_issues.md. Check it before assuming a feature works or before "fixing" behaviour that other code depends on.

## Stack
- HW: SystemVerilog, Vitis HLS and Tcl scripts driven by CMake. Top-level modules are implemented Jinja templates in `hw/templates/`, rendered at `make project`. `hw/services/network` is a git submodule containing the network stacks (HLS RoCE/TCP/IP). Supported Vivado versions: ≥ 2022.1 for UltraScale+, ≥ 2024.2 for Versal.
- Driver: Linux kernel module, C (GPL-2.0; the rest of the repo is MIT).
- SW: C++17 (libcoyote, `sw/`), with Boost. Minimum CMake version is 3.16.

## Conventions & rules
- The agents must not write overly complex or verbose code; the changes should be kept to the bare minimum to implement the target functionality or fix the bug. 
- The comments and documentation should be concise and human-readable, aligned with existing documentation and comments; overly verbose or long comments will be rejected by a human reviewer.
- Files under `*/LEGACY/` and boards u50/vcu118/enzian are unmaintained. Don't modify or reference them.
- Keep the license headers; the driver is GPL-2.0; the rest of the system is MIT. For new files, always add the licence header, the copyright holder (Systems Group, ETH Zurich), and the current year, like it is done in all existing files.
- git branch conventions: `bugfix/…`, `feature/…`, `docs/…`, `dev/…`. Only create a new branch when the human requests; don't create new branches autonomously.
- git commit conventions: conventional style (`fix(sw): …`, `docs(examples): …`), one logical change each. Never push to master. Only commit when human requests; never indepdently.
- When committing, never add yourself (Claude Code/Haiku/Opus/Sonnet) as commit co-author; use the `Assisted-by: AGENT_NAME[:MODEL_VERSION]` trailer format from `CONTRIBUTING.md`. Claude Code adds `Assisted-by: Claude Code` automatically via `.claude/settings.json`; do not add another.
- git PR conventions: by default, target `master` and use `.github/pull_request_template.md`. Only open a PR when a human requests it; never independently.
- Larger chages (more than one file, writing a new file, or affecting more than layer) must be planned first. Always develop a clear, step-by-step plan first, based on the human prompt, and present it to the human for review. The plan must also include steps on verifying the change (simulation, hardware run, how to observe the bug or performance change etc.)
- When necessary, update `docs/agents/` (and `docs/source/` where user-facing) so that the docs and the code stay consistent.
- Periodically, identify whether `CLAUDE.md` should be updated; especially when there are new, highly relavant gotchas. If yes, update but don't commit; human must review first. `CLAUDE.md` must not exceed 100 lines.

## Testing & compilation/synthesis checks

### Hardware
- To build the hardware (takes hours): `mkdir build_hw && cd build_hw && cmake ../hw -DFDEV_NAME=<u55c|u280|u250|v80> && make project && make bitgen`.
- Self-contained hardware changes can be validated with a testbench that reproduces the bug without the fix and confirms the fix solves the bug. For now, testbenches are not commited and must be kept seperate from the codebase (may change in the future once Coyote's testing & CI/CD infrastructure is improved). Check the simulator log, not just the exit code.

### Driver
- To build the driver `cd driver && make TARGET_PLATFORM=<ultrascale_plus|versal>` (default ultrascale_plus)
- When editing driver files, ensure the driver compiles without any new warnings or errors. 

### Software
- To build the software, compile Example 1 SW: `cd examples/01_hello_world/sw && mkdir build_test && cd build_test && cmake ../ && make`
- When editing software files, ensure the driver compiles without any new warnings or errors. 

### Examples
- Any changes to an example should be validated by running the example with the simulation framework, following instructions in: `sim/README.md` and `examples/README.md` (section Simulating the examples). The sim `cThread` supports one cThread per process. RDMA (Example 9), GPU memory (Example 6) and reconfiguration (Example 5) are unsupported in sim.

## Gotchas
- The static layer is a prebuilt locked checkpoint (`hw/checkpoints/`). Edits to `hw/hdl/static`, the static templates or `cr_pci.tcl` take effect only with `-DBUILD_STATIC=1`.
- Networking (`EN_RDMA`/`EN_TCP`/`EN_SNIFFER`) is a CMake fatal error on Versal. `EN_TCP` does not build as shipped, and the sniffer needs `EN_RDMA`.
- On Versal, `EN_PR=1` requires `EN_SHELL_PBLOCK=0`. You get shell PR or app PR, never both.
- In the app flow (`BUILD_APP`), shell parameters from `export.cmake` override any `-D` you pass.
- `N_REGIONS` ≤ 15: MSI-X vector 15 is reserved for reconfiguration.
- An SW build without `EN_AVX` hangs on an AVX shell. An `EN_AVX` SW build adapts at runtime.
- Examples 05 and 06 have no `hw/`; they reuse bitstreams from other examples (see their READMEs).
- Never hand-edit generated HDL in build dirs. Edit `hw/templates/*_tmplt.txt` or `hw/hdl/`. Template keys use the names in `scripts/base.tcl.in` (e.g. `n_reg`, not `n_regions`), and an unknown key silently renders empty.
- UltraScale+ and Versal differ: `hw/bd/{ultrascale_plus,versal}/`, `hw/templates/{ultrascale_plus,versal}/`, `{% if cnfg.fpga_arch == ... %}` in templates, `#ifdef PLATFORM_*` in the driver. Change and check both architectures, or state that a change is single-arch.
- A register change spans several layers that must stay in sync:
  - RTL: `hw/hdl/shell/cnfg_slave.sv` and `cnfg_slave_avx.sv`, and `shell_slave.sv`
  - Driver: register structs and offsets in `driver/include/coyote_defs.h`
  - SW: `CnfgAvxRegs` / `CnfgLegRegs` in `sw/include/coyote/cDefs.hpp`
  - Update all of them in the same change.
- `cThread`'s object layout must not depend on build macros (`EN_AVX`, etc.); see commit 97b26119. Do not add `#ifdef`-guarded data members to public classes.

## When compacting
Preserve the list of modified files, which architectures and layers they touch, build/sim commands used and their results, and any open known_issues IDs being worked on.

## Additional details & docs
- Project docs: @docs/source 
- Examples: @examples