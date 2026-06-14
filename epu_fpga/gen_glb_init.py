#!/usr/bin/env python3
# gen_glb_init.py
# Build the GLB (EPU System SRAM) initialization image for standalone EPU-first
# FPGA bring-up. This reproduces the post-DMA GLB state without needing the
# RISC-V firmware: input at word 0, weights at word 1024, everything else 0.
#
# Layout source of truth (hardware/sim/fpga/link.ld, hw-confirmed):
#   glb region : 0x30000, 0x20000 bytes = 32768 words of 32 bit
#   __input_glb_word_base  = 0       <- in.dat
#   __weight_glb_word_base = 1024    <- weight.dat (decoder.sv BASE_POS_EMBED=1024)
#
# in.dat / weight.dat are text, one 32-bit hex word per line (see txt2bin.py).
#
# Usage:
#   python gen_glb_init.py                       -> glb_init.hex (input + weights)
#   python gen_glb_init.py --zero-input \
#          --out glb_init_zeroinput.hex          -> weights only, input region 0
#
# The --zero-input image is a diagnostic: a board built with it produces a
# NON-golden result with no UART, and the golden result only when the real input
# is streamed in over UART -> airtight proof the result comes from UART.

import argparse
import sys
from pathlib import Path

GLB_WORDS          = 1 << 15   # 32768
INPUT_WORD_BASE    = 0
WEIGHT_WORD_BASE   = 1024

HERE = Path(__file__).resolve().parent
SIM_FPGA = HERE.parent / "AOC-vcs-version" / "hardware" / "sim" / "fpga"
IN_DAT     = SIM_FPGA / "in.dat"
WEIGHT_DAT = SIM_FPGA / "weight.dat"


def load_words(path):
    words = []
    for line_num, raw in enumerate(path.read_text().splitlines(), 1):
        s = raw.strip()
        if not s:
            continue
        try:
            words.append(int(s, 16) & 0xFFFFFFFF)
        except ValueError:
            sys.exit(f"{path.name}:{line_num}: not valid hex: {s!r}")
    return words


def place(mem, base, words, name):
    end = base + len(words)
    if end > GLB_WORDS:
        sys.exit(f"{name}: {len(words)} words @ {base} overruns GLB ({GLB_WORDS})")
    mem[base:end] = words
    return base, end


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="glb_init.hex", help="output hex filename")
    ap.add_argument("--zero-input", action="store_true",
                    help="leave the input region (words 0..543) zero; weights only")
    args = ap.parse_args()

    inp = load_words(IN_DAT)
    wgt = load_words(WEIGHT_DAT)

    mem = [0] * GLB_WORDS
    if args.zero_input:
        i0 = i1 = 0
        print("input : ZEROED (diagnostic: real input must arrive via UART)")
    else:
        i0, i1 = place(mem, INPUT_WORD_BASE, inp, "input")
        print(f"input : {len(inp):5d} words -> GLB[{i0}..{i1-1}]")

    w0, w1 = place(mem, WEIGHT_WORD_BASE, wgt, "weight")
    if i1 > w0:
        sys.exit(f"input [{i0},{i1}) overlaps weight base {w0}")

    out_path = HERE / args.out
    out_path.write_text("".join(f"{w:08X}\n" for w in mem))
    print(f"weight: {len(wgt):5d} words -> GLB[{w0}..{w1-1}]")
    print(f"wrote {out_path} ({GLB_WORDS} words)")


if __name__ == "__main__":
    main()
