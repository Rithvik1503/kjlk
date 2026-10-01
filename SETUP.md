# Setup, step by step

Everything that has to be done by hand, in the order it has to be done. Each step says how to
check it worked before you move on.

If you only want part of it: **1–3** are required for anything to work at all, **4** is
HomeKit, **5** is push notifications, **6** is the widget and Siri. They're independent after
step 3.

---

## 0. Get the code

```bash
cd ~/path/to/kjlk
git pull
```

If git refuses because of local changes to the sketch:

```bash
cp firmware/room-monitor/room-monitor.ino ~/Desktop/room-monitor-backup.ino
git checkout -- firmware/room-monitor/room-monitor.ino
git pull
```

Your `secrets.h` is gitignored and is never touched by this.

---

## 1. Database

Supabase dashboard → **SQL Editor** → **New query**. Paste one file, press **Run**, check it
says Success, then move to the next. Order matters.

| # | File | What breaks without it |
|---|---|---|
| 1 | `supabase/migrations/0001_readings.sql` | everything |
| 2 | `supabase/migrations/0003_metric_buckets.sql` | the Trends tab |
| 3 | `supabase/migrations/0004_zone.sql` | the zone button (room names) |
| 4 | `supabase/migrations/0005_zone_buckets.sql` | the Areas section in Trends |
| 5 | `supabase/migrations/0006_push.sql` | push notifications |

Leave `0007_push_cron.sql` for step 5 — it has to run after the function is deployed.

**Check it:** run this in the SQL editor. All five rows should come back.

```sql
select 'readings'        as thing, to_regclass('public.readings')              is not null as ok
union all select 'zone column',    (select count(*) = 1 from information_schema.columns
                                    where table_name = 'readings' and column_name = 'zone')
union all select 'metric buckets', to_regproc('public.aura_metric_buckets')    is not null
union all select 'zone buckets',   to_regproc('public.aura_zone_buckets')      is not null
union all select 'push tables',    to_regclass('public.push_devices')          is not null;
```

---

## 2. The ingest function

**This is almost certainly still wrong on your project.** The error you saw earlier —
`{"error":"Reading values must be numbers"}` — comes from the *original* function, which takes
one reading per request. The firmware now sends an array. The function in this repo takes
both.

### With the CLI

```bash
cd ~/path/to/kjlk
supabase link --project-ref YOUR_PROJECT_REF     # once
supabase functions deploy ingest-reading --no-verify-jwt
```

`--no-verify-jwt` is deliberate: the ESP32 has no Supabase credentials and authenticates with
the `x-device-token` header instead, which the function checks itself.

### Without the CLI

Dashboard → **Edge Functions** → click **ingest-reading** → **Code** → select everything in
the editor and replace it with the contents of
`supabase/functions/ingest-reading/index.ts` → **Deploy**.

Then **Edge Functions** → **ingest-reading** → **Details**, and make sure "Verify JWT with
legacy secret" is **off**.

### Secrets it needs

Dashboard → **Project Settings** → **Edge Functions** → **Secrets**:

| Name | Value |
|---|---|
| `DEVICE_INGEST_TOKEN` | the same string as `DEVICE_TOKEN` in `secrets.h` |
| `OWNER_USER_ID` | the UUID from Authentication → Users |

**Check it:** this should answer `201 {"ok":true,"inserted":1}`.

```bash
curl -i -X POST \
  -H "Content-Type: application/json" \
  -H "x-device-token: YOUR_TOKEN" \
  -d '[{"co2_ppm":812,"temperature_c":22.4,"humidity_percent":47,"light_lux":210}]' \
  https://YOUR_PROJECT.supabase.co/functions/v1/ingest-reading
```

Note the square brackets — that's the array shape the firmware sends. A `401` means the token
doesn't match; a `404` means the function isn't deployed under that name.

---

## 3. The app

1. Open `ios/Aura.xcodeproj` in **Xcode 16 or newer**.
2. Click the blue **Aura** project at the top of the file list.
3. Under TARGETS, select **Aura** → **Signing & Capabilities** tab.
4. Tick **Automatically manage signing**, and pick your name in **Team**.
5. Select the **AuraWidgetExtension** target and do the same.
6. Pick your iPhone (or a Simulator) in the toolbar and press **⌘R**.

