# Coyote Example 10: FPGA Register Programming

This example demonstrates and verifies the **FPGA register programming** functionality using the **Coyote framework**.

## Overview

The core idea is to export a control register from the FPGA and write to it **directly from the GPU** using **DMAbuf**. The objective is to perform **single write transactions** at different addresses to ensure:

- **No write coalescing**
- **No write reordering**

These are typical GPU features that can interfere with correct register programming. For accurate and deterministic behavior, such optimizations must be avoided.

## Why This Matters

While coalescing and reordering are beneficial for GPU performance, they can **break FPGA register semantics**. This example ensures the GPU respects strict ordering and avoids combining transactions, which is essential for reliable register-level interaction.

## Prerequisites

> ⚠️ **Important:** This example requires modifications to the **AMDGPU driver**.  
> Ensure the necessary patches are applied to enable proper DMAbuf-based communication and register access.

## ILA Support

To test ILA, we suggest that you set probes for axictrl.wready and axictrl.wvalid to 1.
