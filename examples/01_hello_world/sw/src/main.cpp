#include <string>
#include <vector>
#include <cstring>
#include <cassert>
#include <sstream>
#include <fstream>
#include <iostream>
#include <algorithm>

// Coyote-specific includes
#include "cThread.hpp"

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

// Function to reverse the endianess of a hex string
std::string reverseEndianess(const std::string& hex_str) {
    std::string reversed;
    for (size_t i = 0; i < hex_str.size(); i += 2) {
        reversed.insert(0, hex_str.substr(i, 2));
    }
    return reversed;
}

/** @brief Parse data file
 *
 * @param file_path Path to the data file
 * @param coyote_thread Coyote thread used to allocate memory
 * @param data_in Vector to store parsed data buffers
 *
 * The vector is a list of pairs; each pair contains a pointer to a char buffer
 * and its size. Currently, the data in each char* is stored as follows:
 * - After each NoP, a new char buffer is started
 * - The char buffer is assumed complete once a TLAST of 1 is encountered (i.e. next NoP occurs)
 * - The char buffer is populated with the TDATA values, by reversing the endianess and converting 2 hex
 *   'characters' into 1 byte.
 *
 * For example, three data lines (with TLAST values of 0, 0, and 1) would result in a single char buffer
 * with size 3 * (TDATA size / 2) = 96 bytes.
 *
 * @note NoP lines are ignored, as Coyote doesn't support such operations.
 */
void parseDataFile(const std::string& file_path, coyote::cThread& coyote_thread, std::vector<std::pair<char*, size_t>>& data_in) {
    std::ifstream data_file(file_path);
    if (!data_file.is_open()) {
        throw std::runtime_error("Failed to open data file: " + file_path);
    }

    std::string line;
    std::vector<std::string> current_buffer;

    while (std::getline(data_file, line)) {
        if (line.empty()) continue;

        // Ignore NoP lines, as Coyote doesn't support such operations
        // NOTE: Checking for NoPs could probably be done in a better way,
        // by also checking the following line (as NoPs are always pairs of lines)
        // But, assuming the data file is well-formed for now, this should suffice
        if (line.size() == 4) {
            continue; 
        }

        // Extract TLAST and TDATA
        char tlast = line[0];
        std::string tdata = line.substr(1);

        // Reverse endianess of TDATA
        std::string reversedData = reverseEndianess(tdata);

        // Add the reversed data to the current buffer
        current_buffer.push_back(reversedData);

        // If TLAST is 1, finalize the current buffer
        if (tlast == '1') {
            // Concatenate the current buffer into a single string
            std::ostringstream oss;
            for (const auto& part : current_buffer) {
                oss << part;
            }
            std::string concatenated = oss.str();

            // Convert hex string to char buffer
            // 2 hex characters = 1 byte (char); hence, divide size by 2
            size_t char_buff_size = concatenated.size() / 2;

            // Allocate memory for the char buffer
            // Note, Coyote's getMem function will also populate the TLB for
            // this buffer. Under the hood, it uses alligned_alloc (normal malloc
            // doesn't guarantee alignment needed for DMA operations).
            char* char_buff;
            if (char_buff_size > 32768) {
                // To balance between large and small TLB usage, allocate larger buffers with hugepages
                // Note, the threshold of 32 kB is somewhat arbitrary
                char_buff = (char *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, (uint32_t) char_buff_size });
            }  else {
                char_buff = (char *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, (uint32_t) char_buff_size });
            }
            if (!char_buff) { throw std::runtime_error("Could not allocate memory for data buffer, exiting..."); }

            // Convert each two hex characters to a byte
            for (size_t i = 0; i < char_buff_size; i++) {
                std::string byte_str = concatenated.substr(i * 2, 2);
                char_buff[i] = static_cast<char>(std::stoi(byte_str, nullptr, 16));
            }

            // Store the buffer and start processing next buffer
            data_in.emplace_back(char_buff, char_buff_size);
            current_buffer.clear();
        }
    }

    data_file.close();
}

/** @brief Parse meta file
 *
 * @param file_path Path to the data file
 * @param coyote_thread Coyote thread used to allocate memory
 * @param meta_in Vector to store parsed meta buffers
 *
 * @note NoP lines are ignored, as Coyote doesn't support such operations.
 *
 * @note Currently, each line in the meta file is parsed into a separate buffer.
 * This approach is potentially wasteful, as we store one TLB entry per buffer,
 * but TLB entries are suited for a page (4 KiB). Optimization could be made to 
 * group multiple meta lines into a single buffer and zero-pad it to 64 B ~ 512 b.
 */
void parseMetaFile(const std::string& file_path, coyote::cThread& coyote_thread, std::vector<std::pair<char*, size_t>>& meta_in) {
    std::ifstream meta_file(file_path);
    if (!meta_file.is_open()) {
        throw std::runtime_error("Failed to open metadata file: " + file_path);
    }

    std::string line;
    while (std::getline(meta_file, line)) {
        if (line.empty()) continue;

        // Ignore NoP lines, as Coyote doesn't support such operations
        // NOTE: Checking for NoPs could probably be done in a better way,
        // by also checking the following line (as NoPs are always pairs of lines)
        // But, assuming the data file is well-formed for now, this should suffice
        if (line.size() == 4) {
            continue; 
        }

        // Parse metadata line
        std::string tdata = reverseEndianess(line);

        // Sanity check: metadata TDATA should always be 22 hex characters (88 bits)
        // std::cout << "TDATA size: " << tdata.size() << "\n";
        assert(tdata.size() == 22); 

        // Allocate memory for the line; which also populate the TLB for this buffer
        size_t char_buff_size = tdata.size() / 2;
        char* char_buff = (char *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, (uint32_t) char_buff_size });
        if (!char_buff) { throw std::runtime_error("Could not allocate memory for meta buffer, exiting..."); }

        // Convert each two hex characters to a byte
        std::cout << std::endl;
        for (size_t i = 0; i < char_buff_size; i++) {
            std::string byte_str = tdata.substr(i * 2, 2);
            std::cout << byte_str << " ";
            char_buff[i] = static_cast<char>(std::stoi(byte_str, nullptr, 16));
        }

        meta_in.emplace_back(char_buff, char_buff_size);

    }

    meta_file.close();
}

