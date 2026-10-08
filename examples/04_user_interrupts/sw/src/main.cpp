/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <set>
#include <cstring>
#include <mutex>
#include <memory>
#include <chrono>
#include <thread>
#include <vector>
#include <iostream>
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cThread.hpp>

// Size of one notification descriptor in bytes, which corresponds to 512 bits, the default AXI stream bit width in Coyote
#define DESCRIPTOR_SIZE_BYTES 64

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

// Time without new interrupts after which a burst is considered complete
#define IDLE_TIMEOUT std::chrono::seconds(1)

// Interrupt values received by one cThread
// The interrupt callback runs on a separate thread, which is why the values are protected by a mutex
struct ReceivedInterrupts {
    std::mutex mtx;
    std::vector<uint32_t> values;

    size_t size() {
        std::lock_guard<std::mutex> lock(mtx);
        return values.size();
    }
};

// Interrupt value: [31:24] target ctid, [23:16] burst ID, [15:0] index within the burst
// The burst ID starts at 1, so the value is always non-zero
uint32_t encodeValue(int32_t ctid, uint32_t burst_id, uint32_t index) {
    return ((uint32_t) ctid << 24) | ((burst_id & 0xff) << 16) | (index & 0xffff);
}

/**
 * Issues back-to-back interrupts addressed to one cThread and checks that it received each of them exactly once and in order
 * The vFPGA issues one interrupt for every descriptor in the buffer, so all interrupts are raised by a single LOCAL_READ
 * @return true if all interrupts were received by the target and no other cThread received any
 */
bool runBurst(
    coyote::cThread &issuer, int *buffer, uint32_t n_interrupts, uint32_t burst_id, 
    std::vector<std::unique_ptr<coyote::cThread>> &coyote_threads, std::vector<std::unique_ptr<ReceivedInterrupts>> &received, size_t target
) {
    int32_t target_ctid = coyote_threads[target]->getCtid();
    for (auto &r : received) {
        std::lock_guard<std::mutex> lock(r->mtx);
        r->values.clear();
    }

    // Write one descriptor per interrupt: value, ctid and the flag that enables the interrupt
    for (uint32_t i = 0; i < n_interrupts; i++) {
        int *descriptor = buffer + i * DESCRIPTOR_SIZE_BYTES / sizeof(int);
        descriptor[0] = encodeValue(target_ctid, burst_id, i);
        descriptor[1] = target_ctid;
        descriptor[2] = 1;
    }

    coyote::localSg sg = { .addr = buffer, .len = n_interrupts * DESCRIPTOR_SIZE_BYTES };
    issuer.invoke(coyote::CoyoteOper::LOCAL_READ, sg);
    while (!issuer.checkCompleted(coyote::CoyoteOper::LOCAL_READ)) {}
    issuer.clearCompleted();

    // Wait until all interrupts arrived or no further interrupts arrive for IDLE_TIMEOUT
    auto total = [&received]() {
        size_t count = 0;
        for (auto &r : received) { count += r->size(); }
        return count;
    };
    size_t last_count = 0;
    auto last_change = std::chrono::steady_clock::now();
    while (received[target]->size() < n_interrupts && std::chrono::steady_clock::now() - last_change < IDLE_TIMEOUT) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        size_t count = total();
        if (count != last_count) {
            last_count = count;
            last_change = std::chrono::steady_clock::now();
        }
    }
    // Interrupts that are still in flight would otherwise be counted by the next burst
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // Interrupts received by any other cThread were misdelivered
    size_t misdelivered = total() - received[target]->size();

    std::lock_guard<std::mutex> target_lock(received[target]->mtx);
    std::vector<uint32_t> &target_values = received[target]->values;

    // Compare the received values to the expected sequence
    std::set<uint32_t> seen;
    uint32_t duplicates = 0, out_of_order = 0, foreign = 0;
    int64_t previous = -1;
    for (uint32_t value : target_values) {
        if (value >> 16 != encodeValue(target_ctid, burst_id, 0) >> 16) {
            foreign++;
            continue;
        }
        uint32_t index = value & 0xffff;
        if (!seen.insert(index).second) { duplicates++; }
        if ((int64_t) index < previous) { out_of_order++; }
        previous = index;
    }
    std::vector<uint32_t> missing;
    for (uint32_t i = 0; i < n_interrupts; i++) {
        if (!seen.count(i)) { missing.push_back(i); }
    }
    
    bool ok = missing.empty() && !duplicates && !out_of_order && !foreign && !misdelivered;
    std::cout << "  " << n_interrupts << " interrupts to ctid " << target_ctid << ": " << 
        target_values.size() << " received by ctid " << target_ctid << ", " << 
        misdelivered << " received by other cThreads, " << missing.size() << " missing, " << 
        duplicates << " duplicates, " << out_of_order << " out of order, " << foreign << " with a wrong value" << 
        (ok ? "  [OK]" : "  [FAIL]") << std::endl;
    if (!missing.empty()) {
        std::cout << "    missing indices:";
        for (size_t i = 0; i < missing.size() && i < 16; i++) { std::cout << " " << missing[i]; }
        std::cout << (missing.size() > 16 ? " ..." : "") << std::endl;
    }

    return ok;
}

