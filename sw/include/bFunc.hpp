#ifndef _COYOTE_BFUNC_HPP_
#define _COYOTE_BFUNC_HPP_

#include <string>
#include <vector>

#include "cThread.hpp"

namespace coyote {

/**
 * @brief Base user function
 *
 * This class should not be used directly; instead it is be inherited in the cFunc class,
 * which defines the arbitrary user functions and the corresponding bitstreams.
 * Therefore this class is fully abstract and all the functions are pure virtual.
 * Additionally, since it is a fully abstract class, there is no corresponding .cpp file.
 *
 * The only reason this class exists is because the cFunc class has a variadic
 * template, making it difficult to include in other classes. For example,
 * the cService class keeps a map of functions added to the Coyote background service, and,
 * since each function is user-defined, it can have different templates and arguments. 
 */
class bFunc {

public:
    virtual ~bFunc() {}

    virtual std::vector<char> run(cThread* coyote_thread, const std::vector<std::vector<char>>& args) = 0;

    virtual int32_t getFid() const = 0;

    virtual std::string getBitstreamPath() const = 0;

    virtual std::pair<void*, uint32_t> getBitstreamPointer() const = 0;

    virtual void setBitstreamPointer(std::pair<void*, uint32_t> bitstream_pointer) = 0;
    
    virtual std::vector<size_t> getArgumentSizes() const = 0;
    
    virtual size_t getReturnSize() const = 0;
};

}

#endif // _COYOTE_BFUNC_HPP_
