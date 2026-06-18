"""Compatibility re-exports for the numbered hls4ml notebook flow parts.

The implementation lives in ``part1_common`` through ``part7_runner`` so the
flow can be followed in order from the file explorer. Existing callers should
continue importing from ``pipeline.notebook_flow``.
"""

from __future__ import annotations

from .part1_common import *  # noqa: F401,F403
from .part2_train import *  # noqa: F401,F403
from .part3_hls import *  # noqa: F401,F403
from .part4_bitstream import *  # noqa: F401,F403
from .part5_deploy import *  # noqa: F401,F403
from .part6_validate import *  # noqa: F401,F403
from .part7_runner import *  # noqa: F401,F403
