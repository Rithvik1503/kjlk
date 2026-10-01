// Just enough of APNs to send an alert.
//
// Apple authenticates provider requests with a short-lived ES256 JWT signed by a .p8 key, and
// delivers over HTTP/2 — which Deno's fetch speaks, so there is no library here.

const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
/** The app's bundle identifier. */
const TOPIC = Deno.env.get("APNS_TOPIC") ?? "com.aura.roommonitor";

export const apnsConfigured = Boolean(KEY_ID && TEAM_ID && PRIVATE_KEY);

/** Apple rejects a token older than an hour and rate-limits new ones, so it is cached for the
 *  life of the isolate — which is also why this is module scope rather than per-request. */
let cachedToken: { value: string; issuedAt: number } | null = null;

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** Strips the PEM armour and decodes the PKCS#8 body Apple hands out as a .p8 file. */
function derFromPEM(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    // Real newlines, and the literal two-character \n that some secret editors store
    // instead of them. Base64 has neither, so dropping both is safe.
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // Renewed well inside Apple's one-hour limit.
  if (cachedToken && now - cachedToken.issuedAt < 45 * 60) {
    return cachedToken.value;
  }

  const key = await crypto.subtle.importKey(
    "pkcs8",
    derFromPEM(PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = base64url(
    new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: KEY_ID })),
  );
  const payload = base64url(
    new TextEncoder().encode(JSON.stringify({ iss: TEAM_ID, iat: now })),
  );

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );

  // Web Crypto returns the raw r‖s pair, which is exactly what JWS wants — no DER unwrapping.
  const token = `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
  cachedToken = { value: token, issuedAt: now };
  return token;
}

export interface PushResult {
  ok: boolean;
  status: number;
  /** True when Apple says this token is dead and should be forgotten. */
  gone: boolean;
  reason?: string;
}

export async function sendPush(
  deviceToken: string,
  environment: string,
  alert: { title: string; body: string },
  data: Record<string, unknown> = {},
): Promise<PushResult> {
  const host = environment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": TOPIC,
      "apns-push-type": "alert",
      // Delivered immediately; this is a thing the user asked to be told about.
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: { title: alert.title, body: alert.body },
        sound: "default",
        "interruption-level": "active",
      },
      ...data,
    }),
  });

  if (response.ok) {
    return { ok: true, status: response.status, gone: false };
  }

  const text = await response.text();
  let reason = text;
  try {
    reason = JSON.parse(text).reason ?? text;
  } catch {
    // Apple returns plain text on some failures; the body is the message either way.
  }

  // 410 is "this token is no longer valid"; a 400 of BadDeviceToken means the same thing for
  // a token issued against the other environment.
  const gone = response.status === 410 ||
    (response.status === 400 && reason === "BadDeviceToken");

  return { ok: false, status: response.status, gone, reason };
}
