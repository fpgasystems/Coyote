/**
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

#ifndef __ECI_DEV_H__
#define __ECI_DEV_H__

#include "../coyote_dev.h"
#include "../vfpga_dev.h"

/*
███████╗ ██████╗██╗
██╔════╝██╔════╝██║
█████╗  ██║     ██║
██╔══╝  ██║     ██║
███████╗╚██████╗██║
╚══════╝ ╚═════╝╚═╝
*/

/* Physical address (ECI) */
#define IO_PHYS_ADDR 0x900000000000UL

/* Probe */
int shell_eci_init(struct bus_driver_data *d);
void shell_eci_remove(struct bus_driver_data *d);
int eci_init(void);
void eci_exit(void);

#endif // ECI device