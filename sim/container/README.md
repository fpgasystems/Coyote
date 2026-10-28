# Simulation container

A container that runs the Coyote simulation of one example under Verilator. No Vivado is needed, also not to build it: `sim/vl/configure.sh` makes the hardware build folder of the example, and the Xilinx IP of the example comes from the models in `sim/vl/models/`.

One of:

```bash
apptainer build --fakeroot --build-arg COYOTE=<coyote> coyote-sim.sif <coyote>/sim/container/coyote-sim.def
apptainer run --writable-tmpfs coyote-sim.sif -X 1024 -r 1 -s 0

docker build -f sim/container/Dockerfile -t coyote-sim <coyote>
docker run --rm coyote-sim -X 1024 -r 1 -s 0
```

The build argument `EXAMPLE` (default `examples/01_hello_world`) selects another example: its `hw` and `sw` folders. Both builds call `install.sh`. The run calls `run.sh`: the host program, then the Python tests of the example in `sim/unit_test/examples/<example folder>` under Verilator, if that folder exists. The default host program arguments are the ones of example 1; give the arguments of the other examples explicitly.

Example 12 (SpinalHDL) also needs `sbt` and Java 11 or newer at build time. The image does not have them. The CI job `.github/workflows/run_simulation_verilator.yaml` runs examples 1, 4, 7 and 12 with the same `install.sh` on a GitHub-hosted runner.

The build takes about 10 minutes and the run about 30 seconds, because the Python flow builds its own testbench binary on the first run.
