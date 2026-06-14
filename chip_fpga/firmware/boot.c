#include <stdint.h>

extern unsigned int __imem_load_start;
extern unsigned int __imem_size_bytes;
extern unsigned int _imem_start;

extern unsigned int __sdata_start;
extern unsigned int __sdata_end;
extern unsigned int __sdata_paddr_start;

extern unsigned int __data_start;
extern unsigned int __data_end;
extern unsigned int __data_paddr_start;

/* New linker symbols from link.ld */
extern unsigned int __input_load_start;
extern unsigned int __input_glb_dst;
extern unsigned int __input_size_bytes;

extern unsigned int __weight_load_start;
extern unsigned int __weight_glb_dst;
extern unsigned int __weight_size_bytes;

#define DMA_BASE_ADDR       0x10020000
#define DMAEN_REG           (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x100))
#define DESC_BASE_REG       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x200))

// Mode-1 (M1a): the ECG input no longer goes straight ROM->GLB. Instead boot
// stages it into the FPGA buffer (AXI slave S5 @ 0x20000000), mimicking what
// the UART RX path will later do at run time, and main.c then DMAs it from the
// buffer into the EPU GLB on each iteration. Weight still goes ROM->GLB once.
#define FPGA_BUFFER_BASE    0x20000000

#define MSTATUS_VAL         0x1808
#define MIE_VAL             0x880

typedef struct {
    volatile uint32_t src;
    volatile uint32_t dst;
    volatile uint32_t len;
    volatile uint32_t next;
    volatile uint32_t eoc;
} dma_desc_t;

#define DESC_0_ADDR         0x0002FF00
#define DESC_1_ADDR         0x0002FF14
#define DESC_2_ADDR         0x0002FF28
#define DESC_3_ADDR         0x0002FF3C
#define DESC_4_ADDR         0x0002FF50

#define DESC_0              ((dma_desc_t *)DESC_0_ADDR)
#define DESC_1              ((dma_desc_t *)DESC_1_ADDR)
#define DESC_2              ((dma_desc_t *)DESC_2_ADDR)
#define DESC_3              ((dma_desc_t *)DESC_3_ADDR)
#define DESC_4              ((dma_desc_t *)DESC_4_ADDR)

void boot() {
    asm volatile("csrw mstatus, %0" :: "r"(MSTATUS_VAL));
    asm volatile("csrw mie, %0"     :: "r"(MIE_VAL));

    // ROM -> IMEM
    DESC_0->src  = (uint32_t)&__imem_load_start;
    DESC_0->dst  = (uint32_t)&_imem_start;
    DESC_0->len  = (uint32_t)&__imem_size_bytes;
    DESC_0->next = DESC_1_ADDR;
    DESC_0->eoc  = 0;

    // ROM -> SDATA
    DESC_1->src  = (uint32_t)&__sdata_paddr_start;
    DESC_1->dst  = (uint32_t)&__sdata_start;
    DESC_1->len  = (uint32_t)&__sdata_end - (uint32_t)&__sdata_start;
    DESC_1->next = DESC_2_ADDR;
    DESC_1->eoc  = 0;

    // ROM -> DATA
    DESC_2->src  = (uint32_t)&__data_paddr_start;
    DESC_2->dst  = (uint32_t)&__data_start;
    DESC_2->len  = (uint32_t)&__data_end - (uint32_t)&__data_start;
    DESC_2->next = DESC_3_ADDR;
    DESC_2->eoc  = 0;

    // ROM -> FPGA buffer (S5 @ 0x20000000), staging the input there instead of
    // straight into GLB. main.c will move it buffer -> GLB before each EPU run.
    DESC_3->src  = (uint32_t)&__input_load_start;
    DESC_3->dst  = FPGA_BUFFER_BASE;
    DESC_3->len  = (uint32_t)&__input_size_bytes;
    DESC_3->next = DESC_4_ADDR;
    DESC_3->eoc  = 0;

    // ROM -> GLB weight/param region
    // GLB dst = 0x00030000 + 1024 * 4 = 0x00031000
    DESC_4->src  = (uint32_t)&__weight_load_start;
    DESC_4->dst  = (uint32_t)&__weight_glb_dst;
    DESC_4->len  = (uint32_t)&__weight_size_bytes;
    DESC_4->next = 0;
    DESC_4->eoc  = 1;

    // Activate DMA
    DESC_BASE_REG = DESC_0_ADDR;
    DMAEN_REG     = 1;

    asm volatile("wfi");
}