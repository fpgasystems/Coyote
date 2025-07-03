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
