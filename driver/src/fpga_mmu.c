/**
 * Copyright (c) 2021, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
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
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include "fpga_mmu.h"

/*
███╗   ███╗███╗   ███╗██╗   ██╗
████╗ ████║████╗ ████║██║   ██║
██╔████╔██║██╔████╔██║██║   ██║
██║╚██╔╝██║██║╚██╔╝██║██║   ██║
██║ ╚═╝ ██║██║ ╚═╝ ██║╚██████╔╝
╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝
*/

/**
 * @brief ISR
 *
 */
irqreturn_t fpga_isr(int irq, void *dev_id) {
  struct fpga_dev *d;
  __u16 type;
  unsigned long flags;
  struct fpga_irq_pfault *irq_pf;
  struct fpga_irq_notify *irq_not;

  dbg_info("(irq=%d) ISR entry\n", irq);

  d = (struct fpga_dev *)dev_id;
  BUG_ON(!d);

  // lock
  spin_lock_irqsave(&(d->irq_lock), flags);

  // read irq type
  type = fpga_read_irq_type(d);

  switch (type) {
  case IRQ_DMA_OFFL:
    dbg_info("(irq=%d) dma offload completed, vFPGA %d\n", irq, d->id);
    atomic_set(&d->wait_offload, FLAG_SET);
    wake_up_interruptible(&d->waitqueue_offload);
    break;

  case IRQ_DMA_SYNC:
    dbg_info("(irq=%d) dma sync completed, vFPGA %d\n", irq, d->id);
    atomic_set(&d->wait_sync, FLAG_SET);
    wake_up_interruptible(&d->waitqueue_sync);
    break;

  case IRQ_INVLDT:
    dbg_info("(irq=%d) invalidation completed, vFPGA %d\n", irq, d->id);
    atomic_set(&d->wait_invldt, FLAG_SET);
    wake_up_interruptible(&d->waitqueue_invldt);
    break;

  case IRQ_PFAULT:
    dbg_info("(irq=%d) page fault, vFPGA %d\n", irq, d->id);
    irq_pf = kzalloc(sizeof(struct fpga_irq_pfault), GFP_KERNEL);
    BUG_ON(!irq_pf);

    irq_pf->d = d;
    fpga_read_irq_pfault(d, irq_pf);

    INIT_WORK(&irq_pf->work_pfault, fpga_pfault_handler);

    if (!queue_work(d->wqueue_pfault, &irq_pf->work_pfault)) {
      pr_err("could not enqueue a workqueue, page fault ISR");
    }
    break;

  case IRQ_NOTIFY:
    dbg_info("(irq=%d) notify, vFPGA %d\n", irq, d->id);
    irq_not = kzalloc(sizeof(struct fpga_irq_notify), GFP_KERNEL);
    BUG_ON(!irq_not);

    irq_not->d = d;
    fpga_read_irq_notify(d, irq_not);

    INIT_WORK(&irq_not->work_notify, fpga_notify_handler);

    if (!queue_work(d->wqueue_notify, &irq_not->work_notify)) {
      pr_err("could not enqueue a workqueue, notify ISR");
    }
    break;

  default:
    break;
  }

  // clear irq
  fpga_clear_irq(d);

  // unlock
  spin_unlock_irqrestore(&(d->irq_lock), flags);

  return IRQ_HANDLED;
}

/**
 * @brief Notify function handler
 *
 * @param work - work struct
 */
void fpga_notify_handler(struct work_struct *work) {
  int ret_val;
  struct fpga_dev *d;
  struct fpga_irq_notify *irq_not;

  irq_not = container_of(work, struct fpga_irq_notify, work_notify);
  BUG_ON(!irq_not);
  d = irq_not->d;

  mutex_lock(&user_notifier_lock[d->id][irq_not->cpid]);
  dbg_info("notify vFPGA %d, notval %d, cpid %d\n", d->id, irq_not->notval,
           irq_not->cpid);

  if (!user_notifier[d->id][irq_not->cpid]) {
    dbg_info("dropped notify event because there is no recpient\n");
    mutex_unlock(&user_notifier_lock[d->id][irq_not->cpid]);
    kfree(irq_not);
    return;
  }

// NOTE: Starting with Linux 6.8, the eventfd interface no longer increments by
// a user-provided value Instead, it always increments by 1 (and the function
// call also changed...)
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)
  eventfd_signal(user_notifier[d->id][irq_not->cpid]);
  ret_val = 1;
#else
  ret_val =
      eventfd_signal(user_notifier[d->id][irq_not->cpid], irq_not->notval);
#endif
  if (ret_val != irq_not->notval || ret_val == 0) {
    dbg_info("could not signal eventfd\n");
    mutex_unlock(&user_notifier_lock[d->id][irq_not->cpid]);
  }

  kfree(irq_not);
}

/**
 * @brief Page fault handler takes care of the page fault
 * and then restarts the mmu engine. Called from a workqueue
 *
 * @param work - work struct
 */
