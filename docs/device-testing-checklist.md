# Real Android Device Testing Checklist

This is the final end-to-end checklist for the first real Android
device/emulator pass of the TANFINET POP PM Monitoring System. No
device/emulator pass has been done in any session before this one —
every "PASS" claimed elsewhere in this repo's README files is at the
`flutter test` / fake-backed / real-server-but-no-device level
described in "What's already verified" below. This document exists so
that pass has one concrete, checkable list to run through, with no
ambiguity about what's already covered and what genuinely still needs
a device.

Before this pass, the full backend and mobile implementation was
reviewed specifically for device-only defects. One genuine bug was
found and fixed (a `ChangeNotifier`-disposed-while-in-flight crash
affecting six controllers app-wide); one risk was identified and
deliberately left unpatched pending real evidence (a possible
EXIF-orientation watermark issue). Both are called out at the exact
checklist step where they matter — see "Pre-device-testing review
(bug fix)" in `docs/data-model.md` for the full writeup.

## 0. Device requirements

**DEVICE TEST REQUIRED** for all of this — none of it can be verified
in this sandboxed build environment (no Android SDK is installed
here; confirmed via `flutter doctor`).

- **Android version**: minimum **Android 7.0 (API 24)** —
  `android/app/build.gradle.kts` uses Flutter's default
  `flutter.minSdkVersion` (24) / `compileSdk`/`targetSdk` (36, Android
  16). A device on Android 10+ is strongly preferred for this first
  pass so camera/GPS permission-dialog behavior matches what most
  real users will see; Android 7-9 will install and likely run, but
  permission-flow wording differs by OS version and hasn't been
  checked against anything that old.
- **Hardware**: a working rear camera, GPS hardware, and either Wi-Fi
  or mobile data reachable to the backend machine's LAN IP (same
  Wi-Fi network is the simplest setup).
- **Storage**: a few hundred MB free (APK + 5 photos/visit × original
  + watermarked copies, uncompressed JPEGs).
