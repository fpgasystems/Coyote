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

#ifndef _COYOTE_BINARY_OUTPUT_READER_HPP_
#define _COYOTE_BINARY_OUTPUT_READER_HPP_

#include <stdio.h>
#include <functional>
#include <unordered_map>

#include <coyote/cOps.hpp>
#include <coyote/Common.hpp>
#include <coyote/BlockingQueue.hpp>

namespace coyote {

/**
 * This class handles the incoming communication from the Vivado simulation towards the software. 
 * It reads the binary protocol specified in the sim/README.md for all operations that need 
 * communication in that direction from a named pipe that the simulation writes to.
 */
class BinaryOutputReader {
private:
    typedef struct __attribute__((packed)) {
        uint64_t vaddr;
        uint64_t size;
    } vaddr_size_t;

    typedef struct __attribute__((packed)) {
        uint8_t  pid;
        uint32_t value;
    } irq_t;

    enum OutputOperations {
        GET_CSR,         // Result of cThread.getCSR()
        HOST_WRITE,      // Host write through axis_host_send
        IRQ,             // Interrupt through notify interface
        CHECK_COMPLETED, // Result of cThread.checkCompleted()
        HOST_READ        // Host read through sq_rd
    };

    size_t op_type_size[5] = {sizeof(uint64_t), sizeof(vaddr_size_t), sizeof(irq_t), sizeof(uint32_t), sizeof(vaddr_size_t)};

    std::unordered_map<void *, uint32_t> *tlb_pages;

    FILE *fp;

    BlockingQueue<uint64_t> csr_queue;
    BlockingQueue<uint32_t> completed_queue;
    BlockingQueue<uint32_t> irq_queue;

    // InputWriter to transfer data back to the simulation with writeMem(...) after it requested a 
    // host read
    BinaryInputWriter &input_writer;

    void boundsCheck(uint64_t vaddr, uint64_t size) {
        bool bounds_check_success = false;
        for (auto &mapped_page : *tlb_pages) {
            auto mapped_page_vaddr = reinterpret_cast<uint64_t>(mapped_page.first);
            auto mapped_page_size = mapped_page.second;
            if (mapped_page_vaddr <= vaddr && mapped_page_vaddr + mapped_page_size >= vaddr + size) {
                bounds_check_success = true;
            }
        }
        if (!bounds_check_success) {FATAL("Bounds check failed. No mapped pages in the range [" << vaddr << ", " << vaddr + size << ")") std::terminate();}
    }

public:
    BinaryOutputReader(BinaryInputWriter &input_writer) : input_writer(input_writer) {}

    void setTLBPages(std::unordered_map<void *, uint32_t> *tlb_pages) {
        this->tlb_pages = tlb_pages;
    }

    int open(const char *file_name) {
        fp = fopen(file_name, "rb");
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

    int readUntilEOF() {
        char op_type = getc(fp);
        while (op_type != EOF) {
            unsigned char data[op_type_size[op_type]];
            for (int i = 0; i < op_type_size[op_type]; i++)
                data[i] = getc(fp);
            
            switch(op_type) {
                case GET_CSR: {
                    uint64_t result;
                    std::memcpy(&result, data, sizeof(result));
                    DEBUG("Return getCSR(...) = " << result)
                    csr_queue.push(result); 
                    break;}
                case HOST_WRITE: {
                    vaddr_size_t meta;
                    std::memcpy(&meta, data, sizeof(meta));

                    boundsCheck(meta.vaddr, meta.size);

                    char *buffer = reinterpret_cast<char *>(meta.vaddr);
                    for (int i = 0; i < meta.size; i++) {
                        buffer[i] = getc(fp);
                    }
                    DEBUG("Wrote host memory with vaddr " << meta.vaddr << " and size " << meta.size)
                    break;}
                case IRQ: {
                    irq_t irq;
                    std::memcpy(&irq, data, sizeof(irq));
                    DEBUG("Call interrupt handler with value = " << irq.value)
                    irq_queue.push(irq.value);
                    break;}
                case CHECK_COMPLETED: {
                    uint32_t result;
                    std::memcpy(&result, data, sizeof(result));
                    DEBUG("Return checkCompleted() = " << result)
                    completed_queue.push(result); 
                    break;}
                case HOST_READ: {
                    vaddr_size_t meta;
                    std::memcpy(&meta, data, sizeof(meta));

                    boundsCheck(meta.vaddr, meta.size);

                    input_writer.writeMem(meta.vaddr, meta.size, reinterpret_cast<void *>(meta.vaddr));
                    break;}
                default: 
                    FATAL("Unknown operator type " << (int) op_type)
                    std::terminate();
            }
            op_type = getc(fp);
        }
        irq_queue.stop();
        DEBUG("EOF reached")
        return 0;
    }

    /**
     * This function stalls the calling thread until the result of a getCSR(...) call that was sent 
     * to the simulation is put into the csr_queue by the constantly running readUnitlEOF() function.
     */
    uint64_t getCSRResult() {
        uint64_t result;
        csr_queue.pop(result);
        return result;
    }

    /**
     * This function stalls the calling thread until the result of a checkCompleted(...) call that 
     * was sent to the simulation is put into the csr_queue by the constantly running readUnitlEOF() 
     * function.
     */
    uint32_t checkCompletedResult() {
        uint32_t result;
        completed_queue.pop(result);
        return result;
    }

    /**
     * Blocking call that tries to get the next interrupt value.
     * @return true if getting an interrupt value was successful - false if the queue was stopped
     */
    bool getNextIRQ(uint32_t &out) {
        return irq_queue.pop(out);
    }
};

}

#endif
