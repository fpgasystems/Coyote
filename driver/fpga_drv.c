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

#include "fpga_drv.h"

int cyt_arch = CYT_ARCH_PCI;
char *ip_addr_q0 = "0B01D4D1";
char *ip_addr_q1 = "0B01D4D2";
char *mac_addr_q0 = "000A35029DE5";
char *mac_addr_q1 = "000A35029DE6";
long int eost = 1000000;

module_param(cyt_arch, int, S_IRUSR);
MODULE_PARM_DESC(cyt_arch, "target architecture");
module_param(ip_addr_q0, charp, 0000);
MODULE_PARM_DESC(ip_addr_q0, "ip address QSFP0 (hex)");
module_param(ip_addr_q1, charp, 0000);
MODULE_PARM_DESC(ip_addr_q1, "ip address QSFP1 (hex)");
module_param(mac_addr_q0, charp, 0000);
MODULE_PARM_DESC(mac_addr_q0, "mac address QSFP0 (hex)");
module_param(eost, long, 0000);
MODULE_PARM_DESC(eost, "EOS time");

static int __init coyote_init(void) 
{
    int ret_val = 0;

    if(cyt_arch == CYT_ARCH_PCI) {
        pr_info("loading: Coyote PCIe driver ...\n");
        ret_val = pci_init();
    } else if(cyt_arch == CYT_ARCH_ECI) {
        pr_info("loading: Coyote ECI driver ...\n");
        ret_val = eci_init();
    } else {
        pr_err("architecture not supported\n");
        return -ENODEV;
    }

    return ret_val;
}

static void __exit coyote_exit(void) 
{
    pr_info("removal: Coyote driver ...\n");

    if(cyt_arch == CYT_ARCH_PCI) {
        pci_exit();
    } else if(cyt_arch == CYT_ARCH_ECI) {
        eci_exit();
    }
}

module_init(coyote_init);
module_exit(coyote_exit);

/* --------------------------------------------------------------------------- */
MODULE_DESCRIPTION("Coyote driver.");
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Dario Korolija <dario.korolija@inf.ethz.ch");