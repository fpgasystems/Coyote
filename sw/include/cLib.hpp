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
    // isClient: Specifies whether the calling thread is a RDMA-client or -server. This decides who can send first for the exchange of QPs for RDMA. 
    cLib(const char *sock_name, int32_t fid, cThread<Cmpl> *cthread, const char *trgt_addr, uint16_t port, bool isClient = true) {
        // If cLib is called for an RDMA-client, it has to take the active role in the QP-exchange 
        if(isClient) {
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

            // Throw error if no connection at all could be established 
            if (sockfd < 0)
                throw std::runtime_error("Could not connect to master: " + std::string(trgt_addr) + ":" + to_string(port));

            // Fid - send the file descriptor to the connected socket
            if(write(sockfd, &fid, sizeof(int32_t)) != sizeof(int32_t)) {
                std::cout << "ERR:  Failed to send a request" << std::endl;
                exit(EXIT_FAILURE);
            }

            // Send local queue to the remote side. The Qpair is obtained from the thread. 
            ibvQ l_qp = cthread->getQpair()->local;

            // Send the QP to the other side 
            if(write(sockfd, &l_qp, sizeof(ibvQ)) != sizeof(ibvQ)) {
                std::cout << "ERR:  Failed to send a local queue " << std::endl;
                exit(EXIT_FAILURE);
            }

            // Read remote queue from the remote side, received via network 
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
            cthread->writeQpContext(port);

            // ARP lookup to get the MAC-address for the remote QP IP-address 
            cthread->doArpLookup(cthread->getQpair()->remote.ip_addr);

            // Set connection - open the network connection via the thread
            cthread->setConnection(sockfd);

            // Printout the success of established connection 
            std::cout << "Client registered" << std::endl;

        } else {
            // If cLib is created for a RDMA-server, it needs to take the passive part in the QP-exchange

            //////////////////////////////////////////
            // Step 1: Init the socket for QP-exchange
            //////////////////////////////////////////

            int sockfd = -1; 
            struct sockaddr_in server; 

            // Create the socket and check if it's successful 
            sockfd = ::socket(AF_INET, SOCK_STREAM, 0); 
            if (sockfd == -1)
                throw std::runtime_error("Could not create a socket");

            // Select network and address for connection 
            server.sin_family = AF_INET; 
            server.sin_addr.s_addr = INADDR_ANY; 
            server.sin_port = htons(port); 
            
            // Try to connect the socket 
            if (::bind(sockfd, (struct sockaddr*)&server, sizeof(server)) < 0)
                throw std::runtime_error("Could not bind a socket");

            if (sockfd < 0 )
                throw std::runtime_error("Could not listen to a port: " + to_string(port));

            // Try to listen to the network socket 
            if(listen(sockfd, maxNumClients) == -1) {
                syslog(LOG_ERR, "Error listen()");
                exit(EXIT_FAILURE);
            }


            //////////////////////////////////////////
            // Step 2: QP-Exchange
            /////////////////////////////////////////

            // Create all required local variables
            uint32_t recv_qpid; 
            uint8_t ack; 
            uint32_t n; 
            int connfd; 
            int fid; 
            ibvQ r_qp; 

            // Create a receive buffer and allocate memory space for it 
            char recv_buffer[recvBuffSize]; 
            memset(recv_buf, 0, recvBuffSize); 

            // Try to accept the incoming connection 
            if((connfd = ::accept(sockfd, NULL, 0)) != -1) {
                syslog(LOG_NOTICE, "Connection accepted remote, connfd: %d", connfd); 

                // Read fid
                if((n = ::read(connfd, recv_buf, sizeof(int32_t))) == sizeof(int32_t)) {
                    memcpy(&fid, recv_buf, sizeof(int32_t));
                    syslog(LOG_NOTICE, "Function id: %d", fid);
                } else {
                    ::close(connfd);
                    syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
                    exit(EXIT_FAILURE);
                }

                // Read remote queue pair
                if ((n = ::read(connfd, recv_buf, sizeof(ibvQ))) == sizeof(ibvQ)) {
                    memcpy(&r_qp, recv_buf, sizeof(ibvQ));
                    syslog(LOG_NOTICE, "Read remote queue");
                } else {
                    ::close(connfd);
                    syslog(LOG_ERR, "Could not read a remote queue %d", n);
                    exit(EXIT_FAILURE);
                }

                // Store the received remote QP as part of the cThread 
                cthread->getQpair()->remote = r_qp; 
                cthread->getMem({CoyoteAlloc::HPF, r_qp.size, true}); 

                // Send the local queue pair to the remote side 
                if (::write(connfd, &cthread->getQpair()->local, sizeof(ibvQ)) != sizeof(ibvQ))  {
                    ::close(connfd);
                    syslog(LOG_ERR, "Could not write a local queue");
                    exit(EXIT_FAILURE);
                }

                // Write context and connection to the config-space of Coyote 
                cthread->writeQpContext(port); 
                
                // Perform an ARP lookup
                cthread->doArpLookup(cthread->getQpair()->remote.ip_addr); 
            } else {
                syslog(LOG_ERR, "Accept failed"); 
            }
        }
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
            std::cout << "cLib: Read the cmpl_tid " << cmpl_tid << std::endl; 
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
            std::cout << "cLib: Read the cmpl_tid " << cmpl_tid << std::endl; 
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