obj-m := coyote_drv.o
coyote_drv-objs:= fpga_drv.o fpga_fops.o fpga_pops.o fpga_hw.o fpga_sysfs.o fpga_uisr.o fpga_dev.o fpga_gup.o fpga_hmm.o fpga_mmu.o fpga_pr.o pci/pci_dev.o eci/eci_dev.o

KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

ROOT := $(dir $(M))
XILINXINCLUDE := -I$(ROOT)../include -I$(ROOT)/include

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions *.order *.symvers *.mod *mod.dwo *.dwo .??* pci/.??* pci/*.o eci/.??* eci/*.o
