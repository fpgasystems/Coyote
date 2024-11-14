# Read/write benchmark for operations initiated by the CPU

This performance benchmark measures the throughput and latency of the CPU-initiated read and write transfers. `hMem` is the data buffer, `sg` is the struct that contains the transfer parameters, and `invoke` starts the transfer. `hMem` contains random data, the data is read and directly written back into that buffer.

Hint: Results of this benchmark are not checked for correctness.

## Parameters

- `[--regions | -g] <uint32_t>` How many vFPGAs to use (default is 4).
- `[--hugepages | -h] <bool>` If huge pages are used (default is true).
- `[--mapped | -m] <bool>` If pages are mapped (default is true). TODO: What does this mean?
- `[--stream | -s] <bool>` If the data is streamed from the host (true) or card (false) memory. Expected maximum throughput is ~12.5GB/s for host and ~16GB/s for card (default is host).
- `[--repst | -r <uint32_t>` Number of repetitions for the throughput benchmarks (default is 10000).
- `[--repsl | -l <uint32_t>` Number of repetitions for the latency benchmarks (default is 100).
- `[--min_size | -n <uint32_t>` Starting transfer size in bytes (default is 1024).
- `[--max_size | -x <uint32_t>` Ending transfer size in bytes (default is 1024 * 1024).
