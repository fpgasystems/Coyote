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

/**
 * @file coyote_driver.h
 * @brief Top-level file of the Coyote driver; entry and exit point.
 */

#ifndef _COYOTE_DRIVER_H_
#define _COYOTE_DRIVER_H_

#include "pci_xdma.h"
#include "coyote_defs.h"
#include "coyote_setup.h"

/** 
 * Top-level function of the Coyote driver, called when the driver is inserted.
 * This function simply calls the pci_init() function, which is responsible
 * for setting up the FPGA, vFPGAs, memory mappings etc. (see the documentation)
 * 
 * NOTE: In the past, we used to support Enzian (ECI) but it has been deprecated as of 2024.
 * If you would like to add support for Enzian, reach out to us on GitHub or check 
 * how the code use to look before, with the diff commit being: 4555431cf251100e2f16255f7f49e9f02ddfb96d
 */
static int __init coyote_init(void);

/** 
 * Reverse of the init function, called when the driver is removed
 * Handles device clean-up, memory freeing etc. See the documentation in pci_dev
 */
static void __exit coyote_exit(void);

#endif // _COYOTE_DRIVER_H_
