//Authors: Leonard Anderweit, Ralf Kundel
//2022

#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>


#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

#include <cuda.h>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>

#include "dpdk.h"
#include "../settings.h"

#define PIN_MEM     _IOW('a',0,struct ioctl_args*)
#define UNPIN_MEM   _IOW('a',1,void**)
#define RD_ADDR     _IOR('a',2,void**)

#define IXGBE_ADV_TX_DESC_DTYP_DATA 3<<20
#define IXGBE_ADV_TX_DESC_DCMD_EOP 1<<24
#define IXGBE_ADV_TX_DESC_DCMD_INS_FCS 1<<25
#define IXGBE_ADV_TX_DESC_DCMD_RS 1<<27
#define IXGBE_ADV_TX_DESC_DCMD_ADVD 1<<29
#define IXGBE_ADV_TX_PAYLEN_SHIFT 14


struct ioctl_args {
    uint64_t vaddr;
    uint64_t size;
    uint32_t bus;
    uint32_t devfn;
};

struct pkt_info {
    uint16_t position; //within the packet buffer mem
    uint16_t length; //in bytes
};


__device__ volatile pkt_info malloc_empty_desc[PKT_BUFFER_SIZE*RINGS];
__device__ volatile uint32_t malloc_empty_desc_head[RINGS];
__shared__ uint32_t malloc_empty_desc_tail[RINGS];
//__shared__ memory can only be shared within a kernel

__device__ volatile pkt_info malloc_received_desc[PKT_BUFFER_SIZE*RINGS];
__device__ volatile uint32_t malloc_received_desc_head[RINGS];
__shared__ uint32_t malloc_received_desc_tail[RINGS];


__global__ void
init_empty_desc(){
    for(int i = 0; i<PKT_BUFFER_SIZE*RINGS; i++){
        malloc_empty_desc[i].position = i;
        malloc_empty_desc[i].length = 0;
    }
}


