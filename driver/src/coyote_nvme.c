/*
 * Copyright (c) 2025,  Systems Group, ETH Zurich
 * All rights reserved.
 *
 * This file is part of the Coyote device driver for Linux.
 * Coyote can be found at: https://github.com/fpgasystems/Coyote
 *
 * This source code is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * The full GNU General Public License is included in this distribution in
 * the file called "COPYING". If not found, a copy of the GNU General Public
 * License can be found <https://www.gnu.org/licenses/>.
 */

#include "coyote_nvme.h"

#include <linux/pm_runtime.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/dma-mapping.h>
#include <linux/kthread.h>
#include <linux/ktime.h>
#include <linux/sched.h>

/* ============================================================
 * NVMe controller register layout (NVMe over PCIe spec)
 * Kept private to this translation unit; callers never touch these.
 * ============================================================ */
#define NVME_REG_CAP        0x00
#define NVME_REG_VS         0x08
#define NVME_REG_CC         0x14
#define NVME_REG_CSTS       0x1C
#define NVME_REG_AQA        0x24
#define NVME_REG_ASQ        0x28
#define NVME_REG_ACQ        0x30
#define NVME_REG_DOORBELL   0x1000

#define NVME_CC_EN          (1U << 0)
#define NVME_CC_CSS_NVM     (0U << 4)
#define NVME_CC_MPS_4K      (0U << 7)
#define NVME_CC_AMS_RR      (0U << 11)
#define NVME_CC_SHN_NONE    (0U << 14)
#define NVME_CC_IOSQES      (6U << 16)
#define NVME_CC_IOCQES      (4U << 20)

#define NVME_CSTS_RDY       (1U << 0)
#define NVME_CSTS_CFS       (1U << 1)

#define NVME_ADMIN_IDENTIFY         0x06
#define NVME_ADMIN_CREATE_IO_CQ     0x05
#define NVME_ADMIN_CREATE_IO_SQ     0x01
#define NVME_ADMIN_DELETE_IO_SQ     0x00
#define NVME_ADMIN_DELETE_IO_CQ     0x04

#define NVME_ADMIN_QUEUE_SIZE       64
#define NVME_IO_QUEUE_SIZE          64

#define NVME_PCI_CLASS_STORAGE_NVME 0x010802U

/* ============================================================
 * FPGA-side BRAM layout for NVMe queues (offsets within BAR_SHELL_CONFIG)
 * Per-device SQ/CQ memory regions; the SSD DMAs SQEs and CQEs to/from these.
 * Layout must match the HDL nvme_prp_dispatch/nvme_cnfg_slave region map.
 * ============================================================ */
#define NVME_SQ_BASE        0x04010000UL    /* SQ BRAM, 4 KB per device */
#define NVME_SQ_SIZE        0x1000UL
#define NVME_CQ_BASE        0x04020000UL    /* CQ BRAM, 4 KB per device */
#define NVME_CQ_SIZE        0x1000UL

/* Default admin command timeout, in milliseconds */
#define NVME_ADMIN_TIMEOUT_MS   2000
/* Controller enable / disable poll timeout, in milliseconds */
#define NVME_CTRL_TIMEOUT_MS    5000

/* ============================================================
 * Forward declarations (static helpers)
 * ============================================================ */
static int  nvme_open_pci(struct nvme_dev_ctx *ctx, const char *bdf);
static void nvme_close_pci(struct nvme_dev_ctx *ctx);
static int  nvme_create_admin_queue(struct nvme_dev_ctx *ctx);
static void nvme_destroy_admin_queue(struct nvme_dev_ctx *ctx);
static int  nvme_enable_controller(struct nvme_dev_ctx *ctx);
static int  nvme_disable_controller(struct nvme_dev_ctx *ctx);
static int  nvme_wait_ready(struct nvme_dev_ctx *ctx, bool enabled, int timeout_ms);
static int  nvme_submit_admin_cmd(struct nvme_dev_ctx *ctx, void *sqe, void *cqe_out);
static int  nvme_identify(struct nvme_dev_ctx *ctx, uint32_t nsid);
static int  nvme_create_io_queues(struct nvme_dev_ctx *ctx, uint16_t io_qid,
                                  uint64_t io_sq_phys, uint64_t io_cq_phys);
static void nvme_write_device_info(volatile struct nvme_fpga_cnfg_regs *cnfg,
                                   struct nvme_device_state *ds,
                                   uint64_t fpga_bar_base);
static void nvme_write_permission(volatile struct nvme_fpga_cnfg_regs *cnfg,
                                  uint32_t region_id, uint32_t dev_id,
                                  uint64_t lba_offset, uint64_t lba_count,
                                  uint32_t lba_size);

