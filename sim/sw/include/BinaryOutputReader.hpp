#include <stdio.h>

#include "Common.hpp"

namespace fpga {

class BinaryOutputReader {
    FILE *fp;

public:
    BinaryOutputReader() {}

    int open(const char *file_name) {
        fp = fopen(file_name, "rb");
        if (fp < 0) {
            LOG << "BinaryOutputReader: Error: Unable to open output named pipe";
            return -1;
        }
        return 0;
    }

    int read() {
        return 0; // TODO: Implement
    }

    uint64_t getCSRResult() {
        return 0; // TODO: Implement
    }

    uint32_t checkCompletedResult() {
        return 0; // TODO: Implement
    }

    void registerIRQ(void (*uisr)(int)) {
        // TODO: Implement
    }

    void close() {
        fclose(fp);
    }
};

}