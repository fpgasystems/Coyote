#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>
#include <queue>

#include "bFunc.hpp"
#include "cThread.hpp"
#include "cService.hpp"

namespace fpga {

/**
 * @brief User functions
 *
 */

// Template of the function, which is variadic: Completion element is always used as argument, rest of the argument list is variable 
template <typename Cmpl, typename... Args>

// Class cFunc inherits from bFunc (which only has virtual functions to be overwritten)
class cFunc : public bFunc {
private: 
    // Operator id
    int32_t oid;

    // Function as private member variable: Takes a cThread and a variable number of arguments as input, creates a completion element 
    std::function<Cmpl(cThread<Cmpl>*, Args...)> f;

    // Clients
    unordered_map<int, std::unique_ptr<cThread<Cmpl>>> clients; // Maps an integer to a cThread (turn out: maps a connection file descriptor to a registered thread)
    unordered_map<int, std::pair<bool, std::thread>> reqs; // Maps an integer to a pair of bool and std::thread object (turns out: maps a connection file descriptor to )

    // Cleanup thread - special thread for cleaning up 
    bool run_cln = { false };
    std::thread thread_cln;
    mutex mtx_q;
    std::queue<int> cln_q;

public:

    /**
     * @brief Ctor, dtor
    */

   // Constructor: Takes operator instructor and function as input. 
   // This function again is supposed to take a thread as input and create a completion event: Could be a user-function for processing a thread 
    cFunc(int32_t oid, std::function<Cmpl(cThread<Cmpl>*, Args...)> f) {
        this->oid = oid;
        this->f = f;
    }

    // Destructor: Destroy the final clean-up thread 
    ~cFunc() { 
        int connfd;
        run_cln = false;
        thread_cln.join();

        // Finish all threads that are stored in req (set bool to false, join the threads)
        for(auto it = reqs.begin(); it != reqs.end(); it++) {
            connfd = it->first;
            reqs[connfd].first = false;
            reqs[connfd].second.join();
        }
    }

    // Create the clean-up thread -> Thread again points to a function cleanConns defined here in this class 
    // The function cleanConns is to be executed by this clean-up-thread 
    void start() {
        thread_cln = std::thread(&cFunc::cleanConns, this);
    }

    // Creates a new thread based on the information provided as arguments, registers this new thread in the clients-struct and returns it to the caller 
    // connfd - connection file descriptor 
    // vfid - vFPGA identifier 
    // rpid - remote process identifier 
    // dev - device identifier 
    // csched - scheduler 
    // user-defined interrupt service routine 
    bThread* registerClientThread(int connfd, int32_t vfid, pid_t rpid, uint32_t dev, cSched *csched, void (*uisr)(int) = nullptr) {
        
        // Check if there's already a thread registered for this connfd 
        if(clients.find(connfd) == clients.end()) {

            // New insertion into the clients-struct: Mapping between connection-fd and new cThread based on the parameters given 
            clients.insert({connfd, std::make_unique<cThread<Cmpl>>(vfid, rpid, dev, csched, uisr)});

            // Registers a new pair of bool::false and a standard-thread (which again points to the function processRequests and the connfd)
            reqs.insert({connfd, std::make_pair(false, std::thread(&cFunc::processRequests, this, connfd))});

            // The newly added thread is kicked off: 
            clients[connfd]->setConnection(connfd); // Set connection for the new thread 
            clients[connfd]->start(); // Start execution of the cThread

            syslog(LOG_NOTICE, "Connection thread created");

            // Return the thread that has been created and registered in the clients-struct
            return clients[connfd].get();
        }


        // If there's already a thread registered for this connfd, return a nullpointer 
        return nullptr;
    }

    // Function that is given to the standard-threads that are stored in the reqs-struct 
    void processRequests(int connfd) {

        // Create a receive-buffer and set it to 0 
        char recv_buf[recvBuffSize];
        memset(recv_buf, 0, recvBuffSize);

        // Create ack and message-size 
        uint8_t ack_msg;
        int32_t msg_size;

        // Create three requests and opcode, thread-ID and priority 
        int32_t request[3], opcode, tid, priority;
        int n;

        // Completion event 
        Cmpl cmpl_ev;

        // Completion thread-ID 
        int32_t cmpl_tid;

        // Completed set to wrong 
        bool cmpltd = false;

        // Set the reqs-entry to true - probably means something like "active" or "getting processed"
        reqs[connfd].first = true;

        int i = 0;

        // As long as the first value in the struct is true, continue processing in this loop 
        while(reqs[connfd].first) {
            // Read the three request-integers from the socket 
            if(read(connfd, recv_buf, 3 * sizeof(int32_t)) == 3 * sizeof(int32_t)) {
                memcpy(&request, recv_buf, sizeof(int32_t));
                // Parse the received values to opcode, thread ID and priority 
                opcode = request[0];
                tid = request[1];
                priority = request[2];
                syslog(LOG_NOTICE, "Client: %d, opcode %d, tid: %d", connfd, opcode, tid);

                // Further action depends on the opcode that is read from the network socket 
                switch (opcode) {
                
                // Request to close a connection 
                case defOpClose: {
                    syslog(LOG_NOTICE, "Received close connection request");
                    close(connfd);
                    
                    // Set the entry to false, case has been closed 
                    reqs[connfd].first = false;

                    break;
                }

                // Request to execute a function 
                case defOpTask: {
                    // Expansion
                    std::tuple<Args...> msg;

                    auto f_rd = [&](auto& x){
                        using U = decltype(x);
                        int size_arg = sizeof(U);

                        if(n = read(connfd, recv_buf, size_arg) == size_arg) {
                            memcpy(&x, recv_buf, size_arg);
                        } else {
                            syslog(LOG_ERR, "Request invalid, connfd: %d", connfd);
                        }
                    };
                    std::apply([=](auto&&... args) {(f_rd(args), ...);}, msg);
                
                    clients[connfd]->scheduleTask(std::unique_ptr<bTask<Cmpl>>(new auto(std::make_from_tuple<cTask<Cmpl, std::function<Cmpl(cThread<Cmpl>*, Args...)>, Args...>>(std::tuple_cat(
                        std::make_tuple(tid), 
                        std::make_tuple(oid), 
                        std::make_tuple(priority),
                        std::make_tuple(f),
                        msg)))));

                    while(!cmpltd) {
                        cmpltd = clients[connfd]->getTaskCompletedNext(cmpl_tid, cmpl_ev);
                        if(cmpltd) {
                            if(write(connfd, &cmpl_tid, sizeof(int32_t)) != sizeof(int32_t)) {
                                syslog(LOG_ERR, "Completion tid could not be sent, connfd: %d", connfd);
                            }

                            if(write(connfd, &cmpl_ev, sizeof(Cmpl)) != sizeof(Cmpl)) {
                                syslog(LOG_ERR, "Completion could not be sent, connfd: %d", connfd);
                            }
                        } else {
                            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalCompletion));
                        }
                    }
                    
                    break;
                }
                default:
                    break;
               
                }
            }

            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalRequests));
        }

        syslog(LOG_NOTICE, "Connection %d closing ...", connfd);
        // Send cleanup
        mtx_q.lock();
        cln_q.push(connfd);
        mtx_q.unlock();

    }

    void cleanConns() {
        run_cln = true;
        int connfd;

        while(run_cln) {
            mtx_q.lock();
            if(!cln_q.empty()) {
                connfd = cln_q.front(); cln_q.pop();
                reqs[connfd].second.join();

                reqs.erase(connfd);
                clients.erase(connfd);
            }
            mtx_q.unlock();


            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalRequests));
        }
    }
    
};

}
