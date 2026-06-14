/*
 * ESP32 BLE ECG Receiver + UART Transmitter to M55M1
 * 
 * BLE: 連接 TriAnswer ECG，接收 ECG 資料
 * UART: 湊滿 15000 筆 (30s) 後透過 UART2 送給 M55M1
 * 
 * UART 協議:
 *   Header:   0xAA 0x55           (2 bytes, 同步用)
 *   Length:   uint16_t = 15000    (2 bytes, little-endian)
 *   Payload:  int16_t x 15000    (30000 bytes, little-endian)
 *   Checksum: uint8_t            (1 byte, 所有 payload bytes XOR)
 *   總共: 2 + 2 + 30000 + 1 = 30005 bytes
 * 
 * 接線 (ESP32 → M55M1):
 *   ESP32 GPIO17 (TX2) → M55M1 UART RX
 *   ESP32 GPIO16 (RX2) → M55M1 UART TX
 *   ESP32 GND          → M55M1 GND
 */

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEScan.h>
#include <BLEClient.h>

// ===== TriAnswer BLE 設定 =====
#define TARGET_ADDRESS    "f8:5b:b6:4e:26:67"
#define ECG_SERVICE_UUID  "0000a000-0000-1000-8000-00805f9b34fb"
#define ECG_CHAR_UUID     "0000a001-0000-1000-8000-00805f9b34fb"

// ===== UART2 設定 (接 M55M1) =====
#define UART2_TX    17
#define UART2_RX    16
#define UART2_BAUD  115200

// ===== 協議常數 =====
#define HEADER_0    0xAA
#define HEADER_1    0x55

// ===== ECG 參數 =====
#define SAMPLING_RATE     500
#define WINDOW_SEC        30
#define STRIDE_SEC        10
#define WINDOW_SIZE       (SAMPLING_RATE * WINDOW_SEC)
#define STRIDE_SIZE       (SAMPLING_RATE * STRIDE_SEC)

// ===== Buffer =====
int16_t ecg_buffer[WINDOW_SIZE];
volatile uint32_t buffer_index = 0;
volatile uint32_t total_samples = 0;
volatile bool window_ready = false;

// ===== BLE 狀態 =====
BLEClient* pClient = nullptr;
bool connected = false;
bool doConnect = false;
BLEAdvertisedDevice* targetDevice = nullptr;

// ===== 統計 =====
uint32_t window_count = 0;

// ============================================================
//  UART 傳送 Window 給 M55M1
// ============================================================
void sendWindowToM55M1() {
  uint16_t length = WINDOW_SIZE;

  // Header
  Serial2.write(HEADER_0);
  Serial2.write(HEADER_1);

  // Length (little-endian)
  Serial2.write((uint8_t)(length & 0xFF));
  Serial2.write((uint8_t)((length >> 8) & 0xFF));

  // Payload + Checksum
  uint8_t checksum = 0;

  for (int i = 0; i < WINDOW_SIZE; i++) {
    uint8_t lo = (uint8_t)(ecg_buffer[i] & 0xFF);
    uint8_t hi = (uint8_t)((ecg_buffer[i] >> 8) & 0xFF);

    Serial2.write(lo);
    Serial2.write(hi);

    checksum ^= lo;
    checksum ^= hi;
  }

  // Checksum
  Serial2.write(checksum);

  Serial2.flush();
}

// ============================================================
//  BLE Notification Callback
// ============================================================
void notifyCallback(
  BLERemoteCharacteristic* pChar,
  uint8_t* pData,
  size_t length,
  bool isNotify
) {
  int numSamples = length / 2;

  int16_t samples[60];
  for (int i = 0; i < numSamples && i < 60; i++) {
    samples[i] = (int16_t)(pData[i * 2] | (pData[i * 2 + 1] << 8));
  }

  // CH0: 每 3 個取第一個
  for (int i = 0; i < numSamples; i += 3) {
    int16_t ch0_sample = samples[i];

    if (buffer_index < WINDOW_SIZE) {
      ecg_buffer[buffer_index] = ch0_sample;
      buffer_index++;
      total_samples++;
    }

    if (total_samples % 500 == 0) {
      Serial.printf("[%lu samples] CH0: %d  (buffer: %lu/%d)\n",
                    total_samples, ch0_sample, buffer_index, WINDOW_SIZE);
    }
  }

  if (buffer_index >= WINDOW_SIZE && !window_ready) {
    window_ready = true;
  }
}

// ============================================================
//  BLE Scan Callback
// ============================================================
class MyScanCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) {
    String addr = advertisedDevice.getAddress().toString().c_str();

