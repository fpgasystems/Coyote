#pragma once

#include <cstdint>
#include <cstdio>
#include <string>

/* FLAGS */
// TODO: SET ACCORDING TO THE BITSTREAM (Should enable the reading of these things through the driver)
#define EN_AVX
#define EN_DDR
//#define EN_RDMA

/* Farview Op codes */
enum class opCode : uint8_t { READ=0, WRITE=1, RPC=2 };

/* Verbosity */
#define VERBOSE_DEBUG_1
//#define VERBOSE_DEBUG_2
//#define VERBOSE_DEBUG_3

/* ltoh: little to host */
/* htol: little to host */
#if __BYTE_ORDER == __LITTLE_ENDIAN
#  define ltohl(x)       (x)
#  define ltohs(x)       (x)
#  define htoll(x)       (x)
#  define htols(x)       (x)
#elif __BYTE_ORDER == __BIG_ENDIAN
#  define ltohl(x)     __bswap_32(x)
#  define ltohs(x)     __bswap_16(x)
#  define htoll(x)     __bswap_32(x)
#  define htols(x)     __bswap_16(x)
#endif