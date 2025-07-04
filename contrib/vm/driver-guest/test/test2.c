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

#include "test.h"

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>

#include <sys/mman.h>
#include <sys/ioctl.h>

static const char *filename = "/dev/fpga0";

int main()
{
    uint64_t tmp[64];
    int ret_val = 0;
    int fd = open(filename, O_RDWR);
    if (fd < 0)
    {
        printf("Failed to open file\n");
        return -1;
    }

    pid_t pid = getpid();
    tmp[0] = pid;
    ret_val = ioctl(fd, IOCTL_REGISTER_PID, tmp);
    if (ret_val)
    {
        printf("Failed to register pid with code %d\n", ret_val);
        goto err;
    }

    int cpid = tmp[1];
    tmp[0] = 1;
    tmp[1] = cpid;
    ret_val = ioctl(fd, IOCTL_ALLOC_HOST_USER_MEM, tmp);
    if (ret_val)
    {
        printf("failed to allocate memory with code %d\n", ret_val);
        goto err;
    }
    uint64_t *m = mmap(NULL, (tmp[0] + 1) * (1 << 21), PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_BUFF << 12);
    if (m == (void *)(-1))
    {
        printf("Failed ot mmap\n");
        goto err;
    }
    void *m_old = m;
    m = (uint64_t *)((((uint64_t)m + LTLB_PAGE_SIZE - 1) >> LTLB_PAGE_SHIFT) << LTLB_PAGE_SHIFT);

    printf("Mapped region @%p of size %lu\n", m, (uint64_t)2 * (1 << 21));
    
    // test if read and writes work as expected
    for (int i = 0; i < 1000; i++)
    {
        // printf("Iteration %d\n", i);
        *(m + i) = i;
        if (*(m + i) != i)
        {
            printf("ERROR: read does not return written data!\n");
        }
    }

    printf("Done with test\n");

    munmap(m_old, (tmp[0] + 1) * (1 << 21));

err:
    close(fd);
    return ret_val;
}