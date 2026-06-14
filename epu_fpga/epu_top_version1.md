# EPU on FPGA — `epu_top` Version 1 (known-good baseline)

**Status:** ✅ Built and **hardware-verified on Nexys Video** (2026-06-14).
**Bitstream:** `epu_fpga/build/epu_top.bit`
**Board:** Digilent Nexys Video — Artix-7 `XC7A200T` (`xc7a200tsbg484-1`)
**Clock:** single 100 MHz (pin R4), timing met (WNS > 0, no MMCM needed).

This document records exactly what this bitstream does and how the EPU's
correctness was verified, so this working state can be reproduced/restored even
if later work introduces regressions.

> Context: the AOC final project is graded in software (Ubuntu + Verilator); the
> FPGA bring-up is a self-imposed hardware challenge (bonus). This V1 proves the
> EPU accelerator runs end-to-end on real silicon, bit-exact to the VCS golden.

---

## 1. What this bitstream does

It runs **only the EPU** (the Transformer AI accelerator) of the AOC SoC,
standalone — **no CPU, no AXI, no ROM, no DMA, no firmware**. The EPU classifies
**one fixed ECG heartbeat sample** through the whole TinyArrhythmiaTransformer
pipeline and exposes the result on the board LEDs.

Pipeline executed inside the EPU (self-sequenced by its `global_controller`):

```
patch embed -> +pos -> LN1 -> Q/K/V -> QK^T -> log-domain softmax -> A·V
            -> out_proj -> +res1 -> LN2 -> FFN(ReLU) -> +res2 -> LN_cls
            -> sum pool -> head_ecg + head_rr -> logit add -> argmax
```

The model is the ~6643-param TinyArrhythmiaTransformer (PoT multiplier-free,
ReLU, log-domain softmax/LayerNorm, storage-aware UINT8 PE boundaries). The
EPU computes 5 class logits and does the **argmax internally**, driving
`result_class` / `result_score` / `result_valid` out of the chip.

Classes: `0=N, 1=S, 2=V, 3=F, 4=Q`.

---

## 2. How the input/weights get into the EPU (the key idea)

Normally the RISC-V CPU loads the EPU's internal SRAM (GLB) from ROM via DMA,
then writes the EPU start register. That path needs compiled firmware
(`rom0-3.hex`), which requires a RISC-V toolchain we don't have locally.

**V1 bypasses all of that** by pre-initializing the GLB block RAM directly with
the post-DMA image, using `$readmemh` at synthesis. The EPU then reads exactly
the same data it would have after a real DMA preload.

GLB memory map (from `AOC-vcs-version/hardware/sim/fpga/link.ld`, hardware-
confirmed by `decoder.sv BASE_POS_EMBED = 15'd1024`):

| GLB word range | Contents | Source |
|---|---|---|
| `0 .. 543`      | input (544 words)  | `sim/fpga/in.dat` |
| `544 .. 1023`   | zero (gap)         | — |
| `1024 .. 4479`  | weights (3456 words) | `sim/fpga/weight.dat` |
| `4480 .. 32767` | zero               | — |

GLB is 32768 words × 32 bit (`addr[14:0]`). The image is built by
`gen_glb_init.py` into `glb_init.hex` (one 8-hex-digit word per line).

EPU start semantics (from `EPU.sv`): `glb_preload_mode = !system_start_i`. While
`system_start_i = 0` the GLB is driven by the external System port (idle here);
on the **rising edge** of `system_start_i` the internal controller takes over and
computes from the pre-loaded GLB. `result_valid_o` latches the result after
`done_o`.

---

## 3. Files (all under `D:\AOC-final\epu_fpga\`)

| File | Role |
|---|---|
| `gen_glb_init.py` | Builds `glb_init.hex` from `in.dat` + `weight.dat` (input@0, weight@1024, rest 0). |
| `glb_init.hex` | 32768-word GLB init image (generated; the actual data baked into the BRAM). |
| `rtl/GLB.sv` | FPGA overlay of the EPU's GLB: `(* ram_style="block" *)` + `initial $readmemh(INIT_HEX, mem)`. **`INIT_HEX` is an ABSOLUTE path** (`D:/AOC-final/epu_fpga/glb_init.hex`) — see Gotcha #1. Original `EPU/GLB.sv` is left untouched for VCS/Verilator. |
| `rtl/epu_top.sv` | Board top: reset synchronizer + power-on hold, start FSM (one rising edge then held), `EPU` instance (System port idle), heartbeat, and an LED mux selected by `sw[1:0]`. |
| `constraints/epu_nexys_video.xdc` | Pin map: `clk100`→R4, `rst_btn`→BTNC(B22), `sw[1:0]`→E22/F21, `led[7:0]`→T14..Y13; `create_clock 10 ns`. |
| `build_epu.tcl` | Vivado project-mode build. Includes `src/EPU/*.sv` **minus** `EPU_Wrapper.sv` (AXI) and the original `GLB.sv`; adds the overlay + top + hex + XDC; `define.svh` set as global include. |
| `build/epu_top.bit` | The verified bitstream. |
| `build/utilization.rpt`, `build/timing_summary.rpt` | Build reports. |

