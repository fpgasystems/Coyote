// Constants shared by both client and server;
// Placed in separate file to avoid any weird changes in one file not reflect in the other

// Benchmark parameters
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 32

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this is the only possible value
#define DEFAULT_VFPGA_ID 0

// Run-time parameters; users can change these from the CLI
#define N_RUNS_DEFAULT              10
#define MIN_TRANSFER_SIZE_DEFAULT   64
#define MAX_TRANSFER_SIZE_DEFAULT   (1 * 1024 * 1024)

