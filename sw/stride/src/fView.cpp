 #include "fView.hpp"

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

using namespace fpga;

namespace comm {

/**
 * Constructor
 * @param: fdev - array of fDev objects. Has to coincide with the number of regions.
 * @param: node_id - current node ID
 * @param: n_nodes - number of total nodes in the system
 * @param: n_qpairs - qpair organization, ex: {1, 3} => 2 node system, master node, remote node 1 shares 3 qpairs
 * @param: n_regions - number of vFPGA regions
 * @param: mstr_ip_addr - master node IP address
 */
fView::fView(fDev *fdev, uint32_t node_id, uint32_t n_nodes, uint32_t *n_qpairs, uint32_t n_regions, const char *mstr_ip_addr) {
    // Set port
    port = 18515; // ?
    ib_port = 0;
    this->mstr_ip_addr = mstr_ip_addr;
    
    // FPGA device 
    this->fdev = fdev;

    // Nodes
    this->node_id = node_id;
    this->n_nodes = n_nodes;
    this->n_regions = n_regions;

    for (int i = 0; i < n_nodes; i++) {
        std::vector<fQPair> v(n_qpairs[i], fQPair());
        pairs.push_back(v);
    }

    // Connections
    this->connections = new int[n_nodes];
 
    // Initialize local queues
    initializeLocalQueues();

    // Queue exchange
    int ret = 1;
    if (node_id == 0) {
        ret = masterExchangeQueues();
    } else {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        ret = clientExchangeQueues();
    }
    if (ret)
        std::cout << "Exchange failed" << std::endl;
    else 
        std::cout << "Exchange successfull" << std::endl;

    // Load QPn


    // Load context and connections
    for(int i = 0; i < n_nodes; i++) {
        if (i == node_id) continue;

        for (uint j = 0; j < pairs[i].size(); j++) {
            int pair_reg = pairs[i][j].local.region;
            fdev[pair_reg].writeContext(&pairs[i][j]);
            fdev[pair_reg].writeConnection(&pairs[i][j], port);
        }
    }

    // ARP lookup
    fdev[0].doArpLookup();
}

/**
 * Destructor
 */
fView::~fView() {
    for (int i = 0; i < n_nodes; i++) {
        if (i == node_id) continue;
        close(connections[i]);
    }

    delete[] connections;
}

void fView::closeConnections() {
    for (int i = 0; i < n_nodes; i++) {
        if (i == node_id) continue;
        close(connections[i]);
    }
}

static unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

/**
 * Initialization of the local queues (no buffers allocated at this point)
 */
void fView::initializeLocalQueues() {
    std::default_random_engine rand_gen(seed);
    std::uniform_int_distribution<int> distr(0, std::numeric_limits<std::uint32_t>::max());

    uint32_t ip_addr = base_ip_addr + node_id;

    int i = 0, j;
    int node = 0;
    for (auto it1 = pairs.begin(); it1 != pairs.end(); it1++) {
        j = 0;
        for (auto it2 = it1->begin(); it2 != it1->end(); it2++) {
            it2->local.uintToGid(0, ip_addr);
            it2->local.uintToGid(8, ip_addr);
            it2->local.uintToGid(16, ip_addr);
            it2->local.uintToGid(24, ip_addr);
            it2->local.qpn = 0x3 + i++;
            it2->local.psn = distr(rand_gen) & 0xFFFFFF;
            it2->local.region = j++ % n_regions; 
            it2->local.rkey = 0;
            it2->local.vaddr = 0; //TODO remove
            it2->local.size = 0;
        }
        node++;
    }
}

/**
 * Exchange initial qpairs (server side)
 */
int fView::masterExchangeQueues() {
    char *service;
    char recv_buf[100];
    int32_t recv_node_id;
    uint n;
    int sockfd = -1, connfd;
    struct sockaddr_in server;
    memset(recv_buf, 0, 100);

    std::cout << "Server exchange started ..." << std::endl;

    sockfd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) {
        std::cerr << "Could not create socket" << std::endl;
        return 1;
    }

    server.sin_family = AF_INET;
    server.sin_addr.s_addr = INADDR_ANY;
    server.sin_port = htons( port);

