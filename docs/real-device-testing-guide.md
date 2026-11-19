# Real Android Device Testing — Setup, Build, Install, and Run

This is the practical how-to companion to `docs/device-testing-checklist.md`
(the full item-by-item checklist). Read this first to get a real APK
onto a real phone and talk to the backend; use the checklist for the
detailed test steps once the app is running.

**No new features were added and nothing about the product's scope
changed.** One genuine blocker was found and fixed while preparing
this guide — see §0 — because without it, the app cannot reach the
backend at all on a real device, which would make every item below
impossible to test.

## 0. Blocker found and fixed: the app could not talk to the backend from a real device

`android/app/src/main/AndroidManifest.xml` was missing two things
every real-device run needs (debug-only workarounds existed, but not
for the release build type you'll actually install):

1. **`android.permission.INTERNET`** — not declared anywhere in the
   main manifest, and none of the app's plugins (`http`,
   `connectivity_plus`, `geolocator`, `image_picker`, `sqflite`)
   declare it either. A release build (`flutter build apk`, the
   command in §2) would have had **zero network permission** — every
   backend call would fail immediately.
2. **`android:usesCleartextTraffic="true"`** — the backend is plain
   `http://` by design in this dev/LAN setup (see
   `lib/core/network/api_config.dart`), and Android 9+ blocks
   cleartext HTTP by default. Without this, a real device would still
   refuse every request even with the permission above granted.

Both are now set in the main manifest (so they apply to the release
build you'll install, not just `flutter run`'s debug/profile builds).
This was the one genuine blocker found; nothing else in the app
required a production-code change to be ready for device testing —
see `docs/data-model.md` ("Pre-device-testing review (bug fix)") for
the controller-dispose bug fixed in the previous review pass, which is
unrelated to this one.

**Not independently verified here**: this sandboxed environment has no
Android SDK, so the actual Gradle build (§2) could not be run to
completion in this session — only the manifest's XML validity and the
standard, well-documented nature of this exact fix were confirmed.
Running §2 on your own machine is itself the first real verification
of this fix. **DEVICE TEST REQUIRED.**

## 1. Android device requirements

- **Android 7.0 (API 24) or newer** — this is the app's `minSdk`
  (`android/app/build.gradle.kts` uses Flutter's default, currently
  24); anything from a several-years-old budget phone up should run
  it.
- **A rear camera** — `image_picker` is configured for
  `ImageSource.camera` only; there is no gallery fallback, by design.
- **GPS hardware** — a photo cannot be confirmed without a real GPS
  fix; there is no fake-coordinate fallback, by design.
- **Wi-Fi connectivity on the same network as the backend machine**
  (or another way to reach it — see §7). Mobile data alone won't
  reach a backend running on someone's laptop unless you set up a
  tunnel.
- **Enough free storage** for 5 photos × 2 (original + watermarked)
  per visit, plus the app itself.
- **Developer Options + USB debugging enabled**, if you'll install via
  USB/`adb` (§3, option A) — Settings → About phone → tap "Build
  number" 7 times → Developer options → enable USB debugging.
- If you'll install by copying the APK file to the phone instead
  (§3, option B), the phone needs "Install unknown apps" allowed for
  whichever app you use to open the file (file manager, email client,
  etc.) — Android will prompt for this the first time if it isn't
  already allowed.

## 2. The APK build command

From `mobile_app/`, with the Flutter SDK installed and
`flutter pub get` already run:

```bash
cd mobile_app
flutter build apk --release --dart-define=API_BASE_URL=http://<BACKEND-LAN-IP>:8000
```

Replace `<BACKEND-LAN-IP>` with the backend machine's real LAN IP
(§7 explains how to find it) — **not** `10.0.2.2` (that only works
for the Android *emulator*) and **not** `localhost`/`127.0.0.1` (that
means "the phone itself," not your backend machine).

The output APK is at:

```
build/app/outputs/flutter-apk/app-release.apk
```