/* ============================================================
 * Device table helpers (caller holds mgr->lock)
 * ============================================================ */
static struct nvme_device_state *nvme_find_device(struct nvme_manager *mgr,
                                                  const char *bdf, uint32_t nsid) {
    int i;
    for (i = 0; i < mgr->num_devices; i++) {
        if (mgr->devices[i].active &&
            strncmp(mgr->devices[i].bdf, bdf, sizeof(mgr->devices[i].bdf)) == 0 &&
            mgr->devices[i].nsid == nsid) {
            return &mgr->devices[i];
        }
    }
    return NULL;
}

static struct nvme_device_state *nvme_alloc_device(struct nvme_manager *mgr) {
    if (mgr->num_devices >= MAX_NVME_DEVICES) {
        return NULL;
    }
    /* Caller is responsible for bumping num_devices once the slot is committed */
    return &mgr->devices[mgr->num_devices];
}

/* ============================================================
 * PCI device discovery and BAR0 mapping
 * ============================================================ */
static int nvme_open_pci(struct nvme_dev_ctx *ctx, const char *bdf) {
    unsigned int domain = 0, bus = 0, slot = 0, func = 0;
    struct pci_dev *pdev;
    uint16_t vendor;
    uint64_t cap;
    int ret;

    if (sscanf(bdf, "%x:%x:%x.%x", &domain, &bus, &slot, &func) != 4) {
        domain = 0;
        if (sscanf(bdf, "%x:%x.%x", &bus, &slot, &func) != 3) {
            pr_err("nvme_open_pci: invalid BDF: %s\n", bdf);
            return -EINVAL;
        }
    }

    pdev = pci_get_domain_bus_and_slot(domain, bus, PCI_DEVFN(slot, func));
    if (!pdev) {
        pr_err("nvme_open_pci: device not found: %s\n", bdf);
        return -ENODEV;
    }

    if ((pdev->class >> 8) != (NVME_PCI_CLASS_STORAGE_NVME >> 8)) {
        pr_err("nvme_open_pci: not an NVMe device (class=0x%06x)\n", pdev->class);
        pci_dev_put(pdev);
        return -EINVAL;
    }

    if (pdev->driver) {
        pr_err("nvme_open_pci: device bound to '%s', unbind first\n", pdev->driver->name);
        pci_dev_put(pdev);
        return -EBUSY;
    }

    /* Wake device from D3cold (needed after rmmod nvme / unbind) */
    dbg_info("power state: D%d, calling pm_runtime_get_sync\n", pdev->current_state);
    ret = pm_runtime_get_sync(&pdev->dev);
    if (ret < 0 && ret != -EACCES) {
        dbg_info("pm_runtime_get_sync returned %d, continuing\n", ret);
        pm_runtime_put_noidle(&pdev->dev);
    }

    /* Verify PCIe link is up (vendor != 0xFFFF) */
    pci_read_config_word(pdev, PCI_VENDOR_ID, &vendor);
    dbg_info("vendor ID after PM resume: 0x%04x\n", vendor);
    if (vendor == 0xFFFF) {
        pr_err("nvme_open_pci: device not reachable (vendor=0xFFFF, PCIe link down)\n");
        pr_err("nvme_open_pci: try: echo 1 > /sys/bus/pci/devices/%s/remove && echo 1 > /sys/bus/pci/rescan\n", bdf);
        pm_runtime_put(&pdev->dev);
        pci_dev_put(pdev);
        return -ENODEV;
    }

    ret = pci_enable_device_mem(pdev);
    if (ret) {
        pr_err("nvme_open_pci: pci_enable_device_mem failed\n");
        pm_runtime_put(&pdev->dev);
        pci_dev_put(pdev);
        return ret;
    }

    pci_set_master(pdev);

    ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
    if (ret) {
        ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
        if (ret) {
            pr_err("nvme_open_pci: dma_set_mask failed\n");
            pci_disable_device(pdev);
            pm_runtime_put(&pdev->dev);
            pci_dev_put(pdev);
            return ret;
        }
    }

    ctx->bar0_phys = pci_resource_start(pdev, 0);
    ctx->bar0_size = pci_resource_len(pdev, 0);
    ctx->bar0 = pci_iomap(pdev, 0, ctx->bar0_size);
    if (!ctx->bar0) {
        pr_err("nvme_open_pci: pci_iomap failed\n");
        pci_disable_device(pdev);
        pm_runtime_put(&pdev->dev);
        pci_dev_put(pdev);
        return -ENOMEM;
    }
    ctx->pdev = pdev;

    cap = readq(ctx->bar0 + NVME_REG_CAP);
    ctx->db_stride = 4 << ((cap >> 32) & 0xF);

    dbg_info("BAR0=0x%llx, size=%zu, stride=%u\n",
             ctx->bar0_phys, ctx->bar0_size, ctx->db_stride);
    return 0;
}

