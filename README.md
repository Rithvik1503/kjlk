# Aura

A room monitor, end to end: an ESP32 reading CO₂, temperature, humidity and light, a Supabase
project storing the readings, and an iOS app to look at them.

```
ESP32 + SCD40 + BH1750
        │  HTTPS, every 60s, batched if the Wi-Fi drops
        ▼
Supabase edge function  ──writes with the service role key──▶  public.readings
                                                                    │
                                                 row level security │ owner_id = auth.uid()
                                                                    ▼
                                                            Aura (SwiftUI)
                                                       REST for history,
                                                       Realtime for live rows
```

| | |
|---|---|
| `ios/` | The SwiftUI app. No third-party packages — open it and build. |
| `supabase/` | Schema, policies and the ingest function. |
| `firmware/` | The Arduino sketch for the ESP32. |

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

`0002_thermal_baseline.sql` is optional. It adds a function that averages temperature over a
window in Postgres, which the thermal card uses for its "than usual" comparison — a week of
minute-resolution readings is around ten thousand rows and the app only needs one number from
them. Without it the card describes the day on its own terms instead, so nothing breaks.

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

Board: *ESP32 Dev Module*. Wiring: SDA → GPIO21, SCL → GPIO22, both sensors on 3V3 and GND.

What changed from the original sketch:

- **Secrets moved out** into gitignored `secrets.h`.
- **Offline buffering.** Readings go into a 60-slot ring buffer and upload as one batch. A
  router reboot now costs you nothing instead of a gap in the data.
- **NTP time.** Buffered readings carry their real timestamp rather than arriving stamped with
  whenever the network came back.
- **Non-blocking loop.** The original `delay(5000)` plus an early `return` meant a cycle where
  the sensor wasn't ready would skip the upload check entirely. Sampling and uploading are now
  on independent timers.
- **Sensor failures are survivable.** A missing BH1750 no longer takes the light column down
  with a `-1`; it records nothing, and the app draws a gap. CO₂ of 0 ppm during warm-up is
  treated as "no reading" rather than as a measurement.
- **4xx responses drop the batch** instead of retrying a payload the server will never accept.

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

A **Thermal reading** section leads the screen: the temperature as a large light figure, with
the day's average set to its right and how that compares with the week before — "Hotter than
usual", "Colder than usual", "About usual". Its card carries a low wash of the temperature's
own band colour from the top right.

Below it, three cards: CO₂, humidity and light. Each is the number, its unit, and a 96 × 6
dot-matrix level indicator. Each lit column takes the band colour at *its own* position on that
metric's scale, so the lit run is a slice of the scale's ramp rather than a flat block, and the
lit cells bloom so the grid reads as an emissive panel. That is what says whether a number is
good, which is why no card carries a verdict in words. The background glow follows the CO₂ band.

The matrix is drawn in a `Canvas`, in two passes — bloom, then sharp cells on top. As a grid of
`Shape` views it would be 576 views per card.

The navigation bar holds a settings button on the left, and on the right a day stepper
(‹ ›) with a date button between them that opens a graphical `DatePicker` in a popover.

Stepping back a day shows that day's **average** rather than its last reading — a past day has
no "now", and whatever it happened to end on at 3am is a worse answer to "what was it like in
here". Today resolves each metric independently, so a dropped BH1750 read doesn't blank the
light figure while the SCD40 in the same row is reporting fine.

Settings is a sheet: monitor picker, account, sign out, disconnect.

### Notes on how it's built

- **System controls throughout.** `TabView`, navigation bar, toolbar buttons, `Form`, `List`,
  `Picker`, `DatePicker`, `confirmationDialog`. Nothing is a hand-rolled lookalike, which is
  also why the tab bar and toolbar pick up Liquid Glass on iOS 26 without a single
  availability check — there is no iOS 26-only API in the codebase.
- **Home is the only tab** for now; a second one is one `.tabItem` away.
- **No dependencies.** Auth, PostgREST and Realtime are a few hundred lines of `URLSession`.
- **Live updates are silent.** New rows arrive over Realtime and simply appear, with polling
  underneath as a safety net. Nothing in the UI reports on the state of the connection.
- **Opens with data.** Today's readings are cached to disk, so the first frame is never a
  spinner.
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

**Device uploads 401.** The token in `secrets.h` doesn't match `DEVICE_INGEST_TOKEN`. Note that
the function reads the secret at request time — no redeploy needed after changing it.

**Device uploads 400.** The payload had no usable values, or a reading was outside the plausible
range in the check constraint. The serial log prints the response body.

**Temperature reads 1–2 °C high.** Expected — the SCD40 self-heats inside an enclosure. Settings
→ Temperature offset.
