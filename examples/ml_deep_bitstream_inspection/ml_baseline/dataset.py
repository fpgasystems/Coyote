"""Bitstream dataset for binary classification (benign vs standalone).

Loads raw .bin partial bitstreams from one or more dataset vaults,
samples them to a fixed byte window, and exposes either:

- a 2D `1024x1024` grayscale image view
- a 1D fixed-length sequence view
"""

import csv
import os
import re

import numpy as np
import torch
from torch.utils.data import Dataset

# --- Paths ---
DEFAULT_VAULT_BASE = "/mnt/scratch/sdeheredia/coyote_vault_work"
VAULT_BASE_ENV = "COYOTE_DATASET_VAULT"
VAULT_BASE = os.environ.get(VAULT_BASE_ENV, DEFAULT_VAULT_BASE)

IMG_SIZE = 1024  # default 2D view is IMG_SIZE x IMG_SIZE
SEQUENCE_LENGTH = IMG_SIZE * IMG_SIZE
REPRESENTATION_CHOICES = ("2d", "1d")


def discover_vaults(vault_base=None):
    """Find all full_dataset_* directories under vault_base.

    Returns list of (dataset_id, vault_path) tuples sorted by name.
    dataset_id is derived from the directory name, e.g. "it1" from
    "full_dataset_it1_2026-04-01_production".
    """
    vault_base = vault_base or os.environ.get(VAULT_BASE_ENV, VAULT_BASE)
    vaults = []
    for entry in sorted(os.listdir(vault_base)):
        full_path = os.path.join(vault_base, entry)
        if not os.path.isdir(full_path):
            continue
        if not entry.startswith("full_dataset_"):
            continue
        manifest = os.path.join(full_path, "manifest.csv")
        if not os.path.isfile(manifest):
            continue
        # Extract dataset_id: "full_dataset_it1_..." -> "it1", "full_dataset_it2_..." -> "it2"
        m = re.match(r"full_dataset_(it\d+)", entry)
        dataset_id = m.group(1) if m else entry.replace("full_dataset_", "").split("_")[0]
        vaults.append((dataset_id, full_path))
    return vaults


