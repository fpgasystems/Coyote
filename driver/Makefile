###############################################################################
# Copyright (c) 2025,  Systems Group, ETH Zurich
# All rights reserved.
# 
# This file is part of the Coyote device driver for Linux.
# Coyote can be found at: https://github.com/fpgasystems/Coyote
#
# This source code is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# The full GNU General Public License is included in this distribution in
# the file called "COPYING". If not found, a copy of the GNU General Public  
# Licence can be found <https://www.gnu.org/licenses/>.
###############################################################################

# Target output name
obj-m := coyote_driver.o

# Pre-requisites that need to be compiled for the Coyote driver
coyote_driver-objs := src/coyote_driver.o 
coyote_driver-objs += src/coyote_setup.o 
coyote_driver-objs += src/coyote_sysfs.o 

coyote_driver-objs += src/platform/pci_xdma.o
coyote_driver-objs += src/platform/pci_util.o

coyote_driver-objs += src/reconfig/reconfig_hw.o 
coyote_driver-objs += src/reconfig/reconfig_isr.o
coyote_driver-objs += src/reconfig/reconfig_mem.o
coyote_driver-objs += src/reconfig/reconfig_ops.o

coyote_driver-objs += src/vfpga/vfpga_gup.o 
coyote_driver-objs += src/vfpga/vfpga_hw.o 
coyote_driver-objs += src/vfpga/vfpga_isr.o 
coyote_driver-objs += src/vfpga/vfpga_ops.o 
coyote_driver-objs += src/vfpga/vfpga_uisr.o 

# Location of the Linux kernel header files, we will be building within the context of the kernel's Makefile (the flag -C sets the context)
# This gives us access to all the Linux kernel functionality, typically implemented in <linux/*.h> and <asm/*.h>
KERNELDIR ?= /lib/modules/$(shell uname -r)/build

BUILD_DIR := $(shell pwd)/build
EXTRA_CFLAGS := -std=gnu11 -Wno-declaration-after-statement -I$(PWD)/include -I$(PWD)/include/reconfig -I$(PWD)/include/vfpga -I$(PWD)/include/platform 

# To avoid polluting the source files with a bunch of build (*.o, *.mod etc.) files, the source files are temporarily copied to the build folder for compilation
all:
	mkdir -p $(BUILD_DIR)
	cp Makefile $(BUILD_DIR)
	cp -r src/ $(BUILD_DIR)
	cp -r include/ $(BUILD_DIR)
	$(MAKE) -C $(KERNELDIR) M=$(BUILD_DIR) modules
	rm -rf $(BUILD_DIR)/src $(BUILD_DIR)/include $(BUILD_DIR)/Makefile

clean:
	rm -rf build
