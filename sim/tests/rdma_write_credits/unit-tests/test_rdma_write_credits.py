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

# 64-bit words per 512-bit beat
BEAT_WORDS = 8
LAST = 1 << 63
WHOLE_PAYLOAD = 1 << 32

# Payload lengths in bytes: partial last beats (2948 is 46 full beats and 4 B), exact multiples of
# the 64 B beat, and lengths shorter than one beat
LENGTHS = [2948, 64, 100, 30, 4096, 2948, 1, 128, 1000, 2960, 63, 65, 2948, 640, 3000, 2948]


class RdmaWriteCreditsTest(fpga_test_case.FPGATestCase):
    def test_requests_wait_for_their_whole_payload(self):
        requests = []
        expected = []
        for i, length in enumerate(LENGTHS):
            last = LAST if i == len(LENGTHS) - 1 else 0
            requests += [length | last] + [0] * (BEAT_WORDS - 1)
            expected += [length | WHOLE_PAYLOAD | last] + [0] * (BEAT_WORDS - 1)

        self.set_stream_input(0, fpga_stream.Stream(fpga_stream.StreamType.UNSIGNED_INT_64, requests))
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.UNSIGNED_INT_64, expected))
        self.overwrite_simulation_time(
            simulation_time.SimulationTime.fixed_time(20, simulation_time.SimulationTimeUnit.MICROSECONDS)
        )

        self.simulate_fpga()

        self.assert_simulation_output()