- **Settings**: "Install unknown apps" (a.k.a. "Install from unknown
  sources") must be enabled for whichever app you use to open the
  APK file (Files, Chrome, a USB-transfer app, etc.) — this build is
  sideloaded, not from the Play Store. If installing via `adb`/
  `flutter install` over USB, **Developer Options → USB debugging**
  must be enabled instead, and no "unknown apps" toggle is needed.

## 1. Build the APK

Run this on a machine with the Android SDK installed (Android Studio,
or `sdkmanager` command-line tools) — **not** this sandboxed
environment, which has no Android SDK and cannot build or verify this
step. **DEVICE/BUILD-MACHINE TEST REQUIRED.**

```bash
cd mobile_app
flutter pub get

# Replace with the backend machine's real LAN IP, reachable from the
# phone's Wi-Fi/mobile network. 10.0.2.2 (the Flutter default) only
# works for the Android *emulator*, never a real phone.
flutter build apk --debug --dart-define=API_BASE_URL=http://<LAN-IP>:8000
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`.

A **debug** build is recommended for this first pass — better crash
stack traces, no code-shrinking/minification surprises, and this
project's `release` build type is currently signed with the debug
keystore anyway (`android/app/build.gradle.kts`: "Signing with the
debug keys for now" — fine for internal testing, **not** for Play
Store distribution). If you specifically want to test release-mode
performance later:

```bash
flutter build apk --release --dart-define=API_BASE_URL=http://<LAN-IP>:8000
# Output: build/app/outputs/flutter-apk/app-release.apk
```

If the build fails, note the **exact** error — before this pass, only
`flutter pub get`, `flutter analyze`, and `flutter test` have ever
been run against this code; `flutter build apk` itself has never been
run anywhere in this project, since no session so far has had an
Android SDK. A build failure here would be a genuine, previously
unknown blocker — report it rather than working around it.

## 2. Install the APK

Pick whichever is easiest:

**A. Via USB + adb (fastest, works with a debug or release build):**
```bash
# Enable Developer Options -> USB debugging on the phone first,
# connect via USB, accept the "allow USB debugging" prompt on-device.
adb devices   # confirm the phone shows up as "device", not "unauthorized"
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
Or, equivalently, straight from source (builds + installs + launches
in one step):
```bash
flutter run --debug --dart-define=API_BASE_URL=http://<LAN-IP>:8000
```

**B. Without a cable:** copy the APK to the phone (email attachment,
cloud storage, USB file transfer in "file transfer" mode — not ADB),
open it with a file manager, tap to install, and grant the "install
unknown apps" permission for that app when prompted.

Either way, the app will request Camera and Location permission the
first time those features are used, not at install time (standard
modern Android runtime-permission behavior) — this is expected, not a
bug.

## 3. What's already verified vs. what needs a real device

| Area | Already verified (how) | Still needs a real device |
|---|---|---|
| Login / JWT | Real backend `pytest` (`test_auth.py`), real `dart run` against a live `uvicorn` server over a real socket, `flutter test` widget tests | Real device keyboard, autofill, real network (Wi-Fi/mobile data) to the backend's LAN IP |
| District→Block→GP→POP selection | Backend `pytest` (`test_locations.py`), `flutter test` controller/screen tests against fakes | Real dropdown touch interaction, real scroll on long lists |
| Camera capture (5 categories) | `flutter test` against a **fake** `CameraCaptureService` (`image_picker` never exercised) | **Everything about the real camera**: permission prompt, real JPEG output, real file size/orientation/EXIF, cancel behavior, low storage, multiple rapid captures |
| GPS capture | `flutter test` against a **fake** `LocationService` (`geolocator` never exercised); permission-flow *logic* reviewed and is correct | **Everything about real GPS**: permission prompt (first-run, denied, denied-forever), real fix latency (seconds, not instant), real accuracy/noise, indoor/no-fix behavior, location services disabled |
| GPS watermark burn-in | `watermark_service_test.dart` — real `image`-package pixel manipulation on synthetic test images, exact text/field assertions | Real photo resolution/aspect ratio; **the EXIF-orientation risk below is device-only and unverified** |
| Offline SQLite storage | `sqflite_pm_visit_repository_test.dart` — real SQLite via `sqflite_common_ffi` (genuinely real schema/SQL, not faked) | Real app lifecycle: backgrounding mid-capture, process death/restart by Android, low-storage write failures |
| Sync / connectivity | `sync_manager_test.dart` against fake connectivity + fake Drive upload | Real `connectivity_plus` detection, real network drop/recovery mid-sync, real retry timing |
| Google Drive upload | Mobile: fake HTTP transport (`google_drive_upload_service_test.dart`). Backend: `FakeDriveUploadService` (`test_drive_sync.py`) | **No real Google Drive account has ever been used, anywhere, in this project.** Needs `GOOGLE_SERVICE_ACCOUNT_FILE` configured server-side — see `backend/README.md` |
| PM Visit submission/validation | `pm_visit_controller_test.dart` — full lifecycle, duplicate-submit guard, retry, **including the new dispose-while-in-flight regression test** | Real-world timing of the dispose race (tap back mid-GPS-fix) on an actual device; real double-tap timing |
| Dashboard (Districts/Engineers) | Backend `pytest` (`test_dashboard.py`), `dashboard_screen_test.dart` widget tests at a simulated 360×800 width, real `dart run` against a live server | Real narrow-screen layout/safe-area insets, real rotation, real pull-to-refresh gesture, real scroll physics |
| POP Visit History | `pop_visit_history_controller_test.dart` / `_screen_test.dart` widget tests | Same as Dashboard above |
| MIS Excel download | `mis_export_api_client_test.dart` (fake HTTP), `mis_report_download_service_test.dart` (real file write via a faked `path_provider` platform), `mis_report_controller_test.dart`, 3 new `dashboard_screen_test.dart` widget tests for the button | **File discoverability**: whether the saved `.xlsx` is visible/openable from a real device's file manager or needs a share/open action; whether it actually opens correctly in Excel/Sheets/WPS on a real device |

**Bottom line**: every business-logic path (status transitions,
validation rules, compliance math, API contracts) has real automated
coverage. What a device adds is the three plugins `flutter test`
cannot touch at all (`image_picker`, `geolocator`, real
`connectivity_plus`), real timing/latency, real app lifecycle, and
real Google Drive credentials — none of which have been exercised
anywhere in this project until this pass.

## 4. Setup

### 4.1 Backend — must be ready before testing starts

1. **Python 3.11+ and PostgreSQL** (tables are created automatically
   on startup; no separate migration step). SQLite is only used by
   the automated test suite, not for actually running the server.
   ```bash
   cd backend
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   cp .env.example .env   # edit DATABASE_URL to point at your Postgres instance
   ```
2. **Run bound to all interfaces**, not just localhost, so the phone
   can reach it over Wi-Fi:
   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
   Then find this machine's LAN IP (`ipconfig` / `ifconfig` / `ip addr`)
   and confirm the backend is reachable from the phone's browser first:
   `http://<LAN-IP>:8000/health` should return `{"status":"ok"}` (or
   equivalent) before you even open the app.
