/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

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
#include <random>
#include <cstring>
#include <atomic>
#include <signal.h> 
#include <boost/program_options.hpp>

#include "cBench.hpp"
#include "cIbvCtx.hpp"

#define EN_THR_TESTS
//#define EN_LAT_TESTS

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Signal handler */
std::atomic<bool> stalled(false); 
void gotInt(int) {
    stalled.store(true);
}

/* Params */
constexpr auto const devBus = "c4";
constexpr auto const devSlot = "00";

constexpr auto const targetVfid = 0;
constexpr auto const defPort = 18488;

constexpr auto const defSize = 4096;

int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Initialization 
    // ---------------------------------------------------------------

    // Sig handler
    struct sigaction sa;
    memset( &sa, 0, sizeof(sa) );
    sa.sa_handler = gotInt;
    sigfillset(&sa.sa_mask);
    sigaction(SIGINT,&sa,NULL);

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("tcpaddr,t", boost::program_options::value<string>(), "TCP conn IP")
        ("port,p", boost::program_options::value<uint16_t>(), "Server port");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    string tcp_mstr_ip;
    uint16_t port = defPort;
    bool server = true;

    if(commandLineArgs.count("tcpaddr") > 0) {
        tcp_mstr_ip = commandLineArgs["tcpaddr"].as<string>();
        server = false;
    }
    if(commandLineArgs.count("port") > 0) port = commandLineArgs["port"].as<uint16_t>();

    PR_HEADER("PARAMS");
    if(!server) { std::cout << "Server IP address: " << tcp_mstr_ip << std::endl; }
    std::cout << "Buffer size: " << defSize << std::endl;
    
    // Init app layer --------------------------------------------------------------------------------

    if(server) {
        cIbvCtx *cctx = cIbvCtx::getInstance(targetVfid, {devBus, devSlot});
        cctx->start(port, [] (cThread *cthread, uint32_t arg) -> cmplVal{
            std::cout << "DBG:  Received from " << std::hex << cthread->getQpair()->remote.ip_addr << std::dec << std::endl;

            cthread->rdmaConnSync(false);

            std::cout << "DBG:  Synced up with client" << std::endl;

            cthread->rdmaConnClose(false);

            return { 0.0 } ;
        });

        /*
        cIbvCtx::exchangeQpServer(&cthread, port);
        cthread.rdmaConnClose(false);
        */
    } else {
        cThread cthread(targetVfid, getpid(), {devBus, devSlot});
        cthread.getMem({CoyoteAlloc::HPF, defSize, true});

        bool ack = cIbvCtx::exchangeQpClient(&cthread, tcp_mstr_ip.c_str(), port);

        if(ack) {
            std::cout << "DBG:  Exchanged with server ..." << std::endl;

            cthread.rdmaConnSync(true);

            std::cout << "DBG:  Synced up with server, sleeping ..." << std::endl;
            sleep(5);


            cthread.rdmaConnClose(true);
        } else {
            std::cout << "DBG:  Server could not accept connection" << std::endl;
        }
        
    }

    return EXIT_SUCCESS;
}
