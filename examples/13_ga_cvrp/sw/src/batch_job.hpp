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

/**
 * Descriptor for a batch of parent/offspring individuals dispatched between
 * the host Population Manager and vFPGA workers.
 * Pure host data structure - no Coyote dependency.
 */

#ifndef BATCH_JOB_HPP
#define BATCH_JOB_HPP

#include <cstddef>
#include <cstdint>
#include <vector>

struct EncodedIndividual {
    const std::uint8_t* bytes = nullptr;
    std::uint32_t fitness = 0;
    std::uint64_t hash = 0;

    bool operator<(const EncodedIndividual& other) const {
        if (fitness != other.fitness) {
            return fitness < other.fitness;
        }
        return hash < other.hash;
    }

    bool operator==(const EncodedIndividual& other) const {
        return fitness == other.fitness && hash == other.hash;
    }

    bool operator!=(const EncodedIndividual& other) const {
        return !(*this == other);
    }
};

struct BatchBufferSlot {
    int slot_id = 0;
    int vfid = 0;
    std::size_t num_ind_per_stream = 0;

    std::uint8_t *src_buf_0 = nullptr;
    std::uint8_t *src_buf_1 = nullptr;

    std::uint8_t *dst_buf_0 = nullptr;
    std::uint8_t *dst_buf_1 = nullptr;
};

struct BatchJob {
    uint32_t batch_id = 0;
    int vfid = 0;
    int slot_id = 0;
    std::size_t num_ind_per_stream = 0;

    std::uint8_t *src_buf_0 = nullptr;
    std::uint8_t *src_buf_1 = nullptr;
    std::uint8_t *dst_buf_0 = nullptr;
    std::uint8_t *dst_buf_1 = nullptr;

    uint32_t batch_seed = 0;

    std::vector<EncodedIndividual> parents1;
    std::vector<EncodedIndividual> parents2;

    bool operator>(const BatchJob &other) const {
        return batch_id > other.batch_id;
    }

    bool operator<(const BatchJob &other) const {
        return batch_id < other.batch_id;
    }
};

#endif // BATCH_JOB_HPP
