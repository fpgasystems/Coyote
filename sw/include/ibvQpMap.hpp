#pragma once

#include "cDefs.hpp"

#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <atomic>
#include <unordered_map>
#include <stdexcept>

#include "ibvQpConn.hpp"

using namespace fpga;

namespace fpga {

/**
 * IB verbs queue pair map
 */
class ibvQpMap {
    /* Queue pairs */
    std::unordered_map<uint32_t, std::unique_ptr<ibvQpConn>> qpairs;

public:

    ibvQpMap () {}
    ~ibvQpMap() {}

    // Qpair mgmt
    void addQpair(uint32_t qpid, int32_t vfid, string ip_addr, uint32_t n_pages);
    void removeQpair(uint32_t qpid);
    ibvQpConn* getQpairConn(uint32_t qpid);

    // Queue pair exchange
    void exchangeQpMaster(uint16_t port);
    void exchangeQpSlave(const char *trgt_addr, uint16_t port);
    
};

}
