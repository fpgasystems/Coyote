#pragma once

#include <stdio.h>

#include "Common.hpp"
#include "blocking_queue.hpp"

namespace fpga {

class BinaryOutputReader {
private:
    typedef struct __attribute__((packed)) {
        uint64_t vaddr;
        uint64_t size;
    } vaddr_size_t;

    typedef struct __attribute__((packed)) {
        uint32_t value;
        uint8_t  pid;
    } irq_t;

    enum OutputOperations {
        GET_CSR,         // Result of cThread.getCSR()
        HOST_WRITE,      // Host write through axis_host_send
        IRQ,             // Interrupt through notify interface
        CHECK_COMPLETED, // Result of cThread.checkCompleted()
    };

    size_t op_type_size[4] = {sizeof(uint64_t), sizeof(vaddr_size_t), sizeof(irq_t), sizeof(uint32_t)};

    std::unordered_map<void*, csAlloc> *mapped_pages;

    FILE *fp;
    blocking_queue<uint64_t> csr_queue;
    blocking_queue<uint32_t> completed_queue;
    void (*uisr)(int);

public:
    BinaryOutputReader() {}

    void setMappedPages(std::unordered_map<void*, csAlloc> *mapped_pages) {
        this->mapped_pages = mapped_pages;
    }

    int open(const char *file_name) {
        fp = fopen(file_name, "rb");
        if (fp == NULL) {
            LOG << "BinaryOutputReader: Error: Unable to open output named pipe";
            return -1;
        }
        return 0;
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
                    csr_queue.push(result); 
                    break;}
                case HOST_WRITE: {
                    vaddr_size_t meta;
                    std::memcpy(&meta, data, sizeof(meta));

                    bool bounds_check_success = false;
                    for (auto &mapped_page : *mapped_pages) {
                        auto vaddr = reinterpret_cast<uint64_t>(mapped_page.first);
                        auto size = mapped_page.second.size;
                        if (vaddr <= meta.vaddr && vaddr + size >= meta.vaddr + meta.size) {
                            bounds_check_success = true;
                        }
                    }
                    if (!bounds_check_success) std::terminate();

                    char *buffer = reinterpret_cast<char *>(meta.vaddr);
                    for (int i = 0; i < meta.size; i++) {
                        buffer[i] = getc(fp);
                    }
                    break;}
                case IRQ: {
                    irq_t irq;
                    std::memcpy(&irq, data, sizeof(irq));
                    uisr(irq.value);
                    break;}
                case CHECK_COMPLETED: {
                    uint32_t result;
                    std::memcpy(&result, data, sizeof(result));
                    completed_queue.push(result); 
                    break;}
            }
            op_type = getc(fp);
        }
        return 0;
    }

    uint64_t getCSRResult() {
        return csr_queue.pop();
    }

    uint32_t checkCompletedResult() {
        return completed_queue.pop();
    }

    void registerIRQ(void (*uisr)(int)) {
        this->uisr = uisr;
    }

    void close() {
        fclose(fp);
    }
};

}