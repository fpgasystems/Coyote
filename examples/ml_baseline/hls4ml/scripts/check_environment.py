#!/usr/bin/env python3
"""Report missing local dependencies for the hls4ml workspace."""

from __future__ import annotations

import importlib
import shutil


PY_MODULES = [
    "torch",
    "numpy",
    "onnx",
    "qonnx",
    "brevitas",
    "hls4ml",
]

BINARIES = [
    "vivado",
    "vitis_hls",
    "vitis-run",
]


def main() -> None:
    print("Python modules:")
    for module_name in PY_MODULES:
        try:
            module = importlib.import_module(module_name)
            version = getattr(module, "__version__", "unknown")
            print(f"  OK   {module_name} {version}")
        except Exception as exc:  # pragma: no cover - diagnostics only
            print(f"  MISS {module_name}: {type(exc).__name__}")

    print("\nToolchain binaries:")
    for binary in BINARIES:
        path = shutil.which(binary)
        if path:
            print(f"  OK   {binary}: {path}")
        else:
            print(f"  MISS {binary}")


if __name__ == "__main__":
    main()
