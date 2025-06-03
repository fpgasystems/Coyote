#include <stdio.h>

namespace fpga {

class BinaryOutputReader {
    FILE *fp;

public:
    BinaryOutputReader() {}

    void open(char file_name[]) {
        fp = fopen(file_name, "rb");
    }

    void close() {
        fclose(fp);
    }
};

}