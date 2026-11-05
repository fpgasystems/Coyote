/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef XOROSHIRO128PLUSPLUS_HPP
#define XOROSHIRO128PLUSPLUS_HPP

#include <cstdint>

/**
 * @file xoroshiro128plusplus.hpp
 * @brief Synthesizable xoroshiro128++ pseudo-random number generator for Vitis HLS.
 *
 * Designed by David Blackman and Sebastiano Vigna (2019).
 * Features:
 * - 128-bit state with period 2^128 - 1.
 * - 0 DSP / 0 hardware multipliers: state transitions use only bit-rotates (wire renaming) and XORs.
 * - Output scrambler rotl(s0 + s1, 17) + s0 uses two 64-bit carry-chain additions (~2.2 ns).
 * - Full bit independence across all 64 bits (all bits pass BigCrush and PractRand).
 * - Allows extracting two uncorrelated 32-bit random numbers (lower and upper halves)
 *   from a single 64-bit step in 1 clock cycle.
 */
class xoroshiro128plusplus {
private:
    uint64_t s[2];

    static inline uint64_t rotl(const uint64_t x, int k) {
        #pragma HLS INLINE
        return (x << k) | (x >> (64 - k));
    }

public:
    xoroshiro128plusplus() {
        #pragma HLS INLINE
        s[0] = 0x123456789ABCDEF0ULL;
        s[1] = 0x9E3779B97F4A7C15ULL;
    }

    explicit xoroshiro128plusplus(uint64_t seed_val) {
        #pragma HLS INLINE
        seed(seed_val);
    }

    /// Initialize the generator with seed_val.
    inline void init(uint64_t seed_val) {
        #pragma HLS INLINE
        seed(seed_val);
    }

    void seed(uint64_t seed_val) {
        #pragma HLS INLINE
        // Initialize state via SplitMix64 to guarantee non-zero state
        uint64_t z = seed_val + 0x9E3779B97F4A7C15ULL;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        s[0] = z ^ (z >> 31);

        z += 0x9E3779B97F4A7C15ULL;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        s[1] = z ^ (z >> 31);

        if (s[0] == 0ULL && s[1] == 0ULL) {
            s[0] = 1ULL;
        }
    }

    /// Generate 64 bits of uniform pseudo-random output
    inline uint64_t next() {
        #pragma HLS INLINE
        const uint64_t s0 = s[0];
        uint64_t s1 = s[1];
        const uint64_t result = rotl(s0 + s1, 17) + s0;

        s1 ^= s0;
        s[0] = rotl(s0, 49) ^ s1 ^ (s1 << 21);
        s[1] = rotl(s1, 28);

        return result;
    }

    /// Generate a 32-bit unsigned random integer
    inline uint32_t nextUInt() {
        #pragma HLS INLINE
        return static_cast<uint32_t>(next());
    }

    /// Generate a uniformly distributed 32-bit integer in [0, bound) using Lemire's fast range reduction
    inline uint32_t nextUInt(uint32_t bound) {
        #pragma HLS INLINE
        return bound > 0 ? static_cast<uint32_t>((static_cast<uint64_t>(nextUInt()) * bound) >> 32) : 0;
    }

    /// Extract two independent 32-bit random integers from a single 64-bit step
    inline void nextPair(uint32_t &r1, uint32_t &r2) {
        #pragma HLS INLINE
        uint64_t v = next();
        r1 = static_cast<uint32_t>(v);
        r2 = static_cast<uint32_t>(v >> 32);
    }

    /// Extract two independent 32-bit random integers in [0, bound) from a single 64-bit step using Lemire's fast range reduction
    inline void nextPair(uint32_t bound, uint32_t &r1, uint32_t &r2) {
        #pragma HLS INLINE
        uint64_t v = next();
        uint32_t v1 = static_cast<uint32_t>(v);
        uint32_t v2 = static_cast<uint32_t>(v >> 32);
        r1 = bound > 0 ? static_cast<uint32_t>((static_cast<uint64_t>(v1) * bound) >> 32) : 0;
        r2 = bound > 0 ? static_cast<uint32_t>((static_cast<uint64_t>(v2) * bound) >> 32) : 0;
    }
};

#endif // XOROSHIRO128PLUSPLUS_HPP

