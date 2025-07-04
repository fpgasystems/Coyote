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

from typing import List, Any

def split_list(elements, chunk_size):
    return [elements[i : i + chunk_size] for i in range(0, len(elements), chunk_size)]


def split_into_batches(list, n_batches):
    """
    Splits the given list into n_batches as evenly as possible.
    E.g. if n = len(list) % n_batches and n != 0, the remainder will
        be distributed among the first n batches.
    """
    assert len(list) >= n_batches, (
        f"Cannot split list with {len(list)} elements into {n_batches} batches"
    )

    # The sizes of the individual batches
    elem_per_batch = len(list) // n_batches
    sizes = [elem_per_batch for _ in range(0, n_batches)]

    # Add the remainder to the first batches, if there is any
    remainder = len(list) % n_batches
    for i in range(0, remainder):
        sizes[i] += 1

    # Get the batches!
    index = 0
    batches = []
    for size in sizes:
        batches.append(list[index : index + size])
        index += size

    return batches


def flatten_list(xss: List[List[Any]]) -> List[Any]:
    return [x for xs in xss for x in xs]