3. `AUTH_MODE` stays at its default, `dev` (Employee ID + mobile
   number, no OTP) — nothing to configure for that.
4. **Demo accounts** (seeded automatically on first startup against an
   empty database — no manual seeding step):
   | Employee ID | Mobile Number | District |
   |---|---|---|
   | `ENG001` | `9876543210` | Chennai |
   | `ENG002` | `9123456780` | Madurai |
5. **Seeded POPs** to test against (Chennai district):
   `POP-CHN-001` (active), `POP-CHN-002` (**inactive** — use this to
   confirm inactive POPs are excluded/shown correctly where relevant),
   `POP-CHN-003` (active), `POP-CHN-004` (active).

### 4.2 Google Drive — required only if testing a real upload

**Without any Drive configuration**, `/visits/{id}/sync` always
responds with a clear "Google Drive is not configured on this
server" failure — this is expected, not a bug, and still lets you
test the entire app up through the sync *attempt* (§10b below). This
is sufficient for most of this checklist.

**To test a real end-to-end Google Drive upload** (recommended at
least once, since no session has ever done this for this project),
have ready **before** testing starts:

1. A Google Cloud project with the **Drive API enabled** and a
   **service account** created in it, with a downloaded JSON key file.
2. A **Shared Drive** (or a regular folder shared with the service
   account's email address) that account has edit access to — service
   accounts have no personal Drive storage quota, so this step is not
   optional for a real test.
3. The key file placed **outside this repository** (e.g.
   `backend/credentials/google-drive-service-account.json` — already
   `.gitignore`d), and these set on the backend before starting it:
   ```bash
   GOOGLE_SERVICE_ACCOUNT_FILE=/path/to/google-drive-service-account.json
   GOOGLE_DRIVE_PARENT_FOLDER_ID=<the Shared Drive or folder's id>
   # GOOGLE_DRIVE_ROOT_FOLDER_NAME defaults to "TANFINET PM Monitoring" - optional to override
   ```
   See `backend/README.md` ("Google Drive Configuration") for exactly
   how to get the Shared Drive/folder id.
4. After setting these, restart the backend (`uvicorn ...`) before
   running §10c — they're read once at process startup.

### 4.3 Mobile app

Run pointed at the backend's LAN IP (the default `10.0.2.2` only works
for the Android *emulator*, never a real phone) — or just install the
APK built in §1-2, which already has this baked in via `--dart-define`:
```bash
cd mobile_app
flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:8000
```

## 5. Login

