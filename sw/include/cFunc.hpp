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
template <typename Cmpl, typename... Args>
class cFunc : public bFunc {
private: 
    // Operator id
    int32_t oid;

    // Function
    std::function<Cmpl(cThread<Cmpl>*, Args...)> f;

    // Clients
    unordered_map<int, std::unique_ptr<cThread<Cmpl>>> clients;
    unordered_map<int, std::pair<bool, std::thread>> reqs;

    // Cleanup thread
    bool run_cln = { false };
    std::thread thread_cln;
    mutex mtx_q;
    std::queue<int> cln_q;

public:

    /**
     * @brief Ctor, dtor
    */
    cFunc(int32_t oid, std::function<Cmpl(cThread<Cmpl>*, Args...)> f) {
        this->oid = oid;
        this->f = f;
    }

    ~cFunc() { 
        int connfd;
        run_cln = false;
        thread_cln.join();

        for(auto it: reqs) {
            connfd = it.first;
            reqs[connfd].first = false;
            reqs[connfd].second.join();
        }
    }

    void start() {
        thread_cln = std::thread(&cFunc::cleanConns, this);
    }

    //
    bThread* registerClientThread(int connfd, int32_t vfid, pid_t rpid, uint32_t dev, cSched *csched, void (*uisr)(int) = nullptr) {
        
        if(clients.find(connfd) == clients.end()) {
            clients.insert({connfd, std::make_unique<cThread<Cmpl>>(vfid, rpid, dev, csched, uisr)});
            reqs.insert({connfd, std::make_pair(false, std::thread(&cFunc::processRequests, this, connfd))});

            clients[connfd]->setConnection(connfd);
            clients[connfd]->start();

            syslog(LOG_NOTICE, "Connection thread created");
            return clients[connfd].get();
        }

        return nullptr;
    }

    void processRequests(int connfd) {
        char recv_buf[recvBuffSize];
        memset(recv_buf, 0, recvBuffSize);
        uint8_t ack_msg;
        int32_t msg_size;
        int32_t request[3], opcode, tid, priority;
        int n;
        Cmpl cmpl_ev;
        int32_t cmpl_tid;
        bool cmpltd = false;
        reqs[connfd].first = true;

        int i = 0;

        while(reqs[connfd].first) {
            // Schedule
            if(read(connfd, recv_buf, 3 * sizeof(int32_t)) == 3 * sizeof(int32_t)) {
                memcpy(&request, recv_buf, sizeof(int32_t));
                opcode = request[0];
                tid = request[1];
                priority = request[2];
                syslog(LOG_NOTICE, "Client: %d, opcode %d, tid: %d", connfd, opcode, tid);
        
                switch (opcode) {
                
                case defOpClose: {
                    syslog(LOG_NOTICE, "Received close connection request");
                    close(connfd);
                    
                    reqs[connfd].first = false;

                    break;
                }
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
