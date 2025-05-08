// Constants shared by both client and server
// Placed in separate file to avoid any weird changes in one file not reflect in the other

// Default (physical) FPGA device for nodes with multiple FPGAs
#define DEFAULT_DEVICE 0

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

// Operator IDs
#define OP_EUCLIDEAN_DISTANCE 0
#define OP_COSINE_SIMILARITY 1

// Operator priorities
#define DEFAULT_OPERATOR_PRIORITY 1
