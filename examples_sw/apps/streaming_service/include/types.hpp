#include <math.h>

#include "cDefs.hpp"

#include <vector>
#include <chrono>
#include <sys/time.h>  

using namespace fpga;

// Runtime
constexpr auto const fidHLL = 1;
constexpr auto const fidDtrees = 2;

constexpr auto const operatorHLL = 1;
constexpr auto const operatorDtrees = 2;

constexpr auto const opPriority = 1;

constexpr auto const defDevice = 0;
constexpr auto const defTargetVfid = 0;

constexpr auto const defDW = 4;