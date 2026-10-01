import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Ingest endpoint for the ESP32.
 *
 * The device holds a shared secret (DEVICE_INGEST_TOKEN) and nothing else — no Supabase
 * credentials live on it. This function checks that token and writes the row with the
 * service role key on the device's behalf, so a reader pulled off the bench can't be used
 * to read anybody's data back.
 *
 * Secrets to set (Project Settings -> Edge Functions -> Secrets):
 *   DEVICE_INGEST_TOKEN  a long random string, also compiled into the firmware
 *   OWNER_USER_ID        the auth.users UUID the readings belong to
 * SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
 */

const MAX_BATCH = 120;

type Payload = {
  co2_ppm?: unknown;
  temperature_c?: unknown;
  humidity_percent?: unknown;
  light_lux?: unknown;
  device_id?: unknown;
  recorded_at?: unknown;
};

type Row = {
  owner_id: string;
  device_id: string;
  recorded_at: string;
  co2_ppm: number | null;
  temperature_c: number | null;
  humidity_percent: number | null;
  light_lux: number | null;
};

/**
 * Compares two strings without leaking their contents through how long it takes.
 *
 * `a === b` returns on the first differing byte, which over enough requests is enough to
 * recover a token one character at a time. This always walks the full length.
 */
function timingSafeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  // Length alone is not worth hiding, and comparing unequal lengths byte-wise is awkward.
  if (left.length !== right.length) return false;

  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference === 0;
}

/** Parses a measurement, enforcing the same bounds as the table's check constraint. */
function measurement(raw: unknown, min: number, max: number): number | null {
  if (raw === null || raw === undefined || raw === "") return null;

  const value = Number(raw);
  if (!Number.isFinite(value)) return null;
  if (value < min || value > max) return null;
  return value;
}

function badRequest(message: string): Response {
  return Response.json({ error: message }, { status: 400 });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Use POST" }, { status: 405 });
  }

  const expectedToken = Deno.env.get("DEVICE_INGEST_TOKEN");
  const suppliedToken = req.headers.get("x-device-token");

  if (!expectedToken || !suppliedToken || !timingSafeEqual(suppliedToken, expectedToken)) {
    return Response.json({ error: "Unauthorized device" }, { status: 401 });
  }

  const ownerId = Deno.env.get("OWNER_USER_ID");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!ownerId || !supabaseUrl || !serviceRoleKey) {
    console.error("Missing OWNER_USER_ID, SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    return Response.json({ error: "Cloud configuration is incomplete" }, { status: 500 });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return badRequest("Invalid JSON");
  }

  // A single reading or a batch — the firmware can buffer while the Wi-Fi is down and flush
  // everything at once when it comes back.
  const items: Payload[] = Array.isArray(body) ? body : [body as Payload];

  if (items.length === 0) return badRequest("No readings supplied");
  if (items.length > MAX_BATCH) return badRequest(`At most ${MAX_BATCH} readings per request`);

  const rows: Row[] = [];

  for (const item of items) {
    if (typeof item !== "object" || item === null) {
      return badRequest("Each reading must be an object");
    }

    const co2 = measurement(item.co2_ppm, 0, 60000);
    const temperature = measurement(item.temperature_c, -50, 100);
    const humidity = measurement(item.humidity_percent, 0, 100);
    const light = measurement(item.light_lux, 0, 200000);

    // A row where every sensor failed carries no information and would draw as a gap anyway.
    if (co2 === null && temperature === null && humidity === null && light === null) {
      return badRequest("A reading needs at least one usable value");
    }

    // The device may send its own timestamp when flushing a buffer; otherwise it is "now".
    let recordedAt = new Date();
    if (typeof item.recorded_at === "string" && item.recorded_at !== "") {
      const parsed = new Date(item.recorded_at);
      if (Number.isNaN(parsed.getTime())) return badRequest("recorded_at is not a valid timestamp");
      // An ESP32 without NTP can report 1970 or a date far in the future; trust neither.
      const skew = Math.abs(Date.now() - parsed.getTime());
      if (skew < 7 * 24 * 60 * 60 * 1000) recordedAt = parsed;
    }

    const deviceId = typeof item.device_id === "string" && item.device_id.trim() !== ""
      ? item.device_id.trim().slice(0, 64)
      : "esp32-room-1";

    rows.push({
      owner_id: ownerId,
      device_id: deviceId,
      recorded_at: recordedAt.toISOString(),
      co2_ppm: co2 === null ? null : Math.round(co2),
      temperature_c: temperature,
      humidity_percent: humidity,
      light_lux: light,
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error } = await admin.from("readings").insert(rows);

  if (error) {
    console.error("Insert failed", error);
    return Response.json({ error: error.message }, { status: 500 });
  }

  return Response.json({ ok: true, inserted: rows.length }, { status: 201 });
});
