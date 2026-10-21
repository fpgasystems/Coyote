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

#include "genome_hash.hpp"
#include <cstring>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#define HAS_X86_CRC32 1
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC push_options
#pragma GCC target("sse4.2")
#include <nmmintrin.h>
#pragma GCC pop_options
#elif defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

const char *get_hash_backend_name() {
#if defined(HAS_X86_CRC32)
    return "Hardware CRC32 (SSE 4.2)";
#else
    return "Software FNV-1a (Portable)";
#endif
}

#if defined(HAS_X86_CRC32) && (defined(__GNUC__) || defined(__clang__))
__attribute__((target("sse4.2")))
#endif
std::uint64_t hash_genome(const std::uint8_t *bytes, std::size_t length) {
#if defined(HAS_X86_CRC32)
    std::uint64_t crc = 0xFFFFFFFFull;
    std::size_t i = 0;
    for (; i + 8 <= length; i += 8) {
        std::uint64_t chunk;
        std::memcpy(&chunk, bytes + i, sizeof(chunk));
        crc = _mm_crc32_u64(crc, chunk);
    }
    for (; i < length; ++i) {
        crc = _mm_crc32_u8(static_cast<std::uint32_t>(crc), bytes[i]);
    }
    return crc == 0 ? 1ull : crc;
#else
    // Fallback: 64-bit FNV-1a
    std::uint64_t h = 14695981039346656037ull;
    for (std::size_t i = 0; i < length; ++i) {
        h ^= static_cast<std::uint64_t>(bytes[i]);
        h *= 1099511628211ull;
    }
    return h == 0 ? 1ull : h;
#endif
}
