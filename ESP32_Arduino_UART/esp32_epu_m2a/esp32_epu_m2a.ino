/*
 * ESP32 -> UART -> Nexys Video FPGA  (M2A: continuous handshake classification)
 *
 * M2A turns the one-shot mode-1 demo into a self-running loop with a clean
 * FPGA<->ESP32 handshake -- no button / reset press per sample:
 *
 *   1) ESP32 sends a 544-word frame.
 *   2) FPGA UART loader writes it into the buffer BRAM; when complete it raises
 *      a frame-ready interrupt and the CPU DMAs buffer -> EPU GLB and classifies.
 *   3) When the EPU finishes, the FPGA hardware sends ONE ACK byte (0x06) back
 *      over its UART TX (JA7/Y21 -> this ESP32's RX2/GPIO16).
 *   4) On the ACK, the ESP32 sends the next frame -> back to 1.
 *
 * For now the ESP32 just repeats the SAME selected class (type n/s/v/f in the
 * Serial Monitor to switch which one). Because every ACK simply re-sends the
 * current sample, a missed/early ACK is harmless. A retransmit timeout also
 * resends if no ACK arrives (covers the very first frame / any lost ACK), so the
 * handshake self-synchronizes.
 *
 * This is the stepping stone to the real-time ECG sensor front-end: later the
 * ESP32 will, on each ACK, send the NEXT freshly-acquired+tiled beat instead of
 * repeating one canned sample. The FPGA side (chip_top_m2a) does not change.
 *
 * UART frame (matches uart_buffer_loader.sv):
 *   0xAA 0x55 | 544 words x 4 bytes (little-endian) = 2176 payload bytes
 *             | 1 XOR-checksum byte over the 2176 payload bytes
 *
 * Wiring (ESP32 <-> FPGA Pmod JA, both 3.3 V):
 *   ESP32 GPIO17 (TX2) -> FPGA JA1 = AB22  (FPGA uart_rxd)
 *   ESP32 GPIO16 (RX2) <- FPGA JA7 = Y21   (FPGA uart_txd / ACK)
 *   ESP32 GND          -> FPGA JA pin 5 or 11 (GND)
 *
 * FPGA LEDs:
 *   sw=00 -> score          sw=01 -> LED7=valid, LED2:0 = class index
 *   sw=10 -> LED7=rx_seen LED6=uart_err LED5=data_ready   sw=11 -> heartbeat
 *   (result updates on every loop; with one repeated class it looks steady.)
 */

#include "samples.h"

#define UART2_TX    17
#define UART2_RX    16
#define UART2_BAUD  115200

#define HDR0  0xAA
#define HDR1  0x55
#define ACK   0x06

// Resend if no ACK within this long (ms). One classify takes well under this;
// this only covers the bootstrap frame and any lost ACK.
#define ACK_TIMEOUT_MS  800

const sample_desc_t *g_sel = &SAMPLES[0];   // currently repeated class (default N)
uint32_t g_sent   = 0;                       // frames sent
uint32_t g_acks   = 0;                       // ACKs received
unsigned long g_last_send_ms = 0;

void sendSelected() {
  const sample_desc_t *s = g_sel;
  Serial2.write((uint8_t)HDR0);
  Serial2.write((uint8_t)HDR1);

  uint8_t csum = 0;
  for (int i = 0; i < SAMPLE_NWORDS; i++) {
    uint32_t w = s->words[i];
    for (int b = 0; b < 4; b++) {            // little-endian: LSB first
      uint8_t by = (uint8_t)((w >> (8 * b)) & 0xFF);
      Serial2.write(by);
      csum ^= by;
    }
  }
  Serial2.write(csum);
  Serial2.flush();

  g_sent++;
  g_last_send_ms = millis();
  Serial.printf("[%lu] sent class %s (idx %u, expect score 0x%02X) csum=0x%02X\n",
                (unsigned long)g_sent, s->name, s->cls, s->score, csum);
}

void printMenu() {
  Serial.println("------------------------------------------");
  Serial.println("M2A continuous handshake. Type a class to repeat:");
  for (int i = 0; i < NUM_SAMPLES; i++) {
    Serial.printf("  %c -> class %s (idx %u, score 0x%02X)\n",
                  SAMPLES[i].key, SAMPLES[i].name, SAMPLES[i].cls, SAMPLES[i].score);
  }
  Serial.println("The FPGA auto-classifies each frame and ACKs; no button needed.");
  Serial.println("------------------------------------------");
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX, UART2_TX);

  Serial.println("==========================================");
  Serial.println("ESP32 -> UART -> FPGA  M2A continuous handshake demo");
  Serial.printf("UART2: TX=GPIO%d->JA1(AB22), RX=GPIO%d<-JA7(Y21), %d 8N1\n",
                UART2_TX, UART2_RX, UART2_BAUD);
  Serial.println("==========================================");
  printMenu();

  // Bootstrap: send the first frame. The FPGA loop is waiting for it.
  sendSelected();
}

void loop() {
  // 1) class switch from the Serial Monitor (takes effect on the next send).
  if (Serial.available()) {
    int c = Serial.read();
    if (c != '\n' && c != '\r' && c != ' ') {
      const sample_desc_t *sel = nullptr;
      for (int i = 0; i < NUM_SAMPLES; i++) {
        if ((int)SAMPLES[i].key == c || (int)SAMPLES[i].name[0] == (c & ~0x20)) {
          sel = &SAMPLES[i];
          break;
        }
      }
      if (sel) {
        g_sel = sel;
        Serial.printf("Switched repeated class -> %s\n", g_sel->name);
      } else {
        Serial.printf("Unknown class '%c'.\n", (char)c);
        printMenu();
      }
    }
  }

  // 2) ACK from the FPGA (one byte per completed classification) -> send next.
  while (Serial2.available()) {
    int b = Serial2.read();
    if (b == ACK) {
      g_acks++;
      sendSelected();
    }
    // ignore any other byte
  }

  // 3) retransmit safety net (bootstrap frame / lost ACK).
  if (millis() - g_last_send_ms > ACK_TIMEOUT_MS) {
    Serial.println("(no ACK -> resend)");
    sendSelected();
  }
}
