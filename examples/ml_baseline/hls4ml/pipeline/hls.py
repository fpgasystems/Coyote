"""Conversion helpers for the PyTorch → hls4ml path."""

from __future__ import annotations

import importlib
import inspect
import json
from pathlib import Path
from typing import Any

import torch

from .candidates import CandidateConfig
from .evaluation import _fold_dir, load_checkpoint, resolve_device
from .paths import ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

from model import build_model  # noqa: E402

DEFAULT_STAGE1_PRECISION = "fixed<24,8>"
FINAL_AVGPOOL_ACCUM_PRECISION = "fixed<40,20>"


def _require_module(module_name: str) -> Any:
    try:
        return importlib.import_module(module_name)
    except ModuleNotFoundError as exc:
        raise ModuleNotFoundError(
            f"Missing required dependency '{module_name}'. "
            f"Install it in the dedicated hls4ml environment before running this step."
        ) from exc


def candidate_input_shape(candidate: CandidateConfig) -> tuple[int, ...]:
    if candidate.representation == "2d":
        return (1, candidate.img_size, candidate.img_size)
    return (1, candidate.sequence_length)


def candidate_dummy_input(candidate: CandidateConfig, batch_size: int = 1) -> torch.Tensor:
    return torch.zeros((batch_size, *candidate_input_shape(candidate)), dtype=torch.float32)


def load_candidate_model(
    candidate: CandidateConfig,
    fold: int,
    checkpoint_name: str = "final",
    device_arg: str | None = None,
) -> torch.nn.Module:
    device = resolve_device(device_arg)
    checkpoint_path = _fold_dir(candidate, fold) / f"{checkpoint_name}_model.pt"
    model = build_model(candidate.model)
    load_checkpoint(model, checkpoint_path, device)
    model.to(device)
    model.eval()
    return model


def _write_hls_metadata(output_dir: Path, payload: dict) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "conversion_manifest.json").write_text(json.dumps(payload, indent=2, sort_keys=True))


def _apply_final_avgpool_precision(config: dict, default_precision: str) -> None:
    """Avoid overflow in the final average pool accumulator."""
    layer = config.get("LayerName", {}).get("avgpool")
    if layer is None:
        return
    layer["Precision"] = {
        "result": default_precision,
        "accum": FINAL_AVGPOOL_ACCUM_PRECISION,
    }


def build_pytorch_hls_project(
    candidate: CandidateConfig,
    fold: int,
    output_dir: Path,
    checkpoint_name: str = "final",
    io_type: str = "io_stream",
    reuse_factor: int = 4,
    strategy: str = "Resource",
    backend: str = "Vitis",
    part: str | None = None,
    clock_period: float = 5.0,
    default_precision: str = DEFAULT_STAGE1_PRECISION,
    project_name: str = "cnn_medium_hls",
    device_arg: str | None = None,
) -> Path:
    hls4ml = _require_module("hls4ml")
    conversion_device_arg = device_arg or "cpu"
    model = load_candidate_model(candidate, fold, checkpoint_name=checkpoint_name, device_arg=conversion_device_arg)

    config_fn = hls4ml.utils.config_from_pytorch_model
    config_sig = inspect.signature(config_fn)
    config_kwargs = {
        "granularity": "name",
        "backend": backend,
        "default_precision": default_precision,
        "default_reuse_factor": reuse_factor,
    }
    if "input_shape" in config_sig.parameters:
        config_kwargs["input_shape"] = candidate_input_shape(candidate)
    if "channels_last_conversion" in config_sig.parameters:
        config_kwargs["channels_last_conversion"] = "internal" if io_type == "io_stream" else "full"
    elif "inputs_channel_last" in config_sig.parameters:
        config_kwargs["inputs_channel_last"] = False
    config = config_fn(model, **config_kwargs)
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = strategy
    config["Model"]["ReuseFactor"] = reuse_factor
    _apply_final_avgpool_precision(config, default_precision)

    hls_model = hls4ml.converters.convert_from_pytorch_model(
        model,
        output_dir=str(output_dir),
        project_name=project_name,
        backend=backend,
        io_type=io_type,
        hls_config=config,
        part=part or candidate.target_part,
        clock_period=clock_period,
        input_shape=candidate_input_shape(candidate),
    )
    hls_model.compile()
    _write_hls_metadata(
        output_dir,
        {
            "candidate": candidate.name,
            "fold": fold,
            "checkpoint": checkpoint_name,
            "io_type": io_type,
            "reuse_factor": reuse_factor,
            "strategy": strategy,
            "backend": backend,
            "part": part or candidate.target_part,
            "clock_period": clock_period,
            "default_precision": default_precision,
            "project_name": project_name,
        },
    )
    return output_dir