__global__ void
receive(uint64_t *rx_desc_base_virt, uint32_t* rdt_reg){ // rdt receive descriptor tail
    int index = threadIdx.x; // receive ring separator
    
    uint16_t rx_desc_cp[RX_RING_SIZE]; //local copy of mem address in rings
    
    //initialize
    malloc_received_desc_head[index] = 0;
    
    int buf_offset = index * PKT_BUFFER_SIZE;
    volatile union ixgbe_adv_rx_desc* desc_mem = (volatile union ixgbe_adv_rx_desc*) (rx_desc_base_virt + index * RX_RING_SIZE * DESC_SIZE/8); //RX_RING_SIZE ==256, DESC_SIZE==16
    uint16_t pos;
    malloc_empty_desc_tail[index] = 1;
    
	for(uint32_t i = 0; i<RX_RING_SIZE;i++){ //init the first RX_RING_SIZE descriptors for receiving
        pos = malloc_empty_desc[i+buf_offset].position;
		desc_mem[i].read.pkt_addr = GPU_PKT_BUFFER_MEM_ADDR + MEM_PER_PKT * pos;
		desc_mem[i].read.hdr_addr = 0;
        rx_desc_cp[i] = pos;
        malloc_empty_desc_tail[index]++;
	}
	
	uint32_t counter[8];
    
    //end initialize
    

    volatile union ixgbe_adv_rx_desc *rx_ring = (volatile union ixgbe_adv_rx_desc* ) (rx_desc_base_virt + index * RX_RING_SIZE * DESC_SIZE/8);
	volatile union ixgbe_adv_rx_desc *rx_desc;
	uint32_t staterr;
    uint16_t new_pos;
    uint16_t length;
    uint32_t rx_pkt_index = 0;
	
	while(true){
		rx_desc = &rx_ring[rx_pkt_index];
	    staterr = rx_desc->wb.upper.status_error;
	    if(staterr&1) { //check for DD bit
            length = rx_desc->wb.upper.length;
            #if DEBUG
            printf("index%d checking pkt at:%u len:%u\n", index, rx_pkt_index, length);
            #endif
            if(length>0){ // new packet
                #if DEBUG
                printf("index %d: new pkt at rx_pkt_index: %u\n", index,rx_pkt_index);
                printf("index%d head %u, tail %u\n", index, malloc_received_desc_head[index], malloc_received_desc_tail[index]);
                printf("empty_desc_tail[index] %d\n", malloc_empty_desc_tail[index]);
                
                #endif
            
                
                if(malloc_empty_desc_tail[index] != malloc_empty_desc_head[index]){ // check for new empty memory
                
                    counter[index]++;
                
                    malloc_received_desc[malloc_received_desc_head[index]+buf_offset].position = rx_desc_cp[rx_pkt_index];
                    malloc_received_desc[malloc_received_desc_head[index]+buf_offset].length = length;
                    malloc_received_desc_head[index] = (malloc_received_desc_head[index] >= PKT_BUFFER_SIZE-1)? 0 : malloc_received_desc_head[index]+1;
                    // write new desc
                    new_pos = malloc_empty_desc[malloc_empty_desc_tail[index]+buf_offset].position;
		            rx_desc->read.hdr_addr = 0;
		            rx_desc->read.pkt_addr = GPU_PKT_BUFFER_MEM_ADDR + MEM_PER_PKT * new_pos;
                    rx_desc_cp[rx_pkt_index] = new_pos;
                    malloc_empty_desc_tail[index] = (malloc_empty_desc_tail[index] >= PKT_BUFFER_SIZE-1)? 0 : malloc_empty_desc_tail[index]+1;
                    rdt_reg[index*NIC_POINTER_OFFS/4] = rx_pkt_index;
                    rx_pkt_index = (rx_pkt_index >= RX_RING_SIZE-1)? 0 : rx_pkt_index+1;
                    //printf("index %d\n", index);
                    
                    #if DEBUG
                    if (counter[index]%10000 == 0){
                        printf("counter index: %d, counter: %d \n", index, counter[index]);
                    }
                    #endif
                } else{
                    // return;
                    #if DEBUG
                    printf("shit; no mem\n");
                    #endif
                    printf("shit; no mem\n");
                    continue;
                }
            
            } //end length > 0
            
        }
        #if DEBUG
        printf("index%d rx_pkt_index: %u\n", index,rx_pkt_index);
        #endif
    }
    
}

