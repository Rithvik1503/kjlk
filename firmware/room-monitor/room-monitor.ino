// Aura room monitor — ESP32 Dev Module + SCD40 (CO2 / temperature / humidity) + BH1750 (light).
//
// Reads both sensors, prints to serial, and uploads to a Supabase edge function once a
// minute. If the network or the server is unreachable the readings go into a small buffer
// and get flushed as one batch when the connection comes back, so a router reboot leaves a
// gap of nothing rather than a gap in the data.
//
// Libraries (Arduino Library Manager):
//   - BH1750                by Christopher Laws
//   - Sensirion I2C SCD4x   by Sensirion
//
// Wiring (I2C, both sensors share the bus):
//   SDA -> GPIO21, SCL -> GPIO22, VIN -> 3V3, GND -> GND

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <time.h>

#include <Wire.h>
#include <BH1750.h>
#include <SensirionI2cScd4x.h>

#include "secrets.h"

// ---------------------------------------------------------------------------
// Tuning
// ---------------------------------------------------------------------------

static const unsigned long SAMPLE_INTERVAL_MS = 5000;    // SCD40 produces a reading every 5s.
static const unsigned long UPLOAD_INTERVAL_MS = 60000;   // One upload a minute.
static const unsigned long WIFI_RETRY_INTERVAL_MS = 30000;

static const int WIFI_ATTEMPTS_PER_NETWORK = 20;         // x 500 ms = 10 s per network.
static const size_t BUFFER_CAPACITY = 60;                // An hour of readings held in RAM.

static const int KNOWN_WIFI_COUNT = sizeof(KNOWN_WIFIS) / sizeof(KNOWN_WIFIS[0]);

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

struct BufferedReading {
  time_t  recordedAt;      // Unix seconds, or 0 if the clock wasn't set yet.
  int32_t co2;             // -1 when the sensor didn't report.
  float   temperature;
  float   humidity;
  float   light;           // NAN when the BH1750 didn't report.
};

BH1750 lightMeter;
SensirionI2cScd4x sensor;

// Ring buffer. When it fills, the oldest reading is dropped — recent data is worth more.
static BufferedReading buffer[BUFFER_CAPACITY];
static size_t bufferHead = 0;
static size_t bufferCount = 0;

static unsigned long lastSample = 0;
static unsigned long lastUpload = 0;
static unsigned long lastWiFiAttempt = 0;

static bool clockReady = false;
static bool lightSensorReady = false;

static char errorMessage[64];
static int16_t error;

// ---------------------------------------------------------------------------
// Buffer
// ---------------------------------------------------------------------------

static void bufferPush(const BufferedReading& reading) {
  size_t index = (bufferHead + bufferCount) % BUFFER_CAPACITY;
  buffer[index] = reading;

  if (bufferCount < BUFFER_CAPACITY) {
    bufferCount++;
  } else {
    bufferHead = (bufferHead + 1) % BUFFER_CAPACITY;  // Overwrote the oldest.
    Serial.println("Buffer full — dropped the oldest reading.");
  }
}

static void bufferDropFront(size_t count) {
  size_t removed = (count < bufferCount) ? count : bufferCount;
  bufferHead = (bufferHead + removed) % BUFFER_CAPACITY;
  bufferCount -= removed;
}

// ---------------------------------------------------------------------------
// Wi-Fi and time
// ---------------------------------------------------------------------------

static bool connectToWiFi() {
  if (WiFi.status() == WL_CONNECTED) return true;

  // Don't retry on every loop when nothing is reachable.
  if (lastWiFiAttempt != 0 && millis() - lastWiFiAttempt < WIFI_RETRY_INTERVAL_MS) {
    return false;
  }
  lastWiFiAttempt = millis();

  WiFi.mode(WIFI_STA);

  for (int network = 0; network < KNOWN_WIFI_COUNT; network++) {
    Serial.print("Trying Wi-Fi: ");
    Serial.println(KNOWN_WIFIS[network].name);

    WiFi.disconnect();
    delay(300);
    WiFi.begin(KNOWN_WIFIS[network].name, KNOWN_WIFIS[network].password);

    for (int attempt = 0; attempt < WIFI_ATTEMPTS_PER_NETWORK; attempt++) {
      if (WiFi.status() == WL_CONNECTED) {
        Serial.print("\nConnected. IP address: ");
        Serial.println(WiFi.localIP());
        return true;
      }
      delay(500);
      Serial.print(".");
    }
    Serial.println("\nThat network didn't answer.");
  }

  Serial.println("No known Wi-Fi network was available.");
  return false;
}

// Without NTP the board has no idea what time it is, and buffered readings would all be
// stamped 1970. The server falls back to its own clock when we send 0.
static void syncClock() {
  if (clockReady || WiFi.status() != WL_CONNECTED) return;

  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  time_t now = 0;
  for (int attempt = 0; attempt < 10; attempt++) {
    now = time(nullptr);
    if (now > 1700000000) {  // Later than Nov 2023, so the clock has really been set.
      clockReady = true;
      Serial.println("Clock synced.");
      return;
    }
    delay(300);
  }
  Serial.println("Couldn't reach an NTP server; the server will timestamp instead.");
}

// ---------------------------------------------------------------------------
// Upload
// ---------------------------------------------------------------------------