You should see Keychain Sharing already listed as a capability on both targets, and Push
Notifications on Aura — they come from the entitlement files. If Xcode shows a red error about
either, press **+ Capability** on that target and add it by hand (Keychain Sharing needs the
group `com.aura.roommonitor`).

**About Apple accounts:** a free Apple ID is enough for the app, the widget, Siri and HomeKit.
**Push notifications need the paid Apple Developer Program** ($99/year) — a free account can't
create APNs keys, and Xcode will refuse the Push Notifications capability. If you're on a free
account, skip step 5 entirely and delete the `aps-environment` key from
`ios/Entitlements/Aura.entitlements`; everything else works.

**Check it:** the app launches, you sign in, and today's numbers appear.

---

## 4. HomeKit on the ESP32

### 4a. Install the library

Arduino IDE → the **books icon** in the left sidebar (Library Manager) → search
`HomeSpan` → the one by **Gregg Berman** → **Install**.

It may ask to install dependencies; say yes.

### 4b. Set the partition scheme

This is the step that breaks the build if you skip it — the sketch with HomeKit is bigger than
the default app partition, and the error is a wall of linker text ending in
`region 'iram0_0_seg' overflowed` or `text section exceeds available space`.

1. **Tools → Board → esp32 → ESP32 Dev Module** (the Partition Scheme menu only appears once
   an ESP32 board is selected).
2. **Tools → Partition Scheme → Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)**.

In Arduino IDE 2.x the Tools menu is at the top of the screen; in 1.8.x it's the same place.

### 4c. Flash

1. Open `firmware/room-monitor/room-monitor.ino`.
2. **Tools → Port** → your board.
3. Press **→** (Upload).
4. Open **Tools → Serial Monitor**, set it to **115200 baud**.

**Check it:** the serial log should show `Connected. IP address: …` and then
`HomeKit ready. Pair with code 46637726`.

### 4d. Pair it

On your iPhone:

1. Open the **Home** app.
2. **+** (top right) → **Add Accessory**.
3. **More options…** at the bottom.
4. **Aura Room Monitor** appears in the list — tap it.
5. Enter the code **466-37-726**.
6. It'll ask which room; pick one. Then it adds four sensors — CO₂, temperature, humidity and
   light.

If it doesn't appear, the phone and the ESP32 must be on the same Wi-Fi network (and the phone
not on 5GHz-only while the ESP32 is on 2.4GHz — that's fine, same network name is enough).

### 4e. Try an automation

Home app → **Automation** tab → **+** → *An Accessory Detects Something* → **Aura Room
Monitor** → *Carbon Dioxide Detected* → then pick what should happen. That triggers at
1,200 ppm; change `HOMEKIT_CO2_ALERT_PPM` in the sketch to move it.

**Don't want HomeKit?** Set `ENABLE_HOMEKIT` to `0` near the top of the sketch. The library
isn't needed, and the default partition scheme is fine again.

---

## 5. Push notifications

Needs a **paid Apple Developer Program** membership. Skip if you don't have one.

### 5a. Create the APNs key

1. Go to <https://developer.apple.com/account/resources/authkeys/list>.
2. Press **+**.
3. Key Name: anything — `Aura Push`.
4. Tick **Apple Push Notifications service (APNs)**.
5. **Continue** → **Register** → **Download**.

You get a file called `AuthKey_XXXXXXXXXX.p8`. **Apple lets you download it once.** Put it
somewhere you'll find it again.

Write down two things from that page:

- **Key ID** — the 10 characters in the filename, also shown on the key's page.
- **Team ID** — top right of the developer site, under your name. 10 characters.

### 5b. Put them in Supabase

Dashboard → **Project Settings** → **Edge Functions** → **Secrets** → **Add new secret**, four
times:

