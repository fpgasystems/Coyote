#include "cTask.hpp"

namespace coyote {

cTask::cTask(int32_t tid, int32_t fid, size_t ret_val_size, cThread* cthread, std::vector<std::vector<char>> fn_args) 
    : tid(tid), fid(fid), is_completed(false), ret_val_size(ret_val_size), cthread(cthread), fn_args(std::move(fn_args)), ret_code(-1) {}

int32_t cTask::getTid() const {
    return tid;
}

int32_t cTask::getFid() const {
    return fid;
}

bool cTask::isCompleted() const {
    return is_completed;
}

void cTask::setCompleted(bool val) {
    is_completed = val;
}

cThread* cTask::getCThread() const {
    return cthread;
}

std::vector<std::vector<char>> cTask::getArgs() const {
    return fn_args;
}

std::vector<char> cTask::getRetVal() const {
    return ret_val;
}

void cTask::setRetVal(const std::vector<char> retval) {
    ret_val = retval;
}

size_t cTask::getRetValSize() const {
    return ret_val_size;
}

int32_t cTask::getRetCode() const {
    return ret_code;
}

void cTask::setRetCode(int32_t retcode) {
    ret_code = retcode;
}

}
