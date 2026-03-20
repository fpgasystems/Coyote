"""Constants and default parameters for the bitstream visualization pipeline."""

import os

# Paths
PILOT_DIR = "/home/sdeheredia/work/Coyote/examples/pilot_dataset"
BITSTREAM_DIR = os.path.join(PILOT_DIR, "build_hw", "bitstreams")
MANIFEST_PATH = os.path.join(PILOT_DIR, "pilot_manifest.csv")
OUTPUT_DIR = os.path.join(PILOT_DIR, "bitstream_viz", "output")

# Image parameters
IMG_SIZE = 256
WINDOW_SIZE = IMG_SIZE * IMG_SIZE  # 65536 bytes
SUPERSAMPLE_FACTOR = 2  # for Case A PIL rendering

# Window modes (shared by Case B and Case A)
WINDOW_MODES = ["first", "last", "center", "downsample"]

# Default rendering options
DEFAULT_INVERT_B = True     # white bg, dark data for Case B
DEFAULT_INVERT_A = True     # white bg, dark lines for Case A line plots
DEFAULT_INVERT_A4 = False   # black bg, bright density for A4
DEFAULT_A4_NORM = "log"     # log normalization for A4 density
DEFAULT_LINE_WIDTH = 1      # pixel line width for Case A
DEFAULT_A2_GAMMA = 0.2      # gamma < 1 darkens faint lines in A2 (1.0 = no change)

# Case A default window (for A1-A3; A4 uses full file)
DEFAULT_A_WINDOW = "downsample"

# Pilot subset: 10 samples covering all classes, apps, and regions
PILOT_SUBSET = [
    "S00",  # benign, euclidean, reg0
    "S01",  # benign, euclidean, reg1
    "S04",  # benign, vadd, reg0
    "S06",  # benign, aes, reg0
    "S08",  # paired-suspicious, euclidean, reg0 (paired with S00)
    "S10",  # paired-suspicious, cosine, reg0
    "S14",  # paired-suspicious, aes, reg0 (paired with S06)
    "S16",  # standalone_1, reg0 (5 ROs)
    "S17",  # standalone_1, reg1 (5 ROs)
    "S22",  # standalone_4, reg0 (5000 ROs)
]

# Variant names
CASE_B_VARIANTS = ["B1", "B2", "B3", "B4"]
CASE_A_VARIANTS = ["A1", "A2", "A3", "A4"]
ALL_VARIANTS = CASE_B_VARIANTS + CASE_A_VARIANTS

# Map variant to window mode (for B variants and A1-A3 default)
VARIANT_WINDOW_MAP = {
    "B1": "first",
    "B2": "last",
    "B3": "center",
    "B4": "downsample",
}
