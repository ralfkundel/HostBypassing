# Host Bypassing from DPDK NICs to FPGAs via PCIe

For detailed explanation of FPGA-based host bypassing: [Paper](https://ieeexplore.ieee.org/document/9691977)
For detailed explanation of GPU-based host bypassing: [Paper](https://www.kom.tu-darmstadt.de/papers/KAM+22.pdf)

The project consists of three parts:
1. a FPGA project. see: [FPGA readme](FpgaProject/Readme.md)
2. a GPU Project. see: [GPU readme](GpuProject/Readme.md)
3. a modified version of DPDK for enabling host bypassing: [DPDK readme](DpdkProject/Readme.md)

## General Workflow (FPGA)
1. build the FPGA project according to its readme and load the FPGA design on the FPGA. see: [FPGA readme](FpgaProject/Readme.md)
2. reboot the server. This is needed, as the PCIe-configuration of the FPGA has changed.
3. load any kernel module for the FPGA. This is not used at all but needed to make the FPGA physical address space accessible and allow the FPGA to write on the registers of the NIC (bus master). for details:  [Loading the FPGA kernel module](#kernelload)
4. Load the igb_uio kernel module for the NIC you want to use. Update the memory addresses in the sample DPDK app and compile it and start it. for details: [DPDK readme](DpdkProject/Readme.md)

### <a name="kernelload"></a> Loading the FPGA kernel module
We recomend the use of the IGB_UIO kernel module which wille be compiled by the dpdk library anyway. Any other kernel module, supporting bus mastering, should work as well.
For loading the kernel Module (assuming the FPGA PCIe bus address to be 0000:65:00.0):
```
echo "10ee 9038" > /sys/bus/pci/drivers/igb_uio/new_id
# if this is not working, execute the steps in the dpdk readme first to load the igb_uio kernel module
```
and if needed for unbinding/rebinding:
```
echo -n 0000:65:00.0 > /sys/bus/pci/drivers/igb_uio/unbind
echo -n 0000:65:00.0 > /sys/bus/pci/drivers/igb_uio/bind
```

## General Workflow (GPU)
1. Compile and load the special CUDA kernel module to enable GPU memory exposing. see: [GPU readme](GpuProject/CudaKernel/Readme.md)
2. compile the CUDA code for the GPU according to its readme. see: [GPU readme](GpuProject/Readme.md)
3. Load the igb_uio kernel module for the NIC you want to use. Update the memory addresses in the sample DPDK app and compile it and start it. for details: [DPDK readme](DpdkProject/Readme.md)
4. start a) the CUDA application and b) the DpdkDriver in parallel (this order).

## Supported NICs
Currently, the following Network Interface Cards are supported:

* Intel 82599

## Tested GPUs

* NVIDIA Quadro RTX 4000
