# Aura

A room monitor, end to end: an ESP32 reading CO₂, temperature, humidity and light, a Supabase
project storing the readings, and an iOS app to look at them.

```
ESP32 + SCD40 + BH1750 ──HomeKit, over the local network──▶  Apple Home, Siri, automations
        │  HTTPS, every 15s, batched if the Wi-Fi drops
        ▼
Supabase edge function  ──writes with the service role key──▶  public.readings
                                                                    │
                                                 row level security │ owner_id = auth.uid()
                                                                    ▼
                                                            Aura (SwiftUI)
                                                       REST for history,
                                                       Realtime for live rows,
                                                       widget + Siri intents
                                                                    ▲
                                            pg_cron -> push-alerts -> APNs
```

| | |
|---|---|
| `ios/` | The SwiftUI app. No third-party packages — open it and build. |
| `supabase/` | Schema, policies and the ingest function. |
| `firmware/` | The Arduino sketch for the ESP32. |

**[SETUP.md](SETUP.md) is the click-by-click version of everything below** — what to run, in
what order, and how to check each step worked. This file is the explanation; that one is the
checklist.

---

## Before anything else: rotate your token

The `DEVICE_INGEST_TOKEN` and Wi-Fi passwords that were in the original sketch have been
replaced with placeholders here, but **the old token should be considered burned** — it was
pasted into a chat, so treat it as public. Generate a new one and set it in both places:

```bash
openssl rand -hex 32
```

Supabase → Project Settings → Edge Functions → Secrets → `DEVICE_INGEST_TOKEN`, and
`firmware/room-monitor/secrets.h` (which is gitignored).

Anyone holding that token can write readings into your table. It is the only thing guarding
the ingest endpoint.

---

## 1. Supabase

**Schema.** Paste `supabase/migrations/0001_readings.sql` into the SQL editor and run it. It is
written to be safe against the table you already have — it adds what's missing and leaves the
rest alone. It sets up:

- `public.readings` with an index for the exact shape the app queries
- row level security, so each account reads only its own rows
- `public.device_summary`, which backs the device picker
- the table added to the `supabase_realtime` publication, for live updates
- a check constraint rejecting physically impossible values, so one bad sensor read can't
  rescale every chart

`0003_metric_buckets.sql` is required by the Trends tab. It aggregates per-day and per-month
means in Postgres, bucketed in your own time zone — six months of minute-resolution readings is
a quarter of a million rows and the screen needs six numbers from them. Without it Trends says
so and tells you which file to run.

`0005_zone_buckets.sql` is required by the Trends tab's Areas section, which splits the same
aggregates by zone. Without it that one section says so and the rest of the screen is fine.

`0006_push.sql` and `0007_push_cron.sql` are required by push notifications — the ones that
arrive with the app closed. Run `0006` with the rest; run `0007` *after* deploying the
`push-alerts` function, and fill in the two values at the top of it first.

`0004_zone.sql` is required by the zone button. Run it *before* deploying the updated function
or flashing — the column is nullable, so a device that doesn't send a zone keeps working either
side of the change.

**Account.** Authentication → Users → Add user. Create the account you'll sign into the app
with, then copy its UUID.

**Secrets.** Project Settings → Edge Functions → Secrets:

| Name | Value |
|---|---|
| `DEVICE_INGEST_TOKEN` | the token you just generated |
| `OWNER_USER_ID` | the UUID of the account above |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected for you.

**Function.** Deploy `supabase/functions/ingest-reading/`:

```bash
supabase functions deploy ingest-reading --no-verify-jwt
```

`--no-verify-jwt` is deliberate. The device has no Supabase credentials and no way to refresh
a JWT; it authenticates with `x-device-token`, which the function checks itself using a
timing-safe comparison.

**The alerting function.** Deploy `supabase/functions/push-alerts/` too, if you want
notifications with the app closed:

```bash
supabase functions deploy push-alerts
```

