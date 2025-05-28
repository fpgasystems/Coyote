KERNELDIR ?= /lib/modules/$(shell uname -r)/build

obj-m := coyote-guest.o
coyote-guest-objs := guest_drv.o guest_fops.o guest_pci.o guest_mm.o guest_irq.o

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean