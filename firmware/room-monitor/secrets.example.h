// Copy this file to `secrets.h` and fill it in. `secrets.h` is gitignored.
//
//     cp secrets.example.h secrets.h
//
// Keep the real file off GitHub: the ingest token is the only thing standing between the
// internet and your readings table, and Wi-Fi passwords are Wi-Fi passwords.

#pragma once

// Wi-Fi networks to try, in order. Add as many as you like.
struct KnownWiFi {
  const char* name;
  const char* password;
};

static const KnownWiFi KNOWN_WIFIS[] = {
  {"YOUR_WIFI_NAME", "YOUR_WIFI_PASSWORD"},
};

// Must match DEVICE_INGEST_TOKEN in the Supabase edge function secrets.
// Generate a fresh one with:  openssl rand -hex 32
#define DEVICE_TOKEN "YOUR_DEVICE_INGEST_TOKEN"

// Project URL plus the function path.
#define INGEST_URL "https://YOUR_PROJECT.supabase.co/functions/v1/ingest-reading"

// Shown in the app's device picker. Give each board its own name if you build a second one.
#define DEVICE_ID "esp32-room-1"
