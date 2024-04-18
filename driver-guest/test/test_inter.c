#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>

#include <sys/mman.h>
#include <sys/ioctl.h>

#include "test.h"

static const char *filename = "/dev/fpga0";

int main()
{
    int ret_val = 0;
    printf("Opening device %s\n", filename);
    uint64_t tmp[64];

    int fd = open(filename, O_RDWR);
    if (fd < 0)
    {
        printf("Failed to open device file\n");
        return -1;
    }

    pid_t pid = getpid();
    tmp[0] = pid;
    ret_val = ioctl(fd, IOCTL_REGISTER_PID, tmp);
    if (ret_val)
    {
        printf("Failed to register pid\n");
        goto err;
    }

    int32_t cpid = (int32_t)tmp[1];

    printf("Got cpid %d\n", cpid);

    ret_val = ioctl(fd, IOCTL_TEST_INTERRUPT);
    if (ret_val)
    {
        printf("Failed to trigger interrupt\n");
    }

    tmp[0] = cpid;
    ret_val = ioctl(fd, IOCTL_UNREGISTER_PID, tmp);
    if (ret_val)
    {
        printf("Failed to unreguster cpid\n");
        goto err;
    }

    printf("Unregistered cpid %d\n", cpid);

err:
    return ret_val;
}