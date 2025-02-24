# Copyright (c) 2021-2024, Systems Group, ETH Zurich
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its contributors
# may be used to endorse or promote products derived from this software
# without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# obj-m specifies the final Linux module name for the driver; in this case it is coyote_driver.ko
obj-m := coyote_driver.o

# But in order to build the driver, we need to build all of these; the name should match the C files, but replace .c with .o
coyote_driver-objs := coyote_driver_top.o 
coyote_driver-objs += src/reconfig/reconfig_hw.o 
coyote_driver-objs += src/reconfig/reconfig_isr.o
coyote_driver-objs += src/reconfig/reconfig_mem.o
coyote_driver-objs += src/reconfig/reconfig_ops.o

coyote_driver-objs += src/fpga_fops.o 
coyote_driver-objs += src/fpga_hw.o 
coyote_driver-objs += src/fpga_sysfs.o 
coyote_driver-objs += src/fpga_uisr.o 
coyote_driver-objs += src/fpga_dev.o 
coyote_driver-objs += src/fpga_gup.o 
coyote_driver-objs += src/fpga_hmm.o 
coyote_driver-objs += src/fpga_mmu.o 
coyote_driver-objs += src/pci_dev.o

# Location of all the header files to be included during compilation
EXTRA_CFLAGS := -std=gnu11 -Wno-declaration-after-statement -I$(PWD)/include -I$(PWD)/include/reconfig -I$(PWD)/include/vfpga 

# Location of the Linux kernel header files, we will be building within the context of the kernel's Makefile (the flag -C sets the context)
# This gives us access to all the Linux kernel functionality, typically implemented in <linux/*.h> and <asm/*.h>
KERNELDIR ?= /lib/modules/$(shell uname -r)/build

# Current working directory (most likely Coyote/driver/)
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.ko *.o  *.mod.c .tmp_versions *.order *.symvers *.mod *mod.dwo *.dwo  .*.cmd .*.o.cmd 
	rm -rf src/*.o src/*.cmd src/.*.cmd src/.*.o.cmd
	rm -rf src/vfpga/*.o src/vfpga/*.cmd src/vfpga/.*.cmd src/vfpga/.*.o.cmd
	rm -rf src/reconfig/*.o src/reconfig/*.cmd src/reconfig/.*.cmd src/reconfig/.*.o.cmd
