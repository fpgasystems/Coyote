#!/usr/bin/env python3
"""Dataset configuration for full_dataset_it4_big_ro.

This iteration is standalone-only: six reused floorplans, thirteen
big-hammer ring-oscillator sizes, and 78 target partial bitstreams.
Previous dataset iterations are read-only inputs.
"""

import os

# --- Paths ---
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IT1_BASE = os.path.join(os.path.dirname(BASE), "full_dataset_it1")

# --- Iteration metadata ---
ITERATION = "it4_big_ro"
ITERATION_LABEL = "Full dataset iteration 4 - big-hammer RO"

# --- Target sizing model ---
TARGET_DEVICE = "xcu55c-fsvh2892-2L-e"
TARGET_DEVICE_LUTS = 1_304_000
LUTS_PER_RO = 3

# 13 samples: 6.0% through 22.5% in 1.5% steps, plus the 25.0% endpoint.
# The 25% endpoint is floor-rounded so modeled RO LUTs do not exceed 25%.
RO_TARGET_PCTS = [6.0, 7.5, 9.0, 10.5, 12.0, 13.5, 15.0,
                  16.5, 18.0, 19.5, 21.0, 22.5, 25.0]
RO_COUNTS = [26080, 32600, 39120, 45640, 52160, 58680, 65200,
             71720, 78240, 84760, 91280, 97800, 108666]
CONFIG_COUNT = len(RO_COUNTS)
assert len(RO_TARGET_PCTS) == CONFIG_COUNT

# --- Floorplans copied into this iteration ---
FLOORPLANS = {
    "FP04": "FP04_upper_right_trim.xdc",
    "FP06": "FP06_upper_trim_top.xdc",
    "FP08": "FP08_lower_right_trim.xdc",
    "FP09": "FP09_upper_left_plus_lower_bottom.xdc",
    "FP10": "FP10_upper_right_plus_lower_bottom.xdc",
    "FP14": "FP14_upper_inner_band.xdc",
}

# --- Standalone app catalog (derived from RO_COUNTS) ---
STANDALONE_APPS = [
    (f"standalone/ro_{nro:04d}", f"standalone ro_{nro:04d} (N_RO={nro})")
    for nro in RO_COUNTS
]

STANDALONE_APPS_MANIFEST = [
    (f"RO_{nro:04d}", f"ro_{nro:04d}", "standalone")
    for nro in RO_COUNTS
]

# Kept for script compatibility; this iteration does not generate benign batches.
BENIGN_APPS = []
BENIGN_APPS_MANIFEST = []

# --- Batch order ---
BATCH_ORDER = [
    "STAND_FP06",
    "STAND_FP08",
    "STAND_FP09",
    "STAND_FP10",
    "STAND_FP04",
    "STAND_FP14",
]

# Salvage remapping: the original it4 plan used STAND_FP11 in this slot, but
# high-RO FP11 jobs hit routing/unrouted-net behavior. Keep the sample indices
# stable and rebuild the whole slot using FP04.
FLOORPLAN_REASSIGNMENTS = {
    "STAND_FP04": {
        "original_batch_id": "STAND_FP11",
        "original_floorplan_id": "FP11",
        "reason": "FP11_route_congestion_salvage",
    },
}

# --- Shell profile ---
SHELL_PARAMS = {
    "FDEV_NAME": "u55c",
    "N_REGIONS": 1,
    "EN_PR": 1,
    "N_CONFIG": CONFIG_COUNT,
    "EN_STRM": 1,
    "N_STRM_AXI": 2,
    "EN_MEM": 0,
}

# --- Reference HDL source (for gen_standalone_apps.py) ---
PILOT_STANDALONE_HDL = os.path.join(
    IT1_BASE, "hw", "apps", "standalone", "ro_8192", "hdl"
)
