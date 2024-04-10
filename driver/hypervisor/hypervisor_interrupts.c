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

#include "hypervisor_interrupts.h"

/**
 * @brief Set the up msix header.
 *  This function will place the MSIX capapbility in the pci config space
 *  to communicate to the guest vm that we this emulated device supports
 *  MSIX interrupts. The next pointer of the capapbility is set to zero
 *  and has to be set by the caller if there are more capabilities this
 *  one should point to.
 *
 * @param cfg Pointer to the pci config space
 * @param offset offset from the the start of the config region where the cap should
 *  be placed.
 * @param regs Number of interrupts that should be supported
 */
void set_up_msix_header(struct pci_config_space *cfg, uint8_t offset, uint16_t regs)
{
    struct msix_cap_header *header;

    BUG_ON(regs > 2048);

    header = (struct msix_cap_header *)((uint8_t *)cfg + offset);

    header->cap_id = 0x11;
    // explictly set to null, if this is not the last element, this will be handled by the caller
    header->next_pointer = 0x00;

    // message control
    header->message_control = (regs - 1) & GENMASK(10, 0);
    header->message_control |= (0x0 & GENMASK(14, 11));
    header->message_control |= 0 & BIT(15);

    // message upper address
    header->mua = 0x0;

    // table offset
    // lower 3 bits are for identfying the bar (BAR2)
    header->table_offset = 2 & GENMASK(2, 0);
    // The table located at an 0x2000 offset of the BAR2 region
    header->table_offset |= 0x2000 & GENMASK(31, 3);

    // pba table
    header->pba_offset = 2 & GENMASK(2, 0);
    header->pba_offset |= 0x3000 & GENMASK(31, 3);
}

/**
 * @brief Emulating writes to the msix header of the
 * pci device. This happens according to the
 * pci documentation.
 *
 * @param cfg pointer to the start of the capability
 * @param offset into the capability
 * @param val val that is to be written
 * @param count number of bytes to write
 * @return size_t number of bytes actually written (or error code)
 */
size_t write_to_msix_header(void *cfg, uint8_t offset, uint32_t val, uint8_t count)
{
    struct msix_cap_header *header;

    header = (struct msix_cap_header *)cfg;
    switch (offset)
    {
    case 0x2: // message control
    {
        if (count != 2)
        {
            return -EFAULT;
        }

        header->message_control = val & BIT(15);
        return count;
    }
    case 0x04:
    {
        if (count != 4)
        {
            return -EFAULT;
        }

        header->mua = val;
        return count;
    }
    default:
    {
        return -EFAULT;
    }
    }
}

/**
 * @brief Unsets all handlers for all interrupts.
 *  Should only be used in an emulated manner since
 *  this function is only unsetting internal management structs
 *  and could lead to problems if it does not match the state of
 *  the vm.
 *
 * @param d mediated fpga device
 */

void msix_unset_all_interrupts(struct m_fpga_dev *d)
{
    int i;
    for (i = 0; i < NUM_INTERRUPTS; i++)
    {
        // Check if interrupt was ever registered
        if (d->msix_vector[i].eventfd != -1)
        {
            // Only put the eventfd context if we got it before
            if (!IS_ERR_OR_NULL(d->msix_vector[i].ctx))
            {
                eventfd_ctx_put(d->msix_vector[i].ctx);
            }

            // Invalidate
            d->msix_vector[i].eventfd = -1;
        }
    }
}

/**
 * @brief Handles the VFIO ioctl call. Have a look at the documentation
 * of VFIO for more information about the vfio_irq_set struct, it contains
 * framework specific fields.
 *
 * The following cases are supported:
 *
+-------------------------------------------------------------------+----------------------------------+
|                               flags                               |              action              |
+-------------------------------------------------------------------+----------------------------------+
| VFIO_IRQ_SET_ACTION_TRIGGER & VFIO_IRQ_SET_DATA_NONE & count == 0 | unset all interrupts             |
| VFIO_IRQ_SET_ACTION_TRIGGER & VFIO_IRQ_SET_DATA_EVENTFD           | set interrupt with given eventfd |
| VFIO_IRQ_SET_ACTION_MASK || VFIO_IRQ_SET_ACTION_UNMASK            | Mask interrupt                   |
+-------------------------------------------------------------------+----------------------------------+
 * this function should only called from the SET_INTERRUPT vfio ioctl. For more information consult the
 * VFIO documentation.
 *
 * @param d mediated fpga device
 * @param irq_set irq_set struct passed from userspace from the vfio ioctl
 * @return int error code
 */
