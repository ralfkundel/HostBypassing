# Host Bypassing from DPDK NICs to FPGAs via PCIe

For detailed explanation: [Paper](https://www.kom.tu-darmstadt.de/papers/KEM+21.pdf)

The project consists of two parts:
1. a FPGA project. see: [FPGA readme](FpgaProject/Readme.md)
2. a modified version of DPDK for enabling host bypassing. coming soon!

## General Workflow
1. build the FPGA project according to its readme and load the FPGA design on the FPGA. see: [FPGA readme](FpgaProject/Readme.md)
2. reboot the server. This is needed, as the PCIe-configuration of the FPGA has changed.
3. load any kernel module for the FPGA. This is not used at all but needed to make the FPGA physical address space accessible and allow the FPGA to write on the registers of the NIC (bus master). for details:  [Loading the FPGA kernel module](#kernelload)
4. Load the igb_uio kernel module for the NIC you want to use. Update the memory addresses in the sample DPDK app and compile it and start it. for details: [DPDK readme](DpdkProject/Readme.md)

### <a name="kernelload"></a> Loading the FPGA kernel module
We recomend the use of the IGB_UIO kernel module which wille be compiled by the dpdk library anyway. Any other kernel module, supporting bus mastering, should work as well.
For loading the kernel Module (assuming the FPGA PCIe bus address to be 0000:65:00.0):
```
echo "10ee 9038" > /sys/bus/pci/drivers/igb_uio/new_id
```
and if needed for unbinding/rebinding:
```
echo -n 0000:65:00.0 > /sys/bus/pci/drivers/igb_uio/unbind
echo -n 0000:65:00.0 > /sys/bus/pci/drivers/igb_uio/bind
```

## Supported NICs
Currently, the following Network Interface Cards are supported:

* Intel 82599


## Release Plan:
Note: Further documentation will follow in the next weeks as well as DPDK sample code.