<<<<<<< HEAD
int main(int argc, char *argv[])  {
    // Run-time options; for more details see the description below
    bool hugepages, mapped, stream;
    unsigned int min_size, max_size, n_runs;

    // Parse CLI arguments using Boost, an external library, providing easy parsing of run-time parameters
    // We can easily set the variable type, the variable used for storing the parameter and default values
    boost::program_options::options_description runtime_options("Coyote Hello World Example");
    runtime_options.add_options()
        ("hugepages,h", boost::program_options::value<bool>(&hugepages)->default_value(true), "Use hugepages")
        ("mapped,m", boost::program_options::value<bool>(&mapped)->default_value(true), "Use mapped memory (see README for more details)")
        ("stream,s", boost::program_options::value<bool>(&stream)->default_value(1), "Source / destination data stream: HOST(1) or FPGA(0)")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size [B]")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(4 * 1024 * 1024), "Ending (maximum) transfer size [B]");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI PARAMETERS:");
    std::cout << "Enable hugepages: " << hugepages << std::endl;
    std::cout << "Enable mapped pages: " << mapped << std::endl;
    std::cout << "Data stream: " << (stream ? "HOST" : "CARD") << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    // Obtain a Coyote thread
=======
int main() {
    const std::string data_file_path = "multes-example-input-data.txt";
    const std::string meta_file_path = "multes-example-input-meta.txt";

    // Create a Coyote thread
>>>>>>> origin/master
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());

    // Process the data file
    std::vector<std::pair<char*, size_t>> data_in;
    parseDataFile(data_file_path, coyote_thread, data_in);

    // Process the metadata file
    std::vector<std::pair<char*, size_t>> meta_in;
    parseMetaFile(meta_file_path, coyote_thread, meta_in);

    std::cout << "Parsed " << data_in.size() << " data buffers and " 
              << meta_in.size() << " meta buffers." << std::endl;

    
    // Allocate output meta and data buffers 
    std::vector<std::pair<char*, size_t>> meta_out, data_out;

    // Send the metadata; each operation is an asynchronous LOCAL_TRANSFER, i.e.
    // flow of data is host -> vFPGA -> host
    for (const auto& meta_in_pair : meta_in) {
        char* in_ptr = meta_in_pair.first;
        size_t in_size = meta_in_pair.second;  

        // TODO: What's the output size? For now, assuming same as input
        size_t out_size = in_size;

        // Allocate buffer for output metadata
        char* out_ptr = (char *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, (uint32_t) out_size });
        if (!out_ptr) { throw std::runtime_error("Could not allocate memory for output meta buffer, exiting..."); }

        // Store output meta buffer for later use
        meta_out.emplace_back(out_ptr, out_size);

        // dest is one, since the target AXI Stream in the vFPGA is stream 1
        coyote::localSg sg_src = {.addr = in_ptr, .len = (uint32_t) in_size, .dest = 1};
        coyote::localSg sg_dst = {.addr = out_ptr, .len = (uint32_t) out_size, .dest = 1};

        // Start async LOCAL_TRANSFER operation, setting last to true
        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_src, sg_dst, true);
    }

    // Repeat the same for data buffers (.dest = 0)
    for (const auto& data_in_pair : data_in) {
        char* in_ptr = data_in_pair.first;
        size_t in_size = data_in_pair.second;  

        // TODO: What's the output size? For now, assuming same as input
        size_t out_size = in_size;

        // Allocate buffer for output metadata
        char* out_ptr;
        if (out_size > 32768) {
            out_ptr = (char *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, (uint32_t) out_size });
        }  else {
            out_ptr = (char *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, (uint32_t) out_size });
        }
        if (!out_ptr) { throw std::runtime_error("Could not allocate memory for output data buffer, exiting..."); }
        
        // Store output data buffer for later use
        data_out.emplace_back(out_ptr, out_size);

        // dest is zero, since the target AXI Stream in the vFPGA is stream 0
        coyote::localSg sg_src = {.addr = in_ptr, .len = (uint32_t) in_size, .dest = 0};
        coyote::localSg sg_dst = {.addr = out_ptr, .len = (uint32_t) out_size, .dest = 0};

        // Start async LOCAL_TRANSFER operation
        // Since each of the buffers was ended with the line that contains TLAST = 1,
        // set tlast to true here which will assert the singal for the last data beat
        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_src, sg_dst, true);
    }

    // Poll on completions
    while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != (meta_in.size() + data_in.size())) {
        std::this_thread::sleep_for(std::chrono::nanoseconds(50 * 1000));
    }

    std::cout << "All transfers completed." << std::endl;

    // Any additional processing of the output data can be done here

    // NOTE: No need to free the allocated memory, as cThread's destructor will take care of this

    return EXIT_SUCCESS;
}
