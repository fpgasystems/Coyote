"""Validation and application helpers for explicit hls4ml layer tuning."""

from __future__ import annotations

import json
from typing import Any


VALID_STRATEGIES = {"Latency", "Resource"}
ALLOWED_MANUAL_KEYS = {"Strategy", "ReuseFactor"}
MANUAL_LAYER_MODE = "manual_layers"


def conv_layer_names(config: dict[str, Any]) -> list[str]:
    return [str(spec["name"]) for spec in config.get("model", {}).get("conv_specs", [])]


def supported_manual_layer_names(config: dict[str, Any]) -> list[str]:
    conv_names = conv_layer_names(config)
    layers: list[str] = []
    layers.extend(conv_names)
    layers.extend(f"pad_{name}" for name in conv_names)
    layers.extend(f"act{idx}" for idx, _ in enumerate(conv_names))
    layers.extend(f"pool{idx}" for idx, _ in enumerate(conv_names))
    layers.extend(["gap", "output_dense"])
    return layers


def hls_tuning_mode(config: dict[str, Any]) -> str:
    tuning = config.get("hls", {}).get("layer_tuning")
    if tuning is None:
        return ""
    if not isinstance(tuning, dict):
        raise ValueError("hls.layer_tuning must be a mapping")
    mode = str(tuning.get("mode", ""))
    if mode != MANUAL_LAYER_MODE:
        raise ValueError(f"unsupported hls.layer_tuning.mode={mode!r}; expected '{MANUAL_LAYER_MODE}'")
    return mode


def manual_layer_tuning(config: dict[str, Any]) -> dict[str, dict[str, Any]]:
    tuning = config.get("hls", {}).get("layer_tuning")
    if tuning is None:
        return {}
    if not isinstance(tuning, dict):
        raise ValueError("hls.layer_tuning must be a mapping")
    mode = str(tuning.get("mode", ""))
    if mode != MANUAL_LAYER_MODE:
        raise ValueError(f"unsupported hls.layer_tuning.mode={mode!r}; expected '{MANUAL_LAYER_MODE}'")
    layers = tuning.get("layers")
    if not isinstance(layers, dict):
        raise ValueError("hls.layer_tuning.layers must be a mapping")

    supported = supported_manual_layer_names(config)
    supported_set = set(supported)
    actual_set = {str(name) for name in layers}
    extra = sorted(actual_set - supported_set)
    if extra:
        raise ValueError(
            f"hls.layer_tuning.layers contains unsupported layers: {', '.join(extra)}; "
            f"supported layers are: {', '.join(supported)}"
        )

    out: dict[str, dict[str, Any]] = {}
    for name in sorted(actual_set, key=lambda item: supported.index(item)):
        raw = layers[name]
        if not isinstance(raw, dict):
            raise ValueError(f"hls.layer_tuning.layers.{name} must be a mapping")
        keys = set(raw)
        disallowed = sorted(keys - ALLOWED_MANUAL_KEYS)
        if disallowed:
            raise ValueError(
                f"hls.layer_tuning.layers.{name} has unsupported keys: {', '.join(disallowed)}; "
                "only Strategy and ReuseFactor are allowed"
            )
        missing_keys = sorted(ALLOWED_MANUAL_KEYS - keys)
        if missing_keys:
            raise ValueError(f"hls.layer_tuning.layers.{name} is missing keys: {', '.join(missing_keys)}")
        strategy = str(raw["Strategy"])
        if strategy not in VALID_STRATEGIES:
            raise ValueError(
                f"hls.layer_tuning.layers.{name}.Strategy={strategy!r}; "
                f"expected one of {sorted(VALID_STRATEGIES)}"
            )
        try:
            reuse_factor = int(raw["ReuseFactor"])
        except (TypeError, ValueError) as exc:
            raise ValueError(f"hls.layer_tuning.layers.{name}.ReuseFactor must be a positive integer") from exc
        if reuse_factor <= 0:
            raise ValueError(f"hls.layer_tuning.layers.{name}.ReuseFactor must be a positive integer")
        out[name] = {"Strategy": strategy, "ReuseFactor": reuse_factor}
    return out


def apply_manual_layer_tuning(config: dict[str, Any], hls_config: dict[str, Any]) -> None:
    manual = manual_layer_tuning(config)
    if not manual:
        return
    layer_configs = hls_config.get("LayerName", {})
    missing = [name for name in manual if name not in layer_configs]
    if missing:
        raise ValueError(f"hls4ml config is missing manually tuned layers: {', '.join(missing)}")
    for name, knobs in manual.items():
        layer_configs[name]["Strategy"] = knobs["Strategy"]
        layer_configs[name]["ReuseFactor"] = knobs["ReuseFactor"]


def layer_tuning_signature(config: dict[str, Any]) -> str:
    manual = manual_layer_tuning(config)
    if not manual:
        return ""
    return json.dumps(manual, sort_keys=True, separators=(",", ":"))
