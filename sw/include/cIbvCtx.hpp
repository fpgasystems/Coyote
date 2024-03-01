#pragma once

#include "cDefs.hpp"

#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <atomic>
#include <vector>
#include <stdexcept>

#include "cThread.hpp"

using namespace fpga;

namespace fpga {

/**
 * IB verbs queue pair connection 
 */
class cIbvCtx {
    /* Queue pair */
    std::unique_ptr<ibvQp> qpair;

    /* Thread */
    cThread *cthread; 
    bool int_thread;
    bool buff_attached;

    /* Connection */
    int connection = { 0 };
    bool is_connected;

    /* Init */
    void initLocalQueue(string ip_addr, int32_t sid);
    void initLocalBuffs(uint32_t n_pages, CoyoteAlloc calloc);

public:
    cIbvCtx(int32_t vfid, pid_t hpid, csDev dev, string ip_addr, int32_t sid, uint32_t n_pages, CoyoteAlloc calloc = CoyoteAlloc::HPF);
    cIbvCtx(cThread *cthread, string ip_addr, int32_t sid);
    ~cIbvCtx();

    // Buff external
    void initLocalBuffs(void *vaddr, uint32_t size);

    // Getters
    inline auto getQpair() { return qpair.get(); }
    inline auto getCThread() { return cthread; }

    // Connection
    inline auto isConnected() { return is_connected; }
    void setConnection(int connection);
    void closeConnection();
    inline auto doArpLookup() { cthread->doArpLookup(qpair->remote.ip_addr); }

    // Context
    void writeContext(uint16_t port);
    
    // Ops
    void invoke(csInvoke& cs_invoke);

    // Poll
    uint32_t ibvDone(CoyoteOper opcode);
    void ibvClear();

    // Sync
    void sendAck(uint32_t ack);
    uint32_t readAck();
    void ibvSync(bool server);
    void closeAck();    
    
};

}
