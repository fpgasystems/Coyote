#include <dirent.h>
#include <iterator>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <iostream>
#include <stdlib.h>
#include <string>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>
#include <vector>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <iomanip>
#include <chrono>
#include <thread>
#include <limits>
#include <assert.h>
#include <stdio.h>
#include <sys/un.h>
#include <errno.h>
#include <wait.h>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <condition_variable>

#include "cService.hpp"

using namespace std;
using namespace fpga;

// Runtime
constexpr auto const defVfid = 0;

/**
 * @brief Process requests
 * 
 */
void process_requests()
{
    char recv_buf[recvBuffSize];
    memset(recv_buf, 0, recvBuffSize);
    //msgType msg;
    uint8_t ack_msg;
    int n;

    while(thread_req->isRunning()) {
        mtx_cli.lock();

        for (auto & el : clients) {
            int connfd = el.first;
            if(read(connfd, recv_buf, 1) == 1) {
                
                uint8_t opcode = uint8_t(recv_buf[0]);
                syslog(LOG_ERR, "opCode: %d", opcode);

                switch (opcode) {

                // Run the operator
                case opCodeRunRead:
                    syslog(LOG_NOTICE, "Received operation request, connfd: %d", connfd);
                    /*
                    if(n = read(connfd, recv_buf, sizeof(msgType)) == sizeof(msgType)) {
                        memcpy(&msg, recv_buf, sizeof(msgType));
                        syslog(LOG_NOTICE, "Received new request, connfd: %d, tid: %d, src: %lx, len: %d, key_low: %lx, key_high: %lx",
                            el.first, msg.tid, msg.src, msg.len, msg.key_low, msg.key_high);

                        // Schedule
                        el.second->scheduleTask(std::unique_ptr<bTask>(new cTask(msg.tid, aesOpId, opPrio, aes, msg)));
                    } else {
                        syslog(LOG_ERR, "Request invalid, connfd: %d, received: %d", connfd, n);
                    }
                    */
                    break;

                // Close connection
                case opCodeClose:
                    syslog(LOG_NOTICE, "Received close connection request, connfd: %d", connfd);
                    /*close(connfd);
                    connections.users.erase(el.first);*/
                    break;
                
                default:
                    break;
                }
            }
        }

        mtx_cli.unlock();
        nanosleep((const struct timespec[]){{0, sleepIntervalRequests}}, NULL);
    }
}

void process_responses()
{
    int n;
    int ack_msg;
    
    while(thread_rsp->isRunning()) {

        for (auto & el : clients) {
            int32_t tid = el.second->getCompletedNext();
            if(tid != -1) {
                syslog(LOG_NOTICE, "Running here...");
                int connfd = el.first;

                if(write(connfd, &tid, sizeof(int32_t)) == sizeof(int32_t)) {
                    syslog(LOG_NOTICE, "Sent completion, connfd: %d, tid: %d", connfd, tid);
                } else {
                    syslog(LOG_ERR, "Completion could not be sent, connfd: %d", connfd);
                }
            }
        }

        nanosleep((const struct timespec[]){{0, sleepIntervalCompletion}}, NULL);
    }
}

/**
 * @brief Main
 *  
 */
int main(void) 
{   
    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("vfid,i", boost::program_options::value<uint32_t>(), "vFPGA ID");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    uint32_t vfid = defVfid;
    if(commandLineArgs.count("vfid") > 0) vfid = commandLineArgs["vfid"].as<int32_t>();

    // Create service
    cService cservice(vfid, );

    // Run service
    cservice.run();
}