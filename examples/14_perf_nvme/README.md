# Coyote Example 14: NVMe SSD Bandwidth Test
Welcome to the fourteenth Coyote example! In this example we measure the read and write bandwidth of one or more NVMe SSDs that have been claimed by the FPGA shell, with NVMe submission queues (SQ), completion queues (CQ) and PRP lists living in FPGA BRAM. As with all Coyote examples, a brief description of the core Coyote concepts covered in this example are included below. How to synthesize hardware, compile the examples and load the bitstream/driver is explained in the top-level example README in `Coyote/examples/README.md`. Please refer to that file for general Coyote guidance.

## Table of contents
[Example Overview](#example-overview)

[Hardware Concepts](#hardware-concepts)

[Software Concepts](#software-concepts)

[Additional Information](#additional-information)

## Example overview
This example exercises the NVMe stack added to the Coyote shell. The vFPGA contains a bench engine that, on a `start_rd` or `start_wr` pulse, issues `N_REPS` NVMe commands per active device, with up to `MAX_OUTSTANDING` in flight at a time, and measures the wall-clock cycles between go pulse and the last completion (per device). The software side claims one or more NVMe controllers via `coyote::cThread::initNVMe()`, programs the per-run parameters into CSRs, kicks off the bench engine and reads back the aggregated bandwidth.

A high-level walk-through of a single run:

1. The host claims the requested NVMe SSDs via `IOCTL_NVME_INIT`. Internally the driver takes over the PCI device, brings up the controller, sets up an admin queue, identifies the active namespace and creates an I/O SQ/CQ whose memory lives in FPGA BRAM. The kernel returns the assigned `dev_id` (one per device) plus per-namespace info (LBA size, NSZE, MDTS).
2. The host writes the benchmark CSRs (buffer base address, chunk size, number of repetitions per device, starting LBA, device mask, max outstanding, namespace) and pulses `CTRL_REG`.
3. Per-device FSMs in the vFPGA build `req_t` NVMe submission requests (`strm = STRM_NVME`) and feed them to a round-robin arbiter, which forwards them to the shell NVMe pipeline on `m_nvme_sq`.
4. The shell pipeline performs vaddr→paddr translation (via `tlb_fsm` with `STRM_NVME`), builds the NVMe SQE, writes it into the FPGA SQ BRAM and rings the SSD's SQ doorbell via DMA. The SSD then DMAs the requested data to/from the host buffer.
5. Completions flow back through the CQ BRAM, are decoded by the shell into `nvme_cqe_t` and broadcast to all regions as `s_nvme_cpl`. Each per-device FSM consumes completions targeting its `dev_id`, decrements its inflight counter and increments its done counter. When all devices have reached `dev_done >= N_REPS` with no inflight commands, the bench is complete.
6. The host polls `DONE_REG` until it matches the expected count and reads `TIMER_REG` to compute the aggregated bandwidth.

The bench engine supports running a subset of devices via the `DEV_MASK` register, so the same hardware build can sweep individual devices or all devices in parallel without re-synthesizing.

## Hardware concepts
### NVMe submission interface (`m_nvme_sq`)
NVMe submission requests from the vFPGA are sent as `req_t` values with `strm == STRM_NVME`. The relevant fields are:
- `dev_id`  : NVMe device index assigned by the driver (`0..MAX_NVME_DEVICES-1`)
- `nsid`    : namespace identifier (typically `1` for a single-namespace SSD)
- `vaddr`   : host buffer virtual address (translated by the shared `tlb_fsm` pipeline)
- `len`     : transfer length in bytes (must be a multiple of `lba_size`)
- `naddr`   : starting LBA byte offset within the per-region LBA range
- `writeRead`: `1` for WRITE, `0` for READ

### NVMe completion interface (`s_nvme_cpl`)
Completions arrive as `nvme_cqe_t` (`dev_id`, `status[14:0]`, `phase`). The bench engine in this example demuxes them by `dev_id` to update per-device counters. The `s_nvme_cq_rsp` channel additionally surfaces front-end errors (e.g. permission denied, namespace unknown) on a per-request basis; this example latches the most recent error code into the `ERROR_REG` CSR for visibility.

### Per-device FSM + round-robin arbiter
The vFPGA instantiates `BENCH_MAX_DEVS` (default 4) independent FSMs. Each FSM owns its own inflight counter, send pointer and timer, and produces a single `dev_req` to a round-robin arbiter that feeds the shell on `m_nvme_sq`. This keeps the worst-case bandwidth bounded by the shell's single-NVMe-pipeline arbitration rather than by per-device serial issue.

## Software concepts
### `coyote::cThread::initNVMe(bdf, nsid, size)`
Claims an NVMe SSD identified by its PCI BDF for this vFPGA region. The returned `nvmeInitIoctl` exposes the FPGA `dev_id`, the namespace's `lba_size`, total `nsze`, the reserved LBA range (`lba_offset`/`lba_count`) and the device's `mdts` (which the SW uses to clamp the chunk size). The SQ/CQ doorbell addresses are returned for informational purposes.

### `coyote::cThread::closeNVMe(dev_id)`
Releases the LBA range reserved by `initNVMe()` for this region. The shell continues to own the controller until the last region releases it; the driver tears the controller down when no region remains.

### `coyote::cThread::isNVMeRegistered(bdf, nsid)`
Non-throwing query used to discover whether a given `(BDF, NSID)` pair is already registered for this region. Useful for idempotent setup paths and for inspecting the in-kernel device table.

## Additional information
### Command line parameters
- `[--bdf | -b] <BDF>` PCI BDF of the NVMe SSD to claim. Repeat the flag for multi-device tests. **Required.**
- `[--total | -t] <size>` Total transfer per device (suffixes: `K`, `M`, `G`). Default: `64M`.
- `[--chunk | -c] <size>` Size of each NVMe command. Default: `4K`.
- `[--alloc | -a] <size>` Per-device LBA allocation request (default: `total`).
- `[--outstanding | -o] <n>` Maximum in-flight commands per device. Must be `< 64`. Default: `16`.
- `[--vfpga | -v] <id>` vFPGA ID to run on. Default: `0`.
- `[--read-only | -r]` Run only the READ phase.
- `[--write-only | -w]` Run only the WRITE phase.

### Example invocations
Single SSD, 4 KB chunks:
```
bin/test -b 0000:01:00.0
```

Two SSDs in parallel, 128 KB chunks, 1 GB total per device:
```
bin/test -b 0000:01:00.0 -b 0000:02:00.0 -c 128K -t 1G
```

Write-only sweep on one SSD with 32 in-flight commands:
```
bin/test -b 0000:01:00.0 -o 32 -w
```
