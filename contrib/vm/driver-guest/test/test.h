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

#ifndef __TEST_H__

/* MMAP */
/* MMAP Regions */
#define MMAP_CTRL 0x0
#define MMAP_CNFG 0x1
#define MMAP_CNFG_AVX 0x2
#define MMAP_WB 0x3
#define MMAP_BUFF 0x200
#define MMAP_PR 0x400
#define FPGA_CTRL_SIZE 256 * 1024
#define FPGA_CTRL_OFFS 0x100000
#define FPGA_CTRL_LTLB_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_LTLB_OFFS 0x0
#define FPGA_CTRL_STLB_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_STLB_OFFS 0x10000
#define FPGA_CTRL_USER_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_USER_OFFS 0x20000
#define FPGA_CTRL_CNFG_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_CNFG_OFFS 0x30000
#define FPGA_CTRL_CNFG_AVX_SIZE 256 * 1024
#define FPGA_CTRL_CNFG_AVX_OFFS 0x1000000

/* IOCTL */
#define IOCTL_ALLOC_HOST_USER_MEM _IOW('D', 1, unsigned long) // large pages (no hugepage support)
#define IOCTL_FREE_HOST_USER_MEM _IOW('D', 2, unsigned long)
#define IOCTL_ALLOC_HOST_RECONFIG_MEM _IOW('D', 3, unsigned long) // pr pages
#define IOCTL_FREE_HOST_RECONFIG_MEM _IOW('D', 4, unsigned long)
#define IOCTL_MAP_USER _IOW('D', 5, unsigned long) // map
#define IOCTL_UNMAP_USER _IOW('D', 6, unsigned long)
#define IOCTL_REGISTER_PID _IOW('D', 7, unsigned long) // register pid
#define IOCTL_UNREGISTER_PID _IOW('D', 8, unsigned long)
#define IOCTL_RECONFIG_LOAD _IOW('D', 9, unsigned long) // reconfiguration

#define IOCTL_ARP_LOOKUP _IOW('D', 10, unsigned long)    // arp lookup
#define IOCTL_SET_IP_ADDRESS _IOW('D', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS _IOW('D', 12, unsigned long)
#define IOCTL_WRITE_CTX _IOW('D', 13, unsigned long)     // qp context
#define IOCTL_WRITE_CONN _IOW('D', 14, unsigned long)   // qp connection
#define IOCTL_SET_TCP_OFFS _IOW('D', 15, unsigned long) // tcp mem offsets

#define IOCTL_READ_SHELL_CONFIG _IOR('D', 32, unsigned long)       // status cnfg
#define IOCTL_XDMA_STATS _IOR('D', 33, unsigned long)        // status xdma
#define IOCTL_NET_STATS _IOR('D', 34, unsigned long)        // status network
#define IOCTL_READ_ENG_STATUS _IOR('D', 35, unsigned long) // status engines

#define IOCTL_NET_DROP _IOW('D', 36, unsigned long) // net dropper

#define IOCTL_TEST_INTERRUPT _IO('D', 37)

#define LTLB_PAGE_SHIFT 21
#define LTLB_PAGE_SIZE (1 << 21)

#endif