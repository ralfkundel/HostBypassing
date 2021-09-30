/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright(c) 2010-2015 Intel Corporation
 * Modified by Kadir Eryigit and Ralf Kundel, 2019-2021
 */

#include <stdint.h>
#include <inttypes.h>
#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_ethdev_core.h>
#include <rte_cycles.h>
#include <rte_lcore.h>
#include <rte_mbuf.h>
#include <rte_bus_pci.h>
#include <stdio.h>
#include <stdarg.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <inttypes.h>

#include "../../drivers/net/ixgbe/ixgbe_ethdev.h"
#include "../../drivers/net/ixgbe/base/ixgbe_osdep.h"
#include "../../drivers/net/ixgbe/base/ixgbe_type.h"
#include "rte_ethdev_driver.h"
//#include "rte_ethdev.h"

/**
The memory layout on the FPGA looks always as follows and all the areas are adjacent to each other:
512 KB rx packet buffers
512 KB tx packet buffers
4 KB rx descriptor rings
4 KB tx descriptor rings
4 KB configuration registers

If the number of descriptors is smaller than 256, this layout is still the same but some memory regions are not used in operation

for each packet in the rx/tx packet buffer 2048 bytes are reserved and always used --> memory addresses are base_address + n*2048 while n is the id of the packet.
The descriptor ring requires 16 byte for each descriptor. 4KB /16 --> 256 descriptors max. 64 seem to be sufficient on the FPGA. In Software more is better.

Updating the addresses: 3 in total:
1. fpga mem addr
2. fpga bar file
3. NIC base address (find out with "lspci -v | grep 82599 -A 6" --> the region 0 address of the NIC!!!)
**/

#define RX_RING_SIZE 64
#define TX_RING_SIZE 64

#define NUM_MBUFS 8191
#define MBUF_CACHE_SIZE 250
#define BURST_SIZE 32


#define COMMAND_REG  			0 //32bit register
#define NIC_BASE_ADDR_REG  		1
#define FPGA_BASE_ADDR_REG  	2

//TODO: read this from sysfs or lspci instead of constant
#define FPGA_MEM_ADDR 0xc6000000  //this has to be updated manually everytime fpga address changes (usually when fpga memory size or pcie port is changed)
//TODO
#define FPGA_BAR_FILE "/sys/bus/pci/devices/0000:65:00.0/resource0"
#define FPGA_RX_MEM_ADDR FPGA_MEM_ADDR
#define FPGA_TX_MEM_ADDR FPGA_RX_MEM_ADDR + 256 * 2048
#define FPGA_RX_DESC_ADDR FPGA_TX_MEM_ADDR + 256 * 2048 
#define FPGA_TX_DESC_ADDR FPGA_RX_DESC_ADDR + 4096
#define FPGA_REGISTERS_ADDR FPGA_TX_DESC_ADDR + 4096



#define FPGA_BAR_SIZE 2048*1024
#define FPGA_MEM_SIZE (256+256)*2048 + 2*4096 + 3*4 // tx and rx packet bram + desc bram + 3 registers

//TODO
#define NIC_REG_ADDR 0xab780000 //this has to be updated manually everytime nic address changes (usually when pcie port is changed)

#define IXGBE_ADV_TX_DESC_DTYP_DATA  3<<20
#define IXGBE_ADV_TX_DESC_DCMD_EOP 1<<24
#define IXGBE_ADV_TX_DESC_DCMD_INS_FCS 1<<25
#define IXGBE_ADV_TX_DESC_DCMD_ADVD 1<<29

#define IXGBE_ADV_TX_PAYLEN_SHIFT 14



static const struct rte_eth_conf port_conf_default = {
	.rxmode = {
		.max_rx_pkt_len = RTE_ETHER_MAX_LEN,
	},
};

/* basicfwd.c: Basic DPDK skeleton forwarding example. */

/*
 * Initializes a given port using global settings and with the RX buffers
 * coming from the mbuf_pool passed as a parameter.
 */
