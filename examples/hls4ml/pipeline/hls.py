"""Export and conversion helpers for ONNX/QONNX/hls4ml stages."""

from __future__ import annotations

import importlib
import json
from pathlib import Path
from typing import Any

import torch

from .candidates import CandidateConfig
from .evaluation import _fold_dir, load_checkpoint, resolve_device
from .paths import ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

from model import build_model  # noqa: E402


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


def export_candidate_onnx(
    candidate: CandidateConfig,
    fold: int,
    output_path: Path,
    checkpoint_name: str = "final",
    opset_version: int = 17,
    device_arg: str | None = None,
) -> Path:
    _require_module("onnx")
    device = resolve_device(device_arg)
    model = load_candidate_model(candidate, fold, checkpoint_name=checkpoint_name, device_arg=device_arg)
    dummy_input = candidate_dummy_input(candidate).to(device)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model,
        dummy_input,
        str(output_path),
        opset_version=opset_version,
        do_constant_folding=True,
        input_names=["input"],
        output_names=["logits"],
        dynamic_axes=None,
    )
    return output_path


def clean_qonnx_model(
    onnx_path: Path,
    output_path: Path,
    convert_channels_last: bool = True,
) -> Path:
    _require_module("qonnx")
    from qonnx.core.modelwrapper import ModelWrapper
    from qonnx.transformation.channels_last import ConvertToChannelsLastAndClean
    from qonnx.transformation.gemm_to_matmul import GemmToMatMul
    from qonnx.util.cleanup import cleanup_model

    model = ModelWrapper(str(onnx_path))
    model = cleanup_model(model)
    if convert_channels_last:
        model = model.transform(ConvertToChannelsLastAndClean())
    model = model.transform(GemmToMatMul())
    model = cleanup_model(model)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(output_path))
    return output_path


def _write_hls_metadata(output_dir: Path, payload: dict) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "conversion_manifest.json").write_text(json.dumps(payload, indent=2, sort_keys=True))


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
    default_precision: str = "fixed<16,6>",
    project_name: str = "cnn_medium_hls",
    device_arg: str | None = None,
) -> Path:
    hls4ml = _require_module("hls4ml")
    model = load_candidate_model(candidate, fold, checkpoint_name=checkpoint_name, device_arg=device_arg)

    channels_last_conversion = "internal" if io_type == "io_stream" else "full"
    config = hls4ml.utils.config_from_pytorch_model(
        model,
        input_shape=candidate_input_shape(candidate),
        granularity="name",
        backend=backend,
        default_precision=default_precision,
        default_reuse_factor=reuse_factor,
        channels_last_conversion=channels_last_conversion,
    )
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = strategy
    config["Model"]["ReuseFactor"] = reuse_factor

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
            "frontend": "pytorch",
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


def build_onnx_hls_project(
    candidate: CandidateConfig,
    onnx_path: Path,
    output_dir: Path,
    io_type: str = "io_stream",
    reuse_factor: int = 4,
    strategy: str = "Resource",
    backend: str = "Vitis",
    part: str | None = None,
    clock_period: float = 5.0,
    default_precision: str = "fixed<16,6>",
    project_name: str = "cnn_medium_hls",
) -> Path:
    hls4ml = _require_module("hls4ml")
    _require_module("qonnx")
    from qonnx.core.modelwrapper import ModelWrapper

    model = ModelWrapper(str(onnx_path))
    config = hls4ml.utils.config_from_onnx_model(
        model,
        granularity="name",
        backend=backend,
        default_precision=default_precision,
        default_reuse_factor=reuse_factor,
    )
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = strategy
    config["Model"]["ReuseFactor"] = reuse_factor

    hls_model = hls4ml.converters.convert_from_onnx_model(
        model,
        output_dir=str(output_dir),
        project_name=project_name,
        backend=backend,
        io_type=io_type,
        hls_config=config,
        part=part or candidate.target_part,
        clock_period=clock_period,
    )
    hls_model.compile()
    _write_hls_metadata(
        output_dir,
        {
            "candidate": candidate.name,
            "frontend": "onnx",
            "onnx_path": str(onnx_path),
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