    if (::bind(sockfd, (struct sockaddr*)&server, sizeof(server)) < 0) {
        std::cerr << "Could not bind socket" << std::endl;
        return 1;
    }

    if (sockfd < 0 ) {
        std::cerr << "Could not listen to port " << port << std::endl;
        return 1;
    }

    // Get number of local queue pairs for each node
    listen(sockfd, n_nodes);

    size_t msg_len;

    // Receive queues
    for (int i = 1; i < n_nodes; i++) {
        // Accept the connection for each node
        connfd = ::accept(sockfd, NULL, 0);
        if (connfd < 0) {
            std::cerr << "Accept() failed" << std::endl;
            return 1;
        }

        // Read node id
        n = ::read(connfd, &recv_node_id, sizeof(int32_t));
        if (n != sizeof(int32_t)) {
            std::cerr << "Could not read initial node ID message, bytes read: " << n << std::endl;
            close(connfd);
            return 1;
        }
        std::cout << "Qpair exchange nodeid " << recv_node_id << " ... " << std::endl;

        msg_len = fQ::getLength();

        for (uint j = 0; j < pairs[recv_node_id].size(); j++) {
            // Read remote qpair
            n = ::read(connfd, recv_buf, msg_len);
            if (n != msg_len) {
                std::cerr << "Could not read message, bytes read: " << n << std::endl;
                std::cout << "Received msg: " << recv_buf << std::endl;
                close(connfd);
                return 1;
            }

            pairs[recv_node_id][j].remote.decode(recv_buf, msg_len);
            std::cout << "Qpair nodeid " << recv_node_id << "[" << j << "]" << std::endl;
            pairs[recv_node_id][j].local.print("Local ");
            pairs[recv_node_id][j].remote.print("Remote");       
        }

        connections[recv_node_id] = connfd;
    }

    std::cout << "Received all remote qpairs" << std::endl;

    // Send queues
    for (int i = 1; i < n_nodes; i++) {
        for (uint j = 0; j < pairs[i].size(); j++) {
            std::string msg_string;
            msg_string = pairs[i][j].local.encode();
            size_t msg_len = msg_string.length();

            // Write message
            if (::write(connections[i], msg_string.c_str(), msg_len) != msg_len)  {
                std::cerr << "Could not send local qpair" << std::endl;
                ::close(connections[i]);
                return 1;
            }
        }
    }

    std::cout << "Sent all local qpairs" << std::endl;

    ::close(sockfd);
    return 0;
}

/**
 * Exchange initial qpairs (client side)
 */
int fView::clientExchangeQueues() {
    struct addrinfo *res, *t;
    struct addrinfo hints = {};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char* service;
    char recv_buf[100];
    int n = 0;
    int sockfd = -1;
    memset(recv_buf, 0, 100);

    std::cout << "Client exchange" << std::endl;

    if (asprintf(&service, "%d", port) < 0) {
        std::cerr << "Service failed" << std::endl;
        return 1;
    }

    n = getaddrinfo(mstr_ip_addr, service, &hints, &res);
    if (n < 0) {
        std::cerr << "[ERROR] getaddrinfo";
        free(service);
        return 1;
    }

    for (t = res; t; t = t->ai_next) {
        sockfd = ::socket(t->ai_family, t->ai_socktype, t->ai_protocol);
        if (sockfd >= 0) {
            if (!::connect(sockfd, t->ai_addr, t->ai_addrlen)) {
                break;
            }
            ::close(sockfd);
            sockfd = -1;
        }
    }

    if (sockfd < 0) {
        std::cerr << "Could not connect to master: " << mstr_ip_addr << ":" << port << std::endl;
        return 1;
    }

    // Send local node ID
    if (write(sockfd, &node_id, sizeof(int32_t)) != sizeof(int32_t)) {
        std::cerr << "Could not send local node id" << std::endl;
        close(sockfd);
        return 1;
    }

    size_t msg_len;

    /// Send local queues
    for (uint i = 0; i < pairs[0].size(); i++) {
        std::string msg_string = pairs[0][i].local.encode();      

        size_t msg_len = msg_string.length();

        if (write(sockfd, msg_string.c_str(), msg_len) != msg_len) {
            std::cerr << "Could not send local address" << std::endl;
            close(sockfd);
            return 1;
        }
    }

    std::cout << "Sent all local qpairs" << std::endl;

    msg_len = fQ::getLength();

    // Receive remote queues
    for (uint i = 0; i < pairs[0].size(); i++) {
        if ((n = ::read(sockfd, recv_buf, msg_len)) != msg_len) {
            std::cout << "n: " << n << ", instread of " << msg_len << std::endl; 
            std::cout << "Received msg: " << recv_buf << std::endl;
            std::cerr << "Could not read remote address" << std::endl;
            ::close(sockfd);
            return 1;
        }

        pairs[0][i].remote.decode(recv_buf, msg_len);
        std::cout << "Qpair nodeid " << 0 << "[" << i << "]" << std::endl;     
        pairs[0][i].local.print("Local ");
        pairs[0][i].remote.print("Remote");
    }

    std::cout << "Received all remote qpairs" << std::endl;

    //keep connection around
    connections[0] = sockfd;

    if (res) 
        freeaddrinfo(res);
    free(service);

    return 0;
}