No `--no-verify-jwt` here, unlike the ingest function: this one is called by your own database
holding the service role key, so it should reject anything without a valid Supabase JWT. It
needs four more secrets, from an APNs key you create at
[developer.apple.com](https://developer.apple.com/account/resources/authkeys/list) → Keys →
**+** → Apple Push Notifications service:

| Name | Value |
|---|---|
| `APNS_KEY_ID` | the key's 10-character ID |
| `APNS_TEAM_ID` | your Apple Developer team ID |
| `APNS_PRIVATE_KEY` | the whole `.p8` file, `-----BEGIN PRIVATE KEY-----` and all |
| `APNS_TOPIC` | the app's bundle identifier (`com.aura.roommonitor` unless you changed it) |

Apple lets you download a `.p8` once. Keep it somewhere you'll find it again.

Check it end to end:

```bash
curl -i -X POST \
  -H "Content-Type: application/json" \
  -H "x-device-token: YOUR_TOKEN" \
  -d '{"co2_ppm":812,"temperature_c":22.4,"humidity_percent":47,"light_lux":210}' \
  https://YOUR_PROJECT.supabase.co/functions/v1/ingest-reading
```

`201 {"ok":true,"inserted":1}` means you're done here.

---

## 2. Firmware

```bash
cd firmware/room-monitor
cp secrets.example.h secrets.h   # then fill it in
```

Libraries, via the Arduino Library Manager:

- **BH1750** by Christopher Laws
- **Sensirion I2C SCD4x** by Sensirion
- **HomeSpan** by Gregg Berman — only if you want HomeKit; set `ENABLE_HOMEKIT` to 0 and you
  don't need it at all

Board: *ESP32 Dev Module*. Wiring: SDA → GPIO21, SCL → GPIO22, both sensors on 3V3 and GND.

With HomeKit on, the sketch outgrows the default partition table. **Tools → Partition Scheme →
"Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)"**, or it won't link.

What changed from the original sketch:

- **Secrets moved out** into gitignored `secrets.h`.
- **Offline buffering.** Readings go into a 240-slot ring buffer and upload as one batch,
  at most 100 per request. A router reboot now costs you nothing instead of a gap in the data.
- **NTP time.** Buffered readings carry their real timestamp rather than arriving stamped with
  whenever the network came back.
- **Non-blocking loop.** The original `delay(5000)` plus an early `return` meant a cycle where
  the sensor wasn't ready would skip the upload check entirely. Sampling and uploading are now
  on independent timers.
- **Sensor failures are survivable.** A missing BH1750 no longer takes the light column down
  with a `-1`; it records nothing, and the app draws a gap. CO₂ of 0 ppm during warm-up is
  treated as "no reading" rather than as a measurement.
- **4xx responses drop the batch** instead of retrying a payload the server will never accept.
- **A zone button.** Pressing it cycles the monitor's label — "My Room", "Outdoor", edit the
  `ZONES` table to taste. The name travels with every reading and titles the app's home screen;
  an RGB LED flashes that zone's colour, and the built-in LED blinks its number so the board is
  readable with nothing wired up. It defaults to GPIO 0, the BOOT button on most DevKits, so it
  needs no hardware at all. The choice survives a power cut, and a press pushes the next reading
  up immediately rather than waiting for the interval.

### HomeKit

The monitor publishes itself to Apple HomeKit over your local network — no cloud, no account,
nothing leaving the house. One accessory with four services: a CO₂ sensor, a temperature
sensor, a humidity sensor and a light sensor, all first-class HomeKit types.

To pair: Home app → **+** → Add Accessory → *More options…* → the monitor appears as **Aura
Room Monitor** → enter **466-37-726**. Change `HOMEKIT_PAIRING_CODE` in the sketch if the board
lives anywhere other people can reach.

What that gets you beyond the app: Siri on every device in the house ("what's the CO₂ in the
bedroom"), the readings on a HomePod or Apple TV, and automations — *if carbon dioxide is
detected, turn on the fan*. HomeKit's CO₂ "detected" state flips at 1,200 ppm, which is where
the app's scale turns orange; `HOMEKIT_CO2_ALERT_PPM` moves it.

Readings are published only when they move enough to matter — 10 ppm, 0.1 °C, 0.5 %, or 10 %
for light — because every sample would put an event on the network every five seconds for a
number that changed in its second decimal place.

Wi-Fi stays under the sketch's control rather than HomeSpan's, so the list of networks in
`secrets.h` still works; HomeSpan is handed whichever one answered. HomeKit comes up after
Wi-Fi does, and if the network is down at boot it comes up later, in the loop. GPIO 4 is
reserved for HomeSpan's pairing-reset button — nothing needs to be wired to it.

`client.setInsecure()` is still there, as in the original. It skips certificate verification,
which is a reasonable trade on a network you control and keeps setup painless. The comment
above it says what to do instead if you'd rather verify properly.

---

## 3. iOS app

Open `ios/Aura.xcodeproj` in **Xcode 16 or newer** and run. Deployment target is iOS 17.

On first launch the app asks for your project URL and **anon** key (Project Settings → API),
then for the email and password of the account you created. That's it.

To skip that on every reinstall:

```bash
cp ios/Config.example.plist ios/Aura/Resources/Config.plist
```

Fill it in — it's gitignored, and the app picks it up as a default.

> The anon key is meant to ship inside clients; it grants nothing on its own, because row level
> security is what actually protects the data. The service role key and the device token must
> never go in the app — either one would let anyone who pulls apart the binary read and write
> your whole database.

### What's in it

One screen — **Home** — behind a system tab bar.

A thermal card leads the screen: the temperature as a large light figure, with the day's
average to its right and how that compares with the week before — "Hotter than usual",
"Colder than usual", "About usual". It carries a low wash of the temperature's own band colour.

Under an **Atmosphere** heading, three more cards: CO₂, humidity and light. Each is the number
with its unit beside it, over a dense grid of dim cells with a bright marker standing where the
reading falls. The grid carries no colour of its own — only the neighbourhood of the marker is
tinted, by how bad the reading is: green, yellow, orange, red. Ranges are 400–5,000 ppm,
0–100%, and 0–5,000 lux, the last widening to the next round thousand when direct sun runs
past it.

Tapping a card opens that metric's day in a half-height sheet: a scrubbable trace from midnight
to now, its line coloured by height through the same severity bands, with low, average and peak
underneath. The chart is just the line — no gridlines, no fill, no hour labels along the
bottom, since scrubbing reports the time anyway.

The navigation bar holds a settings button on the left, and on the right a day stepper
(‹ ›) with a date button between them that opens a graphical `DatePicker` in a popover.

Stepping back a day shows that day's **average** rather than its last reading — a past day has
no "now", and whatever it happened to end on at 3am is a worse answer to "what was it like in
here". Today resolves each metric independently, so a dropped BH1750 read doesn't blank the
light figure while the SCD40 in the same row is reporting fine.

Date pickers stop at the first reading the monitor ever sent, so there is no walking back
through months that were never recorded.

Settings is a sheet: monitor picker, notifications, account, sign out, disconnect.

### Notifications

Opt in from Settings. Aura alerts when a sensor crosses into a *worse band* than it was in an
hour ago — band crossings, not raw movement, because 620 → 780 ppm is a rise but still fresh
air. Each metric then stays quiet for an hour, so a value hovering on a threshold can't buzz
the phone repeatedly.

There are two paths, and they do the same thing from different places:

- **Local**, evaluated in the app whenever it loads data. Immediate, no server involved, but
  it can only fire while the app is running.
- **Push**, evaluated in Postgres every 15 minutes by `push-alerts` and delivered through
  APNs. This is the one that reaches you with the app closed, which is when it matters.

Turning the toggle on registers the phone with APNs and writes the token to `push_devices`.
Signing out deletes it, and Apple's own "this token is dead" response prunes it server-side.
The band thresholds are duplicated in `supabase/functions/push-alerts/bands.ts`; if you move
one in `MetricKind`, move it there too — a comment in both files says so.

A development build's token only works against Apple's sandbox host and a TestFlight build's
only against production, so the environment is stored alongside each token and the function
picks the host from it. That is the usual reason a push works in one build and not the other.

### Siri and Shortcuts

Two App Intents, offered to Siri without any setup:

- *"How's the air in Aura"* — every sensor at once.
- *"What's the CO₂ in Aura"* — one sensor, where the sensor is a spoken parameter, so
  "humidity", "temperature", "brightness" and a few synonyms each resolve.

Neither opens the app. They read the same keychain the widget does, fetch from Supabase, speak
the answer and show a snippet carrying the dot grid — a number read aloud says what it is, and
the grid says whether that's good, which is the part speech is bad at.

Both appear in the Shortcuts app as building blocks, so they can be dropped into automations
of your own.

### Trends

The second tab: every sensor over **7 days, a month, or 6 months**, one window picker driving
all four rows. Stepping the header moves a whole window at a time, since the point of the
screen is the shape rather than a single reading.

Below that, **Areas** breaks the same window down per room — one block per zone the monitor has
reported from, each with CO₂ and humidity. These rows headline the window's *average* rather
than the latest reading, since a room is somewhere you ask "what is it usually like in here".
Their axis is shared across zones, so one room's bars are comparable with another's.

Each row collapses to a title, a dot-matrix preview and the latest value, and expands into its
own chart — dithered bars in every window — with a fixed y-axis, the period average, and dates
along the bottom. The axis row lays its labels out on the bars' own column geometry, from one
shared gap constant, so a label's centre is always the centre of the column above it. Dragging across a chart scrubs it: the bar under your finger stays
lit while the rest dim, and the row's value and date follow.

Bars are drawn against a **fixed** axis per metric rather than the window's own minimum and
maximum, so a bar's height means the same thing in every window and a quiet week doesn't get
stretched to look like a dramatic one. Missing days keep their slot and draw a dim baseline, so
a gap reads as "no data" instead of letting the next day slide into its place.

The scrub gesture is a UIKit pan recogniser that fails itself the moment a touch moves further
down than across. A SwiftUI `DragGesture` with a zero minimum distance wins against the
enclosing `ScrollView`, and the page would stop scrolling wherever a chart happened to be.

### Home screen widget

A **Room** widget, large or medium. The room's name across the top with the time of the last
reading, the temperature as the same thin figure Home leads with, and CO₂, humidity and light
each over the same dot grid — fewer columns than the app draws, since at widget width the app's
96 would land below a point apiece and smear into a line.

It is a separate target, `AuraWidgetExtension`, and a separate process, so two things had to be
shared with it:

- **Code.** `ios/Shared/` holds what both build: the models, the Supabase client, the keychain,
  the palette and `DotMatrixBar`. The folder is a member of both targets, so adding a file to it
  needs no project-file edit.
- **Credentials.** The widget reads the project URL, the anon key and the session from the
  keychain the app already writes to. Both targets carry a `keychain-access-groups` entitlement
  naming the same group, and `Keychain` pins its service to a literal rather than the bundle
  identifier, which differs between them.

**What to do in Xcode:** select each target → Signing & Capabilities → set your team. The
entitlement files are already in `ios/Entitlements/`, so Keychain Sharing and Push
Notifications come with them; if Xcode complains, add those capabilities by hand — Keychain
Sharing on both targets with the group `com.aura.roommonitor`, Push Notifications on the app.

The widget stores nothing. Each timeline refresh fetches from Supabase, the same promise the app
makes, and refreshes on its own about every 15 minutes — WidgetKit budgets an extension to a few
dozen wake-ups a day, so asking more often than that would only get the requests dropped. While
the app is open it nudges the widget whenever it has fresh numbers, which costs nothing against
that budget.

If there's no session in the keychain it says so rather than showing stale numbers, and signing
out in the app reloads it immediately.

### Notes on how it's built

- **System controls throughout.** `TabView`, navigation bar, toolbar buttons, `Form`, `List`,
  `Picker`, `DatePicker`, `confirmationDialog`. Nothing is a hand-rolled lookalike, which is
  also why the tab bar and toolbar pick up Liquid Glass on iOS 26 without a single
  availability check — there is no iOS 26-only API in the codebase.
- **Home is the only tab** for now; a second one is one `.tabItem` away.
- **No dependencies.** Auth, PostgREST and Realtime are a few hundred lines of `URLSession`.
- **Live updates are silent.** New rows arrive over Realtime and simply appear, with polling
  underneath as a safety net. Nothing in the UI reports on the state of the connection.
- **Nothing is stored on the phone.** Every number and every chart is fetched from Supabase
  on demand. The keychain holds the auth session and `UserDefaults` holds two settings; no
  reading is ever written to disk.
- **Gaps stay gaps.** A failed sensor decodes to `nil` and is skipped. Nothing is zero-filled.

Temperature, humidity and light are still fetched, decoded and banded — they're just not
surfaced. Adding them back is a view, not a schema change.

---

## Troubleshooting

**App signs in but shows no readings.** The signed-in account must be the one whose UUID is in
`OWNER_USER_ID` — RLS filters on `owner_id`, so a different account correctly sees an empty
table. Check with `select owner_id, count(*) from readings group by 1;`.

**"Live" never turns on.** Realtime needs the table in the publication; the migration does that,
but if you created the table afterwards, re-run that block. The app polls regardless, so this
costs freshness, not data.

**Device uploads 401.** The token in `secrets.h` doesn't match `DEVICE_INGEST_TOKEN`. After
changing the secret, give it a minute: the function reads it when its isolate boots, so an
already-warm one can serve the old value for a short while. If 401s outlast that, redeploy with
`supabase functions deploy ingest-reading --no-verify-jwt` to force a fresh isolate.

**Lost the token.** It can't be read back — the dashboard only stores a digest. Generate a new
one with `openssl rand -hex 32`, set it as `DEVICE_INGEST_TOKEN`, put the same value in
`secrets.h` and re-flash. Nothing else depends on it, so rotating costs only the reflash.

**Device uploads 400.** The payload had no usable values, or a reading was outside the plausible
range in the check constraint. The serial log prints the response body.

**No push notifications.** In order: is the toggle on in Settings, is there a row in
`push_devices`, is the cron job running (`select * from cron.job_run_details order by
start_time desc limit 5;`), and what did the function say (`select * from net._http_response
order by created desc limit 5;`). A `BadDeviceToken` in the function logs means the build's
environment and the stored one disagree — see the note about sandbox and production above.

**HomeKit accessory never appears.** It is published only after Wi-Fi connects, so check the
serial log for "HomeKit ready". If the sketch won't link at all, it's the partition scheme.
To pair it to a second home, or after a failed pairing, hold the button on GPIO 4.

**Temperature reads 1–2 °C high.** Expected — the SCD40 self-heats inside an enclosure. Settings
→ Temperature offset.
