# FPGA Host bypassing subproject

This source code base is tested for Xilinx U200, U50, VCU1525, NetFPGA SUME and Intel DE-10 Pro FPGAs. Currently only a build script for U200 is provided.
 
## Build (Xilinx)

1. update the Vivado installation path and License path in createProject_U200.sh
2. execute the sh script:

```
./createProject_U200.sh
```
This script will create a vivado project including all IP cores and the Verilog sources of this project.
3. run the synthesis manually in vivado

### Other Vivado versions
This project is scripted for vivado 2020.1. However, other versions can be used as well. For that, IP-core versions in the tcl script might be up/downgraded.