__global__ void
send(uint64_t *tx_desc_base_virt, uint32_t* tdt_reg){ // tdt transmit descriptor tail
    int index = threadIdx.x;
    
    /* initialize */
    uint32_t tx_pkt_index = 0;
    malloc_received_desc_tail[index] = 0;
    uint16_t tx_desc_cp[RX_RING_SIZE]; //local copy of mem address in rings
    
    int buf_offset = index * PKT_BUFFER_SIZE;
    volatile union ixgbe_adv_tx_desc* tx_desc_ring = (volatile union ixgbe_adv_tx_desc*) (tx_desc_base_virt + index * TX_RING_SIZE * DESC_SIZE/8);
    
    malloc_empty_desc_head[index] = PKT_BUFFER_SIZE-1;
        
    for(int i = 0; i<TX_RING_SIZE; i++){
        tx_desc_ring[i].wb.rsvd = 0;
        tx_desc_ring[i].wb.nxtseq_seed = 0;
        tx_desc_ring[i].wb.status = 1;
        tx_desc_cp[i] = malloc_empty_desc[i+buf_offset+PKT_BUFFER_SIZE-TX_RING_SIZE].position;
    }

    /* end initialize */
    
    

    uint16_t pkt_len;
    uint16_t new_pos;
    
    while(true)
    if(malloc_received_desc_head[index] != malloc_received_desc_tail[index]){
        #if DEBUG
        printf("index%d nxt %x, stat %x at %u\n", index, tx_desc_ring[tx_pkt_index].wb.nxtseq_seed, tx_desc_ring[tx_pkt_index].wb.status, tx_pkt_index);
        #endif
        #if WB
        if(tx_desc_ring[tx_pkt_index].wb.status & 1){
        #endif
            #if DEBUG
            printf("index%d send pkt %u\n", index, tx_pkt_index);
            #endif
        
            malloc_empty_desc[malloc_empty_desc_head[index]+buf_offset].position = tx_desc_cp[tx_pkt_index];
            malloc_empty_desc[malloc_empty_desc_head[index]+buf_offset].length = 0;
        
            pkt_len = malloc_received_desc[malloc_received_desc_tail[index]+buf_offset].length;
            new_pos = malloc_received_desc[malloc_received_desc_tail[index]+buf_offset].position;
            tx_desc_ring[tx_pkt_index].read.buffer_addr   = GPU_PKT_BUFFER_MEM_ADDR + MEM_PER_PKT * new_pos;
            #if WB
            tx_desc_ring[tx_pkt_index].read.cmd_type_len  = (pkt_len) | IXGBE_ADV_TX_DESC_DTYP_DATA | IXGBE_ADV_TX_DESC_DCMD_ADVD | IXGBE_ADV_TX_DESC_DCMD_EOP | IXGBE_ADV_TX_DESC_DCMD_INS_FCS | IXGBE_ADV_TX_DESC_DCMD_RS;
            #else
            tx_desc_ring[tx_pkt_index].read.cmd_type_len  = (pkt_len) | IXGBE_ADV_TX_DESC_DTYP_DATA | IXGBE_ADV_TX_DESC_DCMD_ADVD | IXGBE_ADV_TX_DESC_DCMD_EOP | IXGBE_ADV_TX_DESC_DCMD_INS_FCS;
            #endif
            tx_desc_ring[tx_pkt_index].read.olinfo_status = (pkt_len) << IXGBE_ADV_TX_PAYLEN_SHIFT;
            tx_desc_cp[tx_pkt_index] = new_pos;
            #if DEBUG
            printf("index%d nxt %x, stat %x at %u\n", index, tx_desc_ring[tx_pkt_index].wb.nxtseq_seed, tx_desc_ring[tx_pkt_index].wb.status, tx_pkt_index);
            #endif

            // increase tx tail pointer
            tx_pkt_index = (tx_pkt_index >= TX_RING_SIZE-1)? 0 : tx_pkt_index+1;
            //__threadfence_block(); --> crashes when multiple rings
            tdt_reg[index*NIC_POINTER_OFFS/4] = tx_pkt_index; // tail in nic
            malloc_received_desc_tail[index] = (malloc_received_desc_tail[index] >= PKT_BUFFER_SIZE-1)? 0 : malloc_received_desc_tail[index]+1;
            malloc_empty_desc_head[index] = (malloc_empty_desc_head[index] >= PKT_BUFFER_SIZE-1)? 0 : malloc_empty_desc_head[index]+1;
        #if WB
        }else{
            printf("break send\n");
            continue;
        }
        #endif
    }
}


int pin_mem(uint64_t address, uint64_t size){
    int fd;
    fd = open("/dev/etx_device", O_RDWR);
    if(fd < 0) {
        printf("Cannot open device file...\n");
        return -1;
    }
    struct ioctl_args args;
    args.vaddr = address;
    args.size = size;
    args.bus = NIC_BUS;
    args.devfn = NIC_DEVFN;
    ioctl(fd, PIN_MEM, &args);
    close(fd);
    return 0 ;
}

int unpin_mem(uint64_t address){
    int fd;
    fd = open("/dev/etx_device", O_RDWR);
    if(fd < 0) {
        printf("Cannot open device file...\n");
        return -1;
    }
    ioctl(fd, UNPIN_MEM, 0);
    close(fd);
    return 0 ;
}

