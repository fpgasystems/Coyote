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
4. The shell pipeline translates the buffer address, finishes the PRP list, and stores the NVMe SQE. It enqueues an assignment response on `s_nvme_cq_rsp` before requesting the SQ doorbell. The SSD then transfers the payload to/from the buffer (HBM in the PL read benchmark).
5. Completions flow back through the CQ BRAM, are decoded into `nvme_cqe_t`, and route to the owning region as `s_nvme_cpl`. Each per-device FSM consumes completions targeting its `dev_id`, decrements its inflight counter and increments its done counter. When all devices have reached `dev_done >= N_REPS` with no inflight commands, the bench is complete.
6. The host polls `DONE_REG` until it matches the expected count and reads `TIMER_REG` to compute the aggregated bandwidth.

The bench engine supports running a subset of devices via the `DEV_MASK` register, so the same hardware build can sweep individual devices or all devices in parallel without re-synthesizing.

## Hardware concepts
### NVMe submission interface (`m_nvme_sq`)
NVMe submission requests from the vFPGA are sent as `req_t` values with `strm == STRM_NVME`. The relevant fields are:
- `dev_id`  : NVMe device index assigned by the driver (`0..MAX_NVME_DEVICES-1`)
- `nsid`    : namespace identifier (typically `1` for a single-namespace SSD)
- `vaddr`   : buffer virtual address (translated by the shared `tlb_fsm` pipeline)
- `len`     : transfer length in bytes (must be a multiple of `lba_size`)
- `naddr`   : starting LBA byte offset within the per-region LBA range
- `writeRead`: `1` for WRITE, `0` for READ

### NVMe completion interface (`s_nvme_cq_rsp` and `s_nvme_cpl`)
Completions arrive as `nvme_cqe_t` (`dev_id[3:0]`, `cid[7:0]`, `status[14:0]`, `phase`). The bench engine demuxes them by `dev_id` to update per-device counters. Completions can arrive out of submission order.

The 16-bit `s_nvme_cq_rsp` channel returns one response per accepted request, in submission order within the region:

| Device | Assigned CID (success only) | Local error |
| --- | --- | --- |
| `[15:12]` | `[11:4]` | `[3:0]` |

The layout is the same at every queue depth. The CID field is 8 bits wide, as in `nvme_cqe_t`; at depth 64 or 128 its upper bits are zero. Local errors are 0 success, 1 device/namespace unknown, 3 PRP preparation failure, and 6 permission/range failure (`NVME_RSP_ERROR_BITS` = 4, `NVME_RSP_CID_BITS` = 8).

Set `-DNVME_QUEUE_DEPTH=256` when configuring hardware to increase the I/O queues; supported values are 64, 128, and 256 for both HOST and PL. Admin queues remain 64 entries. Build and bundle the driver, shell and application together. The driver reads the actual depth from shell NVMe configuration CSR bits `[16:8]` and uses it for HOST queue creation. The SQ, CQ and PRP-list address windows are the same at every depth (sized for 256 entries), so only the queue size changes. A ring permits depth minus one unconsumed SQ entries.

Set `-DNVME_NUM_DEVICES=N` to instantiate control state for `N` device slots, numbered `0..N-1`. The default is 1; HOST supports every integer from 1 through 16. A HOST build using multiple SSDs must reserve enough slots. PL currently supports only one physical SSD/queue pair, so CMake requires `NVME_NUM_DEVICES=1` when `EN_NVME=1` and `NVME_TYPE=PL`. Device IDs remain four bits in requests, completions and the unchanged 16-bit assignment response. Inactive-device requests return the existing no-device error. Public SQ/CQ/PRP address windows and their backing data RAM geometry remain unchanged; CID state, CQ validity state and polling are pruned to the configured count. Shell CSR bits `[24:20]` advertise the actual count, and the matching driver rejects claims beyond this capacity.

Each device allocates CIDs from a FIFO with a registered head. Accepted completions return CIDs to the FIFO; an aborted unpublished command returns its CID to a separate one-entry cache, consumed before the FIFO. This handles a completion and preparation abort in the same cycle with one FIFO write port. CID/PRP ownership remains separate from SQ space: SQHD advances SQ capacity, while only a validated completion or preparation abort releases a CID. The pool initializes for `NVME_QUEUE_DEPTH` clocks after reset or quiescent queue recreation (256 clocks = 1.024 microseconds at 250 MHz); submissions wait until initialization finishes.

PL CQ doorbells batch 16 completions at depth 64, or 32 at larger depths, with a 1,000-cycle timeout; HOST retains its original batching. PL MMIO permits eight writes outstanding. Place-and-route timing and hardware throughput must be checked on the rebuilt design.

Successful assignments do not count as completions or return outstanding-command credits. The benchmark ignores them and captures only a nonzero local error into the existing zero-extended `ERROR_REG`; a successful response can have a nonzero packed value. A local failure still requires treating the benchmark run as failed and resetting before retry: its existing inflight counter only decrements on `s_nvme_cpl`.

An application can pair ordered responses with pending requests to learn their `(device, CID)` assignments. Response and completion delivery are independent under backpressure, and CID reuse is allowed while old notifications remain buffered. The application must handle a completion received before its assignment and preserve the order of successive uses of the same `(device, CID)`. The core adds no user-delivery gates. The count-based benchmark does not need such a mapping.

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
