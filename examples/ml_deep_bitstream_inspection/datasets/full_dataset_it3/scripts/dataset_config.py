#!/usr/bin/env python3
"""Dataset configuration for full_dataset_it3.

All iteration-specific parameters are defined here.
Scripts import from this module instead of hardcoding values.
To create a new iteration, copy this file and update values.
"""

import os

# --- Paths ---
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IT1_BASE = os.path.join(os.path.dirname(BASE), "full_dataset_it1")

# --- Iteration metadata ---
ITERATION = "it3"
ITERATION_LABEL = "Full dataset iteration 3"

# --- Floorplans ---
FLOORPLANS = {
    "FP10": "FP10_upper_right_plus_lower_bottom.xdc",
    "FP11": "FP11_upper_left_plus_lower_top.xdc",
    "FP12": "FP12_upper_bottom_plus_lower_left.xdc",
    "FP13": "FP13_upper_top_plus_lower_right.xdc",
    "FP14": "FP14_upper_inner_band.xdc",
}

# --- RO counts (standalone catalog — staggered high-RO regime) ---
RO_COUNTS = [8000, 8750, 9500, 10250, 11000, 11750, 12500, 13250,
             14000, 14750, 15500, 16250, 17000, 17500, 18000]

# --- Benign app catalog (same as it1) ---
BENIGN_APPS = [
    ("benign/A01_hello_world",            "A01 hello_world"),
    ("benign/A02_hls_vadd",               "A02 hls_vadd"),
    ("benign/A03_multitenancy_aes",       "A03 multitenancy_aes"),
    ("benign/A04_user_interrupts",        "A04 user_interrupts"),
    ("benign/A05_perf_fpga",              "A05 perf_fpga"),
    ("benign/A06_multithreading_aes",     "A06 multithreading_aes"),
    ("benign/A07_euclidean",              "A07 euclidean"),
    ("benign/A08_cosine",                 "A08 cosine"),
    ("benign_variants/V01_hello_world_nodbg",        "V01 hello_world nodbg"),
    ("benign_variants/V02_hls_vadd_nodbg",           "V02 hls_vadd nodbg"),
    ("benign_variants/V03_multitenancy_aes_nodbg",   "V03 multitenancy_aes nodbg"),
    ("benign_variants/V04_user_interrupts_nodbg",    "V04 user_interrupts nodbg"),
    ("benign_variants/V05_perf_fpga_nodbg",          "V05 perf_fpga nodbg"),
    ("benign_variants/V06_multithreading_aes_nodbg", "V06 multithreading_aes nodbg"),
    ("benign_variants/V07_euclidean_nodbg",          "V07 euclidean nodbg"),
]

# --- Standalone app catalog (derived from RO_COUNTS) ---
STANDALONE_APPS = [
    (f"standalone/ro_{nro:04d}", f"standalone ro_{nro:04d} (N_RO={nro})")
    for nro in RO_COUNTS
]

# --- Manifest app catalogs (3-tuples for gen_manifest.py) ---
BENIGN_APPS_MANIFEST = [
    ("A01", "hello_world",        "base"),
    ("A02", "hls_vadd",           "base"),
    ("A03", "multitenancy_aes",   "base"),
    ("A04", "user_interrupts",    "base"),
    ("A05", "perf_fpga",          "base"),
    ("A06", "multithreading_aes", "base"),
    ("A07", "euclidean",          "base"),
    ("A08", "cosine",             "base"),
    ("V01", "hello_world_nodbg",        "nodbg"),
    ("V02", "hls_vadd_nodbg",           "nodbg"),
    ("V03", "multitenancy_aes_nodbg",   "nodbg"),
    ("V04", "user_interrupts_nodbg",    "nodbg"),
    ("V05", "perf_fpga_nodbg",          "nodbg"),
    ("V06", "multithreading_aes_nodbg", "nodbg"),
    ("V07", "euclidean_nodbg",          "nodbg"),
]

STANDALONE_APPS_MANIFEST = [
    (f"RO_{nro:04d}", f"ro_{nro:04d}", "standalone")
    for nro in RO_COUNTS
]

# --- Batch order ---
BATCH_ORDER = [
    "BENIGN_FP10", "BENIGN_FP11", "BENIGN_FP12", "BENIGN_FP13", "BENIGN_FP14",
    "STAND_FP10",  "STAND_FP11",  "STAND_FP12",  "STAND_FP13",  "STAND_FP14",
]

# --- Shell profile (frozen) ---
SHELL_PARAMS = {
    "FDEV_NAME": "u55c",
    "N_REGIONS": 1,
    "EN_PR": 1,
    "N_CONFIG": 15,
    "EN_STRM": 1,
    "N_STRM_AXI": 2,
    "EN_MEM": 0,
}

# --- Reference HDL source (for gen_standalone_apps.py) ---
PILOT_STANDALONE_HDL = os.path.join(IT1_BASE, "hw", "apps", "standalone", "ro_8192", "hdl")
