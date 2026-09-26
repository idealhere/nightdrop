# Store images (F-Droid / fastlane layout)

F-Droid pulls the listing graphics from this folder.

- `icon.png` — 512×512 app icon (optional; F-Droid also extracts it from the APK).
  The app icon source lives at `app/assets/icons/icon-512.png`.
- `phoneScreenshots/` — 1080×2340, captured on a Galaxy S25 on 2026-09-26 (0.1.24):
  `01` a chat with burn messages (hidden, burning, sent) and the compact header, `02` the burn
  menu, `03` the chat list, `04` pairing (QR and code redacted), `05` safety-number verification,
  `06` Tor bridges, `07` the home menu, `08` the Exit dialog.

## Regenerating them

The set is shot from **`app/lib/main_screenshots.dart`**: the real UI over the in-memory mock core,
seeded with fictional people and conversations. It is never part of a release (`main.dart` does not
import it). Build it under a separate app id so the real install and its identity are untouched:

```sh
cd app
ORG_GRADLE_PROJECT_appId=app.nightdrop.shots ORG_GRADLE_PROJECT_appName="ND Shots" \
  flutter build apk --release --split-per-abi --target-platform android-arm64 \
  -t lib/main_screenshots.dart
adb -s <serial> install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Samsung ignores Android's status-bar demo mode, so check each shot's status bar for personal
notification icons by eye. Uninstall `app.nightdrop.shots` afterwards.

## Before adding a screenshot — redact secrets

This listing is public, and several screens show live key material. **The pairing screen is the
dangerous one:**

- The **invite QR** encodes the device's onion address *and a pre-authorized pre-key bundle* —
  anyone who scans it can message that identity. It is not merely an address.
- The **short code's secret words** are the SPAKE2 secret; they carry the whole security of
  short-code pairing.
- **My identity** shows the onion address and safety number.

`04.png` has the QR and the code pixelated-then-blurred, which is irreversible — and checked: OpenCV's
QR detector decodes the original capture and finds nothing in the redacted one. Prefer a
visible redaction over substituting plausible-looking fake data, so nobody mistakes a screenshot
for a working invite. Re-check any new screenshot for: onion addresses, invite QRs, short codes,
safety numbers, contact names, message text, and personal notification icons in the status bar.

Capture with throwaway identities where possible:

```sh
adb -s <ip:port> shell settings put system accelerometer_rotation 0
adb -s <ip:port> shell settings put system user_rotation 0   # portrait
adb -s <ip:port> exec-out screencap -p > shot.png
```
