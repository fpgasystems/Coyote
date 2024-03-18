#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

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

    // Service
    cSched *csched;

    // Clients
    mutex mtx_cli;
    unordered_map<int, std::unique_ptr<cThread<Cmpl>>> clients;

    // Function
    std::function<Cmpl(cThread<Cmpl>*, Args...)> f;

public:

    /**
     * @brief Ctor, dtor
    */
    cFunc(int32_t oid, cSched *csched, std::function<Cmpl(cThread<Cmpl>*, Args...)> f) {
        this->oid = oid;
        this->f = f;
        this->csched = csched;
    }

    ~cFunc() { }

    //
    void registerClientThread(int connfd, int32_t vfid, pid_t rpid, csDev dev, void (*uisr)(int) = nullptr) {
        mtx_cli.lock();
        
        if(clients.find(connfd) == clients.end()) {
            clients.insert({connfd, std::make_unique<cThread<Cmpl>>(vfid, rpid, dev, csched, uisr)});
            clients[connfd]->start();
            syslog(LOG_NOTICE, "Connection thread created");
        }

        mtx_cli.unlock();
    }
    
    void requestRecv() {
        char recv_buf[recvBuffSize];
        memset(recv_buf, 0, recvBuffSize);
        uint8_t ack_msg;
        int32_t msg_size;
        int32_t request[3], opcode, tid, priority;
        int n;

        for (auto & el : clients) {
            mtx_cli.lock();
            int connfd = el.first;

            if(read(connfd, recv_buf, 3 * sizeof(int32_t)) == 3 * sizeof(int32_t)) {
                memcpy(&request, recv_buf, sizeof(int32_t));
                opcode = request[0];
                tid = request[1];
                priority = request[2];
                syslog(LOG_NOTICE, "Client: %d, opcode: %d", el.first, opcode);

                switch (opcode) {

                // Close connection
                case defOpClose: {
                    syslog(LOG_NOTICE, "Received close connection request, connfd: %d", connfd);
                    close(connfd);
                    clients.erase(el.first);
                    break;
                }
                // Schedule the task
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
                
                    
                    el.second->scheduleTask(std::unique_ptr<bTask<Cmpl>>(new auto(std::make_from_tuple<cTask<Cmpl, std::function<Cmpl(cThread<Cmpl>*, Args...)>, Args...>>(std::tuple_cat(
                        std::make_tuple(tid), 
                        std::make_tuple(oid), 
                        std::make_tuple(priority),
                        std::make_tuple(f),
                        msg)))));
        
                    break;
                }
                default:
                    break;

                }
            }

            mtx_cli.unlock();
        }
    }
    
    void responseSend() {
        int n;
        int ack_msg;
        Cmpl cmpl_ev;
        int32_t cmpl_tid;
        bool cmpltd = false;
    
        for (auto & el : clients) {
            cmpltd = el.second->getTaskCompletedNext(cmpl_tid, cmpl_ev);
            if(cmpltd) {
                int connfd = el.first;

                if(write(connfd, &cmpl_tid, sizeof(int32_t)) != sizeof(int32_t)) {
                    syslog(LOG_ERR, "Completion tid could not be sent, connfd: %d", connfd);
                }

                if(write(connfd, &cmpl_ev, sizeof(Cmpl)) != sizeof(Cmpl)) {
                    syslog(LOG_ERR, "Completion could not be sent, connfd: %d", connfd);
                }
            }
        }
    }
};

}
