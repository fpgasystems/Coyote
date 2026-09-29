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

import random

from coyote_test import fpga_stream, fpga_test_case, simulation_time

# 64-bit words per 512-bit beat, and the tdata bits the design carries (src/vfpga_top.svh)
BEAT_WORDS = 8
CARRIED_BITS = 408


class MetaWidthTest(fpga_test_case.FPGATestCase):
    def test_every_width_carries_its_data(self):
        rng = random.Random(0)
        beats = 32
        data = [rng.getrandbits(64) for _ in range(beats * BEAT_WORDS)]
        expected = []
        for i, word in enumerate(data):
            carried = max(0, min(64, CARRIED_BITS - (i % BEAT_WORDS) * 64))
            expected.append(word & ((1 << carried) - 1))

        self.set_stream_input(0, fpga_stream.Stream(fpga_stream.StreamType.UNSIGNED_INT_64, data))
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.UNSIGNED_INT_64, expected))
        self.overwrite_simulation_time(
            simulation_time.SimulationTime.fixed_time(20, simulation_time.SimulationTimeUnit.MICROSECONDS)
        )

        self.simulate_fpga()

        self.assert_simulation_output()
