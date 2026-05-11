# Guide to Building the Espere Android APK

This document provides instructions on how to generate a standalone Android Package (APK) for the Espere app, which you can share and install on any Android device.

## 1. Preparation (Very Important)
Before building the APK, you must ensure the app is pointing to the correct backend server.

1.  Open `lib/services/auth_service.dart`.
2.  If you are sharing the app with others, ensure the `getBaseUrl` is pointing to your **Production URL** (e.g., `https://your-domain.com`).
3.  If you are just testing locally on your own phone, use your **Local IP** (e.g., `http://192.168.1.XX:8000`).

## 2. Generate the APK
Open your terminal in the `espere_app` directory and run the following command:

```bash
flutter build apk --release
```

### What this does:
- Compiles the code into high-performance machine code.
- Strips out debugging information to make the file smaller.
- Optimizes the app for speed and battery life.

## 3. Locate the File
Once the build is complete, your APK will be waiting for you here:

**`build/app/outputs/flutter-apk/app-release.apk`**

## 4. How to Install on a Phone
1.  **Transfer the file**: Send the `app-release.apk` to your phone via USB, Google Drive, WhatsApp, or Email.
2.  **Allow Unknown Sources**: On the phone, if you haven't installed an APK before, you may need to:
    -   Go to **Settings > Security**.
    -   Enable **Install from Unknown Sources**.
3.  **Open & Install**: Tap the file on your phone and select **Install**.

## 5. Troubleshooting
- **Build Fails?**: Run `flutter clean` then try the build command again.
- **App won't connect?**: Ensure your Django backend is running and the URL in `auth_service.dart` is exactly correct (including `http://` or `https://`).

---

> [!TIP]
> To make a smaller file that includes only the necessary code for the specific phone's processor, you can run:
> `flutter build apk --split-per-abi`
> This will generate 3 separate APKs (v7, v8, and x86_64). For general sharing, the standard `flutter build apk --release` is easiest as it works on all phones.
