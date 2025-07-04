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

from decimal import Decimal


def frange(start: float, stop: float, step: float, precision : int= 1):
    """
    floating-point equivalent to the built-in range method for integers.
    Returns a list of floating point numbers that goes form [start, stop)
    in step steps. For this to work properly, one needs to supply a precision.
    This denotes the maximum digits after the comma that the resulting list should have

    start       = Inclusive floating-point number to start at
    stop        = Exclusive floating-point number to stop at
    step        = How much to go in one step. This determines the length of the resulting list.
    precision   = How many digits should there be at most after the comma in the resulting list. 

    For example:
    > frange(0.0, 0.5, 0.1, precision = 1)
    will return
    > [0.0, 0.1, 0.2, 0.3, 0.4]
    """
    assert step > 0, "Step must be not 0"
    assert (
        isinstance(start, float) & isinstance(stop, float) & isinstance(step, float)
    ), "frange will only be correct when used with floating-point numbers"
    # Note: We use decimal here to produce the results as mentioned in the example above.
    # With "normal" fp numbers, you would get a result close to this but not exactly
    # like the above.
    dec_start = Decimal(start)
    dec_stop = Decimal(stop)
    dec_step = Decimal(step)

    result = [start]
    while dec_start + dec_step < dec_stop:
        result.append(round(float(dec_start + dec_step), precision))
        dec_start = dec_start + dec_step

    return result
