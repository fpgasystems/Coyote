/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
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

#include <iostream>
#include <stdexcept>
#include <cstdint>

#include <coyote/cThread.hpp>

#define DEFAULT_VFPGA_ID 0

// One 512-bit AXI beat holds exactly 16 × 32-bit integers
static constexpr int N = 16;
static constexpr uint TRANSFER_BYTES = N * sizeof(int32_t);

int main() {
    HEADER("Bug report: reduce_ops int32 add (one AXI beat)");
    std::cout << "Elements per beat : " << N << std::endl;
    std::cout << "Transfer size     : " << TRANSFER_BYTES << " bytes" << std::endl;

    // Allocate buffers for the two operands and the result
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    int32_t *a = (int32_t *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, TRANSFER_BYTES});
    int32_t *b = (int32_t *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, TRANSFER_BYTES});
    int32_t *c = (int32_t *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, TRANSFER_BYTES});
    if (!a || !b || !c) throw std::runtime_error("Memory allocation failed");

    // Fill operands: odd numbers in a, even numbers in b
    // Expected result: a[i] + b[i] = (2i+1) + (2i+2) = 4i+3
    for (int i = 0; i < N; i++) {
        a[i] = 2*i + 1;   // 1, 3, 5, ..., 31
        b[i] = 2*i + 2;   // 2, 4, 6, ..., 32
        c[i] = 0;
    }

    std::cout << "Operand a : ";
    for (int i = 0; i < N; i++) std::cout << a[i] << (i < N-1 ? ", " : "\n");
    std::cout << "Operand b : ";
    for (int i = 0; i < N; i++) std::cout << b[i] << (i < N-1 ? ", " : "\n");

    // Send a to stream 0, b to stream 1; receive result on stream 0
    coyote::localSg sg_a = {.addr = a, .len = TRANSFER_BYTES, .dest = 0};
    coyote::localSg sg_b = {.addr = b, .len = TRANSFER_BYTES, .dest = 1};
    coyote::localSg sg_c = {.addr = c, .len = TRANSFER_BYTES, .dest = 0};

    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ,  sg_a);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ,  sg_b);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_c);
    while (
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 ||
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ)  != 2
    ) {}

    // Verify: c[i] must equal a[i] + b[i]
    std::cout << "Result c  : ";
    for (int i = 0; i < N; i++) std::cout << c[i] << (i < N-1 ? ", " : "\n");

    bool pass = true;
    for (int i = 0; i < N; i++) {
        int32_t expected = a[i] + b[i];
        if (c[i] != expected) {
            std::cerr << "MISMATCH at index " << i
                      << ": got " << c[i] << ", expected " << expected << std::endl;
            pass = false;
        }
    }

    if (!pass) throw std::runtime_error("Validation FAILED");
    HEADER("Validation passed!");
}