static inline int
port_init(uint16_t port, struct rte_mempool *mbuf_pool)
{
	struct rte_eth_conf port_conf = port_conf_default;
	const uint16_t rx_rings = 1, tx_rings = 1;
	uint16_t nb_rxd = RX_RING_SIZE;
	uint16_t nb_txd = TX_RING_SIZE;
	int retval;
	uint16_t q;
	struct rte_eth_dev_info dev_info;
	struct rte_eth_txconf txconf;

	printf("RX-ring size: %d, TX-ring size %d\n",RX_RING_SIZE,TX_RING_SIZE );
	if (!rte_eth_dev_is_valid_port(port))
		return -1;

	rte_eth_dev_info_get(port, &dev_info);
	if (dev_info.tx_offload_capa & DEV_TX_OFFLOAD_MBUF_FAST_FREE)
		port_conf.txmode.offloads |=
			DEV_TX_OFFLOAD_MBUF_FAST_FREE;


	/* Configure the Ethernet device. */
	retval = rte_eth_dev_configure(port, rx_rings, tx_rings, &port_conf);
	if (retval != 0)
		return retval;

	retval = rte_eth_dev_adjust_nb_rx_tx_desc(port, &nb_rxd, &nb_txd);
	if (retval != 0)
		return retval;

	/* Allocate and set up 1 RX queue per Ethernet port. */
	for (q = 0; q < rx_rings; q++) {
		retval = rte_eth_rx_queue_setup(port, q, nb_rxd,
				rte_eth_dev_socket_id(port), NULL, mbuf_pool);
		if (retval < 0)
			return retval;
	}

	txconf = dev_info.default_txconf;
	txconf.offloads = port_conf.txmode.offloads;
	// txconf.tx_free_thresh = 4;
	// txconf.tx_rs_thresh = 4;
	txconf.tx_thresh.pthresh=0;
	printf("tx_free_thresh: %d\n", txconf.tx_free_thresh);
	printf("tx_rs_thresh: %d\n", txconf.tx_rs_thresh);
	printf("pthresh: %d\n",txconf.tx_thresh.pthresh);
	printf("hthresh: %d\n",txconf.tx_thresh.hthresh);
	printf("wthresh: %d\n",txconf.tx_thresh.wthresh);
	printf("rxmode.mq_mode: %x\n",port_conf.rxmode.mq_mode);
	/* Allocate and set up 1 TX queue per Ethernet port. */
	for (q = 0; q < tx_rings; q++) {
		retval = rte_eth_tx_queue_setup(port, q, nb_txd,
				rte_eth_dev_socket_id(port), &txconf);
		if (retval < 0)
			return retval;
	}

	/* Start the Ethernet port. */
	retval = rte_eth_dev_start(port);
	if (retval < 0)
		return retval;

	/* Display the port MAC address. */
	struct rte_ether_addr addr;
	rte_eth_macaddr_get(port, &addr);
	printf("Port %u MAC: %02" PRIx8 " %02" PRIx8 " %02" PRIx8
			   " %02" PRIx8 " %02" PRIx8 " %02" PRIx8 "\n",
			port,
			addr.addr_bytes[0], addr.addr_bytes[1],
			addr.addr_bytes[2], addr.addr_bytes[3],
			addr.addr_bytes[4], addr.addr_bytes[5]);

	/* Enable RX in promiscuous mode for the Ethernet device. */
	rte_eth_promiscuous_enable(port);

	return 0;
}


static void print_fpga_packet(void *pkt_mem, uint32_t size){
	
	char pkt_tmp[size];
	char single;
	memcpy(pkt_tmp,pkt_mem,size);
	for (uint32_t i = 0; i < size; ++i)
	{
		single = pkt_tmp[i]&255;
		if( single>31 && single <127)
			printf("%c",single);
		else printf(".");
	}
	// memcpy(pkt_tmp,pkt_mem,size);

	// for (uint32_t i = 0; i < size; ++i){
	// 	printf("%c",pkt_tmp[i]);
	// }
	printf("\n");
}



static void reset_bram(volatile void* bar, int size){
	volatile uint64_t* bram = (volatile uint64_t*) bar;

	for (int i = 0; i < size/8; ++i){
		bram[i] = 0;
	}
}



/*
 * maps fpga pcie bar to memory address.
 * returns void pointer as address to beginning of BAR
 * size is defined in FPGA config and can be read with lspci. give in bytes
 */
