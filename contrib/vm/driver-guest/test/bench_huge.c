#include "test.h"
#include <immintrin.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <sys/mman.h>
#include <sys/ioctl.h>

static const char *filename = "/dev/coyote-dev-0";
static const int remote_pages = 16;
static const size_t native_size = remote_pages*(1 << 21);
static const uint64_t iterations = 10;

void test_native_lat(int fd, int cpid, uint64_t iterations)
{
    if (iterations * 8 >= native_size)
    {
        printf("Aborted %s, too many iterations for chosen pages\n", __func__);
        return;
    }

    int ret_val = 0;
    uint64_t tmp[64];
    size_t len = native_size;
    volatile uint64_t *buffer = malloc(len);
    uint64_t *data = calloc(1, len);

    tmp[0] = (uint64_t)buffer;
    tmp[1] = len;
    tmp[2] = cpid;

    ret_val = ioctl(fd, IOCTL_MAP_USER, tmp);
    if (ret_val)
    {
        printf("Failed to map user buffer: %d\n", ret_val);
        return;
    }

    printf("--- NATIVE BENCHMARKS ---\n");
    uint64_t start = _rdtsc();
    for (uint64_t i = 0; i < iterations; i++)
    {
        memcpy((void *) buffer, data, len);
    }
    uint64_t end = _rdtsc();
    printf("Average write latency of %lu runs: %lu\n", iterations, (end - start) * 8 / (iterations * len));

    start = _rdtsc();
    for (uint64_t i = 0; i < iterations; i++)
    {
        memcpy(data, (void *) buffer, len);
    }
    end = _rdtsc();
    printf("Average read latency of %lu runs: %lu\n", iterations, (end - start) * 8 / (iterations * len));

    tmp[0] = (uint64_t)buffer;
    tmp[1] = cpid;
    ret_val = ioctl(fd, IOCTL_UNMAP_USER, tmp);
    if (ret_val)
    {
        printf("Failed to unmap buffer!\n");
    }

    free((void *) buffer);
    free((void *) data);
}

void test_legacy_lat(int fd, int cpid, uint64_t iterations)
{
    uint64_t tmp[64];
    int ret_val;

    if (iterations * 8 >= remote_pages * LTLB_PAGE_SIZE)
    {
        printf("Aborted %s, too many iterations for chosen pages\n", __func__);
    }

    tmp[0] = remote_pages;
    tmp[1] = cpid;

    ret_val = ioctl(fd, IOCTL_ALLOC_HOST_USER_MEM, tmp);
    if (ret_val)
    {
        printf("failed to allocate memory\n");
        return;
    }

    uint64_t *buff = mmap(NULL, (remote_pages + 1) * LTLB_PAGE_SIZE, PROT_READ | PROT_WRITE,
                          MAP_SHARED, fd, MMAP_BUFF << 12);
    if (buff == (void *)(-1))
    {
        printf("failed to map memory\n");
        return;
    }
    void *buff_old = buff;
    buff = (uint64_t *)((((uint64_t)buff + LTLB_PAGE_SIZE - 1) >> LTLB_PAGE_SHIFT) << LTLB_PAGE_SHIFT);

    printf("--- LEGACY BENCHMARKS ---\n");

    uint64_t start = _rdtsc();
    for (uint64_t i = 0; i < iterations; i++)
    {
        *(buff + i) = i;
    }
    uint64_t end = _rdtsc();
    printf("Average write latency of %lu runs: %lu\n", iterations, (end - start) / iterations);

    start = _rdtsc();
    for (uint64_t i = 0; i < iterations; i++)
    {
        uint64_t val = *(buff + i);
    }
    end = _rdtsc();
    printf("Average read latency of %lu runs: %lu\n", iterations, (end - start) / iterations);

    munmap(buff_old, (remote_pages + 1) * LTLB_PAGE_SIZE);

    tmp[0] = (uint64_t) buff;
    tmp[1] = cpid;
    ret_val = ioctl(fd, IOCTL_FREE_HOST_USER_MEM, tmp);
    if (ret_val)
    {
        printf("Failed to free buffer\n");
    }

    return;
}

int main()
{
    int fd = open(filename, O_RDWR);
    uint64_t tmp[64];
    int ret_val = 0;

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
    printf("registered with cpid %d, running benchmarks...\n", cpid);

    test_native_lat(fd, cpid, iterations);
    test_legacy_lat(fd, cpid, iterations);

    tmp[0] = cpid;
    ret_val = ioctl(fd, IOCTL_UNREGISTER_PID, tmp);
err:
    close(fd);
    return ret_val;
}