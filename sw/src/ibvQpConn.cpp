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

#include "ibvQpConn.hpp"

using namespace std;

namespace fpga {


// ======-------------------------------------------------------------------------------
/// Public
// ======-------------------------------------------------------------------------------

/**
 * Ctor
 * @param: fdev - attached vFPGA
 * @param: n_pages - number of buffer pages
 */
ibvQpConn::ibvQpConn(int32_t vfid, string ip_addr, uint32_t n_pages) {
    this->fdev = make_unique<cProcess>(vfid, getpid());
    this->n_pages = n_pages;

    // Conn
    is_connected = false;

    // Initialize local queues
    initLocalQueue(ip_addr);
}

/**
 * Dtor
 */
ibvQpConn::~ibvQpConn() {
    closeConnection();
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
void ibvQpConn::initLocalQueue(string ip_addr) {
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
    qpair->local.qpn = ((fdev->getVfid() & nRegMask) << pidBits) || (fdev->getCpid() & pidMask);
    if(qpair->local.qpn == -1) 
        throw std::runtime_error("Coyote PID incorrect, vfid: " + fdev->getVfid());
    qpair->local.psn = distr(rand_gen) & 0xFFFFFF;
    qpair->local.rkey = 0;

    // Allocate buffer
    void *vaddr = fdev->getMem({CoyoteAlloc::HUGE_2M, n_pages});
    qpair->local.vaddr = (uint64_t) vaddr;
    qpair->local.size = n_pages * hugePageSize;
}

/**
 * @brief Set connection
 */
void ibvQpConn::setConnection(int connection) {
    this->connection = connection;
    is_connected = true;
}

void ibvQpConn::closeConnection() {
    if(isConnected()) {
        close(connection);
        is_connected = false;
    }
}

/**
 * @brief Write queue pair context
 */
void ibvQpConn::writeContext(uint16_t port) {
    fdev->writeQpContext(qpair.get());
    fdev->writeConnContext(qpair.get(), port);
}

/**
 * RDMA ops
 * @param: wr - RDMA operation
 */
void ibvQpConn::ibvPostSend(ibvSendWr *wr) {
    if(!is_connected)
        throw std::runtime_error("Queue pair not connected\n");

    fdev->ibvPostSend(qpair.get(), wr);
}

/**
 * RDMA polling function for incoming data
 */
uint32_t ibvQpConn::ibvDone() {
    return fdev->checkCompleted(CoyoteOper::WRITE);
}

/**
 * RDMA polling function for outgoing data
 */
uint32_t ibvQpConn::ibvSent() {
    return fdev->checkCompleted(CoyoteOper::READ);
}

/**
 * Clear completed flags
 */
void ibvQpConn::ibvClear() {
    fdev->clearCompleted();
}

/**
 * Sync with remote
 */
uint32_t ibvQpConn::readAck() {
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
void ibvQpConn::closeAck() {
    uint32_t ack;
    
    if (::read(connection, &ack, sizeof(uint32_t)) == 0) {
        ::close(connection);
    }
}


/**
 * Sync with remote
 * @param: ack - acknowledge message
 */
void ibvQpConn::sendAck(uint32_t ack) {
    if(::write(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t))  {
        ::close(connection);
        throw std::runtime_error("Could not send ack\n");
    }
}

/**
 * Sync with remote
 */
void ibvQpConn::ibvSync(bool mstr) {
    if(mstr) {
        sendAck(0);
        readAck();
    } else {
        readAck();
        sendAck(0);
    }
}

}
