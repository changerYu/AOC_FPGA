# ESP32 multi-class demo (full-SoC mode-1)

Send real MIT-BIH ECG beats of different classes over UART to the FPGA and watch
the hand-built SoC classify each one. The FPGA bitstream is unchanged
(`chip_fpga/release/chip_top_m1c.bit`); multi-class is purely the data sent.

## Files
- `esp32_epu_multiclass.ino` — pick a class (type a letter in Serial Monitor), send it.
- `samples.h` — 4 prepared 544-word input images (classes N/S/V/F), auto-generated.

## How the samples were made (PC side, already done)
1. `extract_mitdb_one_case_layer_io.py --label {N,S,V,F} --label-occurrence 0
   --split test_clean` → a dense 198-ECG + 2-RR uint8 packet per class
   (from `software/datasets/mitdb`, requires numpy/scipy/wfdb/sklearn/torch).
2. `chip_fpga/tools/pack_glb_input.py` → the 544-word tiled GLB image
   (3 ECG samples per word at stride 4, byte3 = ECG zero-point 0x31; RR at
   word 512, padding = RR zero-point 0x7F). Verified byte-exact against the
   golden N image.
3. `chip_fpga/tools/gen_multiclass_header.py` → `samples.h`.

Each sample's expected class/score was confirmed with the bittrue golden model
(argmax of the 5 logits). Q is omitted — too few training samples to classify.

## Wiring (same as B1)
- ESP32 GPIO17 (TX2) -> FPGA JA1 = AB22 (uart_rxd)
- ESP32 GND          -> FPGA JA pin 5 or 11 (GND)

## Demo steps
1. Flash the FPGA with `chip_top_m1c.bit` (USB), power on.
2. Flash this sketch to the ESP32; open Serial Monitor @ 115200.
3. Type a class letter (`n`/`s`/`v`/`f`). The ESP32 sends that frame.
   - On the FPGA, sw=10: LED5 (data_ready) goes high, LED6 (uart_err) stays low.
4. Press the FPGA **BTNC** (reset) — the SoC re-runs on the new buffer contents.
5. Read the result:
   - **sw=01** -> LED7 = valid, LED2:0 = class index
     (N=000, S=001, V=010, F=011)
   - **sw=00** -> score (N=0x67, S=0x6B, V=0x65, F=0x8A)
6. Repeat for other classes.

> Order matters: send the frame, wait for data_ready, THEN press BTNC. Pressing
> reset first just re-classifies whatever is currently in the buffer.
