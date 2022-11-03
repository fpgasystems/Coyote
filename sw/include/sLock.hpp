#pragma once

#include "cDefs.hpp"

#include <cstdint>
#include <cstdio>
#include <string>
#include <unordered_map> 
#include <unordered_set> 
#include <boost/functional/hash.hpp>
#include <boost/interprocess/sync/scoped_lock.hpp>
#include <boost/interprocess/sync/named_mutex.hpp>
#ifdef EN_AVX
#include <x86intrin.h>
#include <smmintrin.h>
#include <immintrin.h>
#endif
#include <unistd.h>
#include <errno.h>
#include <byteswap.h>
#include <iostream>
#include <fcntl.h>
#include <inttypes.h>
#include <mutex>
#include <atomic>
#include <sys/mman.h>
#include <sys/types.h>
#include <thread>
#include <sys/ioctl.h>
#include <fstream>

using namespace std;
using namespace boost::interprocess;

namespace fpga {

/* Spinlock */
class sLock {
private:
	std::atomic_flag lck = ATOMIC_FLAG_INIT;

public:
	void lock() { while(lck.test_and_set(std::memory_order_acquire)) {} }
	void unlock() {lck.clear(std::memory_order_relaxed); }
};

}