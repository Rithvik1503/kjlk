// Aura room monitor — ESP32 Dev Module + SCD40 (CO2 / temperature / humidity) + BH1750 (light).
//
// Reads both sensors every 5 seconds, prints to serial, and uploads to a Supabase edge
// function every 15 seconds. If the network or the server is unreachable the readings go
// into a ring buffer and get flushed as one batch when the connection comes back, so a
// router reboot leaves a gap of nothing rather than a gap in the data.
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

#include <Preferences.h>

#include <Wire.h>
#include <BH1750.h>
#include <SensirionI2cScd4x.h>

#include "secrets.h"

// ---------------------------------------------------------------------------
// Tuning
// ---------------------------------------------------------------------------

// How often a reading is taken. This sets how dense the data is: one row per sample.
// 5s is as fast as the SCD40 goes, and works out at ~17k rows a day.
static const unsigned long SAMPLE_INTERVAL_MS = 5000;

// How often buffered readings are sent. This sets latency, not density — every sample taken
// since the last upload goes out together, each carrying its own timestamp.
static const unsigned long UPLOAD_INTERVAL_MS = 15000;

static const unsigned long WIFI_RETRY_INTERVAL_MS = 30000;
static const int WIFI_ATTEMPTS_PER_NETWORK = 20;         // x 500 ms = 10 s per network.

// ---------------------------------------------------------------------------
// Zones
// ---------------------------------------------------------------------------
//
// Press the button to cycle. The name travels with every reading and titles the app's home
// screen; the colour is just so the board can tell you which one it landed on.
//
// Pure on/off per channel rather than PWM, so this needs no LED library and no version
// juggling over the ESP32 core's changing ledc API. That gives seven usable colours.

struct Zone {
  const char* name;
  bool red;
  bool green;
  bool blue;
};

static const Zone ZONES[] = {
  {"My Room", false, false, true},    // blue
  {"Outdoor", false, true,  false},   // green
};
static const uint8_t ZONE_COUNT = sizeof(ZONES) / sizeof(ZONES[0]);

// GPIO 0 is the BOOT button on most DevKits, so this works with nothing wired up. Holding it
// down during a reset still enters the bootloader; pressing it while running does not.
#define BUTTON_PIN 0

// Optional external RGB LED. Harmless if nothing is attached — the pins just toggle.
#define LED_R_PIN 25
#define LED_G_PIN 26
#define LED_B_PIN 27
// Set true if your LED's long leg goes to 3V3 rather than ground.
static const bool LED_COMMON_ANODE = false;

// The built-in LED blinks the zone's number, so the board is readable without an RGB LED.
#define STATUS_LED_PIN 2

static const unsigned long BUTTON_DEBOUNCE_MS = 50;

// Readings held in RAM while offline — 20 minutes' worth at a 5s sample interval.
static const size_t BUFFER_CAPACITY = 240;

// Most readings in one request. The edge function rejects more than 120, and a rejection is
// a 4xx, which this sketch treats as "the server will never take these" and discards. A
// backlog larger than this drains over several uploads instead of being thrown away.
static const size_t MAX_UPLOAD_BATCH = 100;

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
  uint8_t zone;            // Index into ZONES at the moment it was taken.
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

// Survives a power cut, so the board doesn't wake up claiming to be somewhere else.
static Preferences settings;
static uint8_t zoneIndex = 0;

static int lastButtonState = HIGH;
static unsigned long lastButtonChange = 0;
// True between an edge and the action it causes, so one press is one zone change however
// long the button is held.
static bool buttonArmed = false;
// Set on a press, cleared once a reading taken in the new zone has been sent — so the app
// reflects the change in seconds rather than at the next scheduled upload.
static bool zoneUploadPending = false;

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
// Zone button and LED
// ---------------------------------------------------------------------------

static void writeRGB(bool red, bool green, bool blue) {
  // A common-anode LED lights when its pin is pulled LOW, so the levels invert.
  digitalWrite(LED_R_PIN, red   != LED_COMMON_ANODE ? HIGH : LOW);
  digitalWrite(LED_G_PIN, green != LED_COMMON_ANODE ? HIGH : LOW);
  digitalWrite(LED_B_PIN, blue  != LED_COMMON_ANODE ? HIGH : LOW);
}

