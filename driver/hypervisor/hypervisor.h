/**
 * Copyright (c) 2023, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef __HYPERVISOR_H__
#define __HYPERVISOR_H__

#include "../coyote_dev.h"
#include <linux/eventfd.h>

// #define HYPERVISOR_TEST

#define NUM_INTERRUPTS 1
#define MAX_VMS 16

#define COYOTE_HYPERVISOR_CONFIG_SIZE 0x100
#define COYOTE_HYPERVISOR_BAR0_SIZE ((uint64_t)FPGA_CTRL_SIZE)
#define COYOTE_HYPERVISOR_BAR2_SIZE ((uint64_t)0x4000)
#define COYOTE_HYPERVISOR_BAR4_SIZE ((uint64_t)FPGA_CTRL_CNFG_AVX_SIZE)
#define COYOTE_HYPERVISOR_BAR0_MASK ~(COYOTE_HYPERVISOR_BAR0_SIZE - 1)
#define COYOTE_HYPERVISOR_BAR2_MASK ~(COYOTE_HYPERVISOR_BAR2_SIZE - 1)
#define COYOTE_HYPERVISOR_BAR4_MASK ~(COYOTE_HYPERVISOR_BAR4_SIZE - 1)
#define COYOTE_HYPERVISOR_PCI_MASK(__size) (~(__size - 1))

#define BAR0_INDEX_SHIFT 16

#define COYOTE_REGION_OFFSET 32
#define COYOTE_GET_INDEX(__addr) (__addr >> COYOTE_REGION_OFFSET)
#define COYOTE_INDEX_TO_ADDR(__index) (__index << COYOTE_REGION_OFFSET);
#define HYPERVISOR_OFFSET_MASK (((uint64_t)1 << COYOTE_REGION_OFFSET) - 1)

/* Offsets into BAR2 */
#define REGISTER_PID_OFFSET 0x00
#define UNREGISTER_PID_OFFSET 0x08
#define MAP_USER_OFFSET 0x10
#define UNMAP_USER_OFFSET 0x18
#define READ_CNFG_OFFSET 0x20
#define PUT_ALL_USER_PAGES 0x28
#define TEST_INTERRUPT_OFFSET 0x30

#define INVALID_CPID 0xffffffffffffffff

#define HYPERVISOR_HASH_TABLE_ORDER 8
#define HASH_TABLE_BUCKETS (1 << HYPERVISOR_HASH_TABLE_ORDER)

#define MAX_USER_BUF_SHIFT 27
#define MAX_USER_BUF_SIZE (1 << MAX_USER_BUF_SHIFT)

#define LARGE_TABLE_SHIFT 21
#define LARGE_TABLE_SIZE (1 << 21)

#define MSIX_OFFSET 0x40
#define MSIX_SIZE sizeof(struct msix_cap_header)

/* PCI-Capability header */
struct cap_header
{
    uint8_t cap_id;
    uint8_t next_pointer;
} __packed;

/* MSI-X header*/
struct msix_cap_header
{
    uint8_t cap_id;
    uint8_t next_pointer;
    uint16_t message_control;
    uint32_t table_offset;
    uint32_t pba_offset;
    uint32_t mua;
} __packed;

// struct to manage information about a single entry of an interrupt vector
struct msix_interrupt
{
    int eventfd;
    struct eventfd_ctx * ctx;
    int masked;
};

/* PCI config header */
struct pci_config_space
{
    uint16_t vendor_id;            // 0x00 RO
    uint16_t device_id;            // 0x02 RO
    uint16_t command;              // 0x04
    uint16_t status;               // 0x06
    uint8_t revison_id;            // 0x08 RO
    uint8_t programming_interface; // 0x09
    uint8_t subclass;              // 0x0a
    uint8_t class_code;            // 0x0b RO
    uint8_t cache_line_size;       // 0x0c
    uint8_t lat_time;              // 0x0d
    uint8_t header_typer;          // 0x0e RO
    uint8_t bist;                  // 0x0f
    uint32_t bar0;                 // 0x10
    uint32_t bar1;                 // 0x14
    uint32_t bar2;                 // 0x18
    uint32_t bar3;                 // 0x1c
    uint32_t bar4;                 // 0x20
    uint32_t bar5;                 // 0x24
    uint32_t cardbus_pointer;      // 0x28
    uint16_t subsys_vendor_id;     // 0x2c
    uint16_t subsys_id;            // 0x2e
    uint32_t expansion_rom_base;   // 0x30
    uint8_t cap_pointer;           // 0x34
    uint8_t reserved[7];           // 0x35
    uint8_t interrupt_line;        // 0x3c
    uint8_t interrupt_pin;         // 0x3d
    uint8_t min_gnt;               // 0x3e
    uint8_t max_lat;               // 0x3f
    uint8_t cap_section[0xbf];     // 0x40
} __packed;

struct hypervisor_map_notifier
{
    uint64_t npages;
    uint64_t len;
    uint64_t gva;
    uint64_t cpid;
    uint64_t dirtied;
    uint64_t is_huge;
    uint64_t gpas[0];
};

/* Mediated vFPGA management data */
struct m_fpga_dev
{
    struct fpga_dev *fpga; // Parent fpga struct
    uint32_t id;

    struct list_head next; // next virtual fpga
    struct pci_config_space pci_config;
    spinlock_t current_cpid_lock;
    uint64_t current_cpid;
    struct kvm *kvm;
    uint32_t in_use;
    struct notifier_block notifier;

    void *msix_table;
    struct msix_interrupt *msix_vector;

    struct hlist_head sbuff_map[HASH_TABLE_BUCKETS];

    spinlock_t lock;
};

#endif
