/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
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

#ifndef __PCI_DEV_H__
#define __PCI_DEV_H__

#include "../coyote_dev.h"
#include "../fpga_dev.h"

/*
██████╗  ██████╗██╗███████╗
██╔══██╗██╔════╝██║██╔════╝
██████╔╝██║     ██║█████╗  
██╔═══╝ ██║     ██║██╔══╝  
██║     ╚██████╗██║███████╗
╚═╝      ╚═════╝╚═╝╚══════╝
*/     

/* Interrupts */
int assign_dev_id(struct bus_drvdata *d);
int read_dev_config(const char *fname);
void channel_interrupts_enable(struct bus_drvdata *d, uint32_t mask);
void channel_interrupts_disable(struct bus_drvdata *d, uint32_t mask);
void user_interrupts_enable(struct bus_drvdata *d, uint32_t mask);
void user_interrupts_disable(struct bus_drvdata *d, uint32_t mask);
void pr_interrupt_enable(struct bus_drvdata *d);
void pr_interrupt_disable(struct bus_drvdata *d);
uint32_t read_interrupts(struct bus_drvdata *d);
uint32_t build_vector_reg(uint32_t a, uint32_t b, uint32_t c, uint32_t d);
void write_msix_vectors(struct bus_drvdata *d);
int msix_irq_setup(struct bus_drvdata *d,  struct pci_dev *pdev, bool pr_flow);
int irq_setup(struct bus_drvdata *d, struct pci_dev *pdev, bool pr_flow);
void irq_teardown(struct bus_drvdata *d, bool pr_flow);
int msix_capable(struct pci_dev *pdev, int type);
int pci_check_msix(struct bus_drvdata *d, struct pci_dev *pdev);
void pci_enable_capability(struct pci_dev *pdev, int cmd);

/* Engine */
uint32_t get_engine_channel_id(struct engine_regs *regs);
uint32_t get_engine_id(struct engine_regs *regs);
void engine_destroy(struct bus_drvdata *d, struct xdma_engine *engine);
void remove_engines(struct bus_drvdata *d);
void engine_alignments(struct xdma_engine *engine);
struct xdma_engine *engine_create(struct bus_drvdata *d, int offs, int c2h, int channel);
int probe_for_engine(struct bus_drvdata *d, int c2h, int channel);
int probe_engines(struct bus_drvdata *d);
uint32_t engine_status_read(struct xdma_engine *engine);
//#define XDMA_WBACK
#ifdef XDMA_WBACK
void engine_writeback_teardown(struct bus_drvdata *d, struct xdma_engine *engine);
int engine_writeback_setup(struct bus_drvdata *d, struct xdma_engine *engine);
#endif 

/* BARs */
int map_single_bar(struct bus_drvdata *d, struct pci_dev *pdev, int idx, int curr_idx);
void unmap_bars(struct bus_drvdata *d, struct pci_dev *pdev);
int map_bars(struct bus_drvdata *d, struct pci_dev *pdev);

/* Regions */
int request_regions(struct bus_drvdata *d, struct pci_dev *pdev);

/* Probe */
int shell_pci_init(struct bus_drvdata *d);
void shell_pci_remove(struct bus_drvdata *d);
int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id);
void pci_remove(struct pci_dev *pdev);

/* Init */
int pci_init(void);
void pci_exit(void);

#endif // PCIe device