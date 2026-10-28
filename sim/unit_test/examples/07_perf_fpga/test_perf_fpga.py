######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

"""Python unit test of example 7 (perf FPGA): the vFPGA reads or writes a host buffer n_reps times on its own
(sq_rd / sq_wr) and counts the beats (examples/07_perf_fpga/hw/src/vfpga_top.svh).

The throughput and the latency of the example depend on the simulation speed of the host, so the
tests check what does not:
- DONE becomes 1, which needs the completion of the last request.
- TIMER is at least the number of beats, because a stream moves at most one beat per cycle.
- Read: a second run completes. The FSM goes back to idle only after all n_beats beats, so the second
  start pulse is lost when the first run counted fewer beats.
- Write: the vFPGA sends the beat counter plus one as the data of each beat, so the buffer holds the
  counter of the last repetition.

Run from a hardware build of examples/07_perf_fpga configured with
-DUNIT_TEST_DIR=<coyote>/sim/unit_test/examples/07_perf_fpga:

    PYTHONPATH=<hw build>:<coyote>/sim python3 -m unittest discover -s <coyote>/sim/unit_test/examples/07_perf_fpga

With COYOTE_SIM_VERILATOR=1 the test runs the Verilator binary of sim/vl/build.sh instead of xsim.
"""

from enum import IntEnum

from coyote_test import constants, fpga_register, fpga_test_case, simulation_time

vFPGARegister = fpga_register.vFPGARegister
SimulationTime, SimulationTimeUnit = simulation_time.SimulationTime, simulation_time.SimulationTimeUnit
BYTE_ORDER = constants.BYTE_ORDER

BEAT_BYTES = 64


# The register map of perf_fpga_axi_ctrl_parser.sv (and BenchmarkRegisters of sw/src/main.cpp)
class Reg(IntEnum):
    CTRL = 0
    DONE = 1
    TIMER = 2
    VADDR = 3
    LEN = 4
    PID = 5
    N_REPS = 6
    N_BEATS = 7


START_RD = 0x1
START_WR = 0x2


def register(id: int, value: int) -> vFPGARegister:
    return vFPGARegister(id, bytearray(value.to_bytes(8, BYTE_ORDER)))


class PerfFpgaTestCase(fpga_test_case.FPGATestCase):
    def setUp(self):
        super().setUp()
        # Long enough for the Python round trips between the runs; a hang ends here and fails the test.
        self.overwrite_simulation_time(SimulationTime.fixed_time(1, SimulationTimeUnit.MILLISECONDS))

    def _bench(self, vaddr: int, size: int, n_reps: int, oper: int, runs: int):
        """
        Starts `runs` benchmark runs one after the other, as sw/src/main.cpp does.
        Returns (DONE, TIMER) of each run; None for a value that the simulation did not return before its end.
        """
        n_beats = n_reps * ((size + BEAT_BYTES - 1) // BEAT_BYTES)
        results = []
        end_event = self.simulate_fpga_non_blocking()
        for _ in range(runs):
            for reg, value in ((Reg.VADDR, vaddr), (Reg.LEN, size), (Reg.PID, 0),
                               (Reg.N_REPS, n_reps), (Reg.N_BEATS, n_beats), (Reg.CTRL, oper)):
                self.write_register(register(reg, value))
            # The testbench polls until DONE is 1; the read after it tells a hit from the end of the simulation.
            self.get_io_writer().ctrl_poll(register(Reg.DONE, 1), end_event)
            results.append((self.read_register(Reg.DONE, end_event), self.read_register(Reg.TIMER, end_event)))
        self.get_io_writer().all_input_done()
        self.finish_fpga_simulation()
        return n_beats, results

    def test_read_twice(self):
        size, n_reps = 1024, 4
        vaddr = self.get_io_writer().allocate_and_write_to_next_free_sim_memory(
            bytearray(i % 256 for i in range(size)))

        n_beats, results = self._bench(vaddr, size, n_reps, START_RD, runs=2)

        for run, (done, timer) in enumerate(results):
            self.assertEqual(done, 1, f"run {run}: DONE")
            self.assertGreaterEqual(timer, n_beats, f"run {run}: TIMER")

    def test_write_beat_counter(self):
        size, n_reps = 1024, 2
        vaddr = self.get_io_writer().allocate_next_free_sim_memory(size)

        n_beats, results = self._bench(vaddr, size, n_reps, START_WR, runs=1)

        ((done, timer),) = results
        self.assertEqual(done, 1, "DONE")
        self.assertGreaterEqual(timer, n_beats, "TIMER")
        # Every repetition writes the same buffer: the last one leaves beat b with the counter value
        # (n_reps - 1) * beats per repetition + b + 1 in bytes 0 to 7, zero in the other bytes.
        beats_per_rep = n_beats // n_reps
        expected = bytearray()
        for b in range(beats_per_rep):
            expected += ((n_reps - 1) * beats_per_rep + b + 1).to_bytes(BEAT_BYTES, BYTE_ORDER)
        self.assertEqual(self.get_io_writer().read_from_sim_memory(vaddr, size), expected)
