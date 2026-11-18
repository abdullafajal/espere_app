# Android APK: test builds, website release, signing

How Espere's Android APKs are built and published without a laptop, and what to do when
something goes wrong. Everything here works from a phone browser on github.com.

## At a glance

| What | Where it comes from | Who installs it |
|---|---|---|
| **Website APK** `espere.apk` | Workflow **Publish website APK** (`.github/workflows/publish-apk.yml`) commits it to [`espere-pages`](https://github.com/abdullafajal/espere-pages); GitHub Pages serves it at https://espere.in/espere.apk | Everyone, including you |
| **Test APKs** | Workflow **Build test APK** (`.github/workflows/build-apk.yml`), on every push to a `ccr-*` branch. Download from the run's **Artifacts** | Only for trying a change before it reaches `main` |

The website APK:

- contains every CPU type (arm64, armv7, x86_64), so it installs on any phone;
- has **no auto-track** (notification listener): Google Play Protect blocks browser installs of
  apps that have one (see [README](../README.md#android-with-or-without-auto-track-payments));
- has **Share → Espere** and **Scan receipt** (see below);
- is signed with the shared release key (see [Signing](#signing-key)).

## One-time setup: let the workflow push to espere-pages

The workflow runs in `espere_app` and needs permission to write to `espere-pages`. Create a
token once (works from a phone):

1. github.com → profile photo → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. Name: `espere-pages publish`. Expiration: up to 1 year (put a reminder in your calendar).
3. **Repository access → Only select repositories → `abdullafajal/espere-pages`**.
4. **Permissions → Repository permissions → Contents: Read and write**. Nothing else.
5. **Generate token** and copy it.
6. Open https://github.com/abdullafajal/espere_app/settings/environments → environment
   **`PAGES_TOKEN`** → **Environment secrets → Add environment secret**. Name: `PAGES_TOKEN`.
   Value: the token. (The workflow uses `environment: PAGES_TOKEN`; a repository secret with
   the same name works too.)

When the token expires, the workflow fails with a 403 on "Commit to espere-pages". Create a
new token the same way and update the `PAGES_TOKEN` secret.

This token is the **only** thing that expires. The signing key is valid until 2054 and its
fingerprints in Firebase and `assetlinks.json` never need to change, unless the key itself is
replaced.

## Releasing a new website APK

1. **Bump the version** in `pubspec.yaml`, e.g. `version: 1.0.3+5` → `1.0.4+6`. The number
   after `+` (versionCode) must always go up, or phones refuse the update.
2. **Merge to `main`**. Any push to `main` that changes `lib/`, `android/`, `assets/` or
   `pubspec.*` starts **Publish website APK** by itself.
   To publish without a code change: **Actions → Publish website APK → Run workflow**.
3. Wait about 10 minutes. The run:
   - runs `flutter test`,
   - builds `flutter build apk --release -P espere.autoTrack=false`,
   - checks the APK has no notification listener (stops if it has one),
   - commits it to `espere-pages` as `espere.apk` ("Update APK to 1.0.4+6").
4. `espere-pages` deploys itself (**Deploy static content to Pages**, under a minute). Then
   https://espere.in/espere.apk is the new version.

On a phone, installing the new APK over the old one keeps the login and data.

## Trying a change first (test APK)

Push to a `ccr-*` branch. **Build test APK** runs and leaves two artifacts on the run page
(**Actions → the run → Artifacts**, valid 14 days, needs a GitHub login):

- `espere-apk-arm64`: **with auto-track**, for testing that feature;
- `espere-apk-arm64-no-autotrack`: same as the website APK, arm64 phones only.

Both are zip files: open the zip in the Files app and install the `.apk` inside.
Test APKs are signed with the same key, so they install over the website APK and back.

If Play Protect blocks the auto-track one, use the no-autotrack artifact.
To switch auto-track on: **Profile → Auto-track payments → Allow**. If Android says
"Restricted setting": **Settings → Apps → Espere → ⋮ → Allow restricted settings**, then try
again.

## Signing key

All release APKs (GitHub Actions and laptop builds) are signed with
`android/app/ci-test.keystore` (set in `android/app/build.gradle.kts`):

| | |
|---|---|
| Alias / passwords | `ci-test` / `espere-ci-test` |
| SHA-1 | `CB:F4:D4:F2:AD:ED:DF:FE:EC:58:16:89:3D:80:12:A9:B9:22:F3:13` |
| SHA-256 | `20:FE:40:7C:25:8D:B2:B8:E8:0D:8C:33:DB:68:38:6E:43:D1:6C:01:71:55:4C:08:38:99:C7:4F:EA:B8:10:EB` |

The fingerprints are registered in two places. Both must stay, or things break:

- **Google Cloud** (project `espere-6e6ac`) → APIs & Services → Credentials → an **Android
  OAuth client** with package `com.example.espere_app` and this SHA-1. Without it,
  **Google Sign-In** fails with "Google Sign-In canceled". Adding the fingerprint in Firebase
  alone was not enough. The app does not need this client's ID or JSON file: Google matches it
  by package name + SHA-1. (The fingerprints are also in Firebase → Project settings → Android
  app.)
- **`espere-pages/.well-known/assetlinks.json`** (`sha256_cert_fingerprints`). Without it,
  espere.in links (invites, verify email) open in the browser instead of the app.
  The old laptop key (`28:9B:58:…`) is kept there too.

History: until version 1.0.2 the website APK was signed with the laptop's debug key. Phones
with that version must **uninstall once** before installing 1.0.3 or later ("App not
installed" otherwise). Data is on the server and comes back after login.

The key is stored in the repository, so anyone with access to the repository can sign an APK
with it. Fine for the website APK; **never use it as the Play Store upload key**.

To sign a laptop build with the local debug key instead, add `-P espere.ciSigning=false`
(that APK then can't be installed over the website one, and Google Sign-In will not work).

## Receipts: Share → Espere and Scan receipt

Some payments never produce a notification or SMS (Amazon Pay shows only an in-app "Thank
You" screen; many banks send no SMS for small UPI payments), so auto-track cannot see them.
For those:

- **Share**: on the app's success screen tap Share → **Espere**. Text or image both work.
- **Scan receipt**: Add Transaction → scan icon (top left) → pick a screenshot.

The Add Transaction form opens with amount, payee (notes), date/time, UPI and a category
filled in. Nothing is saved until the user taps Save.

| File | What it does |
|---|---|
| `android/.../receipt/ReceiptBridge.kt` | Receives the share, copies a shared image to the cache, on-device text recognition (ML Kit via Play services) with line boxes, measures how the phone's OCR reads "₹" |
| `lib/services/receipt_service.dart` | Turns a share into the pre-filled form, "Already added?" check |
| `lib/services/receipt_parser.dart` | Reads amount / payee / reference / date: scores every candidate amount, uses the screenshot layout (biggest font, rows, no status bar) and the phone's measured rupee-sign reading |
| `test/receipt_parser_test.dart`, `test/receipt_scan_test.dart` | Parser tests: share texts, and real screenshot layouts under every rupee-sign reading |

If a receipt fills the wrong amount or none: in the form tap **See text read from receipt →
Copy**, then add that text as a new test in `test/receipt_parser_test.dart` and fix
`receipt_parser.dart` until it passes.

The text-recognition model comes from Google Play services. The first scan needs internet.

How the parser works, the OCR problems it handles and its known limits:
[RECEIPT_SCAN_RESEARCH.md](../RECEIPT_SCAN_RESEARCH.md).

## Troubleshooting

| Problem | Cause and fix |
|---|---|
| Workflow fails: "Gradle version (8.14.0) is lower than Flutter's minimum…" | The workflow is not on Flutter **3.47.9**. Newer Flutter needs Gradle 9. Keep `flutter-version: 3.47.9` until `android/` is upgraded (Gradle 9, AGP and Kotlin to match) |
| Workflow fails: "Secret PAGES_TOKEN is missing" or 403 when pushing | Do the [one-time setup](#one-time-setup-let-the-workflow-push-to-espere-pages) or renew the token |
| Workflow fails at "no notification listener" | The build was made without `-P espere.autoTrack=false`. Never publish it |
| Phone: "App not installed" | An Espere signed with another key is installed (laptop debug build or ≤ 1.0.2). Uninstall it, then install |
| Phone: "App blocked to protect your device" | Play Protect: the APK has auto-track. Use the website APK or the no-autotrack test artifact |
| "Google Sign-In canceled" | No Android OAuth client in Google Cloud for the APK's SHA-1. See the [Signing key](#signing-key) section. After adding it, wait 5–10 minutes |
| Espere is missing from the share sheet | Old build installed. **Settings → Apps → Espere** must show version 1.0.3 or later |
