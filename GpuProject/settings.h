#define DEBUG 1
#define P4STA 1
#define SWITCH 1
#define WB 1  //kostet bisschen performance
#define E810 1

#define RX_RING_SIZE 256
#define TX_RING_SIZE 256

// up to 32KB for tx/rx-descriptor-rings each e.g. 8 rings with 256 ring-size or 32 rings with 64 ring-size
#define RINGS 1

#define PKT_BUFFER_MULTIPLIER 16

#define PKT_BUFFER_SIZE (RX_RING_SIZE + TX_RING_SIZE) * PKT_BUFFER_MULTIPLIER 

#define MEM_PER_PKT 2048

#define MEM_SIZE RINGS * PKT_BUFFER_SIZE * MEM_PER_PKT + 16 * 4096 //64kb aligned - up to 8 rx and 8 tx rings each 4096 byte

#define DESC_SIZE 16

#if SWITCH
    #define GPU_MEM_ADDR 0x384000560000
#else
    #define GPU_MEM_ADDR 0x38ffe0560000
#endif

#define GPU_RX_DESC_ADDR GPU_MEM_ADDR
#define GPU_TX_DESC_ADDR GPU_MEM_ADDR + 8 * 4096
#define GPU_PKT_BUFFER_MEM_ADDR GPU_MEM_ADDR + 16 * 4096

#define NIC_RDT_OFFS 0x1018
#define NIC_TDT_OFFS 0x6018
#define NIC_REG_SIZE 512*1024
#define NIC_POINTER_OFFS 0x40

#if SWITCH
    #if P4STA
        #if E810
            #define NIC_BUS 0x1a
            #define NIC_DEVFN 0
            #define NIC_REG_ADDR 0x384018000000
        #else
            #define NIC_BUS 0x1b
            #define NIC_DEVFN 0
            #define NIC_REG_ADDR 0xaca00000
        #endif

    #else
        #define NIC_BUS 0x1b
        #define NIC_DEVFN 1
        #define NIC_REG_ADDR 0xaca80000
    #endif
#else
    #if P4STA
        #define NIC_BUS 0x65
        #define NIC_DEVFN 0
        #define NIC_REG_ADDR 0xc6000000
    #else
        #define NIC_BUS 0x65
        #define NIC_DEVFN 1
        #define NIC_REG_ADDR 0xc6080000
    #endif
#endif