static void nvme_close_pci(struct nvme_dev_ctx *ctx) {
    if (ctx->bar0) {
        pci_iounmap(ctx->pdev, ctx->bar0);
        ctx->bar0 = NULL;
    }
    if (ctx->pdev) {
        pci_clear_master(ctx->pdev);
        pci_disable_device(ctx->pdev);
        pm_runtime_put(&ctx->pdev->dev);
        pci_dev_put(ctx->pdev);
        ctx->pdev = NULL;
    }
}

/* ============================================================
 * Admin queue management
 * ============================================================ */
static int nvme_create_admin_queue(struct nvme_dev_ctx *ctx) {
    struct pci_dev *pdev = ctx->pdev;

    ctx->asq_virt = dma_alloc_coherent(&pdev->dev,
                                       NVME_ADMIN_QUEUE_SIZE * 64,
                                       &ctx->asq_dma, GFP_KERNEL);
    if (!ctx->asq_virt) {
        return -ENOMEM;
    }

    ctx->acq_virt = dma_alloc_coherent(&pdev->dev,
                                       NVME_ADMIN_QUEUE_SIZE * 16,
                                       &ctx->acq_dma, GFP_KERNEL);
    if (!ctx->acq_virt) {
        dma_free_coherent(&pdev->dev, NVME_ADMIN_QUEUE_SIZE * 64,
                          ctx->asq_virt, ctx->asq_dma);
        ctx->asq_virt = NULL;
        return -ENOMEM;
    }

    memset(ctx->asq_virt, 0, NVME_ADMIN_QUEUE_SIZE * 64);
    memset(ctx->acq_virt, 0, NVME_ADMIN_QUEUE_SIZE * 16);
    ctx->asq_tail  = 0;
    ctx->acq_head  = 0;
    ctx->acq_phase = 1;
    ctx->admin_cid = 0;
    return 0;
}

static void nvme_destroy_admin_queue(struct nvme_dev_ctx *ctx) {
    struct pci_dev *pdev = ctx->pdev;
    if (ctx->asq_virt) {
        dma_free_coherent(&pdev->dev, NVME_ADMIN_QUEUE_SIZE * 64,
                          ctx->asq_virt, ctx->asq_dma);
        ctx->asq_virt = NULL;
    }
    if (ctx->acq_virt) {
        dma_free_coherent(&pdev->dev, NVME_ADMIN_QUEUE_SIZE * 16,
                          ctx->acq_virt, ctx->acq_dma);
        ctx->acq_virt = NULL;
    }
}

/* ============================================================
 * Controller enable / disable / wait
 * ============================================================ */
static int nvme_wait_ready(struct nvme_dev_ctx *ctx, bool enabled, int timeout_ms) {
    int waited = 0;
    uint32_t csts = 0;

    while (waited < timeout_ms) {
        csts = readl(ctx->bar0 + NVME_REG_CSTS);

        /* Only check CFS when waiting for enable, not during disable.
         * Per NVMe spec: after CFS, host should reset CC.EN=0 to recover.
         * Checking CFS during disable would prevent recovery. */
        if (enabled && (csts & NVME_CSTS_CFS)) {
            pr_err("nvme_wait_ready: controller fatal status (CSTS=0x%x)\n", csts);
            return -EIO;
        }

        if (((csts & NVME_CSTS_RDY) != 0) == enabled) {
            return 0;
        }

        msleep(10);
        waited += 10;
    }
    pr_err("nvme_wait_ready: timeout (CSTS=0x%x, wanted %s)\n",
           csts, enabled ? "ready" : "not-ready");
    return -ETIMEDOUT;
}

