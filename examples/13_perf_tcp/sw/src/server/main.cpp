/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <iostream>
#include <cstdint>
#include <unistd.h>

#include <boost/program_options.hpp>

#include <coyote/cThread.hpp>

#define DEFAULT_VFPGA_ID 0

int main(int argc, char* argv[]) {
    uint16_t port;

    boost::program_options::options_description runtime_options("Coyote Example 13: TCP Perf Server");
    runtime_options.add_options()
        ("port,p", boost::program_options::value<uint16_t>(&port)->required(), "TCP listen port (required)");

    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    std::cout << "Listen port: " << port << std::endl;

    // Set up thread and listen on port; after that, software need not do anything
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    coyote_thread.listenTcp(port);

    std::cout << "Server running. Press Ctrl+C to stop." << std::endl;

    while (true) { sleep(10); }

    return EXIT_SUCCESS;
}
