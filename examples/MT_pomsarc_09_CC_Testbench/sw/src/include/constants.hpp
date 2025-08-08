// Constants shared by both client and server;
// Placed in separate file to avoid any weird changes in one file not reflect in the other

// Benchmark parameters
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 64

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this is the only possible value
#define DEFAULT_VFPGA_ID 0