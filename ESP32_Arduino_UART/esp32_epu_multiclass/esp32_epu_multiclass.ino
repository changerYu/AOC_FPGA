/*
 * ESP32 -> UART -> Nexys Video FPGA  (full SoC mode-1, multi-class demo)
 *
 * Holds 4 prepared 544-word EPU input images (real MIT-BIH beats of classes
 * N/S/V/F) and sends the one you select over UART. The FPGA's UART loader writes
 * it into the buffer BRAM; you then press the FPGA reset button (BTNC) and the
 * CPU re-boots, DMAs the buffer -> EPU GLB, and classifies. The result on the
 * FPGA LEDs should match the selected class.
 *
 * Select a class by typing one character in the Serial Monitor:
 *   n -> class N (score 0x67)    v -> class V (score 0x65)
 *   s -> class S (score 0x6B)    f -> class F (score 0x8A)
 * (Q is omitted: too few training samples, the model can't classify it.)
 *
 * Expected FPGA LEDs after sending + pressing BTNC:
 *   sw=00 -> score (per table)        sw=01 -> LED7=valid, LED2:0 = class index
 *   sw=10 -> LED7=rx_seen LED6=uart_err LED5=data_ready (watch before reset)
 *
 * Preprocessing/quantization/tiling is all done on the PC; the FPGA only ever
 * receives the ready-made 544-word image, never raw ECG.
 *
 * UART frame (matches uart_buffer_loader.sv):
 *   0xAA 0x55 | 544 words x 4 bytes (little-endian) = 2176 payload bytes
 *             | 1 XOR-checksum byte over the 2176 payload bytes
 *
 * Wiring (ESP32 <-> FPGA Pmod JA, both 3.3 V):
 *   ESP32 GPIO17 (TX2) -> FPGA JA1 = AB22  (FPGA uart_rxd)
 *   ESP32 GND          -> FPGA JA pin 5 or 11 (GND)
 *
 * Demo flow:
 *   1) type a class letter in Serial Monitor (e.g. 'v')
 *   2) wait for "Sent frame" / on the FPGA sw=10 LED5 (data_ready) goes high
 *   3) press the FPGA BTNC (reset) -> FPGA shows the class
 */

#include "samples.h"

#define UART2_TX    17
#define UART2_RX    16
#define UART2_BAUD  115200

#define HDR0  0xAA
#define HDR1  0x55

void sendSample(const sample_desc_t *s) {
  Serial2.write((uint8_t)HDR0);
  Serial2.write((uint8_t)HDR1);

  uint8_t csum = 0;
  for (int i = 0; i < SAMPLE_NWORDS; i++) {
    uint32_t w = s->words[i];
    for (int b = 0; b < 4; b++) {          // little-endian: LSB first
      uint8_t by = (uint8_t)((w >> (8 * b)) & 0xFF);
      Serial2.write(by);
      csum ^= by;
    }
  }
  Serial2.write(csum);
  Serial2.flush();

  Serial.printf("Sent class %s frame: %d payload bytes, checksum=0x%02X\n",
                s->name, SAMPLE_NWORDS * 4, csum);
  Serial.printf("  -> now press FPGA BTNC (reset). Expect class %s (index %u), score 0x%02X.\n",
                s->name, s->cls, s->score);
}

void printMenu() {
  Serial.println("------------------------------------------");
  Serial.println("Select a class to send (type the letter):");
  for (int i = 0; i < NUM_SAMPLES; i++) {
    Serial.printf("  %c -> class %s  (expect index %u, score 0x%02X)\n",
                  SAMPLES[i].key, SAMPLES[i].name, SAMPLES[i].cls, SAMPLES[i].score);
  }
  Serial.println("Then press FPGA BTNC (reset) to classify.");
  Serial.println("------------------------------------------");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX, UART2_TX);

  Serial.println("==========================================");
  Serial.println("ESP32 -> UART -> FPGA full-SoC mode-1 multi-class demo");
  Serial.printf("UART2: TX=GPIO%d -> FPGA JA1(AB22), %d 8N1\n", UART2_TX, UART2_BAUD);
  Serial.println("==========================================");
  printMenu();
}

void loop() {
  if (Serial.available()) {
    int c = Serial.read();
    if (c == '\n' || c == '\r' || c == ' ') return;
    const sample_desc_t *sel = nullptr;
    for (int i = 0; i < NUM_SAMPLES; i++) {
      if ((int)SAMPLES[i].key == c || (int)SAMPLES[i].name[0] == (c & ~0x20)) {
        sel = &SAMPLES[i];
        break;
      }
    }
    if (sel) sendSample(sel);
    else {
      Serial.printf("Unknown class '%c'.\n", (char)c);
      printMenu();
    }
  }
  delay(10);
}
