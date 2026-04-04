#!/usr/bin/env python3
"""Dataset configuration for full_dataset_it2.

All iteration-specific parameters are defined here.
Scripts import from this module instead of hardcoding values.
To create a new iteration, copy this file and update values.
"""

import os

# --- Paths ---
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IT1_BASE = os.path.join(os.path.dirname(BASE), "full_dataset_it1")

# --- Iteration metadata ---
ITERATION = "it2"
ITERATION_LABEL = "Full dataset iteration 2"

# --- Floorplans ---
FLOORPLANS = {
    "FP05": "FP05_upper_trim_bottom.xdc",
    "FP06": "FP06_upper_trim_top.xdc",
    "FP07": "FP07_lower_left_trim.xdc",
    "FP08": "FP08_lower_right_trim.xdc",
    "FP09": "FP09_upper_left_plus_lower_bottom.xdc",
}

# --- RO counts (standalone catalog — high-RO regime) ---
RO_COUNTS = [8000, 9000, 10000, 11000, 12000, 13000, 14000, 15000,
             16000, 17000, 18000, 19000, 20000, 21000, 22000]

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
    "BENIGN_FP05", "BENIGN_FP06", "BENIGN_FP07", "BENIGN_FP08", "BENIGN_FP09",
    "STAND_FP05",  "STAND_FP06",  "STAND_FP07",  "STAND_FP08",  "STAND_FP09",
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