static void* bar_map(const char * resource, uint32_t size){
	int fd = open(resource,O_RDWR);
	if(fd<0) {
		printf("couldn't open fpga_mem resource\n");
		return NULL;
	}
	void* fpga_bram = mmap(NULL,size,PROT_READ | PROT_WRITE,MAP_SHARED,fd,0);
	close(fd);
	if(fpga_bram==MAP_FAILED){
		printf("bram mmap failed\n");
		return NULL;
	}
	return fpga_bram;
}


static uint64_t rx_pkt_base_phy;
static uint64_t rx_desc_base_phy;
static uint64_t tx_pkt_base_phy;
static uint64_t tx_desc_base_phy;

static uint64_t* rx_pkt_base_virt;
static uint64_t* tx_pkt_base_virt;
static uint64_t* rx_desc_base_virt;
static uint64_t* tx_desc_base_virt;

static int write_rx_descriptors(void){

	volatile union ixgbe_adv_rx_desc* desc_bram = (volatile union ixgbe_adv_rx_desc*) rx_desc_base_virt;

	for(int i = 0; i<RX_RING_SIZE;i++){

		desc_bram[i].read.pkt_addr = rx_pkt_base_phy + 2048*i;
		desc_bram[i].read.hdr_addr = 0;
	}
	return 0;
}

struct eth_pkt {
	uint8_t header[14]; //6 Byte dst mac, 6 Byte src mac, 2 Byte type
	uint8_t* payload; //max 1500 bytes
	uint32_t payload_len; //in Byte	
};

static void copy_pkt(struct eth_pkt* dst, volatile void* src,uint32_t len){
	volatile uint8_t* src_data = (volatile uint8_t*) src;
	dst->payload_len = len-14;
	for (int i = 0; i < 14; ++i)
	{
		dst->header[i] = src_data[i];
	}
	for (uint32_t i = 0; i < len-14; ++i)
	{
		dst->payload[i] = src_data[i+14];
	}
}

static void fpga_recv(volatile uint32_t *rxq_rdt_reg_addr,struct eth_pkt* rx_pkt){

	volatile union ixgbe_adv_rx_desc *rx_ring = (volatile union ixgbe_adv_rx_desc* ) rx_desc_base_virt;
	volatile union ixgbe_adv_rx_desc *rx_desc;
	uint32_t staterr;
	uint16_t pkt_len; 


	for(int i = 0;i<RX_RING_SIZE;i++) {
		rx_desc = &rx_ring[i];
		staterr = rx_desc->wb.upper.status_error;

		if(staterr&1) { //check for DD bit

			pkt_len = rx_desc->wb.upper.length;

			printf("new packet at desc: %d, packet length %d Bytes, status: %x\n",i,pkt_len,staterr );

			copy_pkt(rx_pkt,rx_pkt_base_virt + i * 2048/8,pkt_len);

			rx_desc->read.hdr_addr = 0;
			rx_desc->read.pkt_addr = rx_pkt_base_phy + 2048 * i;
			print_fpga_packet(rx_pkt_base_virt + i * 2048/8,pkt_len);


			IXGBE_PCI_REG_WRITE(rxq_rdt_reg_addr, i); //advance tail pointer
			
		 }
	}
}




static uint32_t tx_pkt_index = 0;

static void fpga_write_pkt_data(volatile void* fpga_tx_pkt_mem, struct eth_pkt* pkt_buffer){
	volatile uint8_t* pkt_mem = (volatile uint8_t*) fpga_tx_pkt_mem;

	for (uint32_t i = 0; i < 14; ++i){
		pkt_mem[i] = pkt_buffer->header[i];
	}
	for (uint32_t i = 0; i <pkt_buffer->payload_len ; ++i){
		pkt_mem[14+i] = pkt_buffer->payload[i];
	}
}

