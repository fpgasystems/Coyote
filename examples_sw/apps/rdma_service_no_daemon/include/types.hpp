#include <math.h>

#include "cDefs.hpp"

#include <vector>
#include <chrono>
#include <sys/time.h>  

using namespace fpga;

// Runtime
constexpr auto const fidRDMA = 1;

constexpr auto const operatorRDMA = 1;
constexpr auto const opPriority = 1;
