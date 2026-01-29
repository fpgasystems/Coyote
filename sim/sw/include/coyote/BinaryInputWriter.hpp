/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_BINARY_INPUT_WRITER_HPP_
#define _COYOTE_BINARY_INPUT_WRITER_HPP_

#include <stdio.h>
#include <mutex>

#include <coyote/Common.hpp>

namespace coyote {

/**
 * This class handles the outgoing communication from the software towards the Vivado simulation. 
 * It writes the binary protocol specified in the sim/README.md for all operations that need communication in that direction to a named pipe that the simulation reads from.
 */
class BinaryInputWriter {
    enum InputOperations {
        SET_CSR,         // cThread.setCSR
        GET_CSR,         // cThread.getCSR
        USER_MAP,        // cThread.userMap
        MEM_WRITE,       // Memory writes mem[i] = ...
        INVOKE,          // cThread.invoke
        SLEEP,           // Sleep for a certain duration before processing the next command
        CHECK_COMPLETED, // Return how many requests have been completed for a given CoyoteOper
        CLEAR_COMPLETED, // Clear completed counters
        USER_UNMAP       // cThread.userUnmap
    };

    typedef struct __attribute__((packed)) {
        uint64_t addr;
        uint64_t data;
    } set_csr_op_t;

    typedef struct __attribute__((packed)) {
        uint64_t addr;
        uint64_t data;
        uint8_t  do_polling;
    } get_csr_op_t;

    typedef struct __attribute__((packed)) {
        uint64_t vaddr;
        uint64_t size;
    } vaddr_size_t;

    typedef struct __attribute__((packed)) {
        uint8_t opcode;
        uint8_t strm;
        uint8_t dest;
        uint64_t vaddr;
        uint64_t len;
        uint8_t last;
    } req_t;

    typedef struct __attribute__((packed)) {
        uint8_t opcode;
        uint64_t count;
        uint8_t do_polling;
    } check_completed_t;

    std::mutex write_mtx;

    void writeData(uint8_t op_type, uint64_t size, void *ptr) {
        std::lock_guard<std::mutex> lock(write_mtx);
        fwrite(&op_type, 1, 1, fp);
        if (size > 0) fwrite(ptr, size, 1, fp);
        fflush(fp);
    }

    FILE *fp;

public:
    BinaryInputWriter() {}

    ~BinaryInputWriter() {}

    int open(const char *file_name) {
        fp = fopen(file_name, "wb");
        if (fp == NULL) {
            ERROR("Unable to open named pipe")
            return -1;
        }
        DEBUG("Opened named pipe successfully")
        return 0;
    }

    void close() {
        fclose(fp);
        DEBUG("Closed named pipe")
    }

    void setCSR(uint32_t addr, uint64_t data) {
        set_csr_op_t ctrl_op = {addr * 8, data};
        writeData(SET_CSR, sizeof(set_csr_op_t), &ctrl_op);
        DEBUG("Wrote setCSR(" << addr << ", " << data << ")")
    }

    void getCSR(uint32_t addr) {
        get_csr_op_t ctrl_op = {addr * 8, 0, 0};
        writeData(GET_CSR, sizeof(get_csr_op_t), &ctrl_op);
        DEBUG("Wrote getCSR(" << addr << ")")
    }

    void userMap(uint64_t vaddr, uint64_t size) {
        vaddr_size_t vs = {vaddr, size};
        writeData(USER_MAP, sizeof(vaddr_size_t), &vs);
        DEBUG("Wrote userMap(" << vaddr << ", " << size << ")")
    }

    void userUnmap(uint64_t vaddr) {
        uint8_t op_type = USER_UNMAP;
        writeData(USER_UNMAP, sizeof(uint64_t), &vaddr);
        DEBUG("Wrote userUnmap(" << vaddr << ")")
    }

    void writeMem(uint64_t vaddr, uint64_t size, void *ptr) {
        uint8_t op_type = MEM_WRITE;
        vaddr_size_t vs = {vaddr, size};
        {
            std::lock_guard<std::mutex> lock(write_mtx);
            fwrite(&op_type, 1, 1, fp);
            fwrite(&vs, sizeof(vaddr_size_t), 1, fp);
            fwrite(ptr, size, 1, fp);
            fflush(fp);
        }
        DEBUG("Wrote writeMem(" << vaddr << ", " << size << ", ...)")
    }

    void invoke(uint8_t opcode, uint8_t strm, uint8_t dest, uint64_t vaddr, uint64_t len, uint8_t last) {
        req_t req = {opcode, strm, dest, vaddr, len, last};
        writeData(INVOKE, sizeof(req_t), &req);
        DEBUG("Wrote invoke(" << (int) opcode << ", " << (int) strm << ", " << (int) dest << ", " << vaddr << ", " << len << ", " << (int) last << ")")
    }

    void sleep(uint64_t duration) {
        writeData(SLEEP, sizeof(uint64_t), &duration);
        DEBUG("Wrote sleep(" << duration << ")")
    }

    void checkCompleted(uint8_t opcode, uint64_t count, uint8_t do_polling) {
        check_completed_t cc = {opcode, count, do_polling};
        writeData(CHECK_COMPLETED, sizeof(check_completed_t), &cc);
        DEBUG("Wrote checkCompleted(" << (int) opcode << ", " << count << ", " << (int) do_polling << ")")
    }

    void clearCompleted() {
        writeData(CLEAR_COMPLETED, 0, nullptr);
        DEBUG("Wrote clearCompleted()")
    }
};

}

#endif
