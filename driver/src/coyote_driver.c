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

#include "coyote_driver.h"

/*
* Variables exposed to the user when inserting the driver
* These values can be (and in some cases should be, e.g. IP & MAC) modified by the user
*/

/// FPGA IP address; on the ETHZ HACC it can be obtained from hdev
char *ip_addr = "0B01D4D1";
module_param(ip_addr, charp, 0000);
MODULE_PARM_DESC(ip_addr, "FPGA IP address (hex)");

/// FPGA MAC address; on the ETHZ HACC it can be obtained from hdev
char *mac_addr = "000A35029DE5";
module_param(mac_addr, charp, 0000);
MODULE_PARM_DESC(mac_addr, "FPGA MAC address (hex)");

/// End-of-start-up time (in clock cycles); after which reconfiguration is assumed completed
/// Primarily needed on the U55C, which has no mechanism to detect when the bitstream has been loaded
long int eost = 1000000;
module_param(eost, long, 0000);
MODULE_PARM_DESC(eost, "EOS time");

/// Enable (true) unified memory, using Linux heteregenous memory management; alternative is to use shared virtual memory implemented in get_user_pages
/// NOTE: HMM has been deprecated in Coyote, but for those interested in using it, the source code can be foud in LEGACY (unlikely to work without some fixes etc.)
/// NOTE: If used, it need to be enabled both during driver comilation by passing -DHMM_KERNEL=1 and driver insertion (insmod)
bool en_hmm = false;
module_param(en_hmm, bool, 0000);
MODULE_PARM_DESC(en_hmm, "Enable HMM");

// Include the DMA Buffer mechanism to enable peer-to-peer DMA transfers between FPGAs and GPUs
MODULE_IMPORT_NS(DMA_BUF);

static int __init coyote_init(void) {
    pr_info("Loading Coyote PCIe driver...\n");
    return pci_init();
}

static void __exit coyote_exit(void) {
    pr_info("Removing Coyote driver...\n");
    pci_exit();
}

module_init(coyote_init);
module_exit(coyote_exit);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("Coyote device driver");
MODULE_AUTHOR("Systems Group, ETH Zurich <https://github.com/fpgasystems>");