static int nvme_enable_controller(struct nvme_dev_ctx *ctx) {
    uint32_t cc, csts;
    int ret;

    /* Always disable first to clear stale state or fatal status */
    cc   = readl(ctx->bar0 + NVME_REG_CC);
    csts = readl(ctx->bar0 + NVME_REG_CSTS);
    dbg_info("initial CC=0x%x, CSTS=0x%x\n", cc, csts);

    if (cc & NVME_CC_EN) {
        writel(0, ctx->bar0 + NVME_REG_CC);
        ret = nvme_wait_ready(ctx, false, NVME_CTRL_TIMEOUT_MS);
        if (ret) {
            pr_warn("nvme_enable: disable timed out, attempting subsystem reset\n");
            writel(0, ctx->bar0 + NVME_REG_CC);
            msleep(500);
        }
    } else if (csts & NVME_CSTS_CFS) {
        /* Controller not enabled but in fatal state -- force CC=0 to reset */
        pr_warn("nvme_enable: CFS set while disabled, resetting\n");
        writel(0, ctx->bar0 + NVME_REG_CC);
        msleep(500);
    }

    /* Ensure CC.EN is 0 and wait for RDY to clear */
    writel(0, ctx->bar0 + NVME_REG_CC);
    ret = nvme_wait_ready(ctx, false, NVME_CTRL_TIMEOUT_MS);
    if (ret) {
        pr_err("nvme_enable: controller stuck, cannot disable\n");
        return ret;
    }

    /* Configure admin queues */
    writel(((NVME_ADMIN_QUEUE_SIZE - 1) << 16) | (NVME_ADMIN_QUEUE_SIZE - 1),
           ctx->bar0 + NVME_REG_AQA);
    writeq(ctx->asq_dma, ctx->bar0 + NVME_REG_ASQ);
    writeq(ctx->acq_dma, ctx->bar0 + NVME_REG_ACQ);

    /* Enable */
    cc = NVME_CC_EN | NVME_CC_CSS_NVM | NVME_CC_MPS_4K |
         NVME_CC_AMS_RR | NVME_CC_SHN_NONE |
         NVME_CC_IOSQES | NVME_CC_IOCQES;
    writel(cc, ctx->bar0 + NVME_REG_CC);

    ret = nvme_wait_ready(ctx, true, NVME_CTRL_TIMEOUT_MS);
    if (ret) {
        csts = readl(ctx->bar0 + NVME_REG_CSTS);
        pr_err("nvme_enable: failed to become ready, CSTS=0x%x\n", csts);
        return ret;
    }

    dbg_info("controller enabled\n");
    return 0;
}

static int nvme_disable_controller(struct nvme_dev_ctx *ctx) {
    uint32_t cc = readl(ctx->bar0 + NVME_REG_CC);
    writel(cc & ~NVME_CC_EN, ctx->bar0 + NVME_REG_CC);
    return nvme_wait_ready(ctx, false, NVME_CTRL_TIMEOUT_MS);
}

/* ============================================================
 * Admin command submission
 * ============================================================ */
static int nvme_submit_admin_cmd_timeout(struct nvme_dev_ctx *ctx, void *sqe,
                                         void *cqe_out, int timeout_ms) {
    uint32_t *cqe;
    uint8_t phase;
    uint16_t status;
    int timeout = timeout_ms;

    mutex_lock(&ctx->lock);

    memcpy(ctx->asq_virt + ctx->asq_tail * 64, sqe, 64);
    ctx->asq_tail = (ctx->asq_tail + 1) % NVME_ADMIN_QUEUE_SIZE;
    writel(ctx->asq_tail, ctx->bar0 + NVME_REG_DOORBELL);

    while (timeout > 0) {
        cqe = (uint32_t *)(ctx->acq_virt + ctx->acq_head * 16);
        phase = (cqe[3] >> 16) & 1;
        if (phase == ctx->acq_phase) {
            if (cqe_out) {
                memcpy(cqe_out, cqe, 16);
            }

            ctx->acq_head = (ctx->acq_head + 1) % NVME_ADMIN_QUEUE_SIZE;
            if (ctx->acq_head == 0) {
                ctx->acq_phase ^= 1;
            }

            writel(ctx->acq_head, ctx->bar0 + NVME_REG_DOORBELL + ctx->db_stride);
            mutex_unlock(&ctx->lock);

            status = (cqe[3] >> 17) & 0x7FF;
            if (status) {
                pr_err("nvme admin cmd status=0x%x\n", status);
                return -EIO;
            }
            return 0;
        }
        msleep(1);
        timeout--;
    }

    mutex_unlock(&ctx->lock);
    pr_warn("nvme admin cmd timeout (%d ms)\n", timeout_ms);
    return -ETIMEDOUT;
}

static int nvme_submit_admin_cmd(struct nvme_dev_ctx *ctx, void *sqe, void *cqe_out) {
    return nvme_submit_admin_cmd_timeout(ctx, sqe, cqe_out, NVME_ADMIN_TIMEOUT_MS);
}

/* ============================================================
 * Identify controller & namespace
 * ============================================================ */
