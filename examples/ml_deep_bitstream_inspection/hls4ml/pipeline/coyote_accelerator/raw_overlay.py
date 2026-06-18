"""Local raw-input runtime adapter for generated CoyoteAccelerator projects."""

from __future__ import annotations

import ctypes
import math
import os
import subprocess
import time
from pathlib import Path
from typing import Sequence

import numpy as np


class RawCoyoteOverlay:
    """Load a generated CoyoteAccelerator shared library and run raw-byte inference."""

    def __init__(self, path: str | Path, project_name: str = "myproject") -> None:
        self.path = Path(path).resolve()
        self.project_name = project_name
        self.lib_path = self.path / "build" / f"{self.project_name}_cyt_sw" / "lib" / "libCoyoteInference.so"
        if not self.lib_path.exists():
            raise FileNotFoundError(self.lib_path)
        self.coyote_lib = ctypes.cdll.LoadLibrary(str(self.lib_path))
        self._bind_common_symbols()
        self._bind_raw_symbols()

    def _bind_common_symbols(self) -> None:
        model_ptr = ctypes.POINTER(ctypes.c_void_p)
        self.coyote_lib.flush.argtypes = [model_ptr]
        self.coyote_lib.predict.argtypes = [model_ptr]
        self.coyote_lib.get_inference_predictions.argtypes = [model_ptr, ctypes.c_uint]
        self.coyote_lib.get_inference_predictions.restype = ctypes.POINTER(ctypes.c_float)
        self.coyote_lib.free_model_inference.argtypes = [model_ptr]

    def _bind_raw_symbols(self) -> None:
        model_ptr = ctypes.POINTER(ctypes.c_void_p)
        self.coyote_lib.init_model_inference_raw.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint]
        self.coyote_lib.init_model_inference_raw.restype = model_ptr

        np_pointer_u8 = np.ctypeslib.ndpointer(dtype=np.uint8, ndim=1, flags="C")
        self.coyote_lib.set_inference_raw_data.argtypes = [model_ptr, np_pointer_u8, ctypes.c_uint, ctypes.c_uint]

    @staticmethod
    def _uses_hugepage_alloc() -> bool:
        return os.environ.get("COYOTE_ALLOC_TYPE", "HPF").upper() == "HPF"

    @staticmethod
    def _free_hugepages_2m() -> int | None:
        path = Path("/sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages")
        try:
            return int(path.read_text().strip())
        except OSError:
            return None

    @staticmethod
    def _required_hugepages_2m(batch_size: int, max_input_bytes: int, out_items: int) -> int:
        page_bytes = 2 * 1024 * 1024
        raw_pages = math.ceil((64 + max_input_bytes) / page_bytes)
        out_pages = math.ceil((out_items * np.dtype(np.float32).itemsize) / page_bytes)
        return batch_size * (raw_pages + out_pages)

    def program_hacc_fpga(self) -> None:
        driver_dir = self.path / "Coyote" / "driver"
        util_dir = self.path / "Coyote" / "util"
        bitstream = self.path / "build" / f"{self.project_name}_cyt_hw" / "bitstreams" / "cyt_top.bit"
        driver = driver_dir / "build" / "coyote_driver.ko"
        if not driver_dir.exists():
            raise FileNotFoundError(driver_dir)
        if not util_dir.exists():
            raise FileNotFoundError(util_dir)
        if not bitstream.exists():
            raise FileNotFoundError(bitstream)

        env = os.environ.copy()
        env["PWD"] = str(driver_dir)
        subprocess.run(["make"], cwd=driver_dir, env=env, check=True)
        subprocess.run(["bash", "program_hacc_local.sh", str(bitstream), str(driver)], cwd=util_dir, check=True)

    def predict_raw(self, x: Sequence[np.ndarray], y_shape: tuple[int, ...], batch_size: int = 1) -> np.ndarray:
        raw_samples = [np.ascontiguousarray(np.asarray(sample, dtype=np.uint8).reshape(-1)) for sample in x]
        if batch_size <= 0:
            raise ValueError(f"batch_size must be positive, got {batch_size}")
        if len(raw_samples) % batch_size != 0:
            raise RuntimeError(f"{len(raw_samples)} samples is not divisible by batch size {batch_size}")

        y = np.empty((len(raw_samples), *y_shape), dtype=np.float32)
        max_input_bytes = max((len(sample) for sample in raw_samples), default=0)
        required_hugepages = self._required_hugepages_2m(batch_size, max_input_bytes, int(np.prod(y_shape)))
        free_hugepages = self._free_hugepages_2m()
        if self._uses_hugepage_alloc() and free_hugepages is not None and free_hugepages < required_hugepages:
            raise RuntimeError(
                "Insufficient 2MB hugepages for Coyote raw inference: "
                f"free={free_hugepages}, required>={required_hugepages}, "
                f"batch_size={batch_size}, max_input_bytes={max_input_bytes}. "
                "Retry with COYOTE_ALLOC_TYPE=THP and HLS4ML_COYOTE_BATCH_SIZE=1, "
                "or free/reboot the FPGA host."
            )
        model = self.coyote_lib.init_model_inference_raw(batch_size, max_input_bytes, int(np.prod(y_shape)))

        cnt = 0
        avg_latency_us = 0.0
        avg_throughput = 0.0
        total_batches = 0
        try:
            for sample in raw_samples:
                self.coyote_lib.set_inference_raw_data(model, sample, len(sample), cnt)
                cnt += 1
                if cnt == batch_size:
                    self.coyote_lib.flush(model)

                    start_ns = time.time_ns()
                    self.coyote_lib.predict(model)
                    end_ns = time.time_ns()

                    elapsed_ns = end_ns - start_ns
                    avg_latency_us += elapsed_ns / 1e3
                    avg_throughput += batch_size / (elapsed_ns * 1e-9)

                    for item_idx in range(batch_size):
                        ptr = self.coyote_lib.get_inference_predictions(model, item_idx)
                        y[total_batches * batch_size + item_idx] = np.ctypeslib.as_array(ptr, shape=y_shape)

                    cnt = 0
                    total_batches += 1
        finally:
            self.coyote_lib.free_model_inference(model)

        if total_batches:
            print(f"Batch size: {batch_size}; batches processed: {total_batches}")
            print(f"Mean latency: {round(avg_latency_us / total_batches, 3)}us (inference only)")
            print(f"Mean throughput: {round(avg_throughput / total_batches, 1)} samples/s (inference only)")
        return y
