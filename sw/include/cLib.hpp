#pragma once

#include "cDefs.hpp"

#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <iomanip>
#include <x86intrin.h>
#include <boost/program_options.hpp>
#include <sys/socket.h>
#include <sys/un.h>
#include <sstream>
#include <atomic>
#include <vector>

#include "cThread.hpp"

namespace fpga {

// ======-------------------------------------------------------------------------------
// Communication lib - utilities for communication 
// ======-------------------------------------------------------------------------------

template <typename Cmpl, typename... Args>
class cLib {
private:

    // Variables required for communication: 
    int sockfd = -1; // File Descriptor for the socket 
    struct sockaddr_un server; // Server-socket address for UNIX: AF_UNIX as address family, pathname of the socket 
    char recv_buff[recvBuffSize]; // Receive buffer for communication 

    static std::atomic_uint32_t curr_id; // Atomically protected ID-variable 

public:

    // Constructor #1: Takes the socket-name and the function(?)-ID 
    cLib(const char *sock_name, int32_t fid) {
        # ifdef VERBOSE
            std::cout << "cLib: Called the constructor for a local connection (AF_UNIX)." << std::endl; 
        # endif 

        // Open a socket
        if((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
            std::cout << "ERR:  Failed to create a server socket" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Set sun-family and sun-path in the server-socket address struct
        // Which means: This is a local socket for Inter-Process Communication and not a network socket for network communication 
        server.sun_family = AF_UNIX;
        strcpy(server.sun_path, sock_name);

        // Try to connect the socket to the provided remote server-side network socket 
        if(connect(sockfd, (struct sockaddr *) &server, sizeof(struct sockaddr_un)) < 0) {
            // If it doesn't work, close the socket, print out warning and exit program with failure-code 
            close(sockfd);
            std::cout << "ERR:  Failed to connect to a server socket" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Register
        // Get the current process-ID from the function 
        pid_t pid = getpid();

        # ifdef VERBOSE 
            std::cout << "cLib: Send process-ID" << pid << "function-ID" << fid << "to the remote side." << std::endl; 
        # endif     

        // Send the Process-ID to the remote-side 
        if(write(sockfd, &pid, sizeof(pid_t)) != sizeof(pid_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Send the function-ID to the remote-side 
        if(write(sockfd, &fid, sizeof(int32_t)) != sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }

        // If this exchange concluded successfully, print out that the client was registered as expected 
        std::cout << "Client registered" << std::endl;
    }

    // Constructor #2: More arguments, provides services for RDMA-connection 
    // sock_name: Name of the socket to be created 
    // fid: Function ID 
    // cthread: Associated thread 
    // trgt_addr: Target address for the connection 
    // port: Target port for the connection
    cLib(const char *sock_name, int32_t fid, cThread<Cmpl> *cthread, const char *trgt_addr, uint16_t port) {
        
        # ifdef VERBOSE
            std::cout << "cLib: Called the constructor for a local connection (AF_UNIX)." << std::endl; 
        # endif

        // Establish variables for connection establishment 
        struct addrinfo *res, *t;
        char* service;
        int n = 0;

        // Establish hints for network connection 
        struct addrinfo hints = {};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;

        // Prefill the receive buffer with 0s 
        memset(recv_buff, 0, recvBuffSize);

        // Check if the buffer is attached to the thread 
        if(!cthread->isBuffAttached())
            throw std::runtime_error("buffers not attached");

        // Format the port number in a string 
        if (asprintf(&service, "%d", port) < 0)
            throw std::runtime_error("asprintf() failed");

        // Create list of possible network adresses that are stored in res 
        n = getaddrinfo(trgt_addr, service, &hints, &res);
        if (n < 0) {
            free(service);
            throw std::runtime_error("getaddrinfo() failed");
        }

        // Iterate over the possible address structs and try to create a socket. If connection is successful, we're done with this loop. 
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

        # ifdef VERBOSE
            std::cout << "cLib: Connected to remote side server via" << sockfd << std::endl; 
        # endif

        // Throw error if no connection at all could be established 
        if (sockfd < 0)
            throw std::runtime_error("Could not connect to master: " + std::string(trgt_addr) + ":" + to_string(port));

        // Fid - send the file descriptor to the connected socket
        # ifdef VERBOSE
            std::cout << "cLib: Send fid to the remote side " << fid << std::endl; 
        # endif
        if(write(sockfd, &fid, sizeof(int32_t)) != sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Send local queue to the remote side. The Qpair is obtained from the thread. 
        ibvQ l_qp = cthread->getQpair()->local;

        // Send the QP to the other side 
        # ifdef VERBOSE
            std::cout << "cLib: Send local QP to the remote side" << std::endl; 
        # endif
        if(write(sockfd, &l_qp, sizeof(ibvQ)) != sizeof(ibvQ)) {
            std::cout << "ERR:  Failed to send a local queue " << std::endl;
            exit(EXIT_FAILURE);
        }

        // Read remote queue from the remote side, received via network 
        # ifdef VERBOSE
            std::cout << "cLib: Read remote QP from the remote side" << std::endl; 
        # endif
        if(read(sockfd, recv_buff, sizeof(ibvQ)) != sizeof(ibvQ)) {
            std::cout << "ERR:  Failed to read a remote queue" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Received remote QP is located in the receive buffer and is getting copied over to the thread, which manages all QPs 
        memcpy(&cthread->getQpair()->remote, recv_buff, sizeof(ibvQ));

        // Output: Print local and remote QPs 
        std::cout << "Queue pair: " << std::endl;
        cthread->getQpair()->local.print("Local ");
        cthread->getQpair()->remote.print("Remote");

        // Write context and connection to the configuration registers 
        # ifdef VERBOSE
            std::cout << "cLib: Write QP-context to the configuration registers" << std::endl; 
        # endif
        cthread->writeQpContext(port);

        // ARP lookup to get the MAC-address for the remote QP IP-address 
        # ifdef VERBOSE
            std::cout << "cLib: Initiate an Arp-lookup for the IP-address " << cThread->getQpair()->remote.ip_addr << std::endl; 
        # endif
        cthread->doArpLookup(cthread->getQpair()->remote.ip_addr);

        // Set connection - open the network connection via the thread
        # ifdef VERBOSE
            std::cout << "cLib: Safe the connection in the cThread " << sockfd << std::endl; 
        # endif 
        cthread->setConnection(sockfd);

        // Printout the success of established connection 
        std::cout << "Client registered" << std::endl;
    }

    ~cLib() {
        // Send request to close the connection - probably sent to the cFunc, as this one operates on this level 
        int32_t req[3];
        req[0] = defOpClose;

        // Close conn
        # ifdef VERBOSE
            std::cout << "cLib: Close the connection" << std::endl; 
        # endif 
        if(write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }
        std::cout << "Sent close" << std::endl;

        // After the request to close the connection is sent, actually close the connection afterwards 
        close(sockfd);
    }

    /**
     * task, iTask, iCmpl are used for interaction with cFunc: They send a task to cFunc, which then 
     * places this task in the execution queue of the thread for scheduled execution, wait for the 
     * completion event and send back the completion ID and the completion event here to the iCmpl. 
     */

    // Task blocking: Variadic function that takes a priority and an arbitrary number of arguments for further processing 
    // Function is basically the same as iTask, but with a blocking completion-handshake at the end 
    Cmpl task(int32_t priority, Args... msg) {
        // Send request
        int32_t req[3];
        req[0] = defOpTask;
        req[1] = curr_id++;
        req[2] = priority;

        # ifdef VERBOSE
            std::cout << "cLib: Send task request with defOpTask " << defOpTask << ", curr_id" << req[1] << "and priority" << priority << std::endl; 
        # endif 
        
        // Send tid and opcode to the remote side 
        if(write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Send payload - lambda function to send an arbitrary value to the socket / remote side
        auto f_wr = [&](auto& x){
            using U = decltype(x);
            int size_arg = sizeof(U);

            # ifdef VERBOSE
                std::cout << "cLib: Send the user payload via the task " << x << std::endl; 
            # endif 

            if(write(sockfd, &x, size_arg) != size_arg) {
                std::cout << "ERR:  Failed to send a request" << std::endl;
                exit(EXIT_FAILURE);
            }
        };

        // Unfolding operator: Send all arguments (variadic function!) with the pre-defined lambda function to the other side 
        (f_wr(msg), ...);
        //std::apply([=](auto&&... args) {(f_wr(args), ...);}, msg);
        std::cout << "Sent payload" << std::endl;

        // Wait for completion - exchange completion thread-ID and completion event 
        int32_t cmpl_tid;
        Cmpl cmpl_ev;

        if(read(sockfd, recv_buff, sizeof(int32_t)) != sizeof(int32_t)) {
            std::cout << "ERR:  Failed to receive completion event" << std::endl;
            exit(EXIT_FAILURE);
        }
        memcpy(&cmpl_tid, recv_buff, sizeof(int32_t));

        # ifdef VERBOSE
            std::cout << "cLib: Read the cmplt_tid " << cmplt_tid << std::endl; 
        # endif 

        if(read(sockfd, recv_buff, sizeof(Cmpl)) != sizeof(Cmpl)) {
            std::cout << "ERR:  Failed to receive completion event" << std::endl;
            exit(EXIT_FAILURE);
        }
        memcpy(&cmpl_ev, recv_buff, sizeof(Cmpl));

        # ifdef VERBOSE
            std::cout << "cLib: Read the completion event." << std::endl; 
        # endif 

        // Printout that completion was received 
        std::cout << "Received completion" << std::endl;
        
        // Return the completion event (probably with a completion code)
        return cmpl_ev;
    }

    // Task non-blocking: Variadic function that can take a variable number of arguments (as shown by Args...) and send them to the socket / remote side 
    // Problem: I don't know why this is used in the RDMA-example, since we normally wouldn't need to send experimentation arguments to the other side 
    // Function is basically the same as task, but without the blocking completion-handshake at the end 
    void iTask(int32_t priority, Args... msg) {
        // Send request
        int32_t req[3];
        req[0] = defOpTask;
        req[1] = curr_id++;
        req[2] = priority;
        
        // Send tid and opcode to the sockfd / remote side 
        # ifdef VERBOSE
            std::cout << "cLib: Send iTask request with defOpTask " << defOpTask << ", curr_id" << req[1] << "and priority" << priority << std::endl; 
        # endif 
        if(write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Send payload - lambda function to send an arbitrary value to the socket / remote side
        auto f_wr = [&](auto& x){
            using U = decltype(x);
            int size_arg = sizeof(U);

            # ifdef VERBOSE
                std::cout << "cLib: Send the user payload via the task " << x << std::endl; 
            # endif

            if(write(sockfd, &x, size_arg) != size_arg) {
                std::cout << "ERR:  Failed to send a request" << std::endl;
                exit(EXIT_FAILURE);
            }
        };

        // Unfolding operator: Send all arguments (variadic function!) with the pre-defined lambda function to the other side 
        (f_wr(msg), ...);
        //std::apply([=](auto&&... args) {(f_wr(args), ...);}, msg);
        std::cout << "Sent payload" << std::endl;
    }

    // That's basically the second part of task that's missing in iTask, so that it can be called on its own 
    Cmpl iCmpl() {
        // Wait for completion
        int32_t cmpl_tid;
        Cmpl cmpl_ev;

        # ifdef VERBOSE
            std::cout << "cLib: Called the iCmpl-function." << std::endl; 
        # endif

        // Read the completion thread-ID from the socket 
        if(read(sockfd, recv_buff, sizeof(int32_t)) != sizeof(int32_t)) {
            std::cout << "ERR:  Failed to receive completion event" << std::endl;
            exit(EXIT_FAILURE);
        }
        memcpy(&cmpl_tid, recv_buff, sizeof(int32_t));

        # ifdef VERBOSE
            std::cout << "cLib: Read the cmplt_tid " << cmplt_tid << std::endl; 
        # endif

        // Read the completion event from the socket 
        if(read(sockfd, recv_buff, sizeof(Cmpl)) != sizeof(Cmpl)) {
            std::cout << "ERR:  Failed to receive completion event" << std::endl;
            exit(EXIT_FAILURE);
        }
        memcpy(&cmpl_ev, recv_buff, sizeof(Cmpl));

        # ifdef VERBOSE
            std::cout << "cLib: Read the completion event." << std::endl; 
        # endif 

        // Printout that completion was received 
        std::cout << "Received completion" << std::endl;
        
        return cmpl_ev;
    }
};

// Define cLib as a variadic template 
template <typename Cmpl, typename... Args>

// Defines an atomic uint32 current ID that is part of the cLib template. Allows to generate unique IDs in a thread-safe manner. 
std::atomic<uint32_t> cLib<Cmpl, Args...>::curr_id;

}

// Operations