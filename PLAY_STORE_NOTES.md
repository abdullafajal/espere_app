# Play Store notes: Auto-track payments

Release checklist and policy notes for the **Auto-track payments** feature: on-device capture of
UPI and bank payment notifications.

## How the feature stays within Play policy

| Requirement | How Espere meets it |
|---|---|
| No SMS permissions | No `READ_SMS` / `RECEIVE_SMS`. Bank SMS are seen only as **notifications** from the default SMS app. |
| No Accessibility / `QUERY_ALL_PACKAGES` / foreground service | None declared. Uses only `NotificationListenerService` (`autocapture/PaymentNotificationListener.kt`). |
| No new dangerous permissions | `POST_NOTIFICATIONS` was already present (via `firebase_messaging`) and is already requested by the app. Nothing new was added. |
| Off by default | `auto_track_enabled` = false. The listener ignores everything until the user opts in. |
| Prominent Disclosure before the permission | `lib/widgets/auto_track_disclosure.dart` is shown first. Android's Notification-access screen opens **only** after the user taps **Allow**. |
| Minimal data | Allow-listed packages only. Other apps are dropped before their content is read. For SMS apps, only bank/UPI sender IDs (e.g. `VM-HDFCBK`) are read. WhatsApp chat messages are dropped. Ongoing, group-summary and progress notifications are ignored. |
| On-device processing | Parsing happens in `lib/services/notification_parser.dart` on the phone. Raw text is never uploaded, never logged, and never stored outside the short-lived encrypted queue. |
| What is synced | Only the parsed transaction (amount, type, category, date, payee as the note, payment method), through the existing SyncService queue. Auto entries look exactly like manual ones: no badge, and the note is just the payee name (never the reference number). |
| Encryption at rest | The pending-event queue is AES-256-GCM encrypted with an Android Keystore key, kept in `noBackupFilesDir`, deleted as soon as Dart acknowledges each event, and auto-deleted after 24 h. |
| Backups | `espere_auto.db` (fingerprints, review list, payee categories) and `auto_capture_config.xml` are excluded in `res/xml/data_extraction_rules.xml` (Android 12+) and `res/xml/backup_rules.xml` (Android 11 and older). |
| User control | Profile → Auto-track payments: per-app toggles, "Expenses only" / "Expenses + Income", and **Turn off & delete local data**, which wipes the queue, fingerprints, the Review list and remembered categories. Logout does the same. |

## Distribution: Play Store vs website APK

Google Play Protect's **enhanced fraud protection** (India) **blocks installing** apps that
declare a notification listener (or SMS / Accessibility permissions) when they come from a
browser, messaging app or file manager. It shows "App blocked to protect your device".
Installs from Google Play are not affected.

- **Play Store build** (default, includes Auto-track):
  `flutter build appbundle --release`
- **Website APK** (`build_and_copy_apk.sh`, no Auto-track):
  `flutter build apk --release -P espere.autoTrack=false`
  This removes the listener from the release manifest (`android/app/src/sideload/AndroidManifest.xml`),
  and the app hides the Auto-track option because the listener is missing.

Check any website APK before publishing. This must print `0`:

```bash
aapt2 dump xmltree --file AndroidManifest.xml espere.apk | grep -c BIND_NOTIFICATION_LISTENER_SERVICE
```

## Release checklist

### 1. Data Safety form (Play Console → App content → Data safety)

- **Financial info → Purchase history**
  - Collected: **Yes**. Shared: **No**.
  - Processed ephemerally: No (it is stored in the user's account).
  - Required or optional: **Optional** (the feature is opt-in).
  - Purpose: **App functionality**.
  - Encrypted in transit: **Yes** (HTTPS).
  - Users can request deletion: **Yes**.
- **Messages / notification content**
  - **Not collected.** Notification content is processed only on the device and never leaves it.
    Per Play's definitions, data processed only on the device is not "collected", so do not
    declare SMS or other in-app messages as collected.
- Re-check the existing declarations (account info, etc.). They are unchanged by this feature.

### 2. Privacy policy

Add this section to the privacy policy on espere.in (keep it matching the in-app disclosure):

> **Notification access (Auto-track payments)**
> If you turn on Auto-track payments, Espere reads payment notifications from UPI and bank apps
> on your device to add your expenses automatically. Notification content is processed only on
> your phone and is never uploaded. Only the amount, payee and category of detected transactions
> are saved to your account. Espere only looks at notifications from supported payment and bank
> apps. For SMS, it only reads messages from bank and UPI sender IDs; personal messages and chats
> are never read. You can turn this off at any time in Profile → Auto-track payments. Turning it
> off deletes all locally stored data used by this feature. Transactions already added stay in
> your account until you delete them.

### 3. Store listing

- Add one line to the description, for example: *"Auto-track payments: Espere can add your UPI
  and bank payments automatically from their notifications, processed privately on your phone."*
- Add a screenshot of the Prominent Disclosure dialog and one of the Auto-track settings screen.

### 4. Demo video (keep it ready in case review asks for it)

Record on a real device (30–60 s):

1. Profile → **Auto-track payments** → the disclosure appears.
2. Tap **Not now**: nothing opens.
3. Turn it on again → **Allow** → Android's Notification-access screen → enable Espere → back.
4. Settings screen shows **On**. Make a small UPI payment (or receive a bank SMS) → the entry
   appears in Transactions like any other entry.
5. **Turn off & delete local data**.

## How it works (for reviewers and maintainers)

```
NotificationListenerService (Kotlin)
  allow-list → SMS sender / WhatsApp filters → amount pre-check
  → encrypted queue (≤24 h) ──EventChannel "new"──▶ AutoExpenseService.drain() (Dart)
      NotificationParser → AutoDedupEngine (sqflite, SHA-256 fingerprints, single async lock)
        HIGH (amount + type + ref, or 2 sources agree) → cache + SyncService.queueOperation
        LOW → Review list (user confirms or discards with one tap)
      → ackEvents (raw event deleted)
```

Deduplication rules (`lib/services/auto_dedup_engine.dart`):

- (a) A re-post (same key and same text hash) is skipped.
- (b) A reference seen before is skipped, whichever app it came from.
- (c) The same amount, type and last-4 within ±3 min is merged into the existing entry.
- (d) A manual entry with the same amount and type within ±10 min is linked to that entry
  instead of creating a new one.
- (e) Payments the user deleted or discarded are never recreated.
- (f) A refund or reversal with the same reference removes the auto entry, so a payment that
  was debited and then reversed leaves nothing behind.
- Inserts are two-phase (`adding` → cache and queue → `added`), and `recover()` finishes
  interrupted inserts exactly once.
- Fingerprints older than 60 days are pruned.

## Known limits

- See `AUTO_TRACK_RESEARCH.md` for which notification types are added, sent to Review or
  rejected, and why.

- **Allow-list.** Bank app package names live in
  `android/app/src/main/kotlin/com/example/espere_app/autocapture/AutoCaptureSources.kt`.
  Verify them against the current Play listings before release, and extend the list as needed.
- **Message wording varies by bank.** Notifications whose wording the parser doesn't recognise
  are dropped. Payments without a reference number (for example many card SMS) go to the Review
  list instead of being added.
- **Notification access types.** The listener asks for *Conversations*, *Notifications* and
  *Silent*, because SMS apps post bank messages as conversations. If a user unticks
  *Conversations* in Android's Notification-access screen, bank SMS will not be seen.
