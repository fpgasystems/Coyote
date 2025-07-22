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

# Mimics the existing ExceptionGroup from Python > 3.8
from typing import List
from io import StringIO
import traceback

class ExceptionGroup(Exception):
    """
    This class bundles several exceptions into one.
    When printed, the message and stack trace of all
    containing exceptions is printed.

    This class is useful to collect a set of exceptions
    that are then propagated at once to the user.
    E.g. the fpga_test_case uses this to collect all assertion
    errors to make the user aware of all ways a test failed, not just
    of one!
    """
    def __init__(self, message: str, exceptions: List[Exception]):
        assert isinstance(exceptions, list), "Exception group expected list of Exceptions"
        self.message = message
        self.exceptions = exceptions
        super().__init__(message, exceptions)

    def __str__(self):
        output = StringIO()
        output.write(f"{self.message} ({len(self.exceptions)} exceptions):\n")

        for i, exception in enumerate(self.exceptions):
            output.write(f"\t[{i+1}] {exception}\n")
            if exception.__traceback__:
                tb = traceback.format_tb(exception.__traceback__)
                for line in tb:
                    output.write(f"\t\t{line}\n")
        
        return output.getvalue()