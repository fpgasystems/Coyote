#pragma once

#include <cstdint>
#include <cstdio>
#include <string>

/* FLAGS */
// SET ACCORDING TO THE BITSTREAM
#define EN_AVX
#define EN_DDR
#define EN_RDMA

/* Sleep */
#define POLL_SLEEP_NS 					100

/* Large pages */
#define LARGE_PAGE_SIZE 				(2 * 1024 * 1024)
#define LARGE_PAGE_SHIFT 				21UL
#define PAGE_SIZE 						4 * 1024
#define PAGE_SHIFT 						12UL

/* Clock */
#define CLK_NS 							4

/* Command FIFO depth */
static const uint32_t cmd_fifo_depth = 64; 
static const uint32_t cmd_fifo_thr = 10;

/* Farview Op codes */
enum class opCode : uint8_t { READ=0, WRITE=1, FV=2 };

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