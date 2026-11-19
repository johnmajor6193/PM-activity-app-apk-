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

## 1. What's already verified vs. what needs a real device

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

## 2. Setup

1. **Backend**: run it bound to all interfaces, not just localhost, so
   the phone can reach it over Wi-Fi:
   ```bash
   cd backend
   uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
   ```
   Find the machine's LAN IP (e.g. `ipconfig`/`ifconfig`/`ip addr`).
2. **Google Drive (optional)**: without `GOOGLE_SERVICE_ACCOUNT_FILE`
   configured, Drive upload will deterministically fail with a clear
   "Google Drive is not configured on this server" message — that's
   expected and still lets you test everything up to the sync attempt.
   To test a real upload, see `backend/README.md`
   ("Google Drive Configuration").
3. **Mobile app**: run pointed at that LAN IP (the default
   `10.0.2.2` only works for the Android *emulator*, not a real phone):
   ```bash
   cd mobile_app
   flutter run --dart-define=API_BASE_URL=http://<LAN-IP>:8000
   ```
4. **Demo accounts** (seeded automatically in dev mode):
   | Employee ID | Mobile Number | District |
   |---|---|---|
   | `ENG001` | `9876543210` | Chennai |
   | `ENG002` | `9123456780` | Madurai |
5. **Seeded POPs** to test against (Chennai district):
   `POP-CHN-001` (active), `POP-CHN-002` (**inactive** — use this to
   confirm inactive POPs are excluded/shown correctly where relevant),
   `POP-CHN-003` (active), `POP-CHN-004` (active).

## 3. Login

- [ ] App opens on the Employee Login screen.
- [ ] Submitting empty fields shows validation errors, no crash.
- [ ] Logging in as `ENG001` / `9876543210` succeeds and shows Profile
      (Employee ID, name "Dev Test Engineer", district "Chennai").
- [ ] Logging in with a wrong mobile number for a real employee ID
      shows a clear error, not a crash.
- [ ] Logging out from Profile returns to Login and a re-login works.
- [ ] **Real keyboard**: numeric keyboard appears for the mobile number
      field (if configured), autofill/autocomplete doesn't break input.

## 4. POP Selection (District → Block → GP → POP)

- [ ] District dropdown populates (Chennai, Madurai).
- [ ] Selecting a District populates Blocks; selecting lower levels
      cascades correctly and resets anything below.
- [ ] Selecting `POP-CHN-002` (seeded **inactive**) — confirm whatever
      this screen's Active/Inactive handling is supposed to do
      actually happens (check `mobile_app/README.md` for the exact
      intended behavior before testing this step).
- [ ] "Start PM Visit" and "View Visit History" buttons both work from
      the POP detail card.

## 5. GPS / Location (real device only — never exercised before this)

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
      backing out of the screen *during* that wait (see §9, the
      dispose-race fix) — confirm no crash, and that the category
      correctly stays "Pending" rather than silently completing.

## 6. PM Visit Creation & Photo Capture — all 5 mandatory categories

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

## 7. Offline Storage

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

## 8. Sync & Google Drive Upload

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

## 9. Dispose-race regression (confirms this session's bug fix)

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

## 10. Dashboard (Districts / Engineers)

- [ ] Districts tab: overall summary card and per-district compliance
      % render correctly; expanding a district shows per-POP
      Completed/Pending status and, for an incomplete POP, the exact
      missing category names.
- [ ] After completing the visit in §6-8 above, refresh the Dashboard
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

## 11. POP Visit History

- [ ] Tapping a POP row from the Dashboard, or "View Visit History"
      from POP Selection, opens the history screen for that POP.
- [ ] Shows the District › Block › GP breadcrumb correctly.
- [ ] The test visit from §6-8 appears (once synced) with its correct
      category present/missing breakdown and a visit date.
- [ ] Multiple visits for the same POP render most-recent-first without
      layout overflow on the real screen.

## 12. MIS Excel Download

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
      including the test visit from §6-8 once it's synced.
- [ ] Turn off connectivity and tap the button again — confirm a clear
      network-error SnackBar, not a crash.
- [ ] Tap the button, then immediately navigate away — see §9.

## 13. Final regression pass

- [ ] Nothing above affected GPS watermark text accuracy, offline
      storage integrity, or the existing Dashboard compliance numbers
      for POPs not touched by this test session.
- [ ] `flutter analyze` and `flutter test` still pass on the exact
      code running on the device (no uncommitted device-only patches
      left in place).

## 14. Recording results

For each numbered item above, record **PASS**, **FAIL** (with repro
steps), or **BLOCKED** (environment couldn't test it, e.g. no second
device for a multi-device scenario). File a FAIL as a bug with device
model + Android version + exact repro steps — the kind of detail none
of this project's automated tests can supply.
