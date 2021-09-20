# Host Bypassing from DPDK NICs to FPGAs via PCIe
Note: this repository is currently not complete yet.

it consists of two parts:
1. a FPGA project. see: [FPGA readme](FpgaProject/Readme.md)
2. a modified version of DPDK for enabling host bypassing. coming soon!

## General Workflow
1. build the FPGA project according to its readme and load the FPGA design on the FPGA
2. reboot the server
3. load any kernel module for the FPGA. This is not used at all but needed to make the FPGA accessible via 
4. update the memory addresses in the sample DPDK app and compile it and start it

## Supported NICs
Currently, the following Network Interface Cards are supported:

* Intel 82599


## Release Plan:
Note: Further documentation will follow in the next weeks as well as DPDK sample code.