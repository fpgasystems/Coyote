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

#ifndef __FPGA_DEV_H__
#define __FPGA_DEV_H__

#include "coyote_dev.h"
#include "fpga_pops.h"
#include "fpga_fops.h"
#include "fpga_sysfs.h"

/*
██████╗ ███████╗██╗   ██╗
██╔══██╗██╔════╝██║   ██║
██║  ██║█████╗  ██║   ██║
██║  ██║██╔══╝  ╚██╗ ██╔╝
██████╔╝███████╗ ╚████╔╝ 
╚═════╝ ╚══════╝  ╚═══╝  
*/

/* Read deployment config */
int read_shell_config(struct bus_drvdata *d);

/* Allocate initial card resources */
int alloc_card_resources(struct bus_drvdata *d);
void free_card_resources(struct bus_drvdata *d);

/* Spinlock init */
void init_spin_locks(struct bus_drvdata *d);

/* Create sysfs entry */
int create_sysfs_entry(struct bus_drvdata *d);
void remove_sysfs_entry(struct bus_drvdata *d);

/* Initialize devices */
int init_char_fpga_devices(struct bus_drvdata *d, dev_t dev);
void free_char_fpga_devices(struct bus_drvdata *d);
int init_char_pr_device(struct bus_drvdata *d, dev_t dev);
void free_char_pr_device(struct bus_drvdata *d);

/* Devices */
int init_fpga_devices(struct bus_drvdata *d);
void free_fpga_devices(struct bus_drvdata *d);
int init_pr_device(struct bus_drvdata *d);
void free_pr_device(struct bus_drvdata *d);


#endif // FPGA DEV