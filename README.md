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