static void fpga_write_tx_desc(volatile void* fpga_tx_desc_mem,struct eth_pkt* pkt_buffer, uint64_t pkt_addr ){
	union ixgbe_adv_tx_desc txd;
	volatile union ixgbe_adv_tx_desc* tx_desc_ring = (volatile union ixgbe_adv_tx_desc*) fpga_tx_desc_mem;

	txd.read.buffer_addr = pkt_addr;
	txd.read.cmd_type_len = (pkt_buffer->payload_len+14) | IXGBE_ADV_TX_DESC_DTYP_DATA | IXGBE_ADV_TX_DESC_DCMD_ADVD | IXGBE_ADV_TX_DESC_DCMD_EOP | IXGBE_ADV_TX_DESC_DCMD_INS_FCS;
	txd.read.olinfo_status = (pkt_buffer->payload_len+14) << IXGBE_ADV_TX_PAYLEN_SHIFT;

	tx_desc_ring[0].read.buffer_addr   = txd.read.buffer_addr;
	tx_desc_ring[0].read.cmd_type_len  = txd.read.cmd_type_len;
	tx_desc_ring[0].read.olinfo_status = txd.read.olinfo_status;

}

static void fpga_xmit(struct eth_pkt* pkt_buffer,volatile uint32_t *txq_tdt_reg_addr){

	printf("writing packet index: %d, pkt_length: %d\n",tx_pkt_index,pkt_buffer->payload_len+14 );
	//write packet data to fpga
	fpga_write_pkt_data(tx_pkt_base_virt + tx_pkt_index * 2048,pkt_buffer);
	
	//write tx desc to fpga
	fpga_write_tx_desc(tx_desc_base_virt + tx_pkt_index * 16,pkt_buffer, tx_pkt_base_phy + tx_pkt_index * 2048);

	//increase local tx-tail
	tx_pkt_index++;
	if(tx_pkt_index==TX_RING_SIZE)
		tx_pkt_index=0;

	//write tail pointer to nic
	IXGBE_PCI_REG_WRITE(txq_tdt_reg_addr, tx_pkt_index);

}


static void init_fpga(volatile void* fpga_reg_bar){
	volatile uint32_t* reg_mem = (volatile uint32_t*) fpga_reg_bar + (256 + 256) * 2048 /4 + 2*4096/4;
	reg_mem[NIC_BASE_ADDR_REG]         = NIC_REG_ADDR;
	reg_mem[FPGA_BASE_ADDR_REG]        = FPGA_MEM_ADDR;
	reg_mem[COMMAND_REG]               = 3; //1:start and 0:init 

	printf("\n");
	printf("\n");
	printf("\n");
	printf("fpga_reg_bar %x\n", *((volatile uint32_t *) fpga_reg_bar) );
	printf("reg_mem %x\n", *reg_mem);
	printf("NIC_REG_ADDR %x\n", NIC_REG_ADDR);
	printf("FPGA_MEM_ADDR %x\n", FPGA_MEM_ADDR);
	printf("reg_mem[NIC_BASE_ADDR_REG]  %x\n", reg_mem[NIC_BASE_ADDR_REG] );
	printf("reg_mem[FPGA_BASE_ADDR_REG]  %x\n", reg_mem[FPGA_BASE_ADDR_REG] );
}



