# DPDK Host bypassing subproject

This project is based upon DPDK version 20.05.0. 

## Build it
The following steps should be executed on the server you want to run host bypassing.

1. get the DPDK source code for version 20.05.0
```
wget http://fast.dpdk.org/rel/dpdk-20.05.tar.xz
tar -xf dpdk-20.05.tar.xz
```

2. replace the following files in the dpdk folder by the ones in this repository! Otherwise Host Bypassing is not working.:

* drivers/net/ixgbe/ixgbe_rxtx.c
* drivers/net/ixgbe/ixgbe_rxtx.h
* lib/librte_ethdev/rte_ethdev.c
* lib/librte_ethdev/rte_ethdev.h
* drivers/net/ixgbe/base/ixgbe_type.h


3. Compile the DPDK library (with IGB_UIO kernel module):
```
make config T=x86_64-native-linuxapp-gcc
sed -ri 's,(CONFIG_RTE_EAL_IGB_UIO=).*,\1y,' build/.config
make
export RTE_SDK=$(pwd)
```

4. Bind the DPDK capable NIC to the IGB_UIO module (assuming the NIC is located at 17:00.1):
```
echo 512 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
sudo mkdir -p /mnt/huge
sudo mount -t hugetlbfs nodev /mnt/huge

sudo modprobe uio
sudo  insmod $RTE_SDK/build/kmod/igb_uio.ko
sudo python usertools/dpdk-devbind.py --bind=igb_uio 17:00.1
python usertools/dpdk-devbind.py --status
```

5. Replace the physical addresses in the BypassApp.c file. There are three TODOs which must be modified. The following commands help to find out the right addresses.
```
lspci -vv | grep Xilinx -A 6 
lspci -vv | grep 82599 -A 6
```
 Take the Region 0 address for both devices and replace them as following:
```
#define FPGA_MEM_ADDR 0xc6000000
#define FPGA_BAR_FILE "/sys/bus/pci/devices/0000:65:00.0/resource0"
#define NIC_REG_ADDR 0xab780000
```

6. Compile and run the Host Bypassing Example App:
```
cd HostBypassingApp
make
#run it:
./build/BypassApp
```