def load_manifest(vault_base=None, min_ro=4000):
    """Load and merge manifests from all vaults under vault_base.

    Each sample row is augmented with:
      - _dataset_id: e.g. "it1", "it2"
      - _bitstream_dir: absolute path to that vault's bitstreams/ directory
      - sample_id is prefixed with dataset_id to avoid collisions

    Returns list of dicts with keys from manifest CSV plus the above.
    """
    vaults = discover_vaults(vault_base)
    if not vaults:
        raise FileNotFoundError(
            "No dataset vaults found under "
            f"{vault_base or os.environ.get(VAULT_BASE_ENV, VAULT_BASE)}"
        )

    samples = []
    for dataset_id, vault_path in vaults:
        manifest_path = os.path.join(vault_path, "manifest.csv")
        bitstream_dir = os.path.join(vault_path, "bitstreams")
        with open(manifest_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                class_label = int(row["class_label"])
                ro_count = int(row["ro_count"])

                # Keep all benign (class 0)
                # Keep standalone (class 1) only if RO >= min_ro
                if class_label == 0 or (class_label == 1 and ro_count >= min_ro):
                    # Skip samples with missing bitstreams
                    bin_path = os.path.join(bitstream_dir, row["bitstream_path"])
                    if not os.path.isfile(bin_path):
                        continue
                    row["_dataset_id"] = dataset_id
                    row["_bitstream_dir"] = bitstream_dir
                    row["sample_id"] = f"{dataset_id}_{row['sample_id']}"
                    samples.append(row)

    return samples


def bitstream_to_sequence(bin_path, sequence_length=SEQUENCE_LENGTH, invert=True):
    """Load a raw .bin file and sample/pad it to a fixed-length uint8 sequence."""
    data = np.fromfile(bin_path, dtype=np.uint8)
    n = len(data)
    if n <= sequence_length:
        window = np.zeros(sequence_length, dtype=np.uint8)
        window[:n] = data
    else:
        indices = np.linspace(0, n - 1, sequence_length, dtype=np.int64)
        window = data[indices]

    if invert:
        window = 255 - window

    return window


def reshape_sequence_to_image(sequence_uint8, img_size=IMG_SIZE):
    """Reshape a fixed-length uint8 sequence into a square image for display."""
    expected = img_size * img_size
    if sequence_uint8.size != expected:
        raise ValueError(
            f"Expected sequence of length {expected}, got {sequence_uint8.size}"
        )
    return sequence_uint8.reshape(img_size, img_size)


def bitstream_to_image(bin_path, img_size=IMG_SIZE, invert=True):
    """Load a raw .bin file and expose it as an `img_size x img_size` uint8 image."""
    return reshape_sequence_to_image(
        bitstream_to_sequence(
            bin_path,
            sequence_length=img_size * img_size,
            invert=invert,
        ),
        img_size=img_size,
    )


def bitstream_to_array(bin_path, representation="2d", img_size=IMG_SIZE,
                       sequence_length=SEQUENCE_LENGTH, invert=True):
    """Load a raw .bin file into the requested representation."""
    if representation not in REPRESENTATION_CHOICES:
        raise ValueError(
            f"Unknown representation: {representation!r}. "
            f"Choose from {REPRESENTATION_CHOICES}"
        )

    if representation == "1d":
        sequence_uint8 = bitstream_to_sequence(
            bin_path,
            sequence_length=sequence_length,
            invert=invert,
        )
        return sequence_uint8
    sequence_uint8 = bitstream_to_sequence(
        bin_path,
        sequence_length=img_size * img_size,
        invert=invert,
    )
    return reshape_sequence_to_image(sequence_uint8, img_size=img_size)


def array_to_tensor(array_uint8):
    """Convert a uint8 sequence/image array into a channel-first float tensor."""
    return torch.from_numpy(array_uint8.astype(np.float32) / 255.0).unsqueeze(0)


def tensor_to_display_image_uint8(tensor, img_size=IMG_SIZE):
    """Convert a model-input tensor into a displayable `img_size x img_size` uint8 image."""
    arr = tensor.detach().cpu().numpy()
    if arr.ndim == 3:
        arr = arr.squeeze(0)

    if arr.ndim == 1:
        arr = reshape_sequence_to_image(np.rint(arr * 255.0).astype(np.uint8), img_size=img_size)
    elif arr.ndim == 2:
        arr = np.rint(arr * 255.0).astype(np.uint8)
    else:
        raise ValueError(f"Unsupported tensor shape for display: {tensor.shape}")

    return arr


class BitstreamDataset(Dataset):
    """PyTorch Dataset for bitstream model inputs.

    Each sample is a `(tensor, label)` pair where:
    - 2D representation: `tensor` is float32 `[1, IMG_SIZE, IMG_SIZE]`
    - 1D representation: `tensor` is float32 `[1, SEQUENCE_LENGTH]`
    - `label` is float32 scalar (`0.0 = benign`, `1.0 = standalone`)

    When return_index=True, returns (image_tensor, label, index) so that
    validation/debug code can map outputs back to manifest metadata.
    """

    def __init__(self, sample_list, bitstream_dir=None, img_size=IMG_SIZE,
                 sequence_length=None, representation="2d",
                 transform=None, return_index=False):
        if representation not in REPRESENTATION_CHOICES:
            raise ValueError(
                f"Unknown representation: {representation!r}. "
                f"Choose from {REPRESENTATION_CHOICES}"
            )
        self.samples = sample_list
        self.bitstream_dir = bitstream_dir  # fallback if row has no _bitstream_dir
        self.img_size = img_size
        self.representation = representation
        if sequence_length is None:
            if representation == "2d":
                self.sequence_length = img_size * img_size
            else:
                self.sequence_length = SEQUENCE_LENGTH
        else:
            self.sequence_length = sequence_length
        self.transform = transform
        self.return_index = return_index

    def __len__(self):
        return len(self.samples)

    def _resolve_bin_path(self, row):
        bdir = row.get("_bitstream_dir") or self.bitstream_dir
        return os.path.join(bdir, row["bitstream_path"])

    def get_raw_array(self, idx):
        row = self.samples[idx]
        bin_path = self._resolve_bin_path(row)
        return bitstream_to_array(
            bin_path,
            representation=self.representation,
            img_size=self.img_size,
            sequence_length=self.sequence_length,
        )

    def get_raw_tensor(self, idx):
        return array_to_tensor(self.get_raw_array(idx))

    def __getitem__(self, idx):
        row = self.samples[idx]
        tensor = self.get_raw_tensor(idx)

        if self.transform is not None:
            tensor = self.transform(tensor)

        # Label: 0.0 = benign, 1.0 = standalone
        label = torch.tensor(float(row["class_label"]), dtype=torch.float32)

        if self.return_index:
            return tensor, label, idx

        return tensor, label

    def get_metadata(self, idx):
        """Return the manifest row dict for debugging/visualization."""
        return self.samples[idx]

    def get_image_uint8(self, idx):
        """Return a displayable 2D uint8 image for debugging/visualization."""
        return tensor_to_display_image_uint8(self.get_raw_tensor(idx), img_size=self.img_size)


class CachedTensorDataset(Dataset):
    """Dataset wrapping precomputed tensors and labels.

    Used for the deterministic augmented-validation cache so that the same
    augmented images are evaluated every epoch without recomputation.
    """

    def __init__(self, tensors, labels, sample_list=None, return_index=False,
                 representation="2d", img_size=IMG_SIZE):
        """
        Args:
            tensors: list or stacked tensor of [1, H, W] float32 images
            labels: list or tensor of float32 labels
            sample_list: optional list of manifest row dicts for metadata lookup
        """
        if isinstance(tensors, list):
            self.tensors = torch.stack(tensors)
        else:
            self.tensors = tensors
        if isinstance(labels, list):
            self.labels = torch.tensor(labels, dtype=torch.float32)
        else:
            self.labels = labels
        self.samples = sample_list
        self.return_index = return_index
        self.representation = representation
        self.img_size = img_size

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        if self.return_index:
            return self.tensors[idx], self.labels[idx], idx
        return self.tensors[idx], self.labels[idx]

    def get_metadata(self, idx):
        if self.samples is not None:
            return self.samples[idx]
        return {}

    def get_image_uint8(self, idx):
        tensor = self.tensors[idx]
        return tensor_to_display_image_uint8(tensor, img_size=self.img_size)
