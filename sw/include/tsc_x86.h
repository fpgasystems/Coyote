#pragma once

#include "cDefs.hpp"

#ifdef EN_AVX

// ================= GNU C and possibly other UNIX compilers =================
#ifndef _WIN32

#if defined(__GNUC__) || defined(__linux__)
#define VOLATILE __volatile__
#define ASM __asm__
#else
/* if we're neither compiling with gcc or under linux, we can hope
 * the following lines work, they probably won't */
#define ASM asm
#define VOLATILE
#endif

#define myInt64 unsigned long long
#define INT32 unsigned int

// ================================== WIN32 ==================================
#else

#define myInt64 signed __int64
#define INT32 unsigned __int32

#endif

/* This is the RDTSC timer.
 * RDTSC is an instruction on several Intel and compatible CPUs that Reads the
 * Time Stamp Counter. The Intel manuals contain more information.
 */

#define COUNTER_LO(a) ((a).int32.lo)
#define COUNTER_HI(a) ((a).int32.hi)
#define COUNTER_VAL(a) ((a).int64)

#define COUNTER(a) ((unsigned long long)COUNTER_VAL(a))

#define COUNTER_DIFF(a, b) (COUNTER(a) - COUNTER(b))

// ================= GNU C and possibly other UNIX compilers =================
#ifndef _WIN32

typedef union {
  myInt64 int64;
  struct {
    INT32 lo, hi;
  } int32;
} tsc_counter;

#define RDTSC(cpu_c) \
  ASM VOLATILE("rdtsc" : "=a"((cpu_c).int32.lo), "=d"((cpu_c).int32.hi))
#define CPUID() ASM VOLATILE("cpuid" : : "a"(0) : "bx", "cx", "dx")

// ================================== WIN32 ==================================
#else

typedef union {
  myInt64 int64;
  struct {
    INT32 lo, hi;
  } int32;
} tsc_counter;

#define RDTSC(cpu_c) \
  { __asm rdtsc __asm mov(cpu_c).int32.lo, eax __asm mov(cpu_c).int32.hi, edx }

#define CPUID() \
  { __asm mov eax, 0 __asm cpuid }

#endif

// static void init_tsc() {
//   ;  // no need to initialize anything for x86
// }

static myInt64 start_tsc(void) {
  tsc_counter start;
  CPUID();
  RDTSC(start);
  return COUNTER_VAL(start);
}

static myInt64 stop_tsc(myInt64 start) {
  tsc_counter end;
  RDTSC(end);
  CPUID();
  return COUNTER_VAL(end) - start;
}

#endif

