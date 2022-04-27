// Author: Leonard Anderweit, Jonas Markussen
// based on this tutorial: https://embetronicx.com/tutorials/linux/device-drivers/ioctl-tutorial-in-linux/

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/pci.h>
#include <linux/kdev_t.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/slab.h>                 //kmalloc()
#include <linux/uaccess.h>              //copy_to/from_user()
#include <linux/ioctl.h>

#include "/usr/src/nvidia-460-460.32.03/nvidia/nv-p2p.h"

struct ioctl_args {
    u64 vaddr;
    u64 size;
    u32 bus;
    u32 devfn;
} args;

// ioctl commands
#define PIN_MEM         _IOW('a',0,struct ioctl_args*)
#define UNPIN_MEM       _IOW('a',1,void**)
#define RD_ADDR         _IOR('a',2,u64**)

// for boundary alignment requirement
#define GPU_BOUND_SHIFT   16
#define GPU_BOUND_SIZE    ((u64)1 << GPU_BOUND_SHIFT)
#define GPU_BOUND_OFFSET  (GPU_BOUND_SIZE-1)
#define GPU_BOUND_MASK    (~GPU_BOUND_OFFSET)


dev_t dev = 0;
static struct class *dev_class;
static struct cdev etx_cdev;

/*
** Function Prototypes
*/
static int      __init etx_driver_init(void);
static void     __exit etx_driver_exit(void);
static long     etx_ioctl(struct file *file, unsigned int cmd, unsigned long arg);

/*
** File operation sturcture
*/
static struct file_operations fops = {
        .owner          = THIS_MODULE,
        .unlocked_ioctl = etx_ioctl,
};


struct gpu_mapping {
        u64 vaddr;
        struct pci_dev *pdev;
        nvidia_p2p_page_table_t *pages;
        nvidia_p2p_dma_mapping_t *mappings;
};

struct gpu_mapping *m;


/* this is called if the GPU needs to take back the memory for some reason, for example if the CUDA program crashes */
static void force_release_gpu_mappings(struct gpu_mapping *m) {
        nvidia_p2p_free_dma_mapping(m->mappings);
        nvidia_p2p_free_page_table(m->pages);
        kfree(m);
}

/* you should ideally rely on this for cleaning up mappings and unpinning GPU memory */
void clean_unmap(struct gpu_mapping *m) {
        nvidia_p2p_dma_unmap_pages(m->pdev, m->pages, m->mappings);
        nvidia_p2p_put_pages(0, 0, m->vaddr, m->pages);
        kfree(m);
}

struct gpu_mapping* create_mappings(struct pci_dev *pdev, u64 device_pointer_address, size_t size) {
        int ret;
        struct gpu_mapping *m;
        /* …. */
        m = kmalloc(sizeof(*m), GFP_KERNEL);

        m->vaddr = device_pointer_address; /* same value as attrs.devicePointer */
        /* tells the CUDA driver to pin memory and make it available as device memory */
        ret = nvidia_p2p_get_pages(
        0, /* deprecated */
        0, /* deprecated */
        m->vaddr, size, /* aligned to 64 KB */ 
        &m->pages,
        (void (*)(void*)) force_release_gpu_mappings,
        m);
        printk(KERN_INFO "get_pages return: %d", ret);

        m->pdev = pdev; /* pdev should be the pci_dev representation of your NIC */

        /* make the memory addresses available for a third-party device */
        ret = nvidia_p2p_dma_map_pages(pdev, m->pages, &m->mappings);
        printk(KERN_INFO "map_pages return: %d", ret);

        /* the I/O addresses are in m->mappings->dma_addresses[ i ] */

        /* ….. */
        return m;
}

/*
** This fuction will be called when we write IOCTL on the Device file
*/
static long etx_ioctl(struct file *file, unsigned int cmd, unsigned long arg) {
        switch(cmd) {
                case PIN_MEM:
                        copy_from_user(&args ,(char*) arg, sizeof(args));
                        struct pci_dev *nic;
                        nic = pci_get_domain_bus_and_slot(0x0000, args.bus, args.devfn);
                        if(nic==NULL){
                                printk(KERN_INFO "nic not found");
                                return 0;
                        }
                        m = create_mappings(nic, args.vaddr, args.size);
                        printk(KERN_INFO "addr = %llx\n", m->mappings->dma_addresses[0]);
                        break;
                case UNPIN_MEM:
                        clean_unmap(m);
                        break;
                case RD_ADDR:
                        if(m==NULL){
                                printk(KERN_INFO "no memory mapped");
                        }else{
                                copy_to_user((u64*) arg, &m->mappings->dma_addresses[0], sizeof(u64));
                        }
                        break;
        }
        return 0;
}
 
/*
** Module Init function
*/
static int __init etx_driver_init(void) {
        /*Allocating Major number*/
        if((alloc_chrdev_region(&dev, 0, 1, "etx_Dev")) <0){
                printk(KERN_INFO "Cannot allocate major number\n");
                return -1;
        }
 
        /*Creating cdev structure*/
        cdev_init(&etx_cdev,&fops);
 
        /*Adding character device to the system*/
        if((cdev_add(&etx_cdev,dev,1)) < 0){
            printk(KERN_INFO "Cannot add the device to the system\n");
            goto r_class;
        }
 
        /*Creating struct class*/
        if((dev_class = class_create(THIS_MODULE,"etx_class")) == NULL){
            printk(KERN_INFO "Cannot create the struct class\n");
            goto r_class;
        }
 
        /*Creating device*/
        if((device_create(dev_class,NULL,dev,NULL,"etx_device")) == NULL){
            printk(KERN_INFO "Cannot create the Device 1\n");
            goto r_device;
        }
        printk(KERN_INFO "Device Driver Insert...Done!!!\n");
        return 0;
 
r_device:
        class_destroy(dev_class);
r_class:
        unregister_chrdev_region(dev,1);
        return -1;
}

/*
** Module exit function
*/
static void __exit etx_driver_exit(void) {
        device_destroy(dev_class,dev);
        class_destroy(dev_class);
        cdev_del(&etx_cdev);
        unregister_chrdev_region(dev, 1);
        printk(KERN_INFO "Device Driver Remove...Done!!!\n");
}
 
module_init(etx_driver_init);
module_exit(etx_driver_exit);
 
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Leonard Anderweit, Jonas Markussen");
MODULE_DESCRIPTION("cuda pin memory");
MODULE_VERSION("0.01");