static int nvme_identify(struct nvme_dev_ctx *ctx, uint32_t nsid) {
    void *buf;
    dma_addr_t buf_dma;
    uint32_t sqe[16] = {0};
    uint8_t *bytes;
    uint64_t *qwords;
    uint8_t flbas, lbads, mdts_pow;
    uint32_t *lbaf_p;
    int ret;

    buf = dma_alloc_coherent(&ctx->pdev->dev, 4096, &buf_dma, GFP_KERNEL);
    if (!buf) {
        return -ENOMEM;
    }

    /* Identify Controller (CNS=1) */
    sqe[0]  = NVME_ADMIN_IDENTIFY | (ctx->admin_cid++ << 16);
    sqe[6]  = (uint32_t)buf_dma;
    sqe[7]  = (uint32_t)(buf_dma >> 32);
    sqe[10] = 1; /* CNS=1 */

    ret = nvme_submit_admin_cmd(ctx, sqe, NULL);
    if (ret) {
        goto out;
    }

    bytes    = (uint8_t *)buf;
    mdts_pow = bytes[77];
    ctx->mdts = mdts_pow ? ((1U << mdts_pow) * 4096) : 0;
    dbg_info("identify ctrl: MDTS=%u bytes\n", ctx->mdts);

    /* Identify Namespace (CNS=0) */
    memset(sqe, 0, 64);
    sqe[0]  = NVME_ADMIN_IDENTIFY | (ctx->admin_cid++ << 16);
    sqe[1]  = nsid;
    sqe[6]  = (uint32_t)buf_dma;
    sqe[7]  = (uint32_t)(buf_dma >> 32);
    sqe[10] = 0; /* CNS=0 */

    ret = nvme_submit_admin_cmd(ctx, sqe, NULL);
    if (ret) {
        goto out;
    }

    qwords    = (uint64_t *)buf;
    bytes     = (uint8_t *)buf;
    ctx->nsze = qwords[0];
    ctx->nsid = nsid;

    flbas    = bytes[26] & 0xF;
    lbaf_p   = (uint32_t *)(bytes + 128 + flbas * 4);
    lbads    = (*lbaf_p >> 16) & 0xFF;
    ctx->lba_size = 1U << lbads;

    dbg_info("identify ns: nsze=%llu, lba_size=%u\n", ctx->nsze, ctx->lba_size);

out:
    dma_free_coherent(&ctx->pdev->dev, 4096, buf, buf_dma);
    return ret;
}

/* ============================================================
 * I/O queue creation (SQ/CQ memory lives in FPGA BRAM)
 * ============================================================ */
static int nvme_create_io_queues(struct nvme_dev_ctx *ctx, uint16_t io_qid,
                                 uint64_t io_sq_phys, uint64_t io_cq_phys) {
    uint32_t sqe[16] = {0};
    int ret;

    /* Create I/O CQ */
    sqe[0]  = NVME_ADMIN_CREATE_IO_CQ | (ctx->admin_cid++ << 16);
    sqe[6]  = (uint32_t)io_cq_phys;
    sqe[7]  = (uint32_t)(io_cq_phys >> 32);
    sqe[10] = (io_qid & 0xFFFF) | (((NVME_IO_QUEUE_SIZE - 1) & 0xFFFF) << 16);
    sqe[11] = 1; /* PC=1 */

    ret = nvme_submit_admin_cmd(ctx, sqe, NULL);
    if (ret) {
        return ret;
    }

    /* Create I/O SQ; associate with the CQ created above */
    memset(sqe, 0, 64);
    sqe[0]  = NVME_ADMIN_CREATE_IO_SQ | (ctx->admin_cid++ << 16);
    sqe[6]  = (uint32_t)io_sq_phys;
    sqe[7]  = (uint32_t)(io_sq_phys >> 32);
    sqe[10] = (io_qid & 0xFFFF) | (((NVME_IO_QUEUE_SIZE - 1) & 0xFFFF) << 16);
    sqe[11] = 1 | (io_qid << 16); /* PC=1, CQID */

    ret = nvme_submit_admin_cmd(ctx, sqe, NULL);
    if (ret) {
        /* Roll back the CQ on SQ-create failure */
        memset(sqe, 0, 64);
        sqe[0]  = NVME_ADMIN_DELETE_IO_CQ | (ctx->admin_cid++ << 16);
        sqe[10] = io_qid;
        nvme_submit_admin_cmd(ctx, sqe, NULL);
    }
    return ret;
}

/* ============================================================
 * FPGA register writes
 * ============================================================ */
static void nvme_write_device_info(volatile struct nvme_fpga_cnfg_regs *cnfg,
                                   struct nvme_device_state *ds,
                                   uint64_t fpga_bar_base) {
    struct nvme_dev_ctx *ctx = &ds->ctx;
    /* db_iova = SSD doorbell BAR mapped into the FPGA DMA domain (P2P), or the raw PA
     * without IOMMU. The FPGA rings the doorbell with this address. */
    uint64_t sq_db = ctx->db_iova + NVME_REG_DOORBELL
                     + (2 * ds->io_qid * ctx->db_stride);

    cnfg->fpga_bar_base    = fpga_bar_base;
    cnfg->dev_id           = ds->dev_id;
    cnfg->nsid             = ctx->nsid;
    cnfg->lbaf             = ffs(ctx->lba_size) - 1; /* log2(lba_size) */
    cnfg->nsze             = ctx->nsze;
    cnfg->doorbell_base    = sq_db;
    cnfg->valid_nvme_info  = 3; /* bit[0]=commit, bit[1]=reset_queue */

    dbg_info("dev_id=%u, doorbell=0x%llx, lbaf=%u\n",
             ds->dev_id, sq_db, ffs(ctx->lba_size) - 1);
}