void fpga_pfault_handler(struct work_struct *work) {
  struct fpga_dev *d;
  struct fpga_irq_pfault *irq_pf;
  struct bus_drvdata *pd;
  pid_t hpid;
  int ret_val = 0;

  irq_pf = container_of(work, struct fpga_irq_pfault, work_pfault);
  BUG_ON(!irq_pf);
  d = irq_pf->d;
  pd = d->pd;

  d->n_pfaults++;

  // lock
  mutex_lock(&d->mmu_lock);

  // read page fault from device
  hpid = d->pid_array[irq_pf->cpid];
  dbg_info("page fault vFPGA %d, vaddr %llx, length %x, stream %d, cpid %d\n",
           d->id, irq_pf->vaddr, irq_pf->len, irq_pf->stream, irq_pf->cpid);

#ifdef HMM_KERNEL
  if (en_hmm)
    ret_val = mmu_handler_hmm(d, irq_pf->vaddr, irq_pf->len, irq_pf->cpid,
                              irq_pf->stream, hpid);
  else
#endif
    ret_val = mmu_handler_gup(d, irq_pf->vaddr, irq_pf->len, irq_pf->cpid,
                              irq_pf->stream, hpid);

  if (ret_val) {
    fpga_drop_irq_pfault(d, irq_pf->wr, irq_pf->cpid);
    pr_err("mmu handler error, vFPGA %d, err %d\n", d->id, ret_val);
    goto err_mmu;
  }

  // restart engine
  fpga_restart_mmu(d, irq_pf->wr, irq_pf->cpid);

  // unlock
  mutex_unlock(&d->mmu_lock);

  dbg_info("page fault vFPGA %d handled\n", d->id);

  kfree(irq_pf);

err_mmu:
  return;
}

////////////////// FUNCTION ADDED FOR FPGA-REGISTER
/// PROGRAMMING/////////////////////////

// internal information regarding the DMABuf to export
struct dma_buf_exporter_data {
  void *vaddr;   // virtual address of the CTRL registers memory area
  uint32_t size; // size of the area: see coyote_dev.h/FPGA_CTRL_SIZE
};

/**
 * @brief DMABuf exporter callback for dma_buf_dynamic_attach()
 *
 * @param dmabuf - the exported dmabuf
 * @param attachment - the corresponding dma_buf_attachment
 *
 */
int dma_buf_exporter_attach(struct dma_buf *dmabuf,
                            struct dma_buf_attachment *attachment) {
  dbg_info("executed\n");
  return 0;
}

/**
 * @brief DMABuf exporter callback for dma_buf_detach()
 *
 * @param dmabuf - the exported dmabuf
 * @param attachment - the corresponding dma_buf_attachment
 */
void dma_buf_exporter_detach(struct dma_buf *dmabuf,
                             struct dma_buf_attachment *attachment) {
  dbg_info("executed\n");
  return;
}

/**
 * @brief DMABuf exporter callback for dma_buf_map_attachment()
 *
 * @param attachment - the dma_buf_attachment for the exported dmabuf
 * @param dim - the data direction for DMA: see
 * https://www.kernel.org/doc/Documentation/DMA-API-HOWTO.txt for "DMA
 * Direction"
 */

/**
 * @brief DMABuf exporter callback used when all DMABuf importers close their
 * sessions.
 *
 * @param dmabuf - the exported dmabuf
 */
void dma_buf_exporter_release(struct dma_buf *dma_buf) {
  dbg_info("executed\n");

  // release internal memory
  if (dma_buf->priv != NULL) {
    kfree(dma_buf->priv);
    dma_buf->priv = NULL;
  }
  return;
}

