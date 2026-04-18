/**
 * Minimal Coyote host harness for the hls4ml inference example.
 *
 * The current kernel is a placeholder, so this harness focuses on the data
 * movement contract: send one fixed-length sample blob and receive one result
 * word back. The fixed-length blobs are written by
 * scripts/export_calibration_data.py.
 */

#include <fstream>
#include <iomanip>
#include <iostream>
#include <cstring>
#include <vector>

#include <boost/program_options.hpp>

#include <coyote/cThread.hpp>

namespace {
constexpr uint INPUT_BYTES = 1024 * 1024;
constexpr uint RESULT_BYTES = 64;
constexpr int DEFAULT_VFPGA_ID = 0;
}

int main(int argc, char *argv[]) {
    std::string input_path;

    boost::program_options::options_description runtime_options("Coyote hls4ml inference options");
    runtime_options.add_options()
        ("input,i", boost::program_options::value<std::string>(&input_path)->required(), "Path to a fixed-length 1048576-byte sample blob");

    boost::program_options::variables_map args;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), args);
    boost::program_options::notify(args);

    HEADER("Validation: hls4ml inference skeleton");
    std::cout << "Input blob: " << input_path << std::endl;

    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());

    auto *input_mem = reinterpret_cast<unsigned char *>(
        coyote_thread.getMem({coyote::CoyoteAllocType::HPF, INPUT_BYTES})
    );
    auto *output_mem = reinterpret_cast<unsigned char *>(
        coyote_thread.getMem({coyote::CoyoteAllocType::HPF, RESULT_BYTES})
    );
    if (!input_mem || !output_mem) {
        throw std::runtime_error("Could not allocate Coyote buffers.");
    }

    std::fill(input_mem, input_mem + INPUT_BYTES, 0);
    std::fill(output_mem, output_mem + RESULT_BYTES, 0);

    std::ifstream input_file(input_path, std::ios::binary);
    if (!input_file) {
        throw std::runtime_error("Could not open input blob.");
    }
    input_file.read(reinterpret_cast<char *>(input_mem), INPUT_BYTES);
    std::streamsize bytes_read = input_file.gcount();
    if (bytes_read != INPUT_BYTES) {
        std::cerr << "Warning: expected " << INPUT_BYTES << " bytes, read " << bytes_read
                  << ". Remaining bytes stay zero-padded." << std::endl;
    }

    coyote::localSg sg_in = {.addr = input_mem, .len = INPUT_BYTES, .dest = 0};
    coyote::localSg sg_out = {.addr = output_mem, .len = RESULT_BYTES, .dest = 0};

    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ, sg_in);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_out);

    while (
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1 ||
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1
    ) {}

    float logit = 0.0f;
    std::memcpy(&logit, output_mem, sizeof(float));

    std::cout << "Returned logit (LSB of result word): " << std::setprecision(8) << logit << std::endl;
    return 0;
}