static void nvme_write_permission(volatile struct nvme_fpga_cnfg_regs *cnfg,
                                  uint32_t region_id, uint32_t dev_id,
                                  uint64_t lba_offset, uint64_t lba_count,
                                  uint32_t lba_size) {
    /* Store the permission range in bytes: the HDL works in bytes and checks
     * (naddr + len) <= perm lba_size, so units must match. */
    uint64_t offset_bytes = lba_offset * lba_size;
    uint64_t size_bytes   = lba_count  * lba_size;

    cnfg->perm_region_id  = region_id;
    cnfg->perm_dev_id     = dev_id;
    cnfg->perm_lba_offset = offset_bytes;
    cnfg->perm_lba_size   = size_bytes;
    cnfg->perm_valid      = 1; /* commit */

    dbg_info("region=%u, dev=%u, offset=%llu (%llu LBAs), size=%llu (%llu LBAs)\n",
             region_id, dev_id, offset_bytes, lba_offset, size_bytes, lba_count);
}

/* ============================================================
 * Manager lifecycle
 * ============================================================ */
int nvme_mgr_init(struct bus_driver_data *bd_data) {
    struct nvme_manager *mgr;

    if (!bd_data) {
        return -EINVAL;
    }
    if (bd_data->nvme_mgr) {
        return 0; /* already initialized */
    }

    mgr = kzalloc(sizeof(*mgr), GFP_KERNEL);
    if (!mgr) {
        pr_err("nvme_mgr_init: failed to allocate manager\n");
        return -ENOMEM;
    }

    mutex_init(&mgr->lock);
    mgr->num_devices = 0;

    bd_data->nvme_mgr = mgr;
    dbg_info("NVMe manager allocated (max %d devices)\n", MAX_NVME_DEVICES);
    return 0;
}

void nvme_mgr_free(struct bus_driver_data *bd_data) {
    struct nvme_manager *mgr;
    int i;

    if (!bd_data) {
        return;
    }
    mgr = bd_data->nvme_mgr;
    if (!mgr) {
        return;
    }

    for (i = 0; i < mgr->num_devices; i++) {
        struct nvme_device_state *ds = &mgr->devices[i];
        if (!ds->active) {
            continue;
        }
        if (ds->ctx.initialized) {
            /* Skip admin cmds during teardown: the SSD may already have been reset.
             * Release host-side resources only. */
            nvme_destroy_admin_queue(&ds->ctx);
            if (ds->ctx.iova_size && ds->ctx.pdev) {
                dma_unmap_resource(&ds->ctx.pdev->dev, ds->ctx.iova_base,
                                   ds->ctx.iova_size, DMA_BIDIRECTIONAL, 0);
                ds->ctx.iova_base = 0;
                ds->ctx.iova_size = 0;
            }
            if (ds->ctx.db_iova_size) {
                dma_unmap_resource(&bd_data->pci_dev->dev, ds->ctx.db_iova,
                                   ds->ctx.db_iova_size, DMA_BIDIRECTIONAL, 0);
                ds->ctx.db_iova = 0;
                ds->ctx.db_iova_size = 0;
            }
            nvme_close_pci(&ds->ctx);
            ds->ctx.initialized = false;
        }
        ds->active = false;
    }

    kfree(mgr);
    bd_data->nvme_mgr = NULL;
    dbg_info("NVMe manager freed\n");
}

/* ============================================================
 * IOCTL: claim NVMe device and allocate LBA range for this region
 * ============================================================ */
