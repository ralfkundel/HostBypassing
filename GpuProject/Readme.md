# GPU host bypassing

## General Workflow (GPU)
1. Compile and load the special CUDA kernel module to enable GPU memory exposing. see: [GPU readme](CudaKernel/Readme.md)
2. compile the CUDA code for the GPU according to its readme.
3. Load the igb_uio kernel module for the NIC you want to use. Update the memory addresses in the sample DPDK app and compile it.
4. start a) the CUDA application and b) the DpdkDriver in parallel (this order).

## Compile the cuda code
```
cd CudaSrc
make

```

## Run
after all components are compiled, the dpdk NIC is bound to the dpdk kernel module and the CUDA kernel module is load (may require sudo permissions):
```
./CudaSrc/main
./DpdkDriver/build/dpdk_init
```

