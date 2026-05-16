"""Device resource constants used by hls4ml experiment diagnostics."""

from __future__ import annotations

# XCU55C full-device CLB LUT count. AMD DS978 lists this as 1,304K LUTs.
XCU55C_TOTAL_CLB_LUTS = 1_303_680

# U55C Gen3x16 XDMA base platform dynamic-region CLB LUTs by SLR:
# SLR0=386,880, SLR1=364,320, SLR2=395,040.
XCU55C_DYNAMIC_REGION_CLB_LUTS = 1_146_240

