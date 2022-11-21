#pragma once

#include "cDefs.hpp"

#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <atomic>
#include <vector>
#include <stdexcept>

#include "cProcess.hpp"

using namespace fpga;

namespace fpga {

/**
 * IB verbs queue pair connection 
 */
class ibvQpConn {
    /* Queue pair */
    std::unique_ptr<ibvQp> qpair;

    /* vFPGA */
    std::unique_ptr<cProcess> fdev; 

    /* Buffer pages */
    uint32_t n_pages;
    
    /* Connection */
    int connection = { 0 };
    bool is_connected;

    /* Init */
    void initLocalQueue(string ip_addr);

public:
    ibvQpConn(int32_t vfid, string ip_addr, uint32_t n_pages);
    ~ibvQpConn();

    // Connection
    inline auto isConnected() { return is_connected; }
    void setConnection(int connection);
    void closeConnection();

    // Qpair
    inline auto getQpairStruct() { return qpair.get(); }
    inline auto getCProc() { return fdev.get(); }
    void writeContext(uint16_t port);

    // ARP 
    inline auto doArpLookup() { fdev->doArpLookup(qpair->remote.ip_addr); }

    // RDMA ops
    void ibvPostSend(ibvSendWr *wr);

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