static void ledOff() {
  writeRGB(false, false, false);
}

/// Flashes the zone's colour, then blinks the built-in LED once per zone number — so the
/// board still tells you where it thinks it is with no RGB LED attached.
static void signalZone(uint8_t index) {
  const Zone& zone = ZONES[index];

  for (int flash = 0; flash < 3; flash++) {
    writeRGB(zone.red, zone.green, zone.blue);
    delay(160);
    ledOff();
    delay(110);
  }

  delay(200);
  for (uint8_t blink = 0; blink <= index; blink++) {
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(140);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(160);
  }
}

static void setZone(uint8_t index) {
  zoneIndex = index % ZONE_COUNT;
  settings.putUChar("zone", zoneIndex);

  Serial.print("Zone: ");
  Serial.println(ZONES[zoneIndex].name);

  signalZone(zoneIndex);
  zoneUploadPending = true;
}

/// Debounced falling edge on the button. Called every loop.
static void pollButton() {
  int state = digitalRead(BUTTON_PIN);

  if (state != lastButtonState) {
    lastButtonState = state;
    lastButtonChange = millis();
    buttonArmed = true;
    return;
  }

  // Only act once the level has been steady long enough to not be contact bounce.
  if (buttonArmed && state == LOW && millis() - lastButtonChange >= BUTTON_DEBOUNCE_MS) {
    buttonArmed = false;
    setZone(zoneIndex + 1);
  }
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

  json += ",\"zone\":\"";
  json += ZONES[reading.zone % ZONE_COUNT].name;
  json += "\"";

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

  size_t sending = (bufferCount < MAX_UPLOAD_BATCH) ? bufferCount : MAX_UPLOAD_BATCH;

  String json = "[";
  json.reserve(sending * 140 + 2);   // One allocation rather than a hundred reallocations.
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

    if (responseCode >= 200 && responseCode < 300) {
      accepted = true;
    } else if (responseCode == 400 || responseCode == 413 || responseCode == 422) {
      // Only these say something about the payload itself: malformed, too large, or
      // unprocessable. Re-sending the same bytes would fail the same way forever.
      Serial.print("Server rejected these readings (");
      Serial.print(responseCode);
      Serial.println("); discarding them.");
      accepted = true;
    } else {
      // Everything else — 401 wrong token, 404 wrong URL, 5xx, a timeout — is about the
      // connection or the configuration, not the data. The readings are still good once it
      // is fixed, so they stay buffered.
      Serial.print("Not accepted (");
      Serial.print(responseCode);
      Serial.println("). Readings kept — check DEVICE_TOKEN and INGEST_URL.");
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
  reading.zone = zoneIndex;
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
  Serial.printf("Zone:        %s\n", ZONES[zoneIndex].name);
  Serial.printf("Buffered:    %u\n", (unsigned)bufferCount);
}

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(LED_R_PIN, OUTPUT);
  pinMode(LED_G_PIN, OUTPUT);
  pinMode(LED_B_PIN, OUTPUT);
  pinMode(STATUS_LED_PIN, OUTPUT);
  ledOff();

  settings.begin("aura", false);
  zoneIndex = settings.getUChar("zone", 0) % ZONE_COUNT;
  Serial.print("Zone: ");
  Serial.println(ZONES[zoneIndex].name);

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
  pollButton();

  // Unsigned subtraction, so this keeps working after millis() wraps at ~49 days.
  if (millis() - lastSample >= SAMPLE_INTERVAL_MS) {
    lastSample = millis();
    takeSample();
  }

  // A zone change waits for a reading actually taken in the new zone — sending the buffer
  // early would only re-send readings from the old one.
  bool zoneReady = zoneUploadPending && bufferCount > 0 &&
                   buffer[(bufferHead + bufferCount - 1) % BUFFER_CAPACITY].zone == zoneIndex;

  if (zoneReady || (millis() - lastUpload >= UPLOAD_INTERVAL_MS && bufferCount > 0)) {
    lastUpload = millis();
    if (flushBuffer() && zoneReady) {
      zoneUploadPending = false;
    }
  }

  delay(50);
}