static void appendReadingJSON(String& json, const BufferedReading& reading) {
  json += "{\"device_id\":\"" DEVICE_ID "\"";

  if (reading.recordedAt > 0) {
    struct tm timeinfo;
    gmtime_r(&reading.recordedAt, &timeinfo);

    char stamp[32];
    strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
    json += ",\"recorded_at\":\"";
    json += stamp;
    json += "\"";
  }

  if (reading.co2 >= 0) {
    json += ",\"co2_ppm\":";
    json += String(reading.co2);
  }
  if (!isnan(reading.temperature)) {
    json += ",\"temperature_c\":";
    json += String(reading.temperature, 2);
  }
  if (!isnan(reading.humidity)) {
    json += ",\"humidity_percent\":";
    json += String(reading.humidity, 2);
  }
  if (!isnan(reading.light)) {
    json += ",\"light_lux\":";
    json += String(reading.light, 2);
  }

  json += "}";
}

// Sends everything buffered as one array. Returns true when the server accepted it.
static bool flushBuffer() {
  if (bufferCount == 0) return true;
  if (!connectToWiFi()) return false;

  syncClock();

  WiFiClientSecure client;
  // Skips certificate verification. Fine on a network you control, and it keeps first setup
  // painless. To verify properly, call client.setCACert() with the root CA for *.supabase.co
  // instead — just be ready to update it when the certificate chain rotates.
  client.setInsecure();

  HTTPClient http;
  if (!http.begin(client, INGEST_URL)) {
    Serial.println("Couldn't start the cloud connection.");
    return false;
  }

  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-device-token", DEVICE_TOKEN);
  http.setTimeout(15000);

  size_t sending = bufferCount;
  String json = "[";
  for (size_t i = 0; i < sending; i++) {
    if (i > 0) json += ",";
    appendReadingJSON(json, buffer[(bufferHead + i) % BUFFER_CAPACITY]);
  }
  json += "]";

  int responseCode = http.POST(json);

  bool accepted = false;
  if (responseCode > 0) {
    Serial.print("Upload: ");
    Serial.print(responseCode);
    Serial.print(" — ");
    Serial.println(http.getString());

    // 2xx means stored. A 4xx means the server will never accept these rows, so drop them
    // rather than retrying the same rejected payload forever.
    if (responseCode >= 200 && responseCode < 300) {
      accepted = true;
    } else if (responseCode >= 400 && responseCode < 500 && responseCode != 408 && responseCode != 429) {
      Serial.println("Server rejected these readings; discarding them.");
      accepted = true;
    }
  } else {
    Serial.print("Upload failed: ");
    Serial.println(http.errorToString(responseCode));
  }

  http.end();

  if (accepted) {
    bufferDropFront(sending);
  }
  return accepted;
}

// ---------------------------------------------------------------------------
// Sampling
// ---------------------------------------------------------------------------

static void takeSample() {
  bool dataReady = false;
  error = sensor.getDataReadyStatus(dataReady);
  if (error != 0 || !dataReady) return;

  uint16_t co2 = 0;
  float temperature = 0.0f;
  float humidity = 0.0f;

  error = sensor.readMeasurement(co2, temperature, humidity);
  if (error != 0) {
    errorToString(error, errorMessage, sizeof(errorMessage));
    Serial.print("SCD40 read error: ");
    Serial.println(errorMessage);
    return;
  }

  // The SCD40 reports 0 ppm while it is still warming up; that isn't a measurement.
  BufferedReading reading;
  reading.recordedAt = clockReady ? time(nullptr) : 0;
  reading.co2 = (co2 == 0) ? -1 : (int32_t)co2;
  reading.temperature = temperature;
  reading.humidity = humidity;

  float lux = lightSensorReady ? lightMeter.readLightLevel() : NAN;
  // The library returns a negative value on an I2C error.
  reading.light = (lux < 0) ? NAN : lux;

  bufferPush(reading);

  Serial.println("----------");
  Serial.printf("CO2:         %s ppm\n", reading.co2 >= 0 ? String(reading.co2).c_str() : "warming up");
  Serial.printf("Temperature: %.1f C\n", reading.temperature);
  Serial.printf("Humidity:    %.1f %%\n", reading.humidity);
  if (!isnan(reading.light)) {
    Serial.printf("Light:       %.1f lux\n", reading.light);
  } else {
    Serial.println("Light:       unavailable");
  }
  Serial.printf("Buffered:    %u\n", (unsigned)bufferCount);
}

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(200);

  Wire.begin(21, 22);

  lightSensorReady = lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE, 0x23, &Wire);
  if (!lightSensorReady) {
    Serial.println("BH1750 not found — carrying on without light readings.");
  }

  sensor.begin(Wire, SCD41_I2C_ADDR_62);
  delay(30);

  sensor.wakeUp();
  sensor.stopPeriodicMeasurement();
  sensor.reinit();

  error = sensor.startPeriodicMeasurement();
  if (error != 0) {
    errorToString(error, errorMessage, sizeof(errorMessage));
    Serial.print("SCD40 startup error: ");
    Serial.println(errorMessage);
  }

  connectToWiFi();
  syncClock();

  // Upload the first reading as soon as there is one, instead of waiting a full minute.
  lastUpload = millis() - UPLOAD_INTERVAL_MS;
  lastSample = millis() - SAMPLE_INTERVAL_MS;

  Serial.println("Room monitor running.");
}

void loop() {
  // Unsigned subtraction, so this keeps working after millis() wraps at ~49 days.
  if (millis() - lastSample >= SAMPLE_INTERVAL_MS) {
    lastSample = millis();
    takeSample();
  }

  if (millis() - lastUpload >= UPLOAD_INTERVAL_MS && bufferCount > 0) {
    lastUpload = millis();
    flushBuffer();
  }

  delay(50);
}