/**
 * Exchange windows with target node
 */
int fView::exchangeWindow(int32_t node_id, int32_t qpair_id) {
    if(node_id == 0)
        return clientExchangeWindow(node_id, qpair_id);
    else
        return masterExchangeWindow(node_id, qpair_id);
}

/**
 * Master exchange window
 */
int fView::masterExchangeWindow(int32_t node_id, int32_t qpair_id) {
    int n;
    uint64_t vaddr;
    uint32_t size;

    // Receive
    // vaddr
    n = ::read(connections[node_id], &vaddr, sizeof(uint64_t));
    if (n != sizeof(uint64_t)) {
        std::cerr << "Could not read window, read bytes " << n << std::endl;
        ::close(connections[node_id]);
        return 1;
    }
    // size
    n = ::read(connections[node_id], &size, sizeof(uint32_t));
    if (n != sizeof(uint32_t)) {
        std::cerr << "Could not read window, read bytes " << n << std::endl;
        ::close(connections[node_id]);
        return 1;
    }

    pairs[node_id][qpair_id].remote.vaddr = vaddr;
    pairs[node_id][qpair_id].remote.size = size;

    std::cout << "Qpair nodeid " << node_id << "[" << qpair_id << "]" << std::endl;
    pairs[node_id][qpair_id].local.print("Local ");
    pairs[node_id][qpair_id].remote.print("Remote");     
    
    // Send
    // vaddr
    if ((n = ::write(connections[node_id], &pairs[node_id][qpair_id].local.vaddr, sizeof(uint64_t))) != sizeof(uint64_t))  {
        std::cerr << "Could not send" << std::endl;
        ::close(connections[node_id]);
        return 1;
    }
    // size
    if ((n = ::write(connections[node_id], &pairs[node_id][qpair_id].local.size, sizeof(uint32_t))) != sizeof(uint32_t))  {
        std::cerr << "Could not send" << std::endl;
        ::close(connections[node_id]);
        return 1;
    }

    return 0;
}

/**
 * Client exhchange window
 */
int fView::clientExchangeWindow(int32_t node_id, int32_t qpair_id) {
    int n;
    uint64_t vaddr;
    uint32_t size;

    // Send
    // vaddr
    if ((n = ::write(connections[node_id], &pairs[node_id][qpair_id].local.vaddr, sizeof(uint64_t))) != sizeof(uint64_t))  {
        std::cerr << "Could not send" << std::endl;
        ::close(connections[node_id]);
        return 1;
    }
    // size
    if ((n = ::write(connections[node_id], &pairs[node_id][qpair_id].local.size, sizeof(uint32_t))) != sizeof(uint32_t))  {
        std::cerr << "Could not send" << std::endl;
        ::close(connections[node_id]);
        return 1;
    }
    
    // Receive
    // vaddr
    n = ::read(connections[node_id], &vaddr, sizeof(uint64_t));
    if (n != sizeof(uint64_t)) {
        std::cerr << "Could not read window, read bytes " << n << std::endl;
        ::close(connections[node_id]);
        return 1;
    }
    // size
    n = ::read(connections[node_id], &size, sizeof(uint32_t));
    if (n != sizeof(uint32_t)) {
        std::cerr << "Could not read window, read bytes " << n << std::endl;
        ::close(connections[node_id]);
        return 1;
    }

    pairs[node_id][qpair_id].remote.vaddr = vaddr;
    pairs[node_id][qpair_id].remote.size = size;

    std::cout << "Qpair nodeid " << node_id << "[" << qpair_id << "]" << std::endl;
    pairs[node_id][qpair_id].local.print("Local ");
    pairs[node_id][qpair_id].remote.print("Remote");  
    
    return 0;
}

