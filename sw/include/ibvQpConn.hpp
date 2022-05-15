#pragma once

#include "cDefs.hpp"

#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <atomic>
#include <vector>
#include <stdexcept>

#include "cProc.hpp"

using namespace fpga;

namespace fpga {

/**
 * IB verbs queue pair connection 
 */
class ibvQpConn {
    /* Queue pair */
    std::unique_ptr<ibvQp> qpair;

    /* vFPGA */
    cProc *fdev;

    /* Connection */
    int connection = { 0 };
    bool is_connected;

    /* Buffer pages */
    uint32_t n_pages;

    /* Static */
    static const uint32_t base_ib_addr = { baseIpAddress };

    /* Init */
    void initLocalQueue(uint32_t node_id);

public:

    ibvQpConn(cProc *fdev, uint32_t node_id, uint32_t n_pages);
    ~ibvQpConn();

    // Connection
    inline auto isConnected() { return is_connected; }
    void setConnection(int connection);
    void closeConnection();

    // Qpair
    inline auto getQpairStruct() { return qpair.get(); };
    void writeContext(uint16_t port);

    // RDMA ops
    void ibvPostSend(ibvSendWr *wr);
    void ibvPostGo();

    // Poll
    uint32_t ibvDone();
    uint32_t ibvSent();
    void ibvClear();

    // Sync
    void sendAck(uint32_t ack);
    uint32_t readAck();
    void ibvSync(bool mstr);
    void closeAck();    
    
};

}
