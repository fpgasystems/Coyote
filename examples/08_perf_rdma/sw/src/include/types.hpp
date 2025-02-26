#include <math.h>

#include "cDefs.hpp"

#include <vector>
#include <chrono>
#include <sys/time.h>  

using namespace coyote;

// Runtime
constexpr auto const fidRDMA = 1;

// Constants
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 512

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this is the only possible value
#define DEFAULT_VFPGA_ID 0