- [ ] App opens on the Employee Login screen.
- [ ] Submitting empty fields shows validation errors, no crash.
- [ ] Logging in as `ENG001` / `9876543210` succeeds and shows Profile
      (Employee ID, name "Dev Test Engineer", district "Chennai").
- [ ] Logging in with a wrong mobile number for a real employee ID
      shows a clear error, not a crash.
- [ ] Logging out from Profile returns to Login and a re-login works.
- [ ] **Real keyboard**: numeric keyboard appears for the mobile number
      field (if configured), autofill/autocomplete doesn't break input.

## 6. POP Selection (District → Block → GP → POP)

- [ ] District dropdown populates (Chennai, Madurai).
- [ ] Selecting a District populates Blocks; selecting lower levels
      cascades correctly and resets anything below.
- [ ] Selecting `POP-CHN-002` (seeded **inactive**) — confirm whatever
      this screen's Active/Inactive handling is supposed to do
      actually happens (check `mobile_app/README.md` for the exact
      intended behavior before testing this step).
- [ ] "Start PM Visit" and "View Visit History" buttons both work from
      the POP detail card.

## 7. GPS / Location (real device only — never exercised before this)

- [ ] First GPS request shows the real Android permission prompt.
- [ ] Denying permission once, then granting it on retry, works.
- [ ] Denying permission "forever" is handled with a clear message,
      not a hang or crash (Android requires going to Settings to
      recover from this — confirm the app's message reflects that).
- [ ] Turning off Location Services entirely (not just app permission)
      is handled with a clear error, not a hang.
- [ ] A real GPS fix indoors/with poor signal: confirm the app waits
      a reasonable time and either succeeds or fails clearly — it
      must **never** substitute a fake/cached coordinate.
- [ ] Time a real fix: if it regularly takes several seconds, try
      backing out of the screen *during* that wait (see §11, the
      dispose-race fix) — confirm no crash, and that the category
      correctly stays "Pending" rather than silently completing.

## 8. PM Visit Creation & Photo Capture — all 5 mandatory categories

For a fresh visit at `POP-CHN-001`, in order:

- [ ] **POP Rack** — capture, review screen shows a live preview with
      the GPS watermark banner, Retake works (discards both files,
      category stays Pending), Confirm marks it Completed.
- [ ] **UPS & Battery** — same, confirm a **fresh** GPS fix is taken
      (not reused from POP Rack — check the lat/long differ, however
      slightly, matching real GPS drift).
- [ ] **Busbar** — same.
- [ ] **Earth Pit Chamber** — same.
- [ ] **Earth Pit Open with Rod** — same; once confirmed, the visit
      should automatically become ready for submission.
- [ ] Canceling the camera (back button, no photo taken) for any
      category leaves it Pending with no error shown.
- [ ] Device camera denial (deny the Camera permission) is handled
      with a clear message, not a crash.
- [ ] **Watermark check (device-only risk)**: for at least one photo,
      open the watermarked copy in the review screen AND in a plain
      Android gallery/file viewer app. Confirm the GPS/POP/category/
      timestamp banner is at the **bottom** of the photo as displayed
      (not the side), in both viewers. If it's misplaced in one but
      not the other, that's the EXIF-orientation risk documented in
      `docs/data-model.md` ("Pre-device-testing review") — report it;
      the fix is a one-line `img.bakeOrientation()` call but is only
      worth making if actually observed here.
- [ ] Take all 5 photos back-to-back quickly (stress the camera/GPS
      pipeline) — confirm no file/path collisions or crashes.

## 9. Offline Storage

- [ ] Put the device in Airplane Mode **before** starting a visit;
      confirm the full capture flow (all 5 categories) works
      completely offline.
- [ ] Mid-visit (2-3 photos done), background the app (home button),
      wait, reopen it — confirm it resumes the same visit with the
      already-captured photos still marked Completed (not restarted).
- [ ] Mid-visit, force-stop the app from Android settings (simulates
      a process kill), reopen — confirm the visit and its photos
      survived (SQLite persistence) and the visit resumes correctly
      via "the most recent not-yet-complete visit for this POP."
- [ ] Restart the device entirely mid-visit, reopen the app — same
      check.

## 10. Sync & Google Drive Upload

- [ ] Still offline, confirm the visit becomes "Pending Sync" once all
      5 photos are confirmed, and Submit queues it without erroring
      (clear offline message, not a crash).
- [ ] Turn connectivity back on, tap Submit/Retry — confirm a real
      sync attempt happens.
- [ ] **Without** `GOOGLE_SERVICE_ACCOUNT_FILE` configured: confirm
      the visit lands in "Sync Failed" with the expected
      "Google Drive is not configured on this server" message, and a
      visible Retry action — not a crash, not lost data.
- [ ] **With** Drive configured (if available for this pass): confirm
      a real upload succeeds, the visit reaches "Submitted," and the
      files actually appear in Google Drive under
      `TANFINET PM Monitoring/Chennai/Sholinganallur/Semmancheri GP/
      POP-CHN-001/PM Visits/<date>/<visit id>/` with the 5 expected,
      correctly-named watermarked files (never the plain originals).
- [ ] Toggle connectivity off mid-sync (airplane mode right after
      tapping Submit) — confirm no crash and a sane resulting state
      (not silently "Submitted" without actually uploading).
- [ ] Rapid double-tap Submit — confirm only one upload attempt
      happens (duplicate-submission guard).
- [ ] Resubmitting an already-"Submitted" visit does nothing (no
      second upload).

## 11. Dispose-race regression (confirms this session's bug fix)

- [ ] On the Dashboard screen, start a pull-to-refresh, then
      immediately navigate back before it finishes loading — confirm
      no crash (previously this class of bug could crash with
      "A DashboardController was used after being disposed").
- [ ] On "Start PM Visit," tap a photo category to begin a capture,
      then immediately press the device back button before the GPS
      fix / camera returns — confirm no crash, app returns cleanly to
      the previous screen.
- [ ] Tap "Download MIS Report," then immediately navigate away before
      it finishes — confirm no crash.

## 12. Dashboard (Districts / Engineers)

- [ ] Districts tab: overall summary card and per-district compliance
      % render correctly; expanding a district shows per-POP
      Completed/Pending status and, for an incomplete POP, the exact
      missing category names.
- [ ] After completing the visit in §8-10 above, refresh the Dashboard
      and confirm `POP-CHN-001` now shows as Completed/Compliant (only
      once the sync actually succeeds — if Drive isn't configured,
      confirm it correctly still shows Pending/Sync Failed, since the
      backend only records a visit after a successful Drive upload).
- [ ] Engineers tab: `ENG001`'s visits-synced/compliant ratio updates
      correctly after the same test visit syncs.
- [ ] Fortnight previous/next/today navigation works with real touch.
- [ ] Rotate the device (if supported) and confirm no layout overflow
      on either tab.
- [ ] Pull-to-refresh with Wi-Fi off shows a clear error, not a blank
      screen or crash.

## 13. POP Visit History

- [ ] Tapping a POP row from the Dashboard, or "View Visit History"
      from POP Selection, opens the history screen for that POP.
- [ ] Shows the District › Block › GP breadcrumb correctly.
- [ ] The test visit from §8-10 appears (once synced) with its correct
      category present/missing breakdown and a visit date.
- [ ] Multiple visits for the same POP render most-recent-first without
      layout overflow on the real screen.

## 14. MIS Excel Download

- [ ] On the Dashboard's AppBar, tap "Download MIS Report" — icon
      swaps to a spinner, button disables while downloading.
- [ ] On success, a SnackBar shows the saved file path.
- [ ] **Open the saved file** from a real Android file manager (the
      path is under the app's private storage —
      `<app documents dir>/mis_reports/mis_export_<year>-<month>.xlsx`
      — confirm whether it's visible there at all on this device/
      Android version, or whether a share/"open with" action would be
      needed; this is the one documented unverified limitation for
      this feature).
- [ ] Open the file in a real spreadsheet app (Excel/Sheets/WPS) and
      confirm it opens correctly and the columns/rows look right,
      including the test visit from §8-10 once it's synced.
- [ ] Turn off connectivity and tap the button again — confirm a clear
      network-error SnackBar, not a crash.
- [ ] Tap the button, then immediately navigate away — see §11.

## 15. Final regression pass

- [ ] Nothing above affected GPS watermark text accuracy, offline
      storage integrity, or the existing Dashboard compliance numbers
      for POPs not touched by this test session.
- [ ] `flutter analyze` and `flutter test` still pass on the exact
      code running on the device (no uncommitted device-only patches
      left in place).

## 16. Recording results

For each numbered item above, record **PASS**, **FAIL** (with repro
steps), or **BLOCKED** (environment couldn't test it, e.g. no second
device for a multi-device scenario). File a FAIL as a bug with device
model + Android version + exact repro steps — the kind of detail none
of this project's automated tests can supply.

## 17. What to capture at each step

Capture as you go, not retroactively — a crash's exact `logcat`
output is only available while it's still in the buffer.

- **Screenshot, every step below** (not just failures): Login success
  (Profile screen), each of the 5 photo review screens (showing the
  watermark banner), the Dashboard's Districts and Engineers tabs, the
  POP Visit History screen, the MIS download success SnackBar, and
  the opened `.xlsx` file in a spreadsheet app.
- **`adb logcat` around every capture/GPS/sync/submit action**, filtered
  to this app, running continuously in a second terminal:
  ```bash
  adb logcat --pid=$(adb shell pidof -s com.tanfinet.mobile_app)
  ```
  Save the full log for the session (`adb logcat ... > device-test.log`)
  — this is what proves whether a crash is the dispose-race bug from
  §11, something in `image_picker`/`geolocator`, or something new.
- **The running backend terminal's output**, for every sync/Drive
  attempt (§10) — it shows the exact request received and the
  Drive service's success/failure detail, which the phone's own UI
  deliberately only shows a simplified version of.
- **For a real Google Drive test**: a screenshot of the actual Drive
  folder tree showing the created `TANFINET PM Monitoring/Chennai/
  Sholinganallur/Semmancheri GP/POP-CHN-001/PM Visits/<date>/
  <visit id>/` path and its 5 files.
- **For the MIS download (§14)**: the saved `.xlsx` file itself, pulled
  off the device if useful for comparison with a backend-generated
  copy:
  ```bash
  adb shell run-as com.tanfinet.mobile_app \
    cat files/mis_reports/mis_export_<year>-<month>.xlsx > mis_export_from_device.xlsx
  ```
  (requires a debug build; `run-as` doesn't work against a release
  build on a non-rooted device — if that's a problem, just verify via
  the on-device file manager/spreadsheet app instead, per §14).
- **On any FAIL**: device model, exact Android version
  (`adb shell getprop ro.build.version.release`), the full `logcat`
  excerpt around the failure, and exact repro steps (which POP, which
  category, online/offline, etc.).

## 18. PASS / FAIL table

Copy this into your test report and fill in **Result** (PASS / FAIL /
BLOCKED) and **Notes** as you go. "DEVICE TEST REQUIRED" items have
never been exercised in any form before this pass; the others already
have automated/partial coverage (see §3) and this is their first
real-device confirmation.

| # | Area | Device-only? | Result | Notes |
|---|---|---|---|---|
| 0 | Device meets requirements (§0) | DEVICE TEST REQUIRED | | |
| 1 | APK builds successfully (§1) | DEVICE/BUILD-MACHINE REQUIRED | | |
| 2 | APK installs on the device (§2) | DEVICE TEST REQUIRED | | |
| 5a | Login screen opens, validation works | | | |
| 5b | Login succeeds as ENG001/9876543210 | | | |
| 5c | Wrong-credentials error is clear | | | |
| 5d | Logout → re-login works | | | |
| 5e | Real keyboard/autofill behave correctly | DEVICE TEST REQUIRED | | |
| 6a | District → Block → GP → POP cascade works | | | |
| 6b | Inactive POP (`POP-CHN-002`) handled correctly | | | |
| 7a | Camera permission prompt appears | DEVICE TEST REQUIRED | | |
| 7b | Permission denied / denied-forever handled | DEVICE TEST REQUIRED | | |
| 7c | Location Services off handled | DEVICE TEST REQUIRED | | |
| 7d | Real GPS fix latency / indoor behavior | DEVICE TEST REQUIRED | | |
| 8a | Capture: POP Rack | DEVICE TEST REQUIRED | | |
| 8b | Capture: UPS & Battery (fresh GPS fix) | DEVICE TEST REQUIRED | | |
| 8c | Capture: Busbar | DEVICE TEST REQUIRED | | |
| 8d | Capture: Earth Pit Chamber | DEVICE TEST REQUIRED | | |
| 8e | Capture: Earth Pit Open with Rod → ready for submission | DEVICE TEST REQUIRED | | |
| 8f | Cancel camera mid-capture leaves category Pending | DEVICE TEST REQUIRED | | |
| 8g | Camera permission denial handled | DEVICE TEST REQUIRED | | |
| 8h | Watermark banner on correct edge (EXIF risk, see §11/data-model.md) | DEVICE TEST REQUIRED | | |
| 8i | Rapid back-to-back captures, no crash | DEVICE TEST REQUIRED | | |
| 9a | Full offline capture (Airplane Mode) | DEVICE TEST REQUIRED | | |
| 9b | App backgrounded mid-visit resumes correctly | DEVICE TEST REQUIRED | | |
| 9c | App force-stopped mid-visit resumes correctly | DEVICE TEST REQUIRED | | |
| 9d | Device restarted mid-visit resumes correctly | DEVICE TEST REQUIRED | | |
| 10a | Offline submit queues as Pending Sync | | | |
| 10b | Sync without Drive configured fails cleanly | | | |
| 10c | Sync with Drive configured succeeds end-to-end | DEVICE TEST REQUIRED (needs real credentials) | | |
| 10d | Connectivity drop mid-sync handled | DEVICE TEST REQUIRED | | |
| 10e | Duplicate-submit guard (rapid double-tap) | | | |
| 10f | Resubmitting a Submitted visit is a no-op | | | |
| 11a | Back-navigation mid-Dashboard-refresh, no crash | DEVICE TEST REQUIRED | | |
| 11b | Back-navigation mid-photo-capture, no crash | DEVICE TEST REQUIRED | | |
| 11c | Back-navigation mid-MIS-download, no crash | DEVICE TEST REQUIRED | | |
| 12a | Districts tab renders correctly | | | |
| 12b | Test visit reflected after sync | | | |
| 12c | Engineers tab renders correctly | | | |
| 12d | Fortnight navigation works with real touch | | | |
| 12e | Rotation, no layout overflow | DEVICE TEST REQUIRED | | |
| 12f | Pull-to-refresh offline error is clear | | | |
| 13a | POP Visit History opens and shows correct context | | | |
| 13b | Multiple visits render without overflow | DEVICE TEST REQUIRED | | |
| 14a | Download button: loading/disabled state | | | |
| 14b | Success SnackBar with file path | | | |
| 14c | File discoverable/openable on-device | DEVICE TEST REQUIRED | | |
| 14d | File opens correctly in a spreadsheet app | DEVICE TEST REQUIRED | | |
| 14e | Offline download error is clear | | | |
| 15 | Final regression (no unrelated areas affected) | | | |
