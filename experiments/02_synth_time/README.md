# 9.2. Synthesis Time with Nested Build Flow

This directory contains the software and hardware source code for the results of Section 9.2. of the SOSP paper: *Coyote v2: Raising the Level of Abstraction for Data Center FPGAs*.

In this particular experiment, we evaluate Coyote's ability to synthesize hardware faster, due to its nested build flow.
Namely, for a given shell configuration, one can only synthesize the application and link it with an existing, locked shell.
The specifics of this process are described in the paper.

To demonstrate the results, this directory contains the three applications from the paper: (1) simple pass-through kernel, (2) vector addition from memory and (3) RDMA networking with AES encryption. The utility script, `run_synth.py` can be used to 
run hardware synthesis for all three examples. Additionally, it records the time taken for each synthesis. The mode (shell or app)
can be changed through the constant `MODE` in `run_synth.py`.

**NOTE:** To use the app build flow, one must provide a pre-routed and locked shell checkpoint and its configuration (as explained in the paper). The easiest way of obtaining these is to use the `gen_shell_checkpoints.py` scripts. Then, when running the app flow, for each of the three examples (`perf_local`, `mem_vadd`, `rdma_aes`), it is necessary to have the following files (in the correct path as well):
- `shells/<example-id>/export.cmake` which can be found in a file with the same name in the corresponding *shell* flow build
- `shells/<example-id>/checkpoints/shell_routed_locked.dcp` which can be found in a file with the same name in the corresponding *shell* flow build folder, under `checkpoints`.

**NOTE:** These experiments are conducted on an Alveo u250. If targetting other devices, an appropriate floorplan must be provided.
