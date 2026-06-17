#include "host_libs.hpp"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fcntl.h>
#include <cstring>
#include <string>
#include <unistd.h>

static unsigned int detect_coyote_device() {
    if (const char *env = std::getenv("COYOTE_DEVICE_ID")) {
        return static_cast<unsigned int>(std::strtoul(env, nullptr, 10));
    }
    for (unsigned int attempt = 0; attempt < 40; ++attempt) {
        for (int dev = 255; dev >= 0; --dev) {
            std::string path = "/dev/coyote_fpga_" + std::to_string(dev) + "_v0";
            int fd = open(path.c_str(), O_RDWR | O_SYNC);
            if (fd >= 0) {
                close(fd);
                return static_cast<unsigned int>(dev);
            }
        }
        usleep(250000);
    }
    return 0;
}

static coyote::CoyoteAllocType coyote_alloc_type() {
    if (const char *env = std::getenv("COYOTE_ALLOC_TYPE")) {
        std::string value(env);
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return std::toupper(c); });
        if (value == "REG") {
            return coyote::CoyoteAllocType::REG;
        }
        if (value == "THP") {
            return coyote::CoyoteAllocType::THP;
        }
        if (value == "HPF") {
            return coyote::CoyoteAllocType::HPF;
        }
        throw std::runtime_error("COYOTE_ALLOC_TYPE must be one of REG, THP, or HPF");
    }
    return coyote::CoyoteAllocType::HPF;
}

CoyoteInference::CoyoteInference(unsigned int batch_size, unsigned int in_size, unsigned int out_size): 
    batch_size(batch_size), in_size(in_size), out_size(out_size), 
    coyote_thread(DEFAULT_VFPGA_ID, getpid(), detect_coyote_device()) 
{
    const auto alloc_type = coyote_alloc_type();
    for (unsigned int i = 0; i < batch_size; i++) {
        src_mems.emplace_back((float *) coyote_thread.getMem({alloc_type, (uint) (in_size * sizeof(float))}));
        dst_mems.emplace_back((float *) coyote_thread.getMem({alloc_type, (uint) (out_size * sizeof(float))}));
        if (!src_mems[i] || !dst_mems[i]) { throw std::runtime_error("Could not allocate memory; exiting..."); }

        coyote::localSg src_sg = { .addr = src_mems[i], .len = (uint) (in_size * sizeof(float))};
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = (uint) (out_size * sizeof(float))};
        src_sgs.emplace_back(src_sg);
        dst_sgs.emplace_back(dst_sg);
    }
}

CoyoteInference::CoyoteInference(unsigned int batch_size, unsigned int max_input_bytes, unsigned int out_size, bool raw_input_mode):
    batch_size(batch_size), in_size(max_input_bytes), out_size(out_size), raw_input_mode(raw_input_mode),
    coyote_thread(DEFAULT_VFPGA_ID, getpid(), detect_coyote_device())
{
    if (!raw_input_mode) { throw std::runtime_error("raw constructor requires raw_input_mode=true"); }
    const auto alloc_type = coyote_alloc_type();
    for (unsigned int i = 0; i < batch_size; i++) {
        raw_src_mems.emplace_back((uint8_t *) coyote_thread.getMem({alloc_type, (uint) (RAW_HEADER_BYTES + max_input_bytes)}));
        dst_mems.emplace_back((float *) coyote_thread.getMem({alloc_type, (uint) (out_size * sizeof(float))}));
        if (!raw_src_mems[i] || !dst_mems[i]) { throw std::runtime_error("Could not allocate memory; exiting..."); }

        coyote::localSg src_sg = { .addr = raw_src_mems[i], .len = RAW_HEADER_BYTES };
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = (uint) (out_size * sizeof(float))};
        src_sgs.emplace_back(src_sg);
        dst_sgs.emplace_back(dst_sg);
    }
}

CoyoteInference::~CoyoteInference() {}

void CoyoteInference::flush() {
    for (unsigned int i = 0; i < batch_size; i++) {
        memset(dst_mems[i], 0, out_size * sizeof(float));
    }
    coyote_thread.clearCompleted(); 
}

void CoyoteInference::predict() {
    for (int i = 0 ; i < batch_size; i++) {
        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sgs[i], dst_sgs[i]);
    }
    while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != batch_size) {}
}

void CoyoteInference::set_data(float *x, unsigned int i) { 
    for (int j = 0; j < in_size; j++) { 
        src_mems[i][j] = x[j]; 
    } 
}

void CoyoteInference::set_raw_data(const uint8_t *x, unsigned int raw_len, unsigned int i) {
    if (!raw_input_mode) { throw std::runtime_error("set_raw_data called on non-raw CoyoteInference"); }
    if (i >= batch_size) { throw std::runtime_error("raw batch index out of range"); }
    if (raw_len > in_size) { throw std::runtime_error("raw input is larger than allocated max_input_bytes"); }

    uint8_t *dst = raw_src_mems[i];
    memset(dst, 0, RAW_HEADER_BYTES);
    uint64_t raw_len_64 = raw_len;
    for (unsigned int b = 0; b < 8; b++) {
        dst[b] = (raw_len_64 >> (8 * b)) & 0xff;
    }
    if (raw_len > 0) {
        memcpy(dst + RAW_HEADER_BYTES, x, raw_len);
    }
    src_sgs[i].addr = raw_src_mems[i];
    src_sgs[i].len = RAW_HEADER_BYTES + raw_len;
}

float* CoyoteInference::get_predictions(unsigned int i) { return dst_mems[i]; }

extern "C" {
    CoyoteInference* init_model_inference(unsigned int batch_size, unsigned int in_size, unsigned int out_size) {
        return new CoyoteInference(batch_size, in_size, out_size);
    }

    CoyoteInference* init_model_inference_raw(unsigned int batch_size, unsigned int max_input_bytes, unsigned int out_size) {
        return new CoyoteInference(batch_size, max_input_bytes, out_size, true);
    }

    void free_model_inference(CoyoteInference* obj) {
        delete obj;
    }

    void flush(CoyoteInference* obj) {
        obj->flush();
    }

    void predict(CoyoteInference* obj) {
        obj->predict();
    }

    void set_inference_data(CoyoteInference* obj, float *x, unsigned int i) {
        obj->set_data(x, i);
    }

    void set_inference_raw_data(CoyoteInference* obj, uint8_t *x, unsigned int raw_len, unsigned int i) {
        obj->set_raw_data(x, raw_len, i);
    }

    float* get_inference_predictions(CoyoteInference* obj, unsigned int i) {
        return obj->get_predictions(i);
    }
}
