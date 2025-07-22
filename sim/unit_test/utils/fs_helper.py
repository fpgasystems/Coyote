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

import os
import os.path
from typing import List

class FSHelper:
    """
    Small helper class with FileSystem utility functions
    """

    def get_latest_modification_time(directories_and_files: List[str]) -> float:
        """
        Get the latest modification time from all
        files in the given list of directories or files.
        The given list may contain None elements, which are skipped.
        The time is a floating-point value describing the
        time in seconds since unix epoch of the last
        modification.
        """
        latest_mtime = 0
        for elem in directories_and_files:
            if elem is not None:
                if os.path.isdir(elem):
                    for root, _, files in os.walk(elem):
                        for file in files:
                            filepath = os.path.join(root, file)
                            mtime = os.path.getmtime(filepath)
                            latest_mtime = max(latest_mtime, mtime)
                elif os.path.isfile(elem):
                    mtime = os.path.getmtime(elem)
                    latest_mtime = max(latest_mtime, mtime)
                else:
                    raise ValueError(f"{elem} was neither directory nor file")

        return latest_mtime