    if (addr.equalsIgnoreCase(TARGET_ADDRESS)) {
      Serial.printf("Found TriAnswer! RSSI: %d\n", advertisedDevice.getRSSI());
      targetDevice = new BLEAdvertisedDevice(advertisedDevice);
      doConnect = true;
      advertisedDevice.getScan()->stop();
    }
  }
};

// ============================================================
//  連線到 TriAnswer
// ============================================================
bool connectToServer() {
  Serial.println("Connecting to TriAnswer...");

  pClient = BLEDevice::createClient();

  if (!pClient->connect(targetDevice)) {
    Serial.println("Connect FAILED!");
    return false;
  }
  Serial.println("Connected!");

  BLERemoteService* pService = pClient->getService(ECG_SERVICE_UUID);
  if (pService == nullptr) {
    Serial.println("ECG Service not found!");
    auto* serviceMap = pClient->getServices();
    for (auto it = serviceMap->begin(); it != serviceMap->end(); ++it) {
      Serial.printf("  Service: %s\n", it->first.c_str());
    }
    pClient->disconnect();
    return false;
  }
  Serial.println("Found ECG Service!");

  BLERemoteCharacteristic* pChar = pService->getCharacteristic(ECG_CHAR_UUID);
  if (pChar == nullptr) {
    Serial.println("ECG Characteristic not found!");
    pClient->disconnect();
    return false;
  }
  Serial.println("Found ECG Characteristic!");

  if (pChar->canNotify()) {
    pChar->registerForNotify(notifyCallback);
    Serial.println("Subscribed to ECG notifications!");
  } else {
    Serial.println("Characteristic cannot notify!");
    pClient->disconnect();
    return false;
  }

  connected = true;
  return true;
}

// ============================================================
//  Setup
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX, UART2_TX);

  Serial.println("====================================");
  Serial.println("ESP32 BLE ECG -> UART -> M55M1");
  Serial.println("====================================");
  Serial.printf("UART2: TX=GPIO%d, RX=GPIO%d, Baud=%d\n", UART2_TX, UART2_RX, UART2_BAUD);
  Serial.printf("Window: %d samples (%d sec)\n", WINDOW_SIZE, WINDOW_SEC);
  Serial.printf("Stride: %d samples (%d sec)\n", STRIDE_SIZE, STRIDE_SEC);
  Serial.printf("Packet size: %d bytes\n", 2 + 2 + WINDOW_SIZE * 2 + 1);
  Serial.println("====================================\n");

  BLEDevice::init("ESP32_ECG");

  Serial.println("Scanning for TriAnswer...");
  BLEScan* pScan = BLEDevice::getScan();
  pScan->setAdvertisedDeviceCallbacks(new MyScanCallbacks());
  pScan->setActiveScan(true);
  pScan->setInterval(100);
  pScan->setWindow(99);
  pScan->start(30, false);
}

// ============================================================
//  Loop
// ============================================================
void loop() {
  if (doConnect && !connected) {
    if (connectToServer()) {
      Serial.println("BLE connection established!\n");
    } else {
      Serial.println("BLE connection failed, retrying...");
      doConnect = false;
      delay(3000);
      BLEDevice::getScan()->start(30, false);
    }
  }

  if (window_ready) {
    window_count++;

    float sum = 0;
    for (int i = 0; i < WINDOW_SIZE; i++) sum += ecg_buffer[i];
    float mean = sum / WINDOW_SIZE;

    Serial.printf("\n===== Window #%lu READY =====\n", window_count);
    Serial.printf("Mean: %.2f | First 5: %d %d %d %d %d\n",
                  mean, ecg_buffer[0], ecg_buffer[1], ecg_buffer[2],
                  ecg_buffer[3], ecg_buffer[4]);

    // 送出
    Serial.println("Sending to M55M1 via UART...");
    unsigned long t0 = millis();
    sendWindowToM55M1();
    unsigned long t1 = millis();
    Serial.printf("Sent %d bytes in %lu ms\n", 2 + 2 + WINDOW_SIZE * 2 + 1, t1 - t0);

    // Sliding Window，不等回傳，直接繼續
    memmove(ecg_buffer, ecg_buffer + STRIDE_SIZE,
            (WINDOW_SIZE - STRIDE_SIZE) * sizeof(int16_t));
    buffer_index = WINDOW_SIZE - STRIDE_SIZE;
    window_ready = false;

    Serial.printf("Sliding: kept %d, need %d more\n\n",
                  buffer_index, STRIDE_SIZE);
  }

  if (connected && pClient != nullptr && !pClient->isConnected()) {
    Serial.println("Disconnected! Reconnecting...");
    connected = false;
    doConnect = false;
    delay(3000);
    BLEDevice::getScan()->start(30, false);
  }

  delay(10);
}