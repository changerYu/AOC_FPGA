ELF_NAME := main

export CROSS_PREFIX ?= riscv64-unknown-elf-
export RISCV_GCC ?= $(CROSS_PREFIX)gcc
export RISCV_OBJDUMP ?= $(CROSS_PREFIX)objdump -xsd
export RISCV_OBJCOPY ?= $(CROSS_PREFIX)objcopy -O verilog


LDFILE := link.ld
# CFLAGS := -march=rv32imf -mabi=ilp32
# LDFLAGS := -static -nostdlib -nostartfiles -march=rv32im -mabi=ilp32 -T$(LDFILE) -lgcc
#CFLAGS := -march=rv32imf_zbb_zbs -mabi=ilp32
CFLAGS_C := -march=rv32imf -mabi=ilp32
CFLAGS_S := -march=rv32imf -mabi=ilp32
LDFLAGS := -static -nostdlib -nostartfiles -march=rv32imf -mabi=ilp32 -T$(LDFILE) -lgcc
PYTHON_CMD := python3


SRC_C := $(wildcard *.c)
OBJ_C := $(patsubst %.c,%.o,$(SRC_C))
SRC_S := $(wildcard *.S)
OBJ_S := $(patsubst %.S,%.o,$(SRC_S))
SRC_DAT := $(wildcard *.dat)
OBJ_DAT := $(patsubst %.dat,%.o,$(SRC_DAT))

SRC := $(SRC_C) $(SRC_S) $(SRC_DAT)
OBJ := $(OBJ_C) $(OBJ_S) $(OBJ_DAT)

.SUFFIXES: .o .S .c

.PHONY: all

all: build_elf build_log build_hex

build_elf: $(OBJ) | $(LDFILE)
	$(RISCV_GCC) $^ $(LDFLAGS) -o $(ELF_NAME)

%.o: %.dat
	$(PYTHON_CMD) txt2bin.py $^ $@.bin
	@echo "Converting $^ to $@"
	$(RISCV_OBJCOPY) -I binary -O elf32-littleriscv -B riscv $@.bin $@
	$(RISCV_OBJDUMP) -d $@ > $@.log
	rm $@.bin

build_log: $(ELF_NAME)
	$(RISCV_OBJDUMP) $< > $(ELF_NAME).log

build_hex: $(ELF_NAME)
	$(RISCV_OBJCOPY) $< -i 4 -b 0 -j .text0 -j .text1 -j .init -j .fini -j .rodata -j .sdata -j .data -j .glb_input -j .glb_weight --change-addresses 0 rom0.hex
	$(RISCV_OBJCOPY) $< -i 4 -b 1 -j .text0 -j .text1 -j .init -j .fini -j .rodata -j .sdata -j .data -j .glb_input -j .glb_weight --change-addresses 0 rom1.hex
	$(RISCV_OBJCOPY) $< -i 4 -b 2 -j .text0 -j .text1 -j .init -j .fini -j .rodata -j .sdata -j .data -j .glb_input -j .glb_weight --change-addresses 0 rom2.hex
	$(RISCV_OBJCOPY) $< -i 4 -b 3 -j .text0 -j .text1 -j .init -j .fini -j .rodata -j .sdata -j .data -j .glb_input -j .glb_weight --change-addresses 0 rom3.hex

#%.o: %.S
#	$(RISCV_GCC) -c $(CFLAGS) $^

#%.o: %.c
#	$(RISCV_GCC) -c $(CFLAGS) $^

%.o: %.c
	$(RISCV_GCC) -c $(CFLAGS_C) $^

%.o: %.S
	$(RISCV_GCC) -c $(CFLAGS_S) $^

.PHONY: clean

clean:
	rm -rf $(ELF_NAME) $(ELF_NAME).log rom*.hex dram*.hex *.o *.log *.txt