This `release` build type is signed with the project's debug keystore
(`android/app/build.gradle.kts`: `signingConfig =
signingConfigs.getByName("debug")` — "Signing with the debug keys for
now, so `flutter run --release` works"), so it installs normally
without you needing to set up a release signing key for this test
pass.

**DEVICE TEST REQUIRED**: this build command could not be run to
completion in this session (no Android SDK here — see §0). Run it on
a machine with the Android SDK installed (Android Studio's SDK
Manager, or `flutter doctor --android-licenses` after installing
command-line tools) and confirm it finishes with "Built
build/app/outputs/flutter-apk/app-release.apk" before moving on.

## 3. Installing the APK on your phone

**Option A — via USB with `adb` (recommended if you have a USB cable
and your computer has `adb`, bundled with the Android SDK):**

```bash
adb devices   # confirm your phone is listed and authorized
adb install build/app/outputs/flutter-apk/app-release.apk
```

If an older version is already installed and you get a signature
conflict, uninstall it first: `adb uninstall com.tanfinet.mobile_app`.

**Option B — copy the file to the phone:**

1. Copy `app-release.apk` to the phone (USB file transfer, a cloud
   drive, email to yourself, etc.).
2. On the phone, open it with a file manager and tap to install.
3. If prompted, allow "install unknown apps" for that source — this is
   a one-time Android security prompt, not an app bug.

Either way, launch the installed app ("mobile_app" / the TANFINET
icon) and continue to §4.

## 4. Test sequence: Login through MIS Excel download

Follow `docs/device-testing-checklist.md` in this exact order — each
number below is that document's section:

1. **§2 Setup** — start the backend bound to `0.0.0.0` (§7 below),
   confirm the phone can reach it.
2. **§3 Login** — demo accounts and expected behavior are listed
   there (`ENG001` / `9876543210`, etc.).
3. **§4 POP Selection** — District → Block → GP → POP cascade.
4. **§5 GPS / Location** — permission prompts, denial handling, real
   fix latency. **DEVICE TEST REQUIRED** (never exercised before any
   device pass).
5. **§6 PM Visit Creation & Photo Capture** — all 5 mandatory
   categories in order: POP Rack, UPS & Battery, Busbar, Earth Pit
   Chamber, Earth Pit Open with Rod. Includes the watermark
   placement check (the one risk flagged in §0's linked review).
   **DEVICE TEST REQUIRED.**
6. **§7 Offline Storage** — airplane mode, backgrounding, force-stop,
   device restart, all mid-visit. **DEVICE TEST REQUIRED.**
7. **§8 Sync & Google Drive Upload** — needs backend reachable again;
   Drive credentials are optional (§7 below explains what each case
   looks like). **DEVICE TEST REQUIRED** (Drive has never been
   exercised with real credentials anywhere in this project).
8. **§9 Dispose-race regression** — specifically re-tests this
   session's bug fix (§0's linked fix) under real timing.
9. **§10 Dashboard**, **§11 POP Visit History** — review the test
   visit from steps 5-7 once it's synced.
10. **§12 MIS Excel Download** — tap the button, confirm the file,
    try opening it in a real spreadsheet app. **DEVICE TEST
    REQUIRED** (file discoverability has never been checked on a real
    device).
11. **§13 Final regression pass.**

## 5. What to capture at each important step

| Step | Capture |
|---|---|
| Login | Screenshot of the Profile screen after a successful login (confirms Employee ID/name/district). |
| GPS permission prompts | Screenshot of each prompt (first ask, "denied," "denied forever" if you trigger it) and what you tapped. |
| Each of the 5 photo captures | Screenshot of the Retake/Confirm review screen showing the watermark banner, for every category — not just one. |
| Watermark cross-check | Screenshot of the **same** watermarked photo opened in a plain gallery/file-viewer app, to compare banner placement against the in-app review screen (§0's flagged risk). |
| Offline storage | Screenshot before/after each lifecycle event (airplane mode on, app backgrounded, force-stopped, device restarted) showing the visit/photo state survived. |
| Sync / Drive upload | Screenshot of the resulting status (Pending Sync / Sync Failed / Submitted) and its exact message; if Drive is configured, a screenshot of the actual uploaded files in Google Drive. |
| Any crash | Run `adb logcat *:E > crash.log` (or `adb logcat -b crash`) starting just before the step that crashed, reproduce it, then save the file — this is far more useful for a bug report than a screenshot alone. |
| General app logs during a test session | `adb logcat -s flutter` (prefix the command with `adb logcat -c` first to clear old logs) captures the app's own print/debug output for the session. |
| Dashboard / POP Visit History | Screenshot of the Districts tab, Engineers tab, and the test POP's visit history, after the test visit has synced. |
| MIS download | Screenshot of the success SnackBar (shows the saved path), and a screenshot of the file actually opened in a spreadsheet app. |
| Backend console | Keep the `uvicorn --reload` terminal visible/logged throughout — it prints each request and, on sync, the Drive upload attempt/result, which is useful corroborating evidence for any FAIL. |

## 6. PASS / FAIL table

Fill in device model, Android version, and date once; then one row per
checklist section (cross-reference `docs/device-testing-checklist.md`
for the exact sub-items in each section).

**Device:** _______________  **Android version:** _______________  **Date:** _______________  **Backend commit/branch:** _______________

| # | Area (checklist §) | Result (PASS / FAIL / BLOCKED) | Notes |
|---|---|---|---|
| 1 | Login (§3) | | |
| 2 | POP Selection (§4) | | |
| 3 | GPS / Location (§5) — **DEVICE TEST REQUIRED** | | |
| 4 | Photo Capture, all 5 categories (§6) — **DEVICE TEST REQUIRED** | | |
| 5 | Watermark placement check (§6) — **DEVICE TEST REQUIRED** | | |
| 6 | Offline Storage (§7) — **DEVICE TEST REQUIRED** | | |
| 7 | Sync & Google Drive Upload (§8) — **DEVICE TEST REQUIRED** | | |
| 8 | Dispose-race regression (§9) | | |
| 9 | Dashboard (§10) | | |
| 10 | POP Visit History (§11) | | |
| 11 | MIS Excel Download (§12) — **DEVICE TEST REQUIRED** | | |
| 12 | Final regression pass (§13) | | |

For any FAIL, record it as a bug with device model, Android version,
and exact repro steps — attach the relevant screenshot/log from §5.

## 7. Backend configuration and Google Drive — what must be ready first

**Required, every time:**

1. PostgreSQL running and reachable (tables are created automatically
   on startup — no migrations to run), **or** point `DATABASE_URL` at
   whatever Postgres instance you're using for this test.
2. From `backend/`:
   ```bash
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   cp .env.example .env   # edit DATABASE_URL if not using the default
   uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
   `--host 0.0.0.0` is required — without it, the server only listens
   on localhost and the phone cannot reach it at all.
3. Find the backend machine's LAN IP (`ipconfig` on Windows,
   `ifconfig`/`ip addr` on macOS/Linux) and use it for `<BACKEND-LAN-IP>`
   in §2's build command.
4. Confirm reachability from the phone's browser first, before
   installing the app: visit `http://<BACKEND-LAN-IP>:8000/health`
   over Wi-Fi and confirm it responds — if it doesn't, this is a
   firewall/network issue on the backend machine (allow inbound
   connections on port 8000), not an app issue.
5. Demo accounts are seeded automatically in dev mode — no setup
   needed; see §4 of `docs/device-testing-checklist.md` for the exact
   credentials.

**Google Drive — optional, decide before starting §8 of the test
sequence:**

- **Without any Drive setup** (the default): leave
  `GOOGLE_SERVICE_ACCOUNT_FILE` unset. Sync attempts will
  deterministically fail with "Google Drive is not configured on this
  server" — this is expected and still lets you test everything up to
  that point (offline storage, submission validation, Sync Failed +
  Retry UI). Use this if a real Drive upload isn't part of this pass.
- **With a real Drive upload** (needed to test §8's "real upload
  succeeds" item): before starting, have ready:
  1. A Google Cloud service account (Drive API enabled) with a
     downloaded JSON key file.
  2. That service account granted access to a **Shared Drive** (or a
     folder shared with its email address) — service accounts
     typically have no personal Drive storage quota.
  3. Set on the backend machine (never commit these):
     ```bash
     GOOGLE_SERVICE_ACCOUNT_FILE=/path/to/service-account.json
     GOOGLE_DRIVE_ROOT_FOLDER_NAME=TANFINET PM Monitoring   # optional, this is the default
     GOOGLE_DRIVE_PARENT_FOLDER_ID=<shared drive/folder id>  # optional, needed for a Shared Drive
     ```
  4. Restart `uvicorn` after setting these so they take effect.
  - See `backend/README.md` ("Google Drive Configuration") for the
    full step-by-step if you don't already have a service account.
  - **This has never been exercised with real credentials anywhere in
    this project** — if you do this, it is the very first real test
    of that path. **DEVICE TEST REQUIRED.**