EPU RTL source of truth: `D:\AOC-final\AOC-vcs-version\hardware\src\EPU\*.sv`
(the corrected FPGA branch, files dated 2026-06-12).

---

## 4. How to rebuild

```powershell
cd D:\AOC-final\epu_fpga
# (regenerate the GLB image if in.dat/weight.dat changed)
python gen_glb_init.py
# build: synth -> impl -> bitstream -> build\epu_top.bit
vivado -mode batch -source build_epu.tcl
```

Close any Vivado GUI on the project first (the script does a clean rebuild and
will fail to delete a locked project). Bitstream lands at `build\epu_top.bit`.

---

## 5. How EPU correctness was verified

**Golden reference:** `sim/fpga/golden.hex = 25113D67` (+`00000000`). These are
the final 5 uint8 logits packed little-endian:
`[0x67, 0x3D, 0x11, 0x25, 0x00]` = `[103, 61, 17, 37, 0]`.
→ argmax = index 0 → **class 0 (N)**, winning **score 0x67 = 103**.

**On-board observation.** `epu_top` multiplexes the LEDs by `sw[1:0]`:

| `sw[1:0]` | LED meaning | Expected | **Observed (2026-06-14)** |
|---|---|---|---|
| `00` | `result_score[7:0]` | `0x67` = `0110_0111` | ✅ correct (0x67) |
| `01` | LED7=`result_valid`, LED2:0=`result_class` | valid=1, class=`000` (N) | ✅ LED7 on, others off |
| `10` | LED3:0 = `layer_done,done,busy,result_valid` | valid=1, busy=0 | ✅ LED0(valid) & LED3(layer_done) on |
| `11` | heartbeat `hb[25:18]` | LEDs cycling | ✅ LED4–7 visibly blinking |

`done_o` is a one-cycle pulse, so at steady state (`sw=10`) it reads 0 while
`result_valid` stays latched at 1 and `busy=0` (not stuck) — the healthy
"finished and latched" state.

**Conclusion:** the FPGA EPU output (class N, score 103) is **bit-exact** to the
VCS simulation golden. End-to-end accelerator inference on hardware confirmed.

Build quality: 0 errors, 0 critical warnings, 157 benign warnings (unconnected
ports etc.; no latches, no multi-driver, no result-path truncation). Timing met
at 100 MHz.

Resource usage on XC7A200T (very comfortable):

| Resource | Used | Avail | % |
|---|---|---|---|
| Slice LUTs | 25167 | 134600 | 18.7 |
| Slice Registers | 21482 | 269200 | 8.0 |
| Block RAM (RAMB36) | 32 | 365 | 8.8 |
| DSP48 | 11 | 740 | 1.5 |
| Bonded IOB | 12 | 285 | 4.2 |

(DSP near-zero confirms the PoT multiplier-free datapath.)

---

## 6. Flashing (USB drive method)

1. **Delete every old `.bit` from the USB drive root** (USB-host config reads
   only one top-level bitstream — a stale one silently boots instead).
2. Copy `build\epu_top.bit` to the USB drive root.
3. Board jumpers **JP4 → USB/SD**, **JP3 → USB**. Insert into the USB Host port,
   power on. Toggle `sw[1:0]` to read the result per the table above.

Bitstream is volatile (lost on power-off); re-flash each power cycle.

---

## 7. Gotchas captured (do not regress)

1. **`$readmemh` must use an absolute path.** Vivado synthesis silently ignores
   a not-found bare-basename mem file (CRITICAL WARNING [Synth 8-4445]) → BRAM
   stays all-zero → EPU computes on zeros → wrong result with no error. Confirm
   the synth log says `... glb_init.hex' is read successfully`.
2. **USB drive: only one top-level `.bit`.** Clear old ones before copying.
3. **Close the Vivado GUI before rebuilding** (clean-rebuild deletes the project
   dir; an open GUI locks files).

---

## 8. What is NOT in V1 (future work)

- No CPU / AXI / cache / DMA / ROM / WDT — EPU only.
- Single hard-coded ECG sample (the one in `sim/fpga/in.dat`).
- No UART; results are read from LEDs only.

**Phase B (full SoC):** obtain `rom0-3.hex` (teammates build via RISC-V
toolchain in Docker, or install the toolchain locally), then build the whole
`CHIP` so the CPU autonomously DMA-loads the GLB, starts the EPU, and the same
`result_valid/class/score` appear on pins — demonstrating full HW/SW
integration. **Possible Phase A+ demo strengthening:** multiple ECG samples /
different classes (regenerate `glb_init.hex` per input, select via switches or
multiple bitstreams), and/or add a UART to stream logits to a PC.
