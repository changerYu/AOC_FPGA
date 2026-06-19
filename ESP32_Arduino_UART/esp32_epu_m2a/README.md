# esp32_epu_m2a — M2A continuous handshake demo

Self-running continuous classification with an FPGA↔ESP32 handshake. No button
or reset press per sample (unlike the M1c / multiclass demos).

## Flow

```
ESP32 send frame ──TX(GPIO17)──► FPGA uart_rxd(JA1/AB22) ─► buffer BRAM
                                                              │
                                       CPU: DMA buffer→GLB, start EPU, classify
                                                              │  EPU done
ESP32 send next  ◄──RX(GPIO16)◄── FPGA uart_txd(JA7/Y21) ◄────┘  (HW sends ACK 0x06)
```

1. ESP32 sends a 544-word frame.
2. FPGA loader stores it in the buffer BRAM → raises a frame-ready interrupt.
3. CPU DMAs buffer→EPU GLB, starts the EPU, classifies.
4. On EPU done the FPGA **hardware** sends one ACK byte (0x06) on its UART TX.
5. ESP32 receives the ACK → sends the next frame. Repeat.

Strict ping-pong: the ESP32 sends the next frame only after the ACK (EPU done),
so the buffer BRAM is never overwritten before the CPU has moved it out.

## Wiring (both 3.3 V, Pmod JA)

| ESP32 | dir | FPGA |
|---|---|---|
| GPIO17 (TX2) | → | JA1 = AB22 (uart_rxd) |
| GPIO16 (RX2) | ← | JA7 = Y21 (uart_txd / ACK) |
| GND | — | JA pin 5 or 11 |

## Use

1. Flash the FPGA with `chip_fpga/release/chip_top_m2a.bit` (USB).
2. Flash this sketch to the ESP32; open Serial Monitor @ 115200.
3. The ESP32 auto-sends the first frame (default class **N**); the FPGA classifies
   it and ACKs, and the loop runs on its own.
4. Type `n` / `s` / `v` / `f` to switch which class is repeated. The new class
   takes effect on the next send.
5. Watch the FPGA: `sw=01` shows the class index (N=000, S=001, V=010, F=011),
   `sw=00` shows the score, `sw=10` LED7=rx_seen / LED5=data_ready toggling.

For now the ESP32 repeats one canned MIT-BIH sample per ACK. This is the
stepping stone to the real-time ECG sensor front-end, where each ACK will instead
trigger sending the next freshly acquired + tiled beat. The FPGA bitstream does
not change for that step.

## Notes

- A retransmit timeout (800 ms) resends if no ACK arrives — this covers the very
  first frame and any lost ACK, so the handshake self-synchronizes. Because every
  ACK just re-sends the current sample, an early/duplicate ACK is harmless.
- `samples.h` is the same 4-class image set as `esp32_epu_multiclass`.
