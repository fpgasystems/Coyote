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

"""Python unit test of example 1 (hello world): the vFPGA adds one to every integer of the host stream.

Run from a hardware build of examples/01_hello_world configured with
-DUNIT_TEST_DIR=<coyote>/sim/unit_test/examples/01_hello_world:

    PYTHONPATH=<hw build>:<coyote>/sim python3 -m unittest discover -s <coyote>/sim/unit_test/examples/01_hello_world

With COYOTE_SIM_VERILATOR=1 the test runs the Verilator binary of sim/vl/build.sh instead of xsim.
"""

from coyote_test import fpga_test_case, fpga_stream

Stream, StreamType = fpga_stream.Stream, fpga_stream.StreamType


class HelloWorldTestCase(fpga_test_case.FPGATestCase):
    def test_host_add_one(self):
        data = list(range(1024))
        self.set_stream_input(0, Stream(StreamType.SIGNED_INT_32, data))
        self.set_expected_output(0, Stream(StreamType.SIGNED_INT_32, [x + 1 for x in data]))

        self.simulate_fpga()

        self.assert_simulation_output()

    def test_host_add_one_two_batches(self):
        first = [i * 3 for i in range(256)]
        second = [-i for i in range(512)]
        for batch in (first, second):
            self.set_stream_input(0, Stream(StreamType.SIGNED_INT_32, batch))
            self.set_expected_output(0, Stream(StreamType.SIGNED_INT_32, [x + 1 for x in batch]))

        self.simulate_fpga()

        self.assert_simulation_output()