long vfpga_nvme_init(struct vfpga_dev *device, struct nvme_init_ioctl *req) {
    struct bus_driver_data *bd;
    struct nvme_manager *mgr;
    volatile struct nvme_fpga_cnfg_regs *cnfg;
    struct nvme_device_state *ds;
    uint64_t lba_count, lba_offset;
    int region_id;
    int ret = 0;

    if (!device || !req) {
        return -EINVAL;
    }

    bd  = device->bd_data;
    mgr = bd->nvme_mgr;
    cnfg = bd->nvme_cnfg_regs;
    region_id = device->id;

    if (!mgr) {
        req->result = -ENODEV;
        return -ENODEV;
    }
    if (!cnfg) {
        req->result = -ENODEV;
        return -ENODEV;
    }
    if (region_id < 0 || region_id >= MAX_N_REGIONS) {
        req->result = -EINVAL;
        return -EINVAL;
    }

    mutex_lock(&mgr->lock);

    /* 1. Find or create the device */
    ds = nvme_find_device(mgr, req->bdf, req->nsid);
    if (ds) {
        dbg_info("reusing dev_id=%u for bdf=%s\n", ds->dev_id, req->bdf);
    } else {
        ds = nvme_alloc_device(mgr);
        if (!ds) {
            mutex_unlock(&mgr->lock);
            pr_err("vfpga_nvme_init: device table full (max %d)\n", MAX_NVME_DEVICES);
            req->result = -ENOSPC;
            return -ENOSPC;
        }

        memset(ds, 0, sizeof(*ds));
        ds->dev_id      = mgr->num_devices;
        strncpy(ds->bdf, req->bdf, sizeof(ds->bdf) - 1);
        ds->bdf[sizeof(ds->bdf) - 1] = '\0';
        ds->nsid          = req->nsid;
        ds->next_free_lba = 0;
        ds->io_qid        = 1 + ds->dev_id;

        mutex_init(&ds->ctx.lock);

        ret = nvme_open_pci(&ds->ctx, req->bdf);
        if (ret) { goto err_pci; }

        /* Map the FPGA shell BAR through this NVMe device's DMA API so that the IOMMU
         * (if enabled) translates IOVAs in NVMe PRPs back to the FPGA BAR's physical address.
         * Without an IOMMU this returns the raw PA, so the same code path works either way. */
        ds->ctx.iova_size = bd->bar_len[BAR_SHELL_CONFIG];
        ds->ctx.iova_base = dma_map_resource(&ds->ctx.pdev->dev,
                                             bd->bar_phys_addr[BAR_SHELL_CONFIG],
                                             ds->ctx.iova_size,
                                             DMA_BIDIRECTIONAL, 0);
        if (dma_mapping_error(&ds->ctx.pdev->dev, ds->ctx.iova_base)) {
            pr_err("vfpga_nvme_init: dma_map_resource failed for FPGA BAR\n");
            ds->ctx.iova_base = 0;
            ds->ctx.iova_size = 0;
            ret = -ENOMEM;
            goto err_iova;
        }

        /* SQ/CQ live in the FPGA shell BAR; expose them to the SSD as IOVAs */
        ds->io_sq_phys    = ds->ctx.iova_base + NVME_SQ_BASE + ds->dev_id * NVME_SQ_SIZE;
        ds->io_cq_phys    = ds->ctx.iova_base + NVME_CQ_BASE + ds->dev_id * NVME_CQ_SIZE;

        ret = nvme_create_admin_queue(&ds->ctx);
        if (ret) { goto err_admin; }

        ret = nvme_enable_controller(&ds->ctx);
        if (ret) { goto err_enable; }

        ret = nvme_identify(&ds->ctx, req->nsid);
        if (ret) { goto err_identify; }

        ret = nvme_create_io_queues(&ds->ctx, ds->io_qid,
                                    ds->io_sq_phys, ds->io_cq_phys);
        if (ret) { goto err_io; }

        /* P2P doorbell: map the SSD's BAR0 (doorbell registers) into the FPGA's DMA domain so the
         * FPGA's outbound doorbell write carries a valid bus address. No-op without IOMMU. */
        ds->ctx.db_iova_size = ds->ctx.bar0_size;
        ds->ctx.db_iova = dma_map_resource(&bd->pci_dev->dev, ds->ctx.bar0_phys,
                                           ds->ctx.db_iova_size, DMA_BIDIRECTIONAL, 0);
        if (dma_mapping_error(&bd->pci_dev->dev, ds->ctx.db_iova)) {
            pr_warn("vfpga_nvme_init: SSD doorbell BAR P2P map failed; falling back to raw PA\n");
            ds->ctx.db_iova      = ds->ctx.bar0_phys;
            ds->ctx.db_iova_size = 0;
        }

        /* Push device info to FPGA; the FPGA stamps this base into PRP entries,
         * so it must be the IOVA seen by the NVMe device, not the raw FPGA BAR PA. */
        nvme_write_device_info(cnfg, ds, ds->ctx.iova_base);

        ds->active = true;
        ds->ctx.initialized = true;
        mgr->num_devices++;
    }

    /* 2. Bump-allocate an LBA range for this region */
    lba_count = req->size / ds->ctx.lba_size;
    if (lba_count == 0) {
        lba_count = ds->ctx.nsze; /* size=0 -> whole namespace */
    }

    lba_offset = ds->next_free_lba;
    if (lba_offset + lba_count > ds->ctx.nsze) {
        pr_err("vfpga_nvme_init: not enough LBAs (need %llu, have %llu)\n",
               lba_count, ds->ctx.nsze - lba_offset);
        mutex_unlock(&mgr->lock);
        req->result = -ENOSPC;
        return -ENOSPC;
    }
    ds->next_free_lba += lba_count;

    /* 3. Push permission to FPGA */
    nvme_write_permission(cnfg, region_id, ds->dev_id, lba_offset, lba_count,
                          ds->ctx.lba_size);

    /* 4. Persist the allocation in the manager */
    mgr->region_allocs[region_id][ds->dev_id].dev_id     = ds->dev_id;
    mgr->region_allocs[region_id][ds->dev_id].lba_offset = lba_offset;
    mgr->region_allocs[region_id][ds->dev_id].lba_count  = lba_count;
    mgr->region_allocs[region_id][ds->dev_id].active     = true;

    /* 5. Fill response */
    req->result            = 0;
    req->dev_id            = ds->dev_id;
    req->lba_size          = ds->ctx.lba_size;
    req->nsze              = ds->ctx.nsze;
    req->lba_offset        = lba_offset;
    req->lba_count         = lba_count;
    req->sq_doorbell_addr  = ds->ctx.db_iova + NVME_REG_DOORBELL
                             + (2 * ds->io_qid * ds->ctx.db_stride);
    req->cq_doorbell_addr  = req->sq_doorbell_addr + ds->ctx.db_stride;
    req->mdts              = ds->ctx.mdts;

    mutex_unlock(&mgr->lock);
    return 0;

err_io:
err_identify:
    nvme_disable_controller(&ds->ctx);
err_enable:
    nvme_destroy_admin_queue(&ds->ctx);
err_admin:
    if (ds->ctx.iova_size) {
        dma_unmap_resource(&ds->ctx.pdev->dev, ds->ctx.iova_base,
                           ds->ctx.iova_size, DMA_BIDIRECTIONAL, 0);
        ds->ctx.iova_base = 0;
        ds->ctx.iova_size = 0;
    }
err_iova:
    nvme_close_pci(&ds->ctx);
err_pci:
    memset(ds, 0, sizeof(*ds));
    mutex_unlock(&mgr->lock);
    req->result = ret;
    return ret;
}

