#pragma once

#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <atomic>
#include <vector>

#include "fQ.hpp"
#include "fDev.hpp"

using namespace fpga;

namespace comm {

/**
 * Roce communicator
 */
class fView {

    /* FPGA device */
    fDev *fdev;
    int32_t n_regions;

    /* Nodes */
    int32_t node_id;
    int32_t n_nodes;

    /* Connections */
    const char *mstr_ip_addr;
    int *connections;
    uint16_t port;
    uint16_t ib_port;

    /* Static */
    static const uint32_t base_ip_addr = 0x0B01D4D1;

    /* Queue pairs */
    std::vector<std::vector<fQPair>> pairs;

    void initializeLocalQueues();

    int masterExchangeQueues();
    int clientExchangeQueues();

    int exchangeWindow(int32_t node_id, int32_t qpair_id);
    int masterExchangeWindow(int32_t node_id, int32_t qpair_id);
    int clientExchangeWindow(int32_t node_id, int32_t qpair_id);

public:

    fView(fDev *fdev, uint32_t node_id, uint32_t n_nodes, uint32_t *n_qpairs, uint32_t n_regions, const char *mstr_ip_addr);
    ~fView();

    void closeConnections();

    /**
     * Window management
     */

    uint64_t* allocWindow(uint32_t node_id, uint32_t qpair_id, uint64_t n_pages);
    void freeWindow(uint32_t node_id, uint32_t qpair_id);

    /**
     * RDMA operations base
     */

    void writeRemote(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size); 
    void readRemote(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size);
    void farviewRemote(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size, uint64_t params);
    void farviewRemoteBase(uint32_t node_id, uint32_t qpair_id, uint64_t params_0, uint64_t params_1, uint64_t params_2);

    /**
     * RDMA install operator
     */
    //void installOperator();

    /**
     * Added
     */
    void farviewStride(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t dwidth, uint32_t stride, uint32_t num_elem);
    void farviewRegexConfigLoad(uint32_t node_id, uint32_t qpair_id, unsigned char* config_bytes);
    void farviewRegexRead(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size);

    // Poll
    uint32_t pollRemoteWrite(uint32_t node_id, uint32_t qpair_id);
    uint32_t pollLocalRead(uint32_t node_id, uint32_t qpair_id);

    // Sync
    int32_t waitOnCloseRemote(uint32_t node_id);
    int32_t waitOnReplyRemote(uint32_t node_id);
    int32_t replyRemote(uint32_t node_id, uint32_t ack);
    int32_t syncRemote(uint32_t node_id);
    
};

}
