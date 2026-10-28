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

"""Python unit test of example 4 (user interrupts): the vFPGA sends interrupt (pid 0, value 73)
for each host stream beat whose first integer is 73 (examples/04_user_interrupts/hw/src/vfpga_top.svh).

Run from a hardware build of examples/04_user_interrupts configured with
-DUNIT_TEST_DIR=<coyote>/sim/unit_test/examples/04_user_interrupts:

    PYTHONPATH=<hw build>:<coyote>/sim python3 -m unittest discover -s <coyote>/sim/unit_test/examples/04_user_interrupts

With COYOTE_SIM_VERILATOR=1 the test runs the Verilator binary of sim/vl/build.sh instead of xsim.
"""

from coyote_test import fpga_test_case, fpga_stream, io_writer, simulation_time

Stream, StreamType = fpga_stream.Stream, fpga_stream.StreamType
CoyoteOperator = io_writer.CoyoteOperator
SimulationTime, SimulationTimeUnit = simulation_time.SimulationTime, simulation_time.SimulationTimeUnit

# 16 integers of 4 bytes: one 64 B beat of the host stream
BEAT_INTS = 16


class UserInterruptsTestCase(fpga_test_case.FPGATestCase):
    def setUp(self):
        super().setUp()
        self.overwrite_simulation_time(SimulationTime.fixed_time(20, SimulationTimeUnit.MICROSECONDS))
        self.interrupts = []
        self.get_io_writer().register_interrupt_handler(self._on_interrupt)

    def _on_interrupt(self, pid: int, value: int):
        self.interrupts.append((pid, value))

    def _run(self, batches):
        """
        Sends each batch on host stream 0, waits until the vFPGA took all of them and returns the interrupts.
        The testbench writes an interrupt to the output pipe in the cycle of its beat, before the completion
        of that transfer, so all interrupts are in the queue when the completions are.
        """
        for batch in batches:
            self.set_stream_input(0, Stream(StreamType.SIGNED_INT_32, batch))

        end_event = self.simulate_fpga_non_blocking()
        self.get_io_writer().block_till_completed(CoyoteOperator.LOCAL_READ, len(batches), end_event)
        self.get_io_writer().all_input_done()
        self.finish_fpga_simulation()

        # The handler runs on the interrupt thread of the io writer, after the output thread.
        self.get_io_writer().wait_for_interrupt_handlers()
        return self.interrupts

    def test_interrupt_on_73_only(self):
        first = [73] + list(range(1, BEAT_INTS))
        second = [1024] + list(range(1, BEAT_INTS))

        self.assertEqual(self._run([first, second]), [(0, 73)])

    def test_no_interrupt_for_73_outside_word_0(self):
        beat = [1, 73] + list(range(2, BEAT_INTS))

        self.assertEqual(self._run([beat]), [])

    def test_interrupt_on_second_beat(self):
        data = list(range(BEAT_INTS)) + [73] + list(range(1, BEAT_INTS))

        self.assertEqual(self._run([data]), [(0, 73)])
