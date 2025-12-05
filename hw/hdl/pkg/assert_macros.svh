/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`ifndef COYOTE_ASSERT_MACROS_SVH
`define COYOTE_ASSERT_MACROS_SVH

`define STRINGIFY(x) $sformatf("%0s", `"x`")

`define ASSERT_NOT_UNDEFINED(sig) \
assert property (@(posedge aclk) disable iff (!aresetn) \
    !$isunknown(sig)) \
else $fatal(1, "Signal %s needs to not be undefined!", `STRINGIFY(sig));

`define ASSERT_STABLE(sig, sig_valid, sig_ready) \
assert property (@(posedge aclk) disable iff (!aresetn) \
    sig_valid && !sig_ready |=> $stable(sig)) \
else $fatal(1, "Signal %s needs to be stable while valid && !ready!", `STRINGIFY(sig));

`define ASSERT_SIGNAL_STABLE(sig) `ASSERT_STABLE(sig, tvalid, tready)

`endif
