# Example benchmarking base read and write operations initiated by the FPGA

This performance benchmark measures the throughput and latency of the FPGA initiated read and write transfers. 

The results should (hopefully) point to the advantage the FPGA initiated transfers have over their CPU initiated counterparts. As all user logic in `Coyote` is virtualized, these transfers can use the same virtual address ranges available in the user space.

## Note

On Alveo platforms completion events fired by XDMA signal only the completion within the DMA engine (weird design choice within an XDMA core...). This doesn't measure the time it takes to actually write the data. To measure this, writeback memory should be polled. For this reason, the results will show a much smaller latency for write operations.

This is not the case in Enzian where measurements are actually measuring the correct completion.

## TODO

* Poll on writeback
* Printout results