/* ---------------------------------------------------------------------------------------
/* -- Public
/* ---------------------------------------------------------------------------------------

/**
 * Allocate a window for the specific qpair
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id
 * @param: n_pages - number of large pages (2MB each)
 */
uint64_t* fView::allocWindow(uint32_t node_id, uint32_t qpair_id, uint64_t n_pages) {
    int32_t region = pairs[node_id][qpair_id].local.region;
    uint64_t *vaddr = fdev[region].getHostMem(n_pages);

    pairs[node_id][qpair_id].local.vaddr = (uint64_t)vaddr;
    pairs[node_id][qpair_id].local.size = n_pages * LARGE_PAGE_SIZE;

    exchangeWindow(node_id, qpair_id);

    return vaddr;
}

/**
 * Free window for the specific qpair
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id
 */
void fView::freeWindow(uint32_t node_id, uint32_t qpair_id) {
    int32_t region = pairs[node_id][qpair_id].local.region;
    uint64_t *vaddr = (uint64_t*)pairs[node_id][qpair_id].local.vaddr;
    uint64_t n_pages = (uint64_t)(pairs[node_id][qpair_id].local.size / LARGE_PAGE_SIZE);
    
    fdev[region].freeHostMem(vaddr, n_pages);
}

/**
 * Write RDMA operation
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id
 * @param: src_offs - offset in the source qpair buffer
 * @param: dst_offs - offset in teh destination qpair buffer
 * @param: size - transfer size
 */
void fView::writeRemote(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size) {
    fQPair *l_qp = &pairs[node_id][qpair_id];
    int32_t l_reg = l_qp->local.region;

    if(node_id == this->node_id) {
        uint64_t *l_addr = (uint64_t*)(l_qp->local.vaddr + src_offs);
        uint64_t *r_addr = (uint64_t*)(l_qp->remote.vaddr + dst_offs);

        memcpy(r_addr, l_addr, size);
    } else {
        fdev[l_reg].postWrite(l_qp, src_offs, dst_offs, size);
    }
}

/**
 * Read RDMA operation
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id
 * @param: src_offs - offset in the source qpair buffer
 * @param: dst_offs - offset in teh destination qpair buffer
 * @param: size - transfer size
 */
void fView::readRemote(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size) {
    fQPair *l_qp = &pairs[node_id][qpair_id];
    uint32_t l_reg = l_qp->local.region;

    if(node_id == this->node_id) {
        uint64_t *l_addr = (uint64_t*)(l_qp->local.vaddr + src_offs);
        uint64_t *r_addr = (uint64_t*)(l_qp->remote.vaddr + dst_offs);

        memcpy(r_addr, l_addr, size);
    } else {
        fdev[l_reg].postRead(l_qp, src_offs, dst_offs, size);
    }
}

/**
 * RPC RDMA operation
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id
 * @param: src_offs - offset in the source qpair buffer
 * @param: dst_offs - offset in teh destination qpair buffer
 * @param: size - transfer size
 * @param: params - arbitrary parameters (depends on the implemented operation)
 */
void fView::farviewRemote(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size, uint64_t params) {
    fQPair *l_qp = &pairs[node_id][qpair_id];
    uint32_t l_reg = l_qp->local.region;

    if(node_id == this->node_id) {
        uint64_t *l_addr = (uint64_t*)(l_qp->local.vaddr + src_offs);
        uint64_t *r_addr = (uint64_t*)(l_qp->remote.vaddr + dst_offs);

        memcpy(r_addr, l_addr, size);
    } else {
        fdev[l_reg].postFarview(l_qp, src_offs, dst_offs, size, params);
    }
}

