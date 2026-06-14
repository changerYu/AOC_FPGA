/*
 * ESP32 -> UART -> Nexys Video FPGA (standalone EPU, project B1)
 *
 * Sends one prepared 544-word EPU input image (the golden ECG sample) to the
 * FPGA, which loads it into the EPU's GLB. You then press the FPGA START button
 * (BTNC) to run the classifier. Expected result on the FPGA LEDs: class N,
 * score 0x67 (103).
 *
 * Preprocessing/quantization is done in software (PC); the FPGA only ever
 * receives the ready-made 544-word input image, never raw ECG.
 *
 * UART frame (matches epu_uart_top.sv):
 *   0xAA 0x55 | 544 words x 4 bytes (little-endian) = 2176 payload bytes
 *             | 1 XOR-checksum byte over the 2176 payload bytes
 *
 * Wiring (ESP32 <-> FPGA Pmod JA, both 3.3 V):
 *   ESP32 GPIO17 (TX2) -> FPGA JA1  = AB22  (FPGA uart_rxd)
 *   ESP32 GPIO16 (RX2) <- FPGA JA7  = Y21   (FPGA uart_txd, unused for now)
 *   ESP32 GND          -> FPGA JA pin 5 or 11 (GND)
 *
 * Usage: open the Serial Monitor (115200). The frame is sent once at startup,
 * and again whenever you send any character in the Serial Monitor.
 */

#include "golden_sample.h"

#define UART2_TX    17
#define UART2_RX    16
#define UART2_BAUD  115200

#define HDR0  0xAA
#define HDR1  0x55

void sendFrame() {
  Serial2.write((uint8_t)HDR0);
  Serial2.write((uint8_t)HDR1);

  uint8_t csum = 0;
  for (int i = 0; i < GOLDEN_NWORDS; i++) {
    uint32_t w = GOLDEN_SAMPLE[i];
    for (int b = 0; b < 4; b++) {          // little-endian: LSB first
      uint8_t by = (uint8_t)((w >> (8 * b)) & 0xFF);
      Serial2.write(by);
      csum ^= by;
    }
  }
  Serial2.write(csum);
  Serial2.flush();

  Serial.printf("Sent frame: 2 + %d + 1 = %d bytes, checksum=0x%02X\n",
                GOLDEN_NWORDS * 4, 2 + GOLDEN_NWORDS * 4 + 1, csum);
  Serial.println("Now press the FPGA START button (BTNC). Expect class N, score 0x67.");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX, UART2_TX);

  Serial.println("==========================================");
  Serial.println("ESP32 -> UART -> FPGA EPU (B1)");
  Serial.printf("UART2: TX=GPIO%d -> FPGA JA1(AB22), RX=GPIO%d <- FPGA JA7(Y21), %d 8N1\n",
                UART2_TX, UART2_RX, UART2_BAUD);
  Serial.printf("Payload: %d words (%d bytes)\n", GOLDEN_NWORDS, GOLDEN_NWORDS * 4);
  Serial.println("==========================================");

  delay(1500);          // give the FPGA time to come up after power/config
  sendFrame();
}

void loop() {
  // Resend on any character typed in the Serial Monitor.
  if (Serial.available()) {
    while (Serial.available()) Serial.read();
    Serial.println("Resending frame...");
    sendFrame();
  }
  delay(10);
}
