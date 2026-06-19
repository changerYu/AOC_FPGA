#include <stdint.h>

#define MIP_MEIP (1 << 11)
#define MIP_MTIP (1 << 7)
#define MIP      0x344

#define WDT_BASE_ADDR       0x10010000
#define DMA_BASE_ADDR       0x10020000
#define EPU_START_ADDR      0x00060000
// M2A: writing the EPU reg region sub-address 0x04 clears the frame-ready
// interrupt latched by EPU_Wrapper when the UART loader fills the buffer BRAM.
#define FRAME_CLEAR_ADDR    0x00060004
// M2A: sub-address 0x08 is the per-run EPU soft reset (bit0). The EPU only runs
// clean once after a hard reset; pulse this before each EPU_start so every
// classification gets a freshly re-initialized EPU (GLB BRAM contents survive).
#define EPU_SRESET_ADDR     0x00060008

// The CPU moves the ECG input from the FPGA buffer (AXI slave S5 @ 0x20000000)
// into the EPU GLB input region, then starts the EPU. In M2A the buffer is fed
// continuously by the UART loader; each completed frame raises a frame-ready
// interrupt and the CPU classifies it, then the hardware sends one UART ACK to
// the ESP32 (on EPU done) so the next frame may be sent. No button / reset.
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

volatile uint32_t *WDT_addr    = (volatile uint32_t *)WDT_BASE_ADDR;
volatile uint32_t *EPU_start   = (volatile uint32_t *)EPU_START_ADDR;
volatile uint32_t *FRAME_CLEAR = (volatile uint32_t *)FRAME_CLEAR_ADDR;
volatile uint32_t *EPU_SRESET  = (volatile uint32_t *)EPU_SRESET_ADDR;

void timer_interrupt_handler(void) {
  asm volatile("csrci mstatus, 0x8"); // clear MIE of mstatus
  WDT_addr[0x40] = 0;                 // WDT_en = 0
  asm volatile("j _start");
}

void external_interrupt_handler(void) {
  asm volatile("csrci mstatus, 0x8"); // clear MIE of mstatus

  // The CPU external interrupt is the OR of three level sources: the DMA
  // completion, the EPU done, and the M2A frame-ready latch. They fire in a
  // deterministic order in the loop below, so the handler just clears all
  // three every time -- clearing an inactive source is harmless. Clearing the
  // frame-ready latch here (rather than in main) is essential: a level that is
  // still asserted on return from the trap would re-trap forever.
  DMAEN_REG    = 0;   // clear DMA completion
  EPU_start[0] = 0;   // clear EPU done (cpu_response)
  FRAME_CLEAR[0] = 0; // clear frame-ready latch (any write)
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

  // --- M2A continuous classify loop (strict handshake) ---------------------
  // 1) sleep until a full UART frame has landed in the buffer BRAM
  // 2) DMA the buffer -> EPU GLB input, wait for completion
  // 3) start the EPU, wait for done (the EPU-done pulse sends the ACK in HW)
  // The ACK lets the ESP32 send the next frame, so step 1 wakes again.
  //
  // The descriptor is re-initialized EVERY iteration (not once before the loop):
  // boot rebuilds its descriptor chain on each reset, and a single-shot main only
  // ever ran one transfer, so descriptor REUSE across iterations was never tested.
  // If the DMA engine consumes/updates the descriptor in DMEM, a stale descriptor
  // would make the next transfer never complete and hang at the DMA wfi. Writing
  // it fresh each iteration is cheap and removes that failure mode.
  for (;;) {
    asm volatile("wfi");                  // wait frame-ready interrupt

    DESC_M->src  = FPGA_BUFFER_BASE;              // 0x20000000
    DESC_M->dst  = (uint32_t)&__input_glb_dst;    // 0x00030000
    DESC_M->len  = (uint32_t)&__input_size_bytes; // 2176 bytes (544 words)
    DESC_M->next = 0;
    DESC_M->eoc  = 1;

    DESC_BASE_REG = DESC_M_ADDR;
    DMAEN_REG     = 1;
    asm volatile("wfi");                  // wait DMA completion interrupt

    // Soft-reset the EPU before every run so its internal FSMs/counters start
    // clean (the GLB BRAM weights+input survive). Two writes guarantee the
    // reset is held low for >1 cycle before being released.
    EPU_SRESET[0] = 1;                    // assert EPU reset
    EPU_SRESET[0] = 0;                    // release EPU reset

    EPU_start[0] = 1;
    asm volatile("wfi");                  // wait EPU done interrupt -> ACK sent
    EPU_start[0] = 0;                     // explicit guard (handler already did)
  }

  return 0;
}
