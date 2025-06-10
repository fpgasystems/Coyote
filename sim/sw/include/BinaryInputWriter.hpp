#pragma once

#include <stdio.h>

#include "Common.hpp"

namespace fpga {

class BinaryInputWriter {
    enum InputOperations {
        CSR,         // cThread.get- and setCSR
        USER_MAP,    // cThread.userMap
        MEM_WRITE,   // Memory writes mem[i] = ...
        INVOKE,      // cThread.invoke
        SLEEP,       // Sleep for a certain duration before processing the next command
        CHECK_COMPLETED, // Return how many requests have been completed for a given CoyoteOper
        CLEAR_COMPLETED, // Clear completed counters
        USER_UNMAP   // cThread.userUnmap
    };

    typedef struct __attribute__((packed)) {
        uint8_t is_write;
        uint64_t addr;
        uint64_t data;
        uint8_t do_polling;
    } ctrl_op_t;

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

    FILE *fp;

public:
    BinaryInputWriter() {}

    ~BinaryInputWriter() {};

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
        uint8_t sock_type = CSR;
        ctrl_op_t ctrl_op = {1, addr * 8, data, 0};

        fwrite(&sock_type, 1, 1, fp);
        fwrite(&ctrl_op, sizeof(ctrl_op_t), 1, fp);
        fflush(fp);
        DEBUG("Flushed setCSR(" << addr << ", " << data << ")")
    }

    void getCSR(uint32_t addr) {
        uint8_t sock_type = CSR;
        ctrl_op_t ctrl_op = {0, addr * 8, 0, 0};

        fwrite(&sock_type, 1, 1, fp);
        fwrite(&ctrl_op, sizeof(ctrl_op_t), 1, fp);
        fflush(fp);
        DEBUG("Flushed getCSR(" << addr << ")")
    }

    void userMap(uint64_t vaddr, uint64_t size) {
        uint8_t sock_type = USER_MAP;
        vaddr_size_t vs = {vaddr, size};

        fwrite(&sock_type, 1, 1, fp);
        fwrite(&vs, sizeof(vaddr_size_t), 1, fp);
        fflush(fp);
        DEBUG("Flushed userMap(" << vaddr << ", " << size << ")")
    }

    void userUnmap(uint64_t vaddr) {
        uint8_t sock_type = USER_UNMAP;

        fwrite(&sock_type, 1, 1, fp);
        fwrite(&vaddr, sizeof(uint64_t), 1, fp);
        fflush(fp);
        DEBUG("Flushed userUnmap(" << vaddr << ")")
    }

    void writeMem(uint64_t vaddr, uint64_t size, void *ptr) {
        uint8_t sock_type = MEM_WRITE;
        vaddr_size_t vs = {vaddr, size};

        fwrite(&sock_type, 1, 1, fp);
        fwrite(&vs, sizeof(vaddr_size_t), 1, fp);
        fwrite(ptr, size, 1, fp);
        fflush(fp);
        DEBUG("Flushed writeMem(" << vaddr << ", " << size << ", ...)")
    }

    void invoke(uint8_t opcode, uint8_t strm, uint8_t dest, uint64_t vaddr, uint64_t len, uint8_t last) {
        uint8_t sock_type = INVOKE;
        req_t req = {opcode, strm, dest, vaddr, len, last};

        fwrite(&sock_type, 1, 1, fp);
        fwrite(&req, sizeof(req_t), 1, fp);
        fflush(fp);
        DEBUG("Flushed invoke(" << (int) opcode << ", " << (int) strm << ", " << (int) dest << ", " << vaddr << ", " << len << ", " << (int) last << ")")
    }

    void sleep(uint64_t duration) {
        uint8_t sock_type = SLEEP;
        fwrite(&sock_type, 1, 1, fp);
        fwrite(&duration, sizeof(duration), 1, fp);
        fflush(fp);
        DEBUG("Flushed sleep(" << duration << ")")
    }

    void checkCompleted(uint8_t opcode, uint64_t count, uint8_t do_polling) {
        uint8_t sock_type = CHECK_COMPLETED;
        fwrite(&sock_type, 1, 1, fp);
        fwrite(&opcode, sizeof(opcode), 1, fp);
        fwrite(&count, sizeof(count), 1, fp);
        fwrite(&do_polling, sizeof(do_polling), 1, fp);
        fflush(fp);
        DEBUG("Flushed checkCompleted(" << (int) opcode << ", " << count << ", " << (int) do_polling << ")")
    }

    void clearCompleted() {
        uint8_t sock_type = CLEAR_COMPLETED;
        fwrite(&sock_type, 1, 1, fp);
        fflush(fp);
        DEBUG("Flushed clearCompleted()")
    }
};

}