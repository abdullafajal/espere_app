# Espere — Flutter Mobile App

Modern Expense & Income Tracker — Flutter frontend for the Django backend.

---

## Prerequisites

| Tool | Version | Install Guide |
|------|---------|---------------|
| Flutter SDK | 3.7+ | [flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install) |
| Dart SDK | 3.7+ | Bundled with Flutter |
| Android Studio / Xcode | Latest | For emulator/simulator |
| Django backend | Running | See [Backend Setup](#2-start-django-backend) |

---

## Installation

### 1. Install Flutter SDK

**macOS (Homebrew):**
```bash
brew install flutter
```

**Manual Install:**
```bash
# Download from https://docs.flutter.dev/get-started/install/macos
# Extract and add to PATH
export PATH="$HOME/development/flutter/bin:$PATH"
```

**Verify installation:**
```bash
flutter doctor
```
> Fix any issues `flutter doctor` reports (Android licenses, Xcode, etc.)

---

### 2. Start Django Backend

The Flutter app needs the Django API server running:

```bash
cd ../montra
.venv/bin/python manage.py runserver 0.0.0.0:8000
```

> The API is available at `http://localhost:8000/api/`

---

### 3. Install Flutter Dependencies

```bash
cd espere_app
flutter pub get
```

---

### 4. Configure API Base URL

Edit `lib/services/auth_service.dart` and update the default base URL:

| Platform | Base URL |
|----------|----------|
| Android Emulator | `http://10.0.2.2:8000` (default) |
| iOS Simulator | `http://localhost:8000` |
| Physical Device (same Wi-Fi) | `http://<YOUR_PC_IP>:8000` |
| Production | `https://espere.in` |

```dart
// In lib/services/auth_service.dart, line ~42
return prefs.getString(_baseUrlKey) ?? 'http://10.0.2.2:8000';
```

---

## Running the App

### Android Emulator
```bash
# List available emulators
flutter emulators

# Launch an emulator
flutter emulators --launch <emulator_id>

# Run the app
flutter run
```

#### Starting the emulator from the terminal

The window that shows up as **`qemu-system-aarch64`** (in Activity Monitor / Dock) is the
Android Emulator — it runs on QEMU under the hood. You can start it directly, without
Android Studio:

```bash
# Emulator binary from the Android SDK (default SDK location on macOS)
EMU=~/Library/Android/sdk/emulator/emulator

# 1. See which virtual devices (AVDs) exist
$EMU -list-avds
# e.g. Pixel_10_Pro

# 2. Start one (keeps running in the background; window opens in a few seconds)
$EMU -avd Pixel_10_Pro -no-snapshot-save -no-audio &

# 3. Wait until it has booted
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done

# 4. Install and launch the app
flutter run                     # debug build with hot reload
# or install an APK you already built:
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# Stop the emulator
adb emu kill
```

| Flag | What it does |
|------|--------------|
| `-no-snapshot-save` | Don't save state on exit (next start is a clean boot of the last saved snapshot) |
| `-no-audio` | No audio device (avoids macOS audio warnings) |
| `-wipe-data` | Factory-reset the emulator (use if it is broken or out of storage) |

> No AVD yet? Create one in Android Studio → **Device Manager** → **Create device**
> (any Pixel with a recent system image), then use its name with `-avd`.

#### Testing the home-screen widget on the emulator

1. Long-press an empty spot on the home screen → **Widgets** → search **Espere** →
   tap **Quick Add Expense** → **Add**.
2. Long-press the widget and drag its handles to try other sizes (2x1, 4x1, 2x2, 4x2, 4x3);
   the widget picks the layout that fits.
3. Tap the widget / **+** to open the Quick Add popup.

> Note: data you add from the emulator goes to the real backend if you are logged in to a
> real account.

**Emulator says `INSTALL_FAILED_INSUFFICIENT_STORAGE`?** A debug APK with every ABI is
~190 MB. Build only for the emulator's CPU, or wipe the emulator:

```bash
flutter build apk --debug --target-platform android-arm64   # Apple Silicon emulator
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### iOS Simulator (macOS only)
```bash
# Open simulator
open -a Simulator

# Run the app
flutter run
```

### Physical Device
```bash
# Connect device via USB, enable USB debugging (Android) or trust (iOS)
flutter devices        # Verify device is detected
flutter run -d <device_id>
```

### Chrome (Web - for quick testing)
```bash
flutter run -d chrome
```

---

## Build for Release

### Android: with or without "Auto-track payments"

**Auto-track payments** adds expenses automatically from UPI and bank payment notifications. It
uses a notification listener, and Google Play Protect **blocks installing** any app that declares
one when the app is downloaded from a browser, WhatsApp or a file manager ("App blocked to protect
your device"). So there are separate builds:

| Build | Auto-track | Who it's for | How to install |
|---|---|---|---|
| **Website APK** | ❌ No | Users who download from espere.in | Normal download and install |
| **Auto-track APK** | ✅ Yes | Your own phone, testers | USB / Wi-Fi with `adb install` (not from a browser) |
| **Play Store (AAB)** | ✅ Yes | Play Store users, later | Through Google Play |
| Debug / `flutter run` | ✅ Yes | Development | `flutter run` |

One Gradle switch controls this: `-P espere.autoTrack=false` removes the listener from the
release manifest (`android/app/src/sideload/AndroidManifest.xml`). Without the switch the feature
is included. The app hides the Auto-track option on its own when the listener is missing.

#### 1. Website APK (no auto-track)

> **Without a laptop:** merging to `main` builds and publishes the website APK automatically
> (GitHub Actions → espere-pages). Signing, test APKs and troubleshooting:
> [docs/APK_RELEASE.md](docs/APK_RELEASE.md).

Run from the repository root (the folder that contains `espere_app/` and `espere-pages/`):

```bash
./build_and_copy_apk.sh
# Runs: flutter build apk --release -P espere.autoTrack=false
# and copies the APK to ../espere-pages/espere.apk.
# Then commit and push in espere-pages to publish it.
```

Before publishing, check that the APK has **no** notification listener. This must print `0`:

```bash
AAPT=$(ls -d ~/Library/Android/sdk/build-tools/*/ | sort -V | tail -1)aapt2
$AAPT dump xmltree --file AndroidManifest.xml ../espere-pages/espere.apk | grep -c BIND_NOTIFICATION_LISTENER_SERVICE
```

> Never put an auto-track APK on the website. Play Protect will block it for every user.

#### 2. Auto-track APK for your own phone

```bash
cd espere_app
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (includes auto-track)
```

Install it with `adb`. Installs from a browser are blocked; `adb` installs are not.

1. On the phone: **Settings → About phone → Build number**, tap it 7 times, then
   **Developer options → USB debugging** on.
2. Connect the phone by USB and tap **Allow** on the "Allow USB debugging?" prompt.
3. On the Mac:
   ```bash
   adb devices                     # note your phone's serial, e.g. RZGL80VYKMK
   adb -s <serial> install -r build/app/outputs/flutter-apk/app-release.apk
   ```
   `-s <serial>` picks the phone even when an emulator is also running. `install -r` keeps
   the login and data. (The website and auto-track APKs are signed with the same key.)

Then switch it on in the app:

1. **Espere → Profile → Auto-track payments** → read the disclosure → **Allow**.
2. Android opens *Notification read, reply & control*. Turn on **Espere**, then come back.
   The Auto-track screen must say **On**.
3. On that Android screen, keep **Conversations** ticked. Bank SMS arrive as conversations;
   without it they are not seen.
4. If the switch is greyed out (Samsung / Android 13+): **Settings → Apps → Espere → ⋮ →
   Allow restricted settings**, then repeat step 2.

> Don't install the website APK over the auto-track one. The Auto-track option disappears
> (data stays). Reinstall the auto-track APK to get it back.

#### 3. Play Store (App Bundle, includes auto-track)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

Policy and Data Safety notes for this feature are in [PLAY_STORE_NOTES.md](PLAY_STORE_NOTES.md).

#### Auto-track: how it behaves

- **Added automatically:** payments with an amount, a direction (paid / received) and a
  reference number (UPI Ref / UTR / Txn ID). The note is just the payee, for example "Swiggy".
  The category is picked from the payee and from your past choices for that payee.
- **Review list** (Profile → Auto-track payments → Review list): payments without a reference
  (most card SMS), NACH / SIP / EMI / insurance debits, ATM withdrawals, refunds. One tap to
  add or discard.
- **Never added:** OTPs, payment or collect requests, reminders, "will be debited",
  mandate / AutoPay setup or cancellation, failed or pending payments, offers, credit-card
  bill payments, self-transfers, wallet / UPI Lite top-ups, interest, statements, foreign
  currency, personal SMS and chats.
- **No duplicates:** the same payment reported by Google Pay, the bank app and the bank SMS is
  added once. A reversed payment removes its entry. A deleted entry never comes back.
- **When entries appear:** captured notifications wait (encrypted) on the phone and are added
  as soon as Espere is open. If the app is closed, they are added the next time it opens.
- **Only new notifications** after switching it on are read. Older SMS are never picked up.

Full details: [AUTO_TRACK_RESEARCH.md](AUTO_TRACK_RESEARCH.md).

#### Auto-track: nothing was added?

1. Open **Profile → Auto-track payments**. It must say **On**, not "Notification access needed".
2. Check that **Conversations** is ticked on Android's notification-access screen for Espere.
3. Open Espere. Entries are added when the app runs.
4. Check whether the payment belongs in the "never added" list above. Card spends and SMS
   without a reference go to the **Review list** instead.
5. Still missing? Copy the SMS / notification text (change the amount) and add it as a case
   in `test/notification_parser_test.dart`. That is how new bank wordings are supported.

To inspect what happened on a phone, install a **debug** build. Only debug builds allow
`run-as`:

```bash
flutter build apk --debug --target-platform android-arm64
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
# Native listener switch (must be true when Auto-track is On):
adb -s <serial> exec-out run-as com.example.espere_app cat shared_prefs/auto_capture_config.xml
# Pending captured events (empty after the app has processed them):
adb -s <serial> exec-out run-as com.example.espere_app ls no_backup/auto_capture/
```

Afterwards, reinstall the release auto-track APK (section 2).

### iOS (macOS only)
```bash
flutter build ios --release
# Then open ios/Runner.xcworkspace in Xcode to archive
```

---

## Project Structure

```
espere_app/
├── pubspec.yaml                 # Dependencies & config
├── lib/
│   ├── main.dart                # App entry point + routes
│   ├── theme/
│   │   └── app_theme.dart       # Colors, radii, shadows (matches Django CSS)
│   ├── models/
│   │   ├── user.dart            # User + Profile model
│   │   ├── category.dart        # Category model
│   │   ├── transaction.dart     # Transaction model
│   │   └── dashboard.dart       # Dashboard aggregated data
│   ├── services/
│   │   ├── auth_service.dart    # Token storage (SharedPreferences)
│   │   └── api_service.dart     # All HTTP API calls
│   ├── screens/
│   │   ├── splash_screen.dart   # Animated splash
│   │   ├── login_screen.dart    # Login form
│   │   ├── register_screen.dart # Registration form
│   │   ├── home_screen.dart     # Tab shell + bottom nav
│   │   ├── dashboard_screen.dart       # Dashboard with charts
│   │   ├── transaction_list_screen.dart # Transaction list + filters
│   │   ├── transaction_form_screen.dart # Add/Edit transaction
│   │   └── profile_screen.dart  # User profile + settings
│   └── widgets/
│       ├── bottom_nav_bar.dart  # Floating dark pill nav
│       ├── balance_card.dart    # Dark balance card
│       ├── summary_card.dart    # Income/Expense/Savings card
│       ├── transaction_tile.dart # Transaction row item
│       └── espere_input.dart    # Styled text input
```

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `http` | ^1.2.0 | HTTP requests to Django API |
| `shared_preferences` | ^2.3.0 | Local token storage |
| `fl_chart` | ^0.70.0 | Charts (bar, line) on dashboard |
| `google_fonts` | ^6.2.0 | Inter font family |
| `intl` | ^0.19.0 | Date formatting |

---

## API Endpoints Used

| Method | Endpoint | Screen |
|--------|----------|--------|
| `POST` | `/api/auth/login/` | Login |
| `POST` | `/api/auth/register/` | Register |
| `GET/PUT` | `/api/auth/profile/` | Profile |
| `GET` | `/api/dashboard/` | Dashboard |
| `GET/POST` | `/api/transactions/` | Transaction List / Form |
| `GET/PUT/DELETE` | `/api/transactions/<id>/` | Transaction Detail |
| `GET` | `/api/categories/` | Transaction Form (dropdown) |

---

## Troubleshooting

### `Connection refused` error
- Ensure Django server is running on `0.0.0.0:8000` (not just `127.0.0.1`)
- Check the base URL in `auth_service.dart` matches your setup
- For physical device: use your computer's local IP, not `localhost`

### `flutter pub get` fails
```bash
flutter clean
flutter pub cache repair
flutter pub get
```

### Android build issues
```bash
flutter doctor --android-licenses   # Accept all licenses
```

### iOS build issues
```bash
cd ios && pod install && cd ..
```
