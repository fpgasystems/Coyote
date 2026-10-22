## Description
> :memo: Please include a summary of the change; what does this change do, and why? Include the motivation, context, and any new dependencies.

## Type of change
> :memo: Please select one that best describes the PR:
- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change
- [ ] Documentation update
- [ ] Build, CI or tooling infrastructure
- [ ] Code refactor & cleanup (no functional change)
- [ ] A new research paper code implementation
- [ ] Other

## Layers affected
> :memo: Please select all layers of the system that are affected by this PR:
- [ ] Hardware
- [ ] Driver
- [ ] Sofware
- [ ] Examples & docs
- [ ] Simulation
- [ ] Build scripts

## Tests & results
> :memo: Please describe the tests that you ran to verify your changes. 

**Test configuration:** Include details on your configuration, including if it was tested on hardware (and which FPGA) or in simulation, the OS and Vivado version, and any other relavant configuration details (e.g., CMake, gcc version).

**Bug fixes:** For PRs fixing a bug, clearly describe how to reproduce the bug on the `main` branch of Coyote and add any relavant logs (e.g., dmesg output, sysfs statistics, debug prints from software, SV testbench or ILA waveforms, gdb/valgrind outputs etc.). Include the same logs following the fix. Don't commit the logs to the code base; instead add them to the PR description.

**Performance:** For changes affecting performance-critical data and control paths (e.g., networking modules, software polling, memory accesses etc.), include performance results (throughput, latency) before and after the PR. The PR description should include any necessary logs and/or scripts to recreate the results, which are not commited to the code base, but uploaded with the PR.

## Breaking changes and migration
> :memo: Delete section if not a breaking change; otherwise describe what parts of the system are affected.

**What breaks:**

**How users migrate:**

## AI assistance disclosure

<!--
REQUIRED: Coyote welcomes AI-assisted contributions. We ask two things in
return: disclose the assistance here, and own the result. 

Do not credit AI tools as authors in commit metadata, as authorship carries
copyright and responsibility, neither of which a tool can hold. 
Some assistants automatically add `Co-Authored by`
automatically; please remove them before opening the PR.

The section below is adapted from the hls4ml
pull request template (https://github.com/fastmachinelearning/hls4ml),
licensed under the Apache License 2.0
(https://www.apache.org/licenses/LICENSE-2.0). Modified for Coyote.
-->

- [ ] **None** — no AI tool was used.
- [ ] **Assisted** — completion, refactoring, docstrings, tests; design and code are mine.
- [ ] **Substantial** — significant AI-generated portions, reviewed and edited by me.
- [ ] **Agentic** — produced largely end-to-end by an AI agent from my prompts.

Tool(s) and model(s): <!-- e.g. Claude Code (Opus 4.5), GitHub Copilot, Cursor, Codex -->

If anything other than *None* is ticked, confirm all of the following:

- [ ] **I am the author of this contribution and take full responsibility for it.** I have read the code and can explain it during code review.
- [ ] I verified the generated code against Coyote semantics, and, to the best of my knowledge, it does not introduce any unexpected bugs or behaviours.
- [ ] All numbers, logs and test results quoted in this PR come from runs I actually performed, not from an agent output.
- [ ] I have the right to submit this work under the project's licence, and, to my knowledge, it does not reproduce third-party code that would conflict with it.
- [ ] No AI tool is credited as an author in any commit of this branch.

## Checklist
**Required:**
- [ ] I have read the [contributing guidelines](https://github.com/fpgasystems/Coyote/blob/master/CONTRIBUTING.md).
- [ ] I self-reviewed the full diff and it contains no leftover debug code, commented-out blocks or unrelated changes.
- [ ] The AI assistance disclosure above is complete and accurate.

**For changes in hardware:**
- [ ] I have synthesized the relavant bitstreams and checked that (1) no new critical warnings are generated and (2) the design closes timing.
- [ ] I have verified functionality by running an example or an application on a real FPGA.

**For changes in the driver/software:**
- [ ] I have verified that my changes generate no new compiler warnings or errors.

**For changes in the examples:**
- [ ] I have validated my changes by running the examples against the simulator backend or on real FPGAs and confirming the expected behaviour and outputs (no errors and crashes, line-rate performance for perf. examples etc.)

**If applicable:**
- [ ] I have commented my code and made corresponding changes to the documentation. The comments/docs are not excessive or overly verbose and are easily understandable by humans.
