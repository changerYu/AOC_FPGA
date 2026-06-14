OUTPUT_ARCH( "riscv" )
_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x1000;
/*****************************************************************************
 * Define memory layout
 ****************************************************************************/
MEMORY {
  rom    : ORIGIN = 0x00000000, LENGTH = 0x00008000
  imem   : ORIGIN = 0x00010000, LENGTH = 0x00010000
  dmem   : ORIGIN = 0x00020000, LENGTH = 0x00010000
  glb    : ORIGIN = 0x00030000, LENGTH = 0x00020000
}
ENTRY(_start)

/*****************************************************************************
 * Define the sections
 ****************************************************************************/
SECTIONS {
  .text0 : {
    setup.o(.text);
    boot.o(.text);
  } > rom
  .text1 : {
    . = ALIGN(4);
    _imem_start = .;
    isr.o(.text);
    main.o(.text);
    *(.text);
    *(.text.*);
  } > imem AT > rom
  .init : { KEEP (*(.init)) } > imem AT > rom
  .fini : { KEEP (*(.fini)) } > imem AT > rom
  .rodata : {
    __rodata_start = .;
    *(.rodata); *(.rodata.*); *(.gnu.linkonce.r.*);
    __rodata_end = .;
  } > imem AT > rom
  . = ALIGN(4);
  _imem_end = .;
  __imem_load_start = LOADADDR(.text1);
  __imem_load_end = LOADADDR(.rodata) + SIZEOF(.rodata);
  __imem_size_bytes = __imem_load_end - __imem_load_start;
  __glb_base = ORIGIN(glb);
  __input_glb_word_base  = 0;
  __weight_glb_word_base = 1024;
  __input_glb_dst  = ORIGIN(glb) + (__input_glb_word_base * 4);
  __weight_glb_dst = ORIGIN(glb) + (__weight_glb_word_base * 4);
  .glb_input ORIGIN(glb) : {
    . = ALIGN(4);
    __input_load_start = LOADADDR(.glb_input);
    __input_start = .;
    KEEP(in.o(.data))
    KEEP(in.o(.data.*))
    KEEP(in.o(.rodata))
    KEEP(in.o(.rodata.*))
    . = ALIGN(4);
    __input_end = .;
  } > glb AT > rom
  __input_load_end = LOADADDR(.glb_input) + SIZEOF(.glb_input);
  __input_size_bytes = SIZEOF(.glb_input);
  __input_size_words = SIZEOF(.glb_input) / 4;
  .glb_weight (ORIGIN(glb) + 0x1000) : {
    . = ALIGN(4);
    __weight_load_start = LOADADDR(.glb_weight);
    __weight_start = .;
    KEEP(weight.o(.data))
    KEEP(weight.o(.data.*))
    KEEP(weight.o(.rodata))
    KEEP(weight.o(.rodata.*))
    . = ALIGN(4);
    __weight_end = .;
  } > glb AT > rom
  __weight_load_end = LOADADDR(.glb_weight) + SIZEOF(.glb_weight);
  __weight_size_bytes = SIZEOF(.glb_weight);
  __weight_size_words = SIZEOF(.glb_weight) / 4;
  __glb_end = __weight_end;
  .sbss : {
    __sbss_start = .;
    *(.sbss); *(.sbss.*); *(.gnu.linkonce.sb.*);
    __sbss_end = .;
  } > dmem
  .sdata : {
    __sdata_paddr_start = LOADADDR(.sdata);
    __sdata_start = .;
    _gp = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
    __sdata_end = .;
  } > dmem AT > rom
  .data : {
    . = ALIGN(4);
    __data_paddr_start = LOADADDR(.data);
    __data_start = .;
    *(.data); *(.data.*); *(.gnu.linkonce.d.*);
    __data_end = .;
  } > dmem AT > rom
  .bss : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss); *(.bss.*); *(.gnu.linkonce.b.*); *(COMMON);
    . = ALIGN(4);
    __bss_end = .;
  } > dmem
  .stack : {
    . = ALIGN(4);
    _stack_end = .;
    . += _STACK_SIZE;
    _stack = .;
    __stack = _stack;
  } > dmem
  . = ORIGIN(dmem) + LENGTH(dmem) - 4;
  _sim_end = .;
  . += 4;
  _end = .;
}
