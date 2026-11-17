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

### Android APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

To build the release APK **and** publish it to the website repo in one step, run the
script from the repository root (the folder that contains `espere_app/` and `espere-pages/`):

```bash
./build_and_copy_apk.sh
# Builds the release APK and copies it to ../espere-pages/espere.apk
# Then commit and push in espere-pages to publish it.
```

### Android App Bundle (Play Store)
```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

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
