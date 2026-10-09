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

from coyote_test import fpga_stream, fpga_test_case, simulation_time

# Slots per ring: RDMA_N_WR_OUTSTANDING in lynx_pkg
N_SLOTS = 16
# 64-bit words per 512-bit beat
BEAT_WORDS = 8


def command(qp, read=False, ack=False, last=False):
    """One beat of the design's input (see src/vfpga_top.svh)"""
    return [qp | read << 8 | ack << 9 | last << 10] + [0] * (BEAT_WORDS - 1)


def admitted(qp, slot, read=False):
    """One beat of the design's output: a request rdma_flow admitted, and the slot it was given"""
    return [qp | read << 8 | slot << 16] + [0] * (BEAT_WORDS - 1)


class RdmaFlowTest(fpga_test_case.FPGATestCase):
    def test_each_qp_uses_its_own_ring(self):
        commands = []
        expected = []

        # QP 1 first, while QP 0 has nothing outstanding: slots 0, 1, 2 of its own ring
        for slot in range(3):
            commands += command(1)
            expected += admitted(1, slot)

        # QP 0 fills its WRITE ring
        for slot in range(N_SLOTS):
            commands += command(0)
            expected += admitted(0, slot)

        # QP 1 fills the rest of its ring, although QP 0's is full
        for slot in range(3, N_SLOTS):
            commands += command(1)
            expected += admitted(1, slot)

        # Two ACKs on QP 0 free two of its slots: the next two WRITEs wrap around to 0 and 1
        commands += command(0, ack=True) + command(0, ack=True)
        for slot in range(2):
            commands += command(0)
            expected += admitted(0, slot)

        # READs on QP 0 have a ring of their own
        for slot in range(3):
            commands += command(0, read=True)
            expected += admitted(0, slot, read=True)

        # One ACK on QP 1 frees one of its slots
        commands += command(1, ack=True) + command(1, last=True)
        expected += admitted(1, 0)

        self.set_stream_input(0, fpga_stream.Stream(fpga_stream.StreamType.UNSIGNED_INT_64, commands))
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.UNSIGNED_INT_64, expected))
        self.overwrite_simulation_time(
            simulation_time.SimulationTime.fixed_time(20, simulation_time.SimulationTimeUnit.MICROSECONDS)
        )

        self.simulate_fpga()

        self.assert_simulation_output()
