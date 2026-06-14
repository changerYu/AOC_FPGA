#include <stdint.h>

#define MIP_MEIP (1 << 11)
#define MIP_MTIP (1 << 7)
#define MIP      0x344

#define WDT_BASE_ADDR       0x10010000
#define DMA_BASE_ADDR       0x10020000
#define EPU_START_ADDR      0x00060000

// Mode-1 (M1a): per-iteration the CPU moves the ECG input from the FPGA buffer
// (AXI slave S5 @ 0x20000000) into the EPU GLB input region, then starts the
// EPU. boot.c stages the input into the buffer (later this is the UART RX job).
#define FPGA_BUFFER_BASE    0x20000000

#define MSTATUS_VAL         0x1808
#define MIE_VAL             0x880

#define DMAEN_REG           (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x100))
#define DESC_BASE_REG       (*(volatile uint32_t *)(DMA_BASE_ADDR + 0x200))

// Reuse the descriptor scratch slot in DMEM that boot.c used; it is free now.
#define DESC_M_ADDR         0x0002FF00

typedef struct {
    volatile uint32_t src;
    volatile uint32_t dst;
    volatile uint32_t len;
    volatile uint32_t next;
    volatile uint32_t eoc;
} dma_desc_t;

#define DESC_M ((dma_desc_t *)DESC_M_ADDR)

// Linker symbols: GLB input destination (0x00030000) and input size in bytes.
extern unsigned int __input_glb_dst;
extern unsigned int __input_size_bytes;

volatile uint32_t *WDT_addr  = (volatile uint32_t *)WDT_BASE_ADDR;
volatile uint32_t *EPU_start = (volatile uint32_t *)EPU_START_ADDR;

void timer_interrupt_handler(void) {
  asm volatile("csrci mstatus, 0x8"); // clear MIE of mstatus
  WDT_addr[0x40] = 0;                 // WDT_en = 0
  asm volatile("j _start");
}

void external_interrupt_handler(void) {
  asm volatile("csrci mstatus, 0x8"); // clear MIE of mstatus

  // Disable DMA on its completion interrupt (used both for the boot preload and
  // for the mode-1 buffer->GLB transfer below).
  DMAEN_REG = 0;

  // Deassert EPU start once the EPU done interrupt arrives. Harmless on the DMA
  // completion interrupt because EPU has not been started yet.
  EPU_start[0] = 0;
}

void trap_handler(void) {
  uint32_t mip;
  asm volatile("csrr %0, %1" : "=r"(mip) : "i"(MIP));

  if ((mip & MIP_MTIP) != 0) {
    timer_interrupt_handler();
  }

  if ((mip & MIP_MEIP) != 0) {
    external_interrupt_handler();
  }
}

int main(void) {
  asm volatile("csrw mstatus, %0" :: "r"(MSTATUS_VAL));
  asm volatile("csrw mie, %0"     :: "r"(MIE_VAL));

  // --- Mode-1 step: move the input from the FPGA buffer into the EPU GLB. ---
  // This is the per-sample data move that, in the full mode-1 flow, runs on a
  // trigger (button / UART data-ready). For M1a it runs once automatically so
  // the new firmware data path can be validated against the golden sample.
  DESC_M->src  = FPGA_BUFFER_BASE;                 // 0x20000000
  DESC_M->dst  = (uint32_t)&__input_glb_dst;       // 0x00030000
  DESC_M->len  = (uint32_t)&__input_size_bytes;    // 2176 bytes (544 words)
  DESC_M->next = 0;
  DESC_M->eoc  = 1;

  DESC_BASE_REG = DESC_M_ADDR;
  DMAEN_REG     = 1;
  asm volatile("wfi");                             // wait DMA completion interrupt

  // --- Start the EPU and wait for it to finish. ---
  EPU_start[0] = 1;
  asm volatile("wfi");                             // wait EPU done interrupt

  // external_interrupt_handler() already deasserted EPU_start; explicit guard.
  EPU_start[0] = 0;

  return 0;
}