int* init_gpu(){

    int *d_pointer;
    //extern __shared__ int tmp[MEM_SIZE/4];  //shared memory cannot be pinned
    //d_pointer = tmp;
    cudaMalloc((void **)&d_pointer, MEM_SIZE);
    cudaPointerAttributes attrs;
    cudaPointerGetAttributes(&attrs, d_pointer);
    unsigned int flag = 1;
    CUresult status = cuPointerSetAttribute(&flag, CU_POINTER_ATTRIBUTE_SYNC_MEMOPS, (CUdeviceptr)attrs.devicePointer);
    pin_mem((uint64_t) attrs.devicePointer, MEM_SIZE);
    return d_pointer;
}


int main(int argc, char *argv[]){
    int deviceId = 0; //1; //TODO dirty, if multiple GPUs are in a single system, this must be adapted manually
    cudaDeviceProp deviceProp;
    cudaGetDeviceProperties(&deviceProp, deviceId);
    printf("pciDeviceID: %x \n", deviceProp.pciDeviceID);
    printf("pciBusID: %x \n", deviceProp.pciBusID);
    printf("pciDomainID: %x \n", deviceProp.pciDomainID);
    cudaDeviceReset();
    cudaSetDevice(deviceId);
    cudaError_t err;
    uint32_t* rdt_reg;
    uint32_t* tdt_reg;

    // make nic tailpointer accessible for gpu
    int fd = open("/dev/mem",O_RDWR);
    if(fd<0) {
		printf("couldn't open mem resource\n");
		return -1;
	}
	void* mem = mmap(NULL, NIC_REG_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, NIC_REG_ADDR);
	close(fd);
	if( mem==MAP_FAILED){
		printf("mmap failed errno:%s\n",strerror(errno));
		return -1;
	}

    rdt_reg = (uint32_t*) mem + (NIC_RDT_OFFS)/4;
    tdt_reg = (uint32_t*) mem + (NIC_TDT_OFFS)/4;

    err = cudaHostRegister((void*)rdt_reg,512,cudaHostRegisterIoMemory);
    if(err!=cudaSuccess){
        printf("hostRegister failed!! err:%d\n",err);
    }
    err = cudaHostRegister((void*)tdt_reg,512,cudaHostRegisterIoMemory);
    if(err!=cudaSuccess){
        printf("hostRegister failed!! err:%d\n",err);
    }

    int ret;
    cudaDeviceGetAttribute(&ret, cudaDevAttrCanUseHostPointerForRegisteredMem, 0);
    printf("cudaDevAttrCanUseHostPointerForRegisteredMem: %d\n",ret); // needs to be 1 for code to work

    void *d_pointer = init_gpu(); // virtuelle adresse gpu memory

    static uint64_t* rx_desc_base_virt = (uint64_t*) d_pointer;
    static uint64_t* tx_desc_base_virt = (uint64_t*) d_pointer + 8*4096/8; //4096 byte per ring, up to 8 rx rings

    printf("RINGS: %d\n",RINGS);

    init_empty_desc<<<1,1>>>();
    cudaDeviceSynchronize();
    err = cudaGetLastError();
    if(err!=cudaSuccess){
        printf("init_empty_desc failed!! err:%d\n",err);
    }
    
    cudaStream_t stream1, stream2;
    cudaStreamCreateWithFlags(&stream1, cudaStreamNonBlocking); 
    cudaStreamCreateWithFlags(&stream2, cudaStreamNonBlocking);
    receive<<<1,RINGS, 0, stream1>>>(rx_desc_base_virt, rdt_reg);
    send<<<1,RINGS, 0, stream2>>>(tx_desc_base_virt, tdt_reg);
    

    printf("Press ENTER key to terminate (Currently not working)\n");
    getchar(); 
    printf("stop\n");

    cudaPointerAttributes attrs;
    cudaPointerGetAttributes(&attrs, d_pointer);
    unpin_mem((uint64_t) attrs.devicePointer);
    cudaFree(&d_pointer);
    cudaHostUnregister((void*)rdt_reg);
    cudaHostUnregister((void*)tdt_reg);
    return 0;
}