/**
 * Write RDMA polling function
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id 
 */
uint32_t fView::pollRemoteWrite(uint32_t node_id, uint32_t qpair_id) {
    fQPair *l_qp = &pairs[node_id][qpair_id];
    int32_t l_reg = l_qp->local.region;
    
    return fdev[l_reg].checkCompletedWrite();
}

/**
 * Read RDMA polling function
 * @param: node_id - target node id
 * @param: qpair_id - target qpair id 
 */
uint32_t fView::pollLocalRead(uint32_t node_id, uint32_t qpair_id) {
    fQPair *l_qp = &pairs[node_id][qpair_id];
    int32_t l_reg = l_qp->local.region;
    
    return fdev[l_reg].checkCompletedRead();
}

/**
 * Sync with remote
 * @param: node_id - target node id
 */
int32_t fView::waitOnReplyRemote(uint32_t node_id) {
    int n;
    uint32_t ack;

    // Receive ACK
    n = ::read(connections[node_id], &ack, sizeof(uint32_t));
    if (n != sizeof(uint32_t)) {
        std::cerr << "Could not read ACK, read bytes " << n << std::endl;
        ::close(connections[node_id]);
        return 1;
    }

    return 0;
}

/**
 * Wait on close remote
 * @param: node_id - target node id
 */
int32_t fView::waitOnCloseRemote(uint32_t node_id) {
    int n;
    uint32_t ack;

    // Hacky
    n = ::read(connections[node_id], &ack, sizeof(uint32_t));
    if (n == 0) {
        std::cerr << "Connection closed" << std::endl;
        ::close(connections[node_id]);
        return 0;
    }

    return 1;
}


/**
 * Sync with remote
 * @param: node_id - target node id
 * @param: ack - acknowledge message
 */
int32_t fView::replyRemote(uint32_t node_id, uint32_t ack) {
    int n;

    if ((n = ::write(connections[node_id], &ack, sizeof(uint32_t))) != sizeof(uint32_t))  {
        std::cerr << "Could not send ACK" << std::endl;
        ::close(connections[node_id]);
        return 1;
    }

    return 0;
}

/**
 * Sync with remote
 * @param: node_id - target node id
 */
int32_t fView::syncRemote(uint32_t node_id) {
    if(this->node_id == 0) {
        replyRemote(node_id, 0);
        waitOnReplyRemote(node_id);
    } else {
        waitOnReplyRemote(node_id);
        replyRemote(node_id, 0);
    }

    return 0;
}

// Base control
void fView::farviewRemoteBase(uint32_t node_id, uint32_t qpair_id, uint64_t params_0, uint64_t params_1, uint64_t params_2) {
    fQPair *l_qp = &pairs[node_id][qpair_id];
    uint32_t l_reg = l_qp->local.region;

    fdev[l_reg].postFarviewBase(l_qp, params_0, params_1, params_2);
}

// Stride
void fView::farviewStride(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t dwidth, uint32_t stride, uint32_t num_elem) {
    uint32_t n_bytes = (1 << dwidth) * num_elem;
    uint64_t tmp = ((uint64_t)n_bytes << 32) | stride;
    farviewRemote(node_id, qpair_id, src_offs, dst_offs, dwidth, tmp);
}

// Load the configuration in 2 transactions
void fView::farviewRegexConfigLoad(uint32_t node_id, uint32_t qpair_id, unsigned char* config_bytes) {
    uint64_t* params_0 = (uint64_t*)config_bytes;
    uint64_t* params_1 = (uint64_t*)config_bytes + 1;
    uint64_t* params_2 = (uint64_t*)config_bytes+ 2;

    farviewRemoteBase(node_id, qpair_id, *params_0, *params_1, *params_2);

    params_0 += 3;
    params_1 += 3;
    params_2 += 3;

    farviewRemoteBase(node_id, qpair_id, *params_0, *params_1, *params_2);
}

// Regex read
void fView::farviewRegexRead(uint32_t node_id, uint32_t qpair_id, uint64_t src_offs, uint64_t dst_offs, uint32_t size) {
    farviewRemote(node_id, qpair_id, src_offs, dst_offs, size, ~0);
}


}
