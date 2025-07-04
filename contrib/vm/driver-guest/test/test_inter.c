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