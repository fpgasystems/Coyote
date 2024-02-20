#include <iostream>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <random>
#include <chrono>
#include <thread>
#include <limits>
#include <assert.h>
#include <string>

#include "cIbvCtx.hpp"

using namespace std;

namespace fpga {


// ======-------------------------------------------------------------------------------
/// Public
// ======-------------------------------------------------------------------------------

/**
 * Ctor
 * @param: vfid - vFPGA id
 * @param: n_pages - number of buffer pages
 */
cIbvCtx::cIbvCtx(int32_t vfid, pid_t hpid, string ip_addr, int32_t sid, uint32_t n_pages, CoyoteAlloc calloc) {
    this->cthread = new cThread(vfid, hpid);
    int_thread = true;

    // Conn
    is_connected = false;

    // Initialize local queues
    initLocalQueue(ip_addr, sid);

    // Initialize buffers
    initLocalBuffs(n_pages, calloc);
    buff_attached = true;
}

/**
 * Ctor
 * @param: vfid - vFPGA id
 * @param: n_pages - number of buffer pages
 */
cIbvCtx::cIbvCtx(cThread *cthread, string ip_addr, int32_t sid) {
    this->cthread = cthread;
    int_thread = false;

    // Conn
    is_connected = false;

    // Initialize local queues
    initLocalQueue(ip_addr, sid);

    buff_attached = false;
}

/**
 * Dtor
 */
cIbvCtx::~cIbvCtx() {
    closeConnection();

    if(int_thread) 
        this->cthread->~cThread();
}


static unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

uint32_t convert( const std::string& ipv4Str ) {
    std::istringstream iss( ipv4Str );
    
    uint32_t ipv4 = 0;
    
    for( uint32_t i = 0; i < 4; ++i ) {
        uint32_t part;
        iss >> part;
        if ( iss.fail() || part > 255 )
            throw std::runtime_error( "Invalid IP address - Expected [0, 255]" );
        
        // LSHIFT and OR all parts together with the first part as the MSB
        ipv4 |= part << ( 8 * ( 3 - i ) );

        // Check for delimiter except on last iteration
        if ( i != 3 ) {
            char delimiter;
            iss >> delimiter;
            if ( iss.fail() || delimiter != '.' ) 
                throw std::runtime_error( "Invalid IP address - Expected '.' delimiter" );
        }
    }
    
    return ipv4;
}

/**
 * Initialization of the local queues
 */
void cIbvCtx::initLocalQueue(string ip_addr, int32_t sid) {
    std::default_random_engine rand_gen(seed);
    std::uniform_int_distribution<int> distr(0, std::numeric_limits<std::uint32_t>::max());

    qpair = std::make_unique<ibvQp>();

    // IP 
    uint32_t ibv_ip_addr = convert(ip_addr);
    qpair->local.ip_addr = ibv_ip_addr;
    qpair->local.uintToGid(0, ibv_ip_addr);
    qpair->local.uintToGid(8, ibv_ip_addr);
    qpair->local.uintToGid(16, ibv_ip_addr);
    qpair->local.uintToGid(24, ibv_ip_addr);

    // qpn and psn
    qpair->local.qpn = ((cthread->getVfid() & nRegMask) << pidBits + sidBits) || ((cthread->getCtid() & pidMask) << pidBits) || (sid & sidMask);
    if(qpair->local.qpn == -1) 
        throw std::runtime_error("Coyote PID incorrect, vfid: " + cthread->getVfid());
    qpair->local.psn = distr(rand_gen) & 0xFFFFFF;
    qpair->local.rkey = 0;
}

/**
 * Initialization of the local buffers
 */
void cIbvCtx::initLocalBuffs(uint32_t n_pages, CoyoteAlloc calloc) {
    // Allocate buffer
    void *vaddr = cthread->getMem({calloc, n_pages});
    qpair->local.vaddr = vaddr;
    qpair->local.size = n_pages * (isAllocHuge(calloc) ? hugePageSize : pageSize);
}

/**
 * Initialization of the local buffers
 */
void cIbvCtx::initLocalBuffs(void *vaddr, uint32_t size) {
    if(!int_thread) {
        // Allocate buffer
        qpair->local.vaddr = vaddr;
        qpair->local.size = size;

        buff_attached = true;
    }
}

/**
 * Init memory
 * 
 */

/**
 * @brief Set connection
 */
void cIbvCtx::setConnection(int connection) {
    this->connection = connection;
    is_connected = true;
}

void cIbvCtx::closeConnection() {
    if(isConnected()) {
        close(connection);
        is_connected = false;
    }
}

/**
 * @brief Write queue pair context
 */
void cIbvCtx::writeContext(uint16_t port) {
    cthread->writeQpContext(qpair.get());
    cthread->writeConnContext(qpair.get(), port);
}

/**
 * RDMA ops
 * @param: wr - RDMA operation
 */
void cIbvCtx::invoke(csInvoke &cs_invoke) {
    if(!is_connected)
        throw std::runtime_error("Queue pair not connected\n");

    cthread->invoke(cs_invoke, qpair.get());
}

/**
 * RDMA polling function for incoming data
 */
uint32_t cIbvCtx::ibvDone(CoyoteOper opcode) {
    if(!isRemoteRdma(opcode))
        throw std::runtime_error("Wrong opcode\n");

    return cthread->checkCompleted(opcode);
}

/**
 * Clear completed status counters
 */
void cIbvCtx::ibvClear() {
    cthread->clearCompleted();
}

/**
 * Sync with remote
 */
uint32_t cIbvCtx::readAck() {
    uint32_t ack;
   
    if (::read(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t)) {
        ::close(connection);
        throw std::runtime_error("Could not read ack\n");
    }

    return ack;
}

/**
 * Wait on close remote
 */
void cIbvCtx::closeAck() {
    uint32_t ack;
    
    if (::read(connection, &ack, sizeof(uint32_t)) == 0) {
        ::close(connection);
    }
}


/**
 * Sync with remote
 * @param: ack - acknowledge message
 */
void cIbvCtx::sendAck(uint32_t ack) {
    if(::write(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t))  {
        ::close(connection);
        throw std::runtime_error("Could not send ack\n");
    }
}

/**
 * Sync with remote
 */
void cIbvCtx::ibvSync(bool server) {
    if(server) {
        sendAck(0);
        readAck();
    } else {
        readAck();
        sendAck(0);
    }
}

}