/* ============================================================
 * IOCTL: release this region's LBA allocations
 * ============================================================ */
long vfpga_nvme_close(struct vfpga_dev *device, uint32_t dev_id) {
    struct bus_driver_data *bd;
    struct nvme_manager *mgr;
    int region_id;
    int i;

    if (!device) {
        return -EINVAL;
    }

    bd  = device->bd_data;
    mgr = bd->nvme_mgr;
    region_id = device->id;

    if (!mgr) {
        return -ENODEV;
    }
    if (region_id < 0 || region_id >= MAX_N_REGIONS) {
        return -EINVAL;
    }

    mutex_lock(&mgr->lock);
    if (dev_id < MAX_NVME_DEVICES) {
        /* Release allocations for the specified device only */
        mgr->region_allocs[region_id][dev_id].active = false;
    } else {
        /* dev_id out of range: release every allocation for this region */
        for (i = 0; i < MAX_NVME_DEVICES; i++) {
            mgr->region_allocs[region_id][i].active = false;
        }
    }
    mutex_unlock(&mgr->lock);

    dbg_info("cleared allocations for region %d, dev_id=%u\n", region_id, dev_id);
    return 0;
}

/* ============================================================
 * IOCTL: query whether (bdf, nsid) is already registered
 * ============================================================ */
long vfpga_nvme_is_registered(struct vfpga_dev *device, struct nvme_init_ioctl *req) {
    struct bus_driver_data *bd;
    struct nvme_manager *mgr;
    struct nvme_device_state *ds;

    if (!device || !req) {
        return -EINVAL;
    }

    bd  = device->bd_data;
    mgr = bd->nvme_mgr;

    if (!mgr) {
        req->result = -ENODEV;
        return -ENODEV;
    }

    mutex_lock(&mgr->lock);
    ds = nvme_find_device(mgr, req->bdf, req->nsid);
    if (ds) {
        req->result           = 0;
        req->dev_id           = ds->dev_id;
        req->lba_size         = ds->ctx.lba_size;
        req->nsze             = ds->ctx.nsze;
        req->sq_doorbell_addr = ds->ctx.db_iova + NVME_REG_DOORBELL
                                + (2 * ds->io_qid * ds->ctx.db_stride);
        req->cq_doorbell_addr = req->sq_doorbell_addr + ds->ctx.db_stride;
        req->mdts             = ds->ctx.mdts;
        mutex_unlock(&mgr->lock);
        return 0;
    }
    mutex_unlock(&mgr->lock);

    req->result = -ENOENT;
    return -ENOENT;
}
