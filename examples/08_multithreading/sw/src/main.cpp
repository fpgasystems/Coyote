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

#include <string>
#include <fstream>
#include <iostream>

// External library, Boost, for easier parsing of CLI arguments
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cBench.hpp>
#include <coyote/cThread.hpp>

// Constants
#define DEFAULT_VFPGA_ID 0

// Registers, corresponding to the ones in aes_axi_ctrl_parser
#define KEY_LOW_REG     0
#define KEY_HIGH_REG    1
#define IV_LOW_REG      2
#define IV_HIGH_REG     3
#define IV_DEST_REG     4

// 128-bit encryption key
// Partitioned into two 64-bit values, since hardware registers are 64b (8B)
constexpr uint64_t KEY_LOW  = 0x6167717a7a767668;
constexpr uint64_t KEY_HIGH = 0x6a64727366626362;

// 128-bit initialization vector (IV)
// Partitioned into two 64-bit values, since hardware registers are 64b (8B)
constexpr uint64_t IV_LOW  = 0x6162636465666768;
constexpr uint64_t IV_HIGH = 0x3132333435363738;

// Sample text to encrypt, unless the user provides their own
std::string default_path("../src/sample_text.txt");

using sg_pair = std::pair<coyote::localSg, coyote::localSg>;

int main(int argc, char *argv[])  {
    // CLI Arguments
    std::string source_path;
    unsigned int n_runs, n_threads;

    boost::program_options::options_description runtime_options("Coyote Multi-threaded AES Encryption Example Options");
    runtime_options.add_options()
        ("threads,t", boost::program_options::value<unsigned int>(&n_threads)->default_value(1), "How many Coyote threads to use?")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("source_path,s", boost::program_options::value<std::string>(&source_path)->default_value(default_path), "Text file to be encrypted");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    if (n_threads > 4) {
        throw std::runtime_error("The vFPGA is built with 4 host streams; cannot have more threads than streams in this specific example...");
    }

    // Open source file to be encrypted
    FILE *source_file = fopen(source_path.c_str(), "rb");
    if (!source_file) { throw std::runtime_error("Could not open source text; exiting..."); }
    fseek(source_file, 0, SEEK_END);
    uint32_t size = ftell(source_file);

    HEADER("CLI PARAMETERS:");
    std::cout << "Number of Coyote threads: " << n_threads << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Text size: " << size << std::endl;

    // Create multiple Coyote threads, and, for each one of them, allocated destination memory
    // Destination will hold the encrypted text after being processed by the vFPGA
    // The i-th thread uses axis_host_(recv|send)[i] as its data interface
    // Therefore, it makes no sense to have more than N_STRM_AXI threads
    std::vector<std::unique_ptr<coyote::cThread>> coyote_threads;
    std::vector<char *> src_mems, dst_mems;
    std::vector<sg_pair> sg_list;
    for (unsigned int i = 0; i < n_threads; i++) {
        // Note, how all the different Coyote threads point to the same vFPGA, hence multi-threading
        // Multiple software threads but one hardware instance (vFPGA)
        coyote_threads.emplace_back(new coyote::cThread(DEFAULT_VFPGA_ID, getpid()));

        // Allocate source memory and copy file contents into it
        src_mems.emplace_back((char *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, size + 1}));
        fseek(source_file, 0, SEEK_SET);
        if (!fread(src_mems[i], size, 1, source_file)) { throw std::runtime_error("Could not read source text; exiting..."); }
        
        // Allocate destination memory and set it to zero
        dst_mems.emplace_back((char *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, size + 1}));
        memset(dst_mems[i], 0, size + 1);
        if (!dst_mems[i]) { throw std::runtime_error("Could not allocate memory; exiting..."); }

        // Allocate scatter-gather entry for this Coyote thread to do encryption
        // As with Example 1, we will be doing a LOCAL_TRANSFER: CPU MEM => vFPGA (encryption) => CPU MEM
        // Note, how dest is set to i, corresponding to the i-th Coyote thread using the i-th axis_host data interface
        coyote::localSg src_sg = { .addr = src_mems[i], .len = size, .dest = i };
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = size, .dest = i };
        sg_list.emplace_back(std::make_pair(src_sg, dst_sg));
    }
    
    /*
    The vFPGA expects keys for encryption and the initialization vector (IV) to be set
    
    IMPORTANT: In this example, there is only one encryption key and IV in the vFPGA 
    Therefore, all the cThreads have the same key and IV, so it's fine to set it with coyote_thread[0]->setCSR
    In practice, it's possible to add another register, corresponding to the coyote_thread ID, e.g. coyote_thread[i]->setCSR(i, 2)
    And then modify the vFPGA logic to include one key and IV per Coyote thread
    */
    coyote_threads[0]->setCSR(KEY_LOW, KEY_LOW_REG);
    coyote_threads[0]->setCSR(KEY_HIGH, KEY_HIGH_REG);
    coyote_threads[0]->setCSR(IV_LOW, IV_LOW_REG);
    coyote_threads[0]->setCSR(IV_HIGH, IV_HIGH_REG);
    
    auto prep_fn = [&]() {
        // Clear the completion counters for the next iteration of the benchmark
        for (unsigned int i = 0; i < n_threads; i++) {
            coyote_threads[i]->clearCompleted();
        }
    };
    
    auto benchmark_thr = [&]() {
        for (unsigned int i = 0; i < n_threads; i++) {
            /*
            AES CBC is a block sequential algorithm, so encryption is performed on text of fixed length (128b)
            The encryption depends on the current chunk of text and the last encrypted chunk
            That is output[t] = AES(input[t] XOR output[t-1]), for t = 0, output[0] = iv 
            So the IV must be set and used to start the encryption process

            Therefore, an additional register in the vFPGA is used to indicate 
            That the i-th (software) thread / (hardware) stream can now use the above-set IV
            This is necessary to start the encryption (invoked below using LOCAL_TRANSFER)
            */
            coyote_threads[i]->setCSR(static_cast<uint64_t>(i), IV_DEST_REG);
            
            // Start asynchronous transfer for each thread
            // Flow of data is: plain_text from CPU mem => AES CBC in vFPGA => encrypted text stored in CPU mem
            coyote_threads[i]->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_list[i].first, sg_list[i].second);
        }
        
        // Wait until all the Coyote threads are complete
        bool k = false;
        while(!k) {
            k = true;
            for (unsigned int i = 0; i < n_threads; i++) {
                if (coyote_threads[i]->checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != 1) k = false;
            }
        } 
    };

    // Start throughput test
    coyote::cBench bench(n_runs);
    HEADER("MULTI-THREADED AES ECB ENCRYPTION");
    bench.execute(benchmark_thr, prep_fn);
    double throughput = ((double) size * (double) n_threads) / (1024.0 * 1024.0 * 1e-9 * bench.getAvg());
    std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; " << std::endl;
    
    // Since all the Coyote threads operate on the same text and have the same encryption key and IV
    // We can confirm that the encrypted text is the same for all the threads
    for (unsigned int i = 1; i < n_threads; i++) {
        for (size_t s = 0; s < size; s++) {
            assert(dst_mems[0][s] == dst_mems[i][s]);
        }
    }

    // Write encrypted text to a file, to inspect that the file was actually encrypted
    // It will be stored in $(pwd)/encrypted_text.txt
    dst_mems[0][size] = '\0';
    std::ofstream encrypted_file("encyrypted_text.txt", std::ios::binary);
    encrypted_file.write(dst_mems[0], size + 1);
    
    fclose(source_file);
    return EXIT_SUCCESS;
}
