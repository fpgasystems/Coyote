# Bitstream Visualization — Plot Generation Commands

All commands run from the `bitstream_viz/` directory:

```bash
cd /home/sdeheredia/work/Coyote/examples/pilot_dataset/bitstream_viz
```

## 1. Generate All Images (Full Pipeline)

Generates 192 images (24 samples × 8 variants) + all montages in ~24 seconds.

```bash
python3 run_all.py
```

Output: `output/case_b/`, `output/case_a/`, `output/montages/`, `output/metadata/`

### Selective runs

```bash
# Case B only (byte-to-pixel)
python3 run_all.py --case-b-only

# Case A only (plotted data-series)
python3 run_all.py --case-a-only

# Specific variants only
python3 run_all.py --variants B1 B4 A2 A4

# Pilot subset (10 samples) instead of all 24
python3 run_all.py --pilot

# Images only, skip montages
python3 run_all.py --no-montage
```

---

## 2. Per-Class Montages (One App Per Row, Region 0 Only)

4 rows × 8 variant columns per class.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_class_montages
manifest = load_manifest()
create_class_montages(manifest)
"
```

Output:
- `output/montages/class_0_benign.png`
- `output/montages/class_1_suspicious.png`
- `output/montages/class_2_standalone.png`

---

## 3. Benign vs Standalone — Side by Side (Case A)

4 rows (one per app) × 8 columns (A1 Ben, A1 Std, A2 Ben, A2 Std, ...). Row labels include LUT counts.

> **Note:** This montage is now generated automatically by `python3 run_all.py`. The command below is only needed for standalone regeneration.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_benign_vs_standalone
manifest = load_manifest()
p = create_benign_vs_standalone(manifest, case='a')
print(f'Saved: {p}')
"
```

Output: `output/montages/benign_vs_standalone_case_A.png`

---

## 4. Benign vs Standalone — Side by Side (Case B)

Same layout as above but for B1–B4.

> **Note:** This montage is now generated automatically by `python3 run_all.py`. The command below is only needed for standalone regeneration.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_benign_vs_standalone
manifest = load_manifest()
p = create_benign_vs_standalone(manifest, case='b')
print(f'Saved: {p}')
"
```

Output: `output/montages/benign_vs_standalone_case_B.png`

---

## 5. Benign vs Standalone — A2 Only

Single-column comparison, A2 variant only.

> **Note:** This montage is now generated automatically by `python3 run_all.py`. The command below is only needed for standalone regeneration.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_benign_vs_standalone_single
manifest = load_manifest()
p = create_benign_vs_standalone_single(manifest, variant='A2')
print(f'Saved: {p}')
"
```

Output: `output/montages/benign_vs_standalone_A2.png`

---

## 6. Paired Comparisons (Benign vs Suspicious, Same App)

One montage per app: 2 rows (benign, suspicious) × 8 variants.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_pair_comparison
manifest = load_manifest()
for ben, sus, app in [('S00','S08','euclidean'), ('S02','S10','cosine'),
                       ('S04','S12','vadd'), ('S06','S14','aes')]:
    p = create_pair_comparison(ben, sus, app, manifest=manifest)
    print(f'Saved: {p}')
"
```

Output:
- `output/montages/pair_euclidean_S00_vs_S08.png`
- `output/montages/pair_cosine_S02_vs_S10.png`
- `output/montages/pair_vadd_S04_vs_S12.png`
- `output/montages/pair_aes_S06_vs_S14.png`

---

## 7. Standalone Progression (5 → 50 → 500 → 5000 ROs)

4 rows (increasing RO count) × 8 variants.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_standalone_progression
manifest = load_manifest()
p = create_standalone_progression(manifest=manifest)
print(f'Saved: {p}')
"
```

Output: `output/montages/standalone_progression.png`

---

## 8. Full 10×8 Comparison (Pilot Subset)

10 representative samples × 8 variants.

```bash
python3 -c "
from io_utils import load_manifest
from montage import create_montage
from config import PILOT_SUBSET, ALL_VARIANTS
manifest = load_manifest()
p = create_montage(PILOT_SUBSET, ALL_VARIANTS,
                   output_path='output/montages/comparison_10x8.png',
                   manifest=manifest)
print(f'Saved: {p}')
"
```

Output: `output/montages/comparison_10x8.png`

---

## Output Summary

| Plot | File | Size | What it shows |
|------|------|------|---------------|
| Per-class benign | `class_0_benign.png` | 2186×1054 | 4 benign apps × 8 variants |
| Per-class suspicious | `class_1_suspicious.png` | 2186×1054 | 4 suspicious apps × 8 variants |
| Per-class standalone | `class_2_standalone.png` | 2186×1054 | 4 standalone apps × 8 variants |
| Benign vs Standalone Case A | `benign_vs_standalone_case_A.png` | 2206×1054 | Side-by-side A1–A4, with LUTs |
| Benign vs Standalone Case B | `benign_vs_standalone_case_B.png` | 2206×1054 | Side-by-side B1–B4, with LUTs |
| Benign vs Standalone A2 | `benign_vs_standalone_A2.png` | ~654×1054 | A2 only, with LUTs |
| Pair euclidean | `pair_euclidean_S00_vs_S08.png` | 2186×538 | Benign vs suspicious (same app) |
| Pair cosine | `pair_cosine_S02_vs_S10.png` | 2186×538 | Benign vs suspicious (same app) |
| Pair vadd | `pair_vadd_S04_vs_S12.png` | 2186×538 | Benign vs suspicious (same app) |
| Pair aes | `pair_aes_S06_vs_S14.png` | 2186×538 | Benign vs suspicious (same app) |
| Standalone progression | `standalone_progression.png` | 2186×1054 | 5→50→500→5000 ROs |
| Full 10×8 comparison | `comparison_10x8.png` | 2186×2602 | 10 pilot samples × 8 variants |

---

## Notes

- **B3 (center window) looks similar across samples** because the center of most region-0 partial bitstreams falls in sparse Xilinx frame padding (~85% zero bytes). This is correct behavior, not a bug. B1, B2, and B4 are more informative.
- **All montages (including benign vs standalone) are now generated by `python3 run_all.py`.** The individual commands in sections 2–8 are provided for selective regeneration only.
- All montages use region 0 only (one config per app) to keep them compact.