/**
* This function is for debugging only and does the descriptor handling in software but on the FPGA --> just replaced CPU DDR by FPGA BRAM
**/
static void software_driver_loop(volatile uint32_t* rxq_rdt_reg_addr,volatile uint32_t *txq_tdt_reg_addr){

	volatile uint32_t rdt_reg;
	volatile uint32_t rdh_reg;
	volatile uint32_t tdt_reg;
	volatile uint32_t tdh_reg;
	uint16_t rxq_index = 0;
	uint16_t txq_index = 0;
	uint16_t port_id = 0;
	struct ixgbe_hw     *hw;
	struct rte_eth_dev* dev = eth_dev_get(port_id);
	
	write_rx_descriptors();


	hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);

	rdt_reg = IXGBE_READ_REG(hw, IXGBE_RDT(rxq_index));
	rdh_reg = IXGBE_READ_REG(hw, IXGBE_RDH(rxq_index));
	tdt_reg = IXGBE_READ_REG(hw, IXGBE_TDT(rxq_index));
	tdh_reg = IXGBE_READ_REG(hw, IXGBE_TDH(rxq_index));


	uint32_t desc_c = 0;
	uint32_t rdt_reg_old = -1;
	uint32_t rdh_reg_old = -1;
	uint32_t tdt_reg_old = -1;
	uint32_t tdh_reg_old = -1;
	char print_char = 'o';
	struct eth_pkt rx_pkt;
	uint8_t rx_pkt_payload[1500];
	rx_pkt.payload = rx_pkt_payload;

	while(1){

		fpga_recv(rxq_rdt_reg_addr,&rx_pkt);
		if(rx_pkt.payload_len>0){
			printf("SEND:\n");
			fpga_xmit(&rx_pkt,txq_tdt_reg_addr);
			rx_pkt.payload_len = 0;
		}

		rdt_reg = IXGBE_READ_REG(hw, IXGBE_RDT(rxq_index));
		rdh_reg = IXGBE_READ_REG(hw, IXGBE_RDH(rxq_index));
		tdt_reg = IXGBE_READ_REG(hw, IXGBE_TDT(txq_index));
		tdh_reg = IXGBE_READ_REG(hw, IXGBE_TDH(txq_index));
		if(tdt_reg!= tdt_reg_old || tdh_reg !=tdh_reg_old) {
			tdt_reg_old = tdt_reg;
			tdh_reg_old = tdh_reg;
			printf("nic TX-head/tail: [%d/%d]\n",tdh_reg,tdt_reg);
		}
		if(rdt_reg!= rdt_reg_old || rdh_reg !=rdh_reg_old) {
			printf("nic RX-head/tail: [%02d/%02d] [",rdh_reg,rdt_reg);
			if(rdh_reg==RX_RING_SIZE) printf("XXXXXXXXXXXXXX---Strange HEAD-Pointer---XXXXXXXXXXXXXX\n");
			rdh_reg_old = rdh_reg;
			rdt_reg_old = rdt_reg;
			rdh_reg = rdh_reg & (RX_RING_SIZE-1);
			if(rdh_reg< (rdh_reg_old& (RX_RING_SIZE-1)))
				print_char = '.';
			if(rdt_reg < rdt_reg_old)
				print_char = 'o';
			if(rdt_reg==rdh_reg) printf("ERROR. RX-Head and Tail Register are equal\n");
			for(desc_c  = 0;desc_c < RX_RING_SIZE;desc_c++) {
				if(desc_c==rdt_reg && rdh_reg==rdt_reg)
					printf("E");
				else if(desc_c==rdt_reg){
					printf("T");
					print_char = '.';
				}
				else if(desc_c==rdh_reg) {
					printf("H");
					print_char = 'o';
				}
				else
					printf("%c",print_char);
			}
			printf("]\n");
		}
	}
}


static uint32_t rdt_reg_old = -1;
static uint32_t rdh_reg_old = -1;
static uint32_t tdt_reg_old = -1;
static uint32_t tdh_reg_old = -1;
static void print_tail_head_regs(void){

    struct ixgbe_hw     *hw;
	int port_id = 0;
	struct rte_eth_dev* dev = eth_dev_get(port_id);
	

	hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);

	uint16_t rxq_index = 0; //currently only using one rx queue
	uint16_t txq_index = 0;
	volatile uint32_t rdh_reg = IXGBE_READ_REG(hw, IXGBE_RDH(rxq_index));
	volatile uint32_t rdt_reg = IXGBE_READ_REG(hw, IXGBE_RDT(rxq_index));
	volatile uint32_t tdh_reg = IXGBE_READ_REG(hw, IXGBE_TDH(txq_index));
	volatile uint32_t tdt_reg = IXGBE_READ_REG(hw, IXGBE_TDT(txq_index));


	uint32_t desc_c = 0;
	char print_char = 'o';

	if(tdt_reg!= tdt_reg_old || tdh_reg !=tdh_reg_old) {
		tdt_reg_old = tdt_reg;
		tdh_reg_old = tdh_reg;
		printf("nic TX-head/tail: [%02d/%02d]\n",tdh_reg,tdt_reg);
	}
	if(rdt_reg!= rdt_reg_old || rdh_reg !=rdh_reg_old) {
		printf("nic RX-head/tail: [%02d/%02d] [",rdh_reg,rdt_reg);
		if(rdh_reg>=RX_RING_SIZE) printf("XXXXXXXXXXXXXX---Strange HEAD-Pointer---XXXXXXXXXXXXXX\n");
		rdh_reg_old = rdh_reg;
		rdt_reg_old = rdt_reg;
		rdh_reg = rdh_reg & (RX_RING_SIZE-1);
		if(rdh_reg< (rdh_reg_old& (RX_RING_SIZE-1)))
			print_char = '.';
		if(rdt_reg < rdt_reg_old)
			print_char = 'o';
		if(rdt_reg==rdh_reg) printf("ERROR. RX-Head and Tail Register are equal\n");
		for(desc_c  = 0;desc_c < RX_RING_SIZE;desc_c++) {
			if(desc_c==rdt_reg && rdh_reg==rdt_reg){
				printf("E");
			}
			else if(desc_c==rdt_reg){
				printf("T");
				print_char = '.';
			}
			else if(desc_c==rdh_reg) {
				printf("H");
				print_char = 'o';
			}
			else{
				printf("%c",print_char);
			}
		}
		printf("]\n");
	}
}


