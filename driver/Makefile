obj-m := fpga_drv.o

KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

ROOT := $(dir $(M))
XILINXINCLUDE := -I$(ROOT)../include -I$(ROOT)/include

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	rm -rf *.o *~ core .depend .*.cmd *.ko *.mod.c .tmp_versions *.order *.symvers *.dwo *.mod *.mod.dwo
