# Bitstream Visualization Pipeline

Converts FPGA partial bitstreams into grayscale 256x256 images for visual inspection and ML preprocessing evaluation.

## Representation Families

### Case B: Direct Byte-to-Pixel

Each byte maps to exactly one grayscale pixel, filled row-major into a 256x256 array. This is deterministic, invertible, and hardware-friendly.

| Variant | Window Rule | Description |
|---------|-------------|-------------|
| **B1** | First 65536 bytes | Captures bitstream header + initial configuration frames |
| **B2** | Last 65536 bytes | Captures trailing configuration frames |
| **B3** | Center 65536 bytes | Middle of the bitstream |
| **B4** | Evenly downsampled | Every Nth byte from full file, where N = file_size/65536 |

**Pixel mapping:** `pixel = 255 - byte_value` (inverted by default: zero bytes appear white, non-zero bytes appear dark). Configurable via `invert` flag.

**Variable-length handling:** All pilot bitstreams are 6.2-11.2 MB (>> 65536 bytes), so no padding is needed. If a file is shorter than 65536 bytes, it is zero-padded.

### Case A: Plotted Data-Series (Paper Reverse-Engineering)

These variants attempt to reproduce the "bitstream-to-data-series-to-2D-plot" approach described in the ETS paper. The paper does not specify the exact mapping, so we implement multiple plausible interpretations.

All Case A variants (except A4) use a 65536-byte window extracted from the file (default: evenly downsampled, matching B4). A4 uses the full file.

| Variant | Method | Description |
|---------|--------|-------------|
| **A1** | Index-value line plot | x=byte index, y=byte value. Consecutive bytes connected by thin lines. Rendered via matplotlib (anti-aliased). |
| **A2** | Paired-point line plot | Bytes interpreted as (x,y) coordinate pairs: (b0,b1), (b2,b3), ... Lines connect consecutive pairs. All coordinates in [0,255]x[0,255]. |
| **A3** | Chunked polyline | File split into 256 chunks. Each chunk's mean byte value plotted as one point. Connected by lines. Shows smoothed byte-value profile. |
| **A4** | Density/accumulation map | Consecutive byte pairs (b_i, b_{i+1}) index into a 256x256 grid. Each hit increments the cell. Log-normalized to handle dynamic range. Uses full file. |

**A2 is the strongest candidate** for matching the paper's figures because it naturally produces many diagonal line segments in a square canvas, consistent with the paper's example images.

## Outputs

```
output/
├── case_b/
│   ├── B1/  S00_B1.png ... S23_B1.png   (24 images)
│   ├── B2/  ...
│   ├── B3/  ...
│   └── B4/  ...
├── case_a/
│   ├── A1/  ...
│   ├── A2/  ...
│   ├── A3/  ...
│   └── A4/  ...
├── montages/
│   ├── comparison_10x8.png              10 pilot samples x 8 variants
│   ├── pair_euclidean_S00_vs_S08.png    benign vs suspicious pairs
│   ├── pair_cosine_S02_vs_S10.png
│   ├── pair_vadd_S04_vs_S12.png
│   ├── pair_aes_S06_vs_S14.png
│   └── standalone_progression.png       5→50→500→5000 ROs
└── metadata/
    └── S00_B1.json ... S23_A4.json      per-image metadata
```

## Per-Image Metadata (JSON)

Each image has a companion JSON file recording:

```json
{
  "sample_id": "S00",
  "bitstream_filename": "vfpga_c0_0.bin",
  "file_size_bytes": 7058856,
  "variant": "B1",
  "window_mode": "first",
  "bytes_used": 65536,
  "byte_offset_start": 0,
  "byte_offset_end": 65536,
  "output_image_size": [256, 256],
  "invert": true,
  "class_label": 0,
  "base_app_id": "app1_euclidean",
  "region_id": 0,
  "output_path": "case_b/B1/S00_B1.png"
}
```

## Usage

```bash
cd bitstream_viz/

# Full run: all 24 samples x 8 variants + montages
python3 run_all.py

# Pilot subset only (10 samples, faster)
python3 run_all.py --pilot

# Case B only
python3 run_all.py --case-b-only

# Specific variants
python3 run_all.py --variants B1 B4 A2 A4
```

## Dependencies

- Python 3.10+
- numpy
- Pillow (PIL)
- matplotlib (Agg backend, no display needed)

## Key Design Notes

1. **Bitstream zero-byte fraction is ~62%.** Most bytes are 0x00. With inverted rendering (default), the images are mostly white with dark structural patterns.

2. **Region 0 vs Region 1 size difference.** Region 0 files are ~6.2-7.6 MB; Region 1 is ~9.5-11 MB. B1/B2/B3 capture different physical fractions depending on region. B4 and A4 are size-invariant.

3. **Paired benign/suspicious delta is tiny.** Only 48 LUTs differ (~144 bytes out of 6-11 MB). Visual differences between paired samples may be imperceptible at 256x256 resolution. This is expected and scientifically important.

4. **A4 normalization.** The density map has extreme dynamic range (the (0,0) cell from zero-bytes dominates). Log normalization (`np.log1p`) is applied by default. Alternative: `log_clip` clips the top 0.1% before normalizing.
