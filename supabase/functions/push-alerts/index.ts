// Aura: alerts that arrive with the app closed.
//
// Called on a schedule by pg_cron (see 0007_push_cron.sql). For every monitor that has
// reported in the last 20 minutes it compares the air now with the air an hour ago, and
// pushes when a sensor has crossed into a worse band — band crossings, not raw movement,
// because 620 → 780 ppm is a rise but still fresh air.
//
// Deploy WITH JWT verification (the default), so only a caller holding a Supabase key gets
// in:
//     supabase functions deploy push-alerts

import { apnsConfigured, sendPush } from "./apns.ts";
import { bandFor, format, METRICS, MetricKey, TITLES, UNITS } from "./bands.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/** Matches the app's own quiet period: one alert per metric per hour. */
const QUIET_PERIOD_MS = 60 * 60 * 1000;

interface Candidate {
  owner_id: string;
  device_id: string;
  recorded_at: string;
  co2_now: number | null;
  temp_now: number | null;
  humidity_now: number | null;
  light_now: number | null;
  co2_then: number | null;
  temp_then: number | null;
  humidity_then: number | null;
  light_then: number | null;
}

interface AlertState {
  owner_id: string;
  device_id: string;
  metric: string;
  band: number;
  notified_at: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function headers(): HeadersInit {
  return {
    apikey: SERVICE_ROLE_KEY,
    authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    "content-type": "application/json",
  };
}

async function rpc<T>(name: string): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: headers(),
    body: "{}",
  });
  if (!response.ok) {
    throw new Error(`${name}: ${response.status} ${await response.text()}`);
  }
  return await response.json() as T;
}

async function select<T>(path: string): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: headers() });
  if (!response.ok) {
    throw new Error(`${path}: ${response.status} ${await response.text()}`);
  }
  return await response.json() as T;
}

/** Current and hour-ago value for one metric, or null when either end is missing. */
function pair(row: Candidate, metric: MetricKey): [number, number] | null {
  const now = {
    co2: row.co2_now,
    temperature: row.temp_now,
    humidity: row.humidity_now,
    light: row.light_now,
  }[metric];
  const then = {
    co2: row.co2_then,
    temperature: row.temp_then,
    humidity: row.humidity_then,
    light: row.light_then,
  }[metric];

  if (now === null || then === null || now === undefined || then === undefined) return null;
  return [now, then];
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    return json({ error: "Function is missing its Supabase environment" }, 500);
  }
  if (!apnsConfigured) {
    return json(
      { error: "Set APNS_KEY_ID, APNS_TEAM_ID and APNS_PRIVATE_KEY in the function secrets" },
      500,
    );
  }

  const started = Date.now();

  try {
    const candidates = await rpc<Candidate[]>("aura_alert_candidates");
    if (candidates.length === 0) {
      return json({ ok: true, checked: 0, sent: 0 });
    }

    const [states, devices] = await Promise.all([
      select<AlertState[]>("push_alert_state?select=owner_id,device_id,metric,band,notified_at"),
      select<{ token: string; owner_id: string; environment: string }[]>(
        "push_devices?select=token,owner_id,environment",
      ),
    ]);

    const stateKey = (owner: string, device: string, metric: string) =>
      `${owner}|${device}|${metric}`;
    const lastAlert = new Map(
      states.map((state) => [stateKey(state.owner_id, state.device_id, state.metric), state]),
    );

    const tokensByOwner = new Map<string, { token: string; environment: string }[]>();
    for (const device of devices) {
      const list = tokensByOwner.get(device.owner_id) ?? [];
      list.push({ token: device.token, environment: device.environment });
      tokensByOwner.set(device.owner_id, list);
    }

    const stateWrites: AlertState[] = [];
    const deadTokens: string[] = [];
    let sent = 0;

    for (const row of candidates) {
      const tokens = tokensByOwner.get(row.owner_id) ?? [];
      if (tokens.length === 0) continue;

      for (const metric of METRICS) {
        const values = pair(row, metric);
        if (!values) continue;

        const [now, then] = values;
        const current = bandFor(metric, now);
        const previous = bandFor(metric, then);

        // Only a step into a worse band is worth waking someone for. Settling back down, or
        // drifting within a band, is not news.
        if (current.severity <= previous.severity) continue;

        const key = stateKey(row.owner_id, row.device_id, metric);
        const last = lastAlert.get(key);

        // Already said this, recently enough that saying it again is just noise.
        if (
          last && last.band === current.severity &&
          Date.now() - new Date(last.notified_at).getTime() < QUIET_PERIOD_MS
        ) {
          continue;
        }

        const title = `${TITLES[metric]} — ${current.label}`;
        const body =
          `${format(metric, now)} ${UNITS[metric]}, up from ${previous.label.toLowerCase()} an hour ago.`;

        for (const device of tokens) {
          const result = await sendPush(device.token, device.environment, { title, body }, {
            metric,
            device_id: row.device_id,
          });

          if (result.ok) {
            sent++;
          } else if (result.gone) {
            deadTokens.push(device.token);
          } else {
            console.error("APNs refused", result.status, result.reason);
          }
        }

        stateWrites.push({
          owner_id: row.owner_id,
          device_id: row.device_id,
          metric,
          band: current.severity,
          notified_at: new Date().toISOString(),
        });
      }
    }

    if (stateWrites.length > 0) {
      await fetch(`${SUPABASE_URL}/rest/v1/push_alert_state`, {
        method: "POST",
        headers: {
          ...headers(),
          prefer: "resolution=merge-duplicates,return=minimal",
        },
        body: JSON.stringify(stateWrites),
      });
    }

    // A token Apple has disowned will never work again; keeping it only costs a failed
    // request every quarter of an hour.
    if (deadTokens.length > 0) {
      const list = deadTokens.map((token) => `"${token}"`).join(",");
      await fetch(`${SUPABASE_URL}/rest/v1/push_devices?token=in.(${list})`, {
        method: "DELETE",
        headers: headers(),
      });
    }

    return json({
      ok: true,
      checked: candidates.length,
      sent,
      pruned: deadTokens.length,
      ms: Date.now() - started,
    });
  } catch (error) {
    console.error(error);
    return json({ error: String(error) }, 500);
  }
});
