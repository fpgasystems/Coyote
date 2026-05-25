#ifndef HOST_LIBS_HPP_
#define HOST_LIBS_HPP_

#include <vector>
#include <cstdint>
#include "cOps.hpp"
#include "cThread.hpp"

#define DEFAULT_VFPGA_ID 0

class CoyoteInference {
public:
    CoyoteInference(unsigned int batch_size, unsigned int in_size, unsigned int out_size);
    CoyoteInference(unsigned int batch_size, unsigned int max_input_bytes, unsigned int out_size, bool raw_input_mode);
    ~CoyoteInference();

    void flush();
    void predict();
    void set_data(float *x, unsigned int i);
    void set_raw_data(const uint8_t *x, unsigned int raw_len, unsigned int i);
    float* get_predictions(unsigned int i);

private:
    unsigned int batch_size, in_size, out_size;
    bool raw_input_mode = false;
    static constexpr unsigned int RAW_HEADER_BYTES = 64;
    coyote::cThread coyote_thread;
    std::vector<coyote::localSg> src_sgs, dst_sgs;
    std::vector<float*> src_mems, dst_mems;
    std::vector<uint8_t*> raw_src_mems;
};

#endif
