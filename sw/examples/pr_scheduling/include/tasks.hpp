#pragma once

#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h>
#include <sys/time.h>
#include <chrono>
#include <set>
#include <vector>
#include <sstream>

#include "cArbiter.hpp"

using namespace std;
using namespace std::chrono;

constexpr auto const defAddmul = 2; 

/**
 * @brief Tasks
 * 
 */

// Add + multiply
auto addmul = [](cThread *cthread, uint32_t size, uint32_t add, uint32_t mul);

// Stream statistics
auto minmax = [](cThread *cthread, uint32_t size);

// Rotation
auto rotation = [](cThread *cthread, uint32_t size);

// Testcount
auto testcount = [](cThread *cthread, uint32_t size, uint32_t type, uint32_t cond);