int handle_set_irq_msix(struct m_fpga_dev *d, struct vfio_irq_set *irq_set)
{
    int i;
    int ret_val;
    int start, end;
    int mask_val;

    ret_val = 0;

    // Disable all interrupts
    if ((irq_set->flags & VFIO_IRQ_SET_ACTION_TRIGGER) && (irq_set->flags & VFIO_IRQ_SET_DATA_NONE) && (irq_set->count == 0))
    {
        msix_unset_all_interrupts(d);
    }

    // Set eventfd
    else if ((irq_set->flags & VFIO_IRQ_SET_ACTION_TRIGGER) && (irq_set->flags & VFIO_IRQ_SET_DATA_EVENTFD))
    {
        // start and end allows to only specify a range of interrupts to set
        start = irq_set->start;
        end = start + irq_set->count;

        for (i = start; i < end; i++)
        {
            // There is already an interrupt, deregister
            if (d->msix_vector[i].eventfd != -1 && !IS_ERR_OR_NULL(d->msix_vector[i].ctx))
            {
                eventfd_ctx_put(d->msix_vector[i].ctx);
            }

            // Register the interrupt and get the eventfd context
            d->msix_vector[i].eventfd = irq_set->data[i - start];
            d->msix_vector[i].ctx = eventfd_ctx_fdget(irq_set->data[i - start]);
            if (IS_ERR_OR_NULL(d->msix_vector[i].ctx))
            {
                dbg_info("Failed to get eventfd ctx, fd: %d, ctx: %p", d->msix_vector[i].eventfd, d->msix_vector[i].ctx);
            }
            dbg_info("Set interrupt %d to %d, ctx: %p\n", i, irq_set->data[i - start], d->msix_vector[i].ctx);
        }
    }

    // Mask interrupts
    else if ((irq_set->flags & VFIO_IRQ_SET_ACTION_MASK) || (irq_set->flags & VFIO_IRQ_SET_ACTION_UNMASK))
    {
        mask_val = (irq_set->flags & VFIO_IRQ_SET_ACTION_MASK) ? 1 : 0;
        // start and end allow to mask a range of interrupts
        start = irq_set->start;
        end = start + irq_set->count;

        // If data none is set, then all interrupts should be set accordingly to the
        // mask or unmask flask
        if (irq_set->flags & VFIO_IRQ_SET_DATA_NONE)
        {
            for (i = start; i < end; i++)
            {
                d->msix_vector[i].masked = mask_val;
                dbg_info("Set %d to %s\n", i, (mask_val ? "masked" : "unmasked"));
            }
        }
        // Else, we have a bool array and the interrupts should be masked based on the 
        // values in this array.
        else
        {
            for (i = start; i < end; i++)
            {
                if (irq_set->data[i - start])
                {
                    d->msix_vector[i].masked = mask_val;
                    dbg_info("Set %d to %s\n", i, (mask_val ? "masked" : "unmasked"));
                }
            }
        }
    }

    else
    {
        dbg_info("Invalid args\n");
        return -EINVAL;
    }

    return ret_val;
}

/**
 * @brief forwards an interrupt to the vm. Uses the eventfd context
 * stored in the passed argument. This function should only 
 * be called when currently handling an interrupt!
 * 
 * @param inter msix interrupt storage. 
 * @return uint64_t eventfd_signal value. Can be discarded for our use.
 */
inline uint64_t fire_interrupt(struct msix_interrupt *inter)
{
    if (IS_ERR_OR_NULL(inter->ctx))
    {
        pr_info("Failed ot get context for eventfd %d", inter->eventfd);
        return -1;
    }

    //  dbg_info("Firing interrupt!\n");
    return eventfd_signal(inter->ctx, 0);
}

/**
 * @brief Hypervisor version of the tlb miss interrupt
 * service routine. This function uses the same registers from the
 * fpga to read the faulting address. Instead of handling the page fault
 * it is forwarded to the vm to be handled there. This is because 
 * the fault address will be a guest virtual address and cannot be 
 * resolved from the hypervisor. 
 * 
 * @param irq interrupt request number
 * @param dev_id pointer to device, given then registered the interrupt
 * @return irqreturn_t 
 */
irqreturn_t hypervisor_tlb_miss_isr(int irq, void *dev_id)
{
    struct m_fpga_dev *md;
    unsigned long flags;
    int32_t cpid;
    struct fpga_dev *d;
    struct bus_drvdata *pd;
    uint64_t tmp;

    dbg_info("(irq=%d) page fault ISR\n", irq);
    BUG_ON(!dev_id);

    d = (struct fpga_dev *)dev_id;
    BUG_ON(!d);

    pd = d->pd;
    BUG_ON(!pd);

    // lock
    spin_lock_irqsave(&(d->lock), flags);

    // read page fault
    // tmp cointains the cpid.
    if (pd->en_avx)
    {
        tmp = d->fpga_cnfg_avx->len_miss;
        cpid = (int32_t)HIGH_32(tmp);
    }
    else
    {
        tmp = d->fpga_cnfg->len_miss;
        cpid = (int32_t)HIGH_32(tmp);
    }

    // Get the medaited device by looking up the cpid 
    md = d->vdevs[cpid];
    BUG_ON(!md);

    // Fire interrupt in vm
    fire_interrupt(&md->msix_vector[0]);
    // dbg_info("Interrupt forwarded to vm!\n");

    // unlock
    spin_unlock_irqrestore(&(d->lock), flags);

    return IRQ_HANDLED;
}