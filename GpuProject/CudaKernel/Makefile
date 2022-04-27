obj-m += cuda_kernel.o
ccflags-y := -std=gnu99 -Wno-declaration-after-statement

KBUILD_EXTRA_SYMBOLS := $(PWD)/../../NVIDIA-Linux-x86_64-460.67/kernel/Module.symvers

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean