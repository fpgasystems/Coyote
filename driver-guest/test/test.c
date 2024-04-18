#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <x86intrin.h>

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

    int32_t cpid = (int32_t) tmp[1];

    printf("Got cpid %d\n", cpid);

    printf("Trying to map regions\n");

    // Map ctrl
    void * user_ctrl = mmap(NULL, FPGA_CTRL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CTRL << 12);
    if (!user_ctrl)
    {
        printf("Failed to map ctrl region\n");
    }
    else
    {
        printf("Mapped ctrl region\n");
        *((uint64_t *) user_ctrl) = 0;
        printf("Wrote test to user ctrl\n");
        ret_val = munmap(user_ctrl, FPGA_CTRL_SIZE);
        if (ret_val)
        {
            printf("Failed to unmap with code %d\n", ret_val);
        }
        else
        {
            printf("Unmapped ctrl region\n");
        }
    }

    // map cnfg
    void * user_cnfg = mmap(NULL, FPGA_CTRL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG << 12);
    if (!user_cnfg)
    {
        printf("Failed to map ctrl region\n");
    }
    else
    {
        printf("Mapped user cnfg\n");
        *((uint64_t *) user_cnfg) = 0;
        printf("Wrote test to user cnfg\n");
        ret_val = munmap(user_cnfg, FPGA_CTRL_SIZE);
        if (ret_val)
        {
            printf("Failed to unmap with code %d\n", ret_val);
        }
        else
        {
            printf("Unmapped user confg\n");
        }
    }

    // map avx cnfg
    void * user_cnfg_avx = mmap(NULL, FPGA_CTRL_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG_AVX << 12);
    if (!user_cnfg_avx)
    {
        printf("Failed to map ctrl region\n");
    }
    else
    {
        printf("Mapped cnfg avx\n");
        *((__m256i *) user_cnfg_avx) = _mm256_set_epi64x(0,0,0,0);
        printf("Wrote test to cnfg avx\n");
        ret_val = munmap(user_cnfg_avx, FPGA_CTRL_SIZE);
        if (ret_val)
        {
            printf("Failed to unmap with code %d\n", ret_val);
        }
        else
        {
            printf("Unmapped user cnfg\n");
        }
    }

    // Test get config
    ret_val = ioctl(fd, IOCTL_READ_CNFG, tmp);
    if (ret_val)
    {
        printf("Failed to read config!\n");
    }
    else
    {
        printf("Config is 0x%lx\n", tmp[0]);
        if (tmp[0] != 0xdeadbeef)
        {
            printf("WARNING: Config value differs from test value. Ignore this if running on actual hardware\n");
        }
    }

    // TODO: extend this to more test cases
    // map 4 pages
    size_t len = 1*(1 << 12);
    // void *buffer = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
    void *buffer = malloc(len);
    if (!buffer)
    {
        printf("Failed to allocate buffer\n");
        goto err_cpid;
    }
    tmp[0] = (uint64_t) buffer;
    tmp[1] = len;
    tmp[2] = cpid;

    ret_val = ioctl(fd, IOCTL_MAP_USER, tmp);
    if (ret_val)
    {
        printf("Failed to allocate with code %d\n", ret_val);
        goto err_map;
    }

    printf("Mapped user buffer for fpga use\n");

    tmp[0] = (uint64_t) buffer;
    tmp[1] = cpid;
    ret_val = ioctl(fd, IOCTL_UNMAP_USER, tmp);
    if (ret_val)
    {
        printf("Failed to unmap with code %d\n", ret_val);
    }
    else
    {
        printf("Unmapped user buffer successfully\n");
    }
    


err_map:
    munmap(buffer, len);
err_cpid:
    tmp[0] = cpid;
    ret_val = ioctl(fd, IOCTL_UNREGISTER_PID, tmp);
    if (ret_val)
    {
        printf("Failed to unreguster cpid\n");
        goto err;
    }

    printf("Unregistered cpid %d\n", cpid);
    
err:
    printf("Closing device file %d\n", fd);
    close(fd);
    return ret_val;
}