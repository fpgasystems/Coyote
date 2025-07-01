#ifndef _COYOTE_BINARY_OUTPUT_READER_HPP
#define _COYOTE_BINARY_OUTPUT_READER_HPP

#include <stdio.h>

#include "Common.hpp"
#include "BlockingQueue.hpp"

namespace coyote {

/**
 * This class handles the incoming communication from the Vivado simulation towards the software. 
 * It reads the binary protocol specified in the sim/README.md for all operations that need communication in that direction from a named pipe that the simulation writes to.
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

    std::unordered_map<void*, CoyoteAlloc> *mapped_pages;

    FILE *fp;
    BlockingQueue<uint64_t> csr_queue;
    BlockingQueue<uint32_t> completed_queue;
    void (*uisr)(int);
    void (*syncMem)(void *, uint64_t);

    void boundsCheck(uint64_t vaddr, uint64_t size) {
        bool bounds_check_success = false;
        for (auto &mapped_page : *mapped_pages) {
            auto vaddr = reinterpret_cast<uint64_t>(mapped_page.first);
            auto size = mapped_page.second.size;
            if (vaddr <= vaddr && vaddr + size >= vaddr + size) {
                bounds_check_success = true;
            }
        }
        if (!bounds_check_success) {FATAL("Bounds check failed. No mapped pages in the range [" << vaddr << ", " << vaddr + size << "}") std::terminate();}
    }

public:
    BinaryOutputReader(void (*syncMem)(void *, uint64_t)) : syncMem(syncMem) {}

    void setMappedPages(std::unordered_map<void*, CoyoteAlloc> *mapped_pages) {
        this->mapped_pages = mapped_pages;
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
                    uisr(irq.value);
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

                    syncMem(reinterpret_cast<void *>(meta.vaddr), meta.size);
                    break;}
                default: 
                    FATAL("Unknown operator type " << (int) op_type)
                    std::terminate();
            }
            op_type = getc(fp);
        }
        return 0;
    }

    /**
     * This function stalls the calling thread until the result of a getCSR(...) call that was sent to the simulation is put into the csr_queue by the constantly running readUnitlEOF() function.
     */
    uint64_t getCSRResult() {
        return csr_queue.pop();
    }

    /**
     * This function stalls the calling thread until the result of a checkCompleted(...) call that was sent to the simulation is put into the csr_queue by the constantly running readUnitlEOF() function.
     */
    uint32_t checkCompletedResult() {
        return completed_queue.pop();
    }

    void registerIRQ(void (*uisr)(int)) {
        this->uisr = uisr;
    }
};

}

#endif
