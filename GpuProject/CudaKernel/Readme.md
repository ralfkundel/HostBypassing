# How to compile the Cuda Kernel

## download and install the cuda driver
- nvidia driver https://www.nvidia.de/Download/index.aspx?lang=de (tested with 460.67)
- cuda https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html (tested with 11.2)

## build the kernel module
1. extract the downloaded nvidia driver
```
./NVIDIA-Linux-x86_64-<version>.run -x
```
2. compile the nvidia kernel:
```
cd NVIDIA-Linux-x86_64-460.67/kernel
make
```
3. update path `KBUILD_EXTRA_SYMBOLS := $(PWD)/<path-to-driver>/NVIDIA-Linux-x86_64-<version>/kernel/Module.symvers` in the Makefile in the CudaKernel directory

4. run make
```
make
```

5. load the compiled kernel module
```
rmmod cuda_kernel.ko  #to avoid old kernels - normally not needed
insmod cuda_kernel.ko
```
