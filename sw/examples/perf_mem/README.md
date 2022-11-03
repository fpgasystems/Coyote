# Example benchmarking base read and write operations initiated by the HOST

This performance benchmark measures the throughput and latency of the FPGA side memories with striping access pattern (across multiple channels) when 4 vFPGAs are accessing the memory concurrently. 

## Note

`Coyote` provides the unified environment for the user logic independent of the attached memory type. This benchmark can thus run with both DRAM and HBM.

## TODO

* Printout results