| Name | Value |
|---|---|
| `APNS_KEY_ID` | the 10-character Key ID |
| `APNS_TEAM_ID` | the 10-character Team ID |
| `APNS_PRIVATE_KEY` | the **entire contents** of the `.p8` file |
| `APNS_TOPIC` | `com.aura.roommonitor` |

For `APNS_PRIVATE_KEY`, open the `.p8` in a text editor and copy all of it, including the
`-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines. Line breaks are fine.

`APNS_TOPIC` is your app's bundle identifier — `com.aura.roommonitor` unless you changed it in
Xcode. It must match exactly.

### 5c. Deploy the function

```bash
supabase functions deploy push-alerts
```

No `--no-verify-jwt` this time. This one is called by your own database with the service role
key, so it should reject anything without a valid Supabase JWT.

Without the CLI: Dashboard → **Edge Functions** → **Deploy a new function** → name it exactly
`push-alerts` → paste `index.ts`, then add two more files called exactly `apns.ts` and
`bands.ts` with the contents from `supabase/functions/push-alerts/`.

**Check it:** this should answer `{"ok":true,...}` rather than an error about missing secrets.

```bash
curl -i -X POST \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  https://YOUR_PROJECT.supabase.co/functions/v1/push-alerts
```

The service role key is in **Project Settings → API → Project API keys → `service_role`**.

### 5d. Schedule it

1. Open `supabase/migrations/0007_push_cron.sql`.
2. Near the top, replace `YOUR_PROJECT_REF` with your project ref (the subdomain of your
   project URL — the `abcdefghij` in `https://abcdefghij.supabase.co`).
3. Replace `YOUR_SERVICE_ROLE_KEY` with the service role key.
4. Paste the whole file into the SQL editor and **Run**.

It stores both in Supabase Vault rather than inside the job definition, so the key isn't
sitting in plain text in `cron.job`.

**Check it:**

```sql
select jobname, schedule, active from cron.job where jobname = 'aura-push-alerts';
select status, start_time from cron.job_run_details order by start_time desc limit 5;
```

### 5e. Turn it on in the app

Open Aura → **gear icon** (top left) → **Tell me when it gets worse** → allow notifications.

**Check it:** a row should appear here, with `environment` = `sandbox` for a build run from
Xcode.

```sql
select token, environment, updated_at from push_devices;
```

Alerts only fire when a sensor crosses into a *worse band* than an hour ago, so you may not see
one for a while. To force one: breathe near the sensor for a few minutes until CO₂ goes over
800, wait for the next quarter hour, and the phone should buzz.

---

## 6. Widget and Siri

Nothing to configure — they ship with the app. Both read the credentials the app saved, so
sign in first.

**Widget:** long-press the home screen → **+** (top left) → scroll to **Aura** → swipe to the
**large** size → **Add Widget**.

**Siri:** say *"Hey Siri, how's the air in Aura"* or *"Hey Siri, what's the CO₂ in Aura"*. They
also appear in the **Shortcuts** app under Aura, as blocks you can drop into your own
automations.

If Siri says it doesn't know, open the app once and lock the phone — iOS indexes app shortcuts
shortly after first launch.

---

## Quick troubleshooting

| What you see | What it means |
|---|---|
| Serial: `Upload: 404` | the ingest function isn't deployed under that name (step 2) |
| Serial: `Upload: 400 — Reading values must be numbers` | the **old** function is still deployed (step 2) |
| Serial: `Upload: 401` | `DEVICE_TOKEN` in `secrets.h` ≠ `DEVICE_INGEST_TOKEN` in Supabase |
| App signs in but is empty | the signed-in account's UUID isn't `OWNER_USER_ID` |
| Trends says "needs one more migration" | `0003` hasn't been run |
| Areas says the same | `0005` hasn't been run |
| `zone` is null in the table | `0004` wasn't run before the device started sending |
| Build fails with `region … overflowed` | partition scheme (step 4b) |
| HomeKit accessory never appears | serial log doesn't say "HomeKit ready" — Wi-Fi, not HomeKit |
| Push works in TestFlight but not Xcode, or vice versa | sandbox vs production token; delete the row in `push_devices` and toggle notifications off and on |
