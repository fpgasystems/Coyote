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

#include "coyote_driver_top.h"

/*
* Variables exposed to the user when inserting the driver
* These values can be (and in some cases should be, e.g. IP & MAC) modified by the user
*/

/// FPGA IP address; on the ETHZ HACC it can be obtained from sgutil
char *ip_addr = "0B01D4D1";
module_param(ip_addr, charp, 0000);
MODULE_PARM_DESC(ip_addr, "FPGA IP address (hex)");

/// FPGA MAC address; on the ETHZ HACC it can be obtained from sgutil
char *mac_addr = "000A35029DE5";
module_param(mac_addr, charp, 0000);
MODULE_PARM_DESC(mac_addr, "FPGA MAC address (hex)");

/// Enable unified memory, using Linux heteregenous memory management
/// NOTE: It need to be enabled both during driver comilation by passing -DHMM_KERNEL=1 and driver insertion (insmod)
bool en_hmm = false;
module_param(en_hmm, bool, 0000);
MODULE_PARM_DESC(en_hmm, "Enable HMM");

/// TODO: Comment OR depracate the following two if not used
long int eost = 1000000;
module_param(eost, long, 0000);
MODULE_PARM_DESC(eost, "EOS time");

char *config_fname = "";
module_param(config_fname, charp, 0644);
MODULE_PARM_DESC(config_fname, "Device configuration file");

MODULE_IMPORT_NS(DMA_BUF);

/** 
 * Top-level function of the Coyote driver, called when the driver is inserted.
 * This function simply calls the pci_init() function, which is responsible
 * for setting up the FPGA, vFPGAs, memory mappings etc. (see the documentation)
 * 
 * In the past, we used to support Enzian (ECI) but it has been depracated as of 2024.
 * If you would like to add support for Enzian, reach out to us on GitHub or check 
 * how the code use to look before, with the diff commit being: <insert commit here later>
*/
static int __init coyote_init(void) {
    pr_info("Loading Coyote PCIe driver...\n");
    return pci_init();
}

/** 
 * Reverse of the init function, called when the driver is removed
 * Handles device clean-up, memory freeing etc. See the documentation in pci_dev
*/
static void __exit coyote_exit(void) {
    pr_info("Removing Coyote driver...\n");
    pci_exit();
}

module_init(coyote_init);
module_exit(coyote_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Coyote driver");
MODULE_AUTHOR("Systems Group, ETH Zurich <https://github.com/fpgasystems>");
