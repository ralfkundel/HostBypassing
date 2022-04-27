// initially dpdk skelleton, modified by kadir eryigit, leonard anderweit, and ralf kundel

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

#include "../../drivers/net/ixgbe/ixgbe_ethdev.h"
#include "../../drivers/net/ixgbe/base/ixgbe_osdep.h"
#include "../../drivers/net/ixgbe/base/ixgbe_type.h"
#include "rte_ethdev_driver.h"
#include "../settings.h"

#define NUM_MBUFS 8191
#define MBUF_CACHE_SIZE 250
#define BURST_SIZE 32

static const struct rte_eth_conf port_conf_default = {
	.rxmode = {
		.max_rx_pkt_len = RTE_ETHER_MAX_LEN,
	},
};

static uint64_t rx_desc_base_phy;
static uint64_t tx_desc_base_phy;

/*
 * Initializes a given port using global settings and with the RX buffers
 * coming from the mbuf_pool passed as a parameter.
 */
static inline int
port_init(uint16_t port, struct rte_mempool *mbuf_pool) {
	struct rte_eth_conf port_conf = port_conf_default;
	const uint16_t rx_rings = RINGS, tx_rings = RINGS;
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

	// multi rx queue support
	port_conf.rxmode.mq_mode = ETH_MQ_RX_RSS;
	port_conf.rx_adv_conf.rss_conf.rss_key = NULL;
	port_conf.rx_adv_conf.rss_conf.rss_hf = ETH_RSS_IP | ETH_RSS_TCP | ETH_RSS_UDP | ETH_RSS_SCTP;
	port_conf.rx_adv_conf.rss_conf.rss_hf &= dev_info.flow_type_rss_offloads;

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

static uint32_t rdt_reg_old = -1;
static uint32_t rdh_reg_old = -1;
static uint32_t tdt_reg_old = -1;
static uint32_t tdh_reg_old = -1;
static void print_tail_head_regs(void){

    struct ixgbe_hw     *hw;
	int port_id = 0;
	struct rte_eth_dev* dev = eth_dev_get(port_id);
	

	hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);

	for(int i=0;i<RINGS;i++){
	uint16_t rxq_index = i;
	uint16_t txq_index = i;
	volatile uint32_t rdh_reg = IXGBE_READ_REG(hw, IXGBE_RDH(rxq_index));
	volatile uint32_t rdt_reg = IXGBE_READ_REG(hw, IXGBE_RDT(rxq_index));
	volatile uint32_t tdh_reg = IXGBE_READ_REG(hw, IXGBE_TDH(txq_index));
	volatile uint32_t tdt_reg = IXGBE_READ_REG(hw, IXGBE_TDT(txq_index));

	if(tdt_reg!= tdt_reg_old || tdh_reg !=tdh_reg_old) {
		tdt_reg_old = tdt_reg;
		tdh_reg_old = tdh_reg;
		printf("index%d nic TX-head/tail: [%02d/%02d]\n", i, tdh_reg,tdt_reg);
	}
	if(rdt_reg!= rdt_reg_old || rdh_reg !=rdh_reg_old) {
		printf("index%d nic RX-head/tail: [%02d/%02d] [", i, rdh_reg,rdt_reg);
		if(rdh_reg>=RX_RING_SIZE) printf("XXXXXXXXXXXXXX---Strange HEAD-Pointer---XXXXXXXXXXXXXX\n");
		rdh_reg_old = rdh_reg;
		rdt_reg_old = rdt_reg;
		rdh_reg = rdh_reg & (RX_RING_SIZE-1);
		printf("]\n");
	}
	}
}

/**
* This function is for monitoring/debugging only
**/
static void hardware_loop(void){
	while(1){
		 sleep(1);
		print_tail_head_regs();
	}
}


int main(int argc, char *argv[]) {
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

    hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);

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

	rx_desc_base_phy  = GPU_RX_DESC_ADDR; 
	tx_desc_base_phy  = GPU_TX_DESC_ADDR;

    hw->custom_addr_enable  = true;
	hw->custom_rx_desc_addr = rx_desc_base_phy;
	hw->custom_tx_desc_addr = tx_desc_base_phy;
	hw->custom_desc_addr_offset = RX_RING_SIZE*DESC_SIZE;


	

	printf("rz_iova : 0x%"PRIx64"\n", rz->iova );
	printf("rz_addr : %p\n", rz->addr );
	/* Initialize all ports. */
	RTE_ETH_FOREACH_DEV(portid)
		if (port_init(portid, mbuf_pool) != 0)
			rte_exit(EXIT_FAILURE, "Cannot init port %"PRIu16 "\n",
					portid);

	if (rte_lcore_count() > 1)
		printf("\nWARNING: Too many lcores enabled. Only 1 used.\n");

	if(true)hardware_loop();

	printf("Press ENTER key to Continue\n");
    getchar(); 
}
