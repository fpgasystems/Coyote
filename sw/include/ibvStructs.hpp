#pragma once

#include "cDefs.hpp"

#include <cstdint>
#include <string>
#include <cstring>
#include <atomic>
#include <iostream>


namespace fpga {

/**
 * Single queue wrapper
 */
struct ibvQ {
    // Node
    uint32_t ip_addr;

    // Queue
    uint32_t qpn;
    uint32_t psn;  
    uint32_t rkey;

    // Buffer
    void *vaddr; 
    uint32_t size;
    
    // Global ID
    char gid[33] = { 0 };

    uint32_t gidToUint(int idx);
    void uintToGid(int idx, uint32_t ip_addr);

    void print(const char *name);
};

/**
 * Queue pair
 */
struct ibvQp {
protected:
    static std::atomic<uint32_t> curr_id;
public:
    uint32_t id;
    ibvQ local;
    ibvQ remote;

    ibvQp() : id(curr_id++) {}
    inline uint32_t getId() { return id; }

    void print() {
        std::cout << "Queue Pair: "
                  << "id: " << id << std::endl;
        std::cout << "Local Queue: ";
        local.print("local"); // Call the print function of ibvQ to print local queue variables
        std::cout << "Remote Queue: ";
        remote.print("remote"); // Call the print function of ibvQ to print remote queue variables
    }
};

/**
 * SG lists
 */
struct ibvSge {
    uint64_t local_offs;
    uint64_t remote_offs;
    uint32_t len;
};

/* RDMA flags */
struct ibvSendFlags {
    bool host = { true };
    bool mode = { 0 };
    bool last = { true };
    bool clr = { false };
};

/**
 * RDMA request
 */
struct ibvSendWr {
    ibvOpcode opcode;
    ibvSendWr *next;
    ibvSge *sg_list;
    int32_t num_sge;
    ibvSendFlags send_flags; 

    int isRDMA() { return opcode == IBV_WR_RDMA_READ || opcode == IBV_WR_RDMA_WRITE; }
    int isSEND() { return opcode == IBV_WR_SEND; }
};

/**
 * QP id allocator
 */
class ibvQpPool {
    struct el {
        int32_t id;
        bool free;
        el *next;
    };

    uint32_t n_free_el;
    el *pool;
    el *curr_el;

    ibvQpPool(int32_t n_el);
    ~ibvQpPool();

    int32_t acquire();
    bool release(int32_t id);
};

} /* namespace fpga */