/**
* This function is for monitoring/debugging only
**/
static void hardware_loop(void* fpga_bar_virt){

	reset_bram(fpga_bar_virt,FPGA_MEM_SIZE);

	init_fpga(fpga_bar_virt);


	while(1){
		 sleep(1);
		print_tail_head_regs();
	}
}

/*
 * The main function, which does initialization and calls the per-lcore
 * functions.
 */
int
main(int argc, char *argv[])
{
	struct rte_mempool *mbuf_pool;
	unsigned nb_ports;
	uint16_t portid;


	/* Initialize the Environment Abstraction Layer (EAL). */
	int ret = rte_eal_init(argc, argv);
	if (ret < 0)
		rte_exit(EXIT_FAILURE, "Error with EAL initialization\n");

	uint16_t port_id = 0;

	struct ixgbe_hw     *hw;

	struct rte_eth_dev* dev = eth_dev_get(port_id);
	const struct rte_memzone *rz;

	
	

	argc -= ret;
	argv += ret;


	hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);

	void* fpga_bar_virt = bar_map(FPGA_BAR_FILE,FPGA_BAR_SIZE);
	if(fpga_bar_virt==NULL){
		printf("couldnt map bar 0\n");
		return errno;
	}

	/* Check that there is an even number of ports to send/receive on. */
	nb_ports = rte_eth_dev_count_avail();
	if (nb_ports < 1 )
		rte_exit(EXIT_FAILURE, "Error: no port found\n");

	/* Creates a new mempool in memory to hold the mbufs. */
	mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL", NUM_MBUFS,
		MBUF_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE, rte_socket_id());

	if (mbuf_pool == NULL)
		rte_exit(EXIT_FAILURE, "Cannot create mbuf pool\n");

	rz = rte_eth_dma_zone_reserve(dev, "custom_mem", 0,
		512*1024,
		128, rte_eth_dev_socket_id(0));
	
	rx_pkt_base_phy   = FPGA_RX_MEM_ADDR;  
	tx_pkt_base_phy   = FPGA_TX_MEM_ADDR;  
	rx_desc_base_phy  = FPGA_RX_DESC_ADDR; 
	tx_desc_base_phy  = FPGA_TX_DESC_ADDR; 

	rx_pkt_base_virt  = (uint64_t*) fpga_bar_virt;
	tx_pkt_base_virt  = (uint64_t*) fpga_bar_virt + 256 * 2048/8; //divide by 8 because 8 bytes in 64bit, 2048bytes space per packet
	rx_desc_base_virt = (uint64_t*) fpga_bar_virt + (256 + 256) * 2048/8; 
	tx_desc_base_virt = (uint64_t*) fpga_bar_virt + (256 + 256) * 2048/8 + 4096/8;

	hw->custom_addr_enable = true;
	hw->custom_rx_desc_addr = rx_desc_base_phy;
	hw->custom_tx_desc_addr = tx_desc_base_phy;


	printf("rz_iova : 0x%"PRIx64"\n", rz->iova );
	printf("rz_addr : %p\n", rz->addr );
	/* Initialize all ports. */
	RTE_ETH_FOREACH_DEV(portid)
		if (port_init(portid, mbuf_pool) != 0)
			rte_exit(EXIT_FAILURE, "Cannot init port %"PRIu16 "\n",
					portid);

	if (rte_lcore_count() > 1)
		printf("\nWARNING: Too many lcores enabled. Only 1 used.\n");
	
	hardware_loop(fpga_bar_virt);

	if(false){software_driver_loop(0,0);}


	return 0;
}