struct sg_table *dma_buf_exporter_map(struct dma_buf_attachment *attachment,
                                      enum dma_data_direction dir) {
  struct sg_table *table;
  struct scatterlist *sgl;
  struct dma_buf_exporter_data *data;
  struct page *pages;
  int i, ret_val;

  // get internal data
  data = attachment->dmabuf->priv;
  if (!data) {
    pr_err("pointer to data is null\n");
    return -ENOMEM;
  }

  // allocate and build scattergather table

  dbg_info("allocating sg_table\n");

  table = kmalloc(sizeof(struct sg_table), GFP_KERNEL);
  if (!table) {
    pr_err("cannot allocate table\n");
    return -ENOMEM;
  }

  int num_pages = PAGE_ALIGN(data->size) / PAGE_SIZE;

  dbg_info("num_pages for CTRL region: %d\n", num_pages);

  if (sg_alloc_table(table, num_pages, GFP_KERNEL)) {
    kfree(table);
    pr_err("cannot allocate table, after kmalloc\n");
    return -ENOMEM;
  }

  sgl = table->sgl;

  dbg_info("building table\n");

  // This should be useless for our purpose
  //      #if LINUX_VERSION_CODE >= KERNEL_VERSION(5,9,0)
  //      ret_val = get_user_pages_fast((unsigned long)data->vaddr, num_pages,
  //      1, &pages);
  //  #else
  //      ret_val = get_user_pages_fast((unsigned long)data->vaddr, num_pages,
  //      1, &pages);
  //  #endif

  //     dbg_info("dma_buf_exporter_map(): retval = %d", ret_val);

  pgd_t *pgd;
  pmd_t *pmd;
  pte_t *pte;
  p4d_t *p4d;
  pud_t *pud;

  struct mm_struct *mm = current->mm;

  // find struct page * for CTRL memory area, as it can be done by using
  // internal Linux data structure
  for (i = 0; i < num_pages; i++) {
    spinlock_t *ptl;
    pgd = pgd_offset(mm, data->vaddr + i * PAGE_SIZE);
    p4d = p4d_offset(pgd, data->vaddr + i * PAGE_SIZE);
    pud = pud_offset(p4d, data->vaddr + i * PAGE_SIZE);
    pmd = pmd_offset(pud, data->vaddr + i * PAGE_SIZE);
    // pte = pte_offset_map_lock(mm, pmd, data->vaddr + i * PAGE_SIZE, &ptl);
    // pte = pte_offset_map(pmd, data->vaddr + i * PAGE_SIZE);
    pte = pte_offset_kernel(pmd, data->vaddr + i * PAGE_SIZE);
    if (pte_present(*pte) == 0) {
      pte_unmap(pte);
      dbg_info("pte_offset_kernel crashed\n");
      continue;
    }

    struct page *pag = pte_page(*pte);

    sg_set_page(sgl, pag, PAGE_SIZE, 0);

    dbg_info(
        "vaddr: %lx is valid ? %d\n", data->vaddr + i * PAGE_SIZE,
        virt_addr_valid(
            data->vaddr +
            i * PAGE_SIZE)); // Linux says this register is not a valid virtual
                             // address, I am not sure if this is an issue

    dma_addr_t addr = dma_map_page(
        attachment->dev, pag, 0, PAGE_SIZE,
        DMA_BIDIRECTIONAL); // map CTRL register area into GPU memory
    sgl->dma_address = addr;
    sgl->dma_length = PAGE_SIZE;
    sgl->length = PAGE_SIZE;
    sgl->offset = (unsigned int)((unsigned long)(data->vaddr + i * PAGE_SIZE) &
                                 (unsigned int)~PAGE_MASK);
    dbg_info("dma_address = %lx, dma_length = %lx, dma_offset = %lx\n",
             sgl->dma_address, sgl->dma_length, sgl->offset);
    sg_dma_mark_bus_address(sgl);
    sgl = sg_next(sgl);
    // pte_unmap_unlock(pte, ptl);
  }

  dbg_info("terminated\n");

  return table;
}

/**
 * @brief DMABuf exporter callback for dma_buf_unmap_attachment()
 *
 * @param attachment - the dma_buf_attachment for the exported dmabuf
 * @param table - the scattergather table of the mapping
 * @param dim - the data direction for DMA: see
 * https://www.kernel.org/doc/Documentation/DMA-API-HOWTO.txt for "DMA
 * Direction"
 */
void dma_buf_exporter_unmap(struct dma_buf_attachment *attachment,
                            struct sg_table *table,
                            enum dma_data_direction dir) {
  dbg_info("unmapping dma_buf\n");
  dma_unmap_sg(attachment->dev, table->sgl, table->nents, dir);
  sg_free_table(table);
  kfree(table);
  dbg_info("terminated\n");
  return;
}

int dma_buf_export_close(uint32_t dma_buf_fd) {

  dbg_info("dma_buf_export_close() terminated\n");

  return 0;
}

// Data structure required to associated the DMABuf exporter with its callbacks
const struct dma_buf_ops exporter_ops = {.attach = dma_buf_exporter_attach,
                                         .detach = dma_buf_exporter_detach,
                                         .map_dma_buf = dma_buf_exporter_map,
                                         .unmap_dma_buf =
                                             dma_buf_exporter_unmap,
                                         .release = dma_buf_exporter_release};

unsigned long dma_buf_export_regs(struct fpga_dev *d, void *vaddr,
                                  uint32_t size) {

  struct dma_buf *buf;
  struct dma_buf_exporter_data *data;

  dbg_info("allocating dma_buf data\n");

  data = kmalloc(sizeof(struct dma_buf_exporter_data), GFP_KERNEL);
  if (!data) {
    dbg_info("allocation of data failed\n");
    return -ENOMEM;
  }

  data->vaddr = vaddr;
  data->size = size;

  DEFINE_DMA_BUF_EXPORT_INFO(export_info);

  export_info.owner = THIS_MODULE;
  export_info.ops = &exporter_ops;
  export_info.size = size;
  export_info.flags = O_CLOEXEC;
  export_info.resv = NULL;
  export_info.priv = data;

  // export DMABuf
  dbg_info("exporting dma_buf\n");
  buf = dma_buf_export(&export_info);

  if (IS_ERR(buf)) {
    pr_err("failed to export dma_buf\n");
    goto err;
  }

  // open DMABuf and retrieve its file descriptor
  unsigned long fd = dma_buf_fd(buf, O_CLOEXEC);

  dbg_info("terminated\n");

  return fd;

err:

  kfree(data);

  return -ENOMEM;
}