int main(int argc, char *argv[])  { 
    // CLI arguments
    uint32_t n_threads, n_interrupts, n_rounds;
    boost::program_options::options_description runtime_options("Coyote User Interrupts Options");
    runtime_options.add_options()
        ("threads,t", boost::program_options::value<uint32_t>(&n_threads)->default_value(2), "Number of cThreads per round")
        ("interrupts,n", boost::program_options::value<uint32_t>(&n_interrupts)->default_value(128), "Number of back-to-back interrupts per burst")
        ("rounds,r", boost::program_options::value<uint32_t>(&n_rounds)->default_value(4), "Number of rounds, each with new cThreads");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    if (n_threads == 0) {
        std::cerr << "ERROR: at least one cThread is required" << std::endl;
        return EXIT_FAILURE;
    }
    if (n_interrupts == 0 || n_interrupts > 0xffff) {
        std::cerr << "ERROR: the number of interrupts must be between 1 and 65535" << std::endl;
        return EXIT_FAILURE;
    }

    bool all_ok = true;
    uint32_t burst_id = 1;
    for (uint32_t round = 0; round < n_rounds; round++) {
        // Declared before the cThreads, so the callbacks can still write to them until the cThreads are destroyed
        std::vector<std::unique_ptr<ReceivedInterrupts>> received;
        std::vector<std::unique_ptr<coyote::cThread>> coyote_threads;

        // Obtain Coyote threads with interrupt callbacks, which only record the interrupt value
        // The cThreads are destroyed at the end of each round, so the next round obtains the same ctids again
        for (uint32_t t = 0; t < n_threads; t++) {
            received.push_back(std::make_unique<ReceivedInterrupts>());
            ReceivedInterrupts *r = received.back().get();
            coyote_threads.push_back(std::make_unique<coyote::cThread>(DEFAULT_VFPGA_ID, getpid(), 0, [r](int value) {
                std::lock_guard<std::mutex> lock(r->mtx);
                r->values.push_back(value);
            }));
        }
        std::cout << "Round " << round << " (cThreads with ctid";
        for (auto &coyote_thread : coyote_threads) { std::cout << " " << coyote_thread->getCtid(); }
        std::cout << ")" << std::endl;

        int *buffer = (int *) coyote_threads[0]->getMem({coyote::CoyoteAllocType::REG, n_interrupts * DESCRIPTOR_SIZE_BYTES});
        memset(buffer, 0, n_interrupts * DESCRIPTOR_SIZE_BYTES);

        // Every interrupt must reach the cThread it is addressed to, regardless of which cThread issued the transfer
        for (size_t target = 0; target < coyote_threads.size(); target++) {
            all_ok &= runBurst(*coyote_threads[0], buffer, n_interrupts, burst_id++, coyote_threads, received, target);
        }
    }

    std::cout << std::endl << (all_ok ? "All interrupts were delivered correctly" : "Some interrupts were lost or misdelivered") << std::endl;
    return all_ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
