# Receipt scan: research and design

How Espere reads a payment receipt that the user shares to the app or scans from a
screenshot (Amazon Pay, Google Pay, PhonePe, Paytm, BHIM, CRED, WhatsApp, bank apps), why it
works the way it does, and what is still out of reach.

The form always opens for a check before anything is saved, so the rule is: **a field the
parser is not sure about stays empty**. A wrong amount is worse than an empty one.

## 1. What goes wrong when reading a screenshot

Findings from real screenshots (Amazon Pay, Google Pay, PhonePe; 1080x2340) and on-device
results reported from a phone:

| Problem | Example | Why |
|---|---|---|
| **The rupee sign** | "₹60" read as `760` (ML Kit on the test phone), `60` (RapidOCR), sometimes `Z60` / `%60` | The Latin OCR models have no "₹" character. Each engine and font maps it to something else. A wrong "7" turns ₹60 into ₹760. |
| Status bar text | battery `60`, `59`, clock `1:30`, speed `1.93 K/s` | Part of the screenshot. On the Google Pay screen the battery (60) and the amount (140) are both plain numbers. |
| Letters inside words | `14 0ct 2026`, `UP transaction ID`, `PhonePe Transaction iD` | O/0, I/l confusion. |
| Reading order | PhonePe "Flipkart Payments" and "₹1,232" sit on one row; OCR returns them as two lines, sometimes amount first | ML Kit returns blocks, not rows. |
| Avatar initials | `FP`, `LC`, `T` next to the name | The round avatar is text too. |
| No sentence at all | PhonePe: only "Paid to / Flipkart Payments ₹1,232 / Debited from XXXXXX9025 ₹1,232" | Nothing like "Payment of ₹X" to anchor on. |
| Promotions | "You've won ₹0.6 cashback", "payments up to ₹10,000", "Save 19%" | Real amounts that are not the payment. |
| Time before date | "08:18 pm on 14 Oct 2026" (PhonePe) | Different order per app. |

Other projects hit the same problems: an OCR engine's English model has no ₹ (ProofCheck),
other OCR tools read ₹ as 7, 2, 3 or % (Tesseract and Blue Prism users), and taking "the
single money amount in the largest text" is a known way to find the payment on a screenshot
(unmoney).

## 2. Design

### 2.1 Native side (`android/.../receipt/ReceiptBridge.kt`)

- ML Kit text recognition (Latin, via Play services) returns every **line with its box**
  (left, top, right, bottom) and the image size, not just text.
- **Rupee calibration.** ML Kit's behaviour with "₹" is not documented and differs per model
  version, so the app measures it. The first scan draws `₹60`, `₹140`, `₹1,232`, `₹85` on a
  white bitmap (Android's own font, bold / regular / medium), runs OCR on it and records
  what came back:
  - `keep`: the ₹ is read;
  - `drop`: ₹ left out (`60`);
  - a character, e.g. `7` (`760`) or `Z` (`Z60`);
  - nothing (unclear result).
  The result is cached for 14 days (Play services updates the model now and then).

### 2.2 Dart side (`lib/services/receipt_parser.dart`)

`ReceiptParser.parseScan(OcrScan)`:

1. Drops the status bar (lines in the top 3.5% of the image).
2. Rebuilds **rows**: lines whose vertical extents overlap by at least half are one row,
   left to right ("Flipkart Payments ₹1,232", "XXXXXX9025 ₹1,232").
3. Finds the **hero amount**: an amount-only line at least 1.35x the median line height
   (Google Pay ₹140 is 141 px against ~40 px text).
4. Applies the rupee reading. If the screenshot contradicts the calibration (calibrated
   `keep` but no ₹ anywhere; or calibrated `7` but a ₹ was read), the app font behaves
   differently, so it falls back to "unknown" (7 and 2 are treated as possible ₹).
5. Normalises OCR slips: `0ct` → `Oct`, `1,2O0` → `1,200`, `UP transaction` → `UPI transaction`.

Then every candidate amount gets points:

| Sign | Points |
|---|---|
| In a payment sentence: "Payment of ₹60 to", "Paid ₹250", "Payment of 140 completed" | 4 |
| Printed in the biggest font (hero) | 4 |
| Written with ₹ / Rs / INR | 3 per line |
| After an "Amount" / "Total amount" label | 3 |
| Alone at the end of a line | 1, +1 with a separator or symbol |
| Seen on two or more lines | +2 |

Never counted: promo lines (cashback, offers, "up to", "enjoy", "activate"), balances and
limits, ids / UTR / reference / account / IFSC lines, clock times, a year after a month,
links, phone numbers.

The winner must have at least 3 points and lead by at least 2; otherwise the amount stays
empty.

Payee: "Payment of ₹X to NAME", "Paid to NAME", "Paid Successfully to", "To NAME", a lone
"Paid to" / "Beneficiary Name" label with the name on a following line (amount lines and
avatar initials skipped), "Beneficiary Name: NAME". Money received: "From NAME" (not
"From: <your bank account>"), "Received from".

Shared text (no screenshot) goes through `ReceiptParser.parse` with the same rules except
layout. When an app shares both text and an image, the text wins and the image fills the gaps.

## 3. Tests

`test/receipt_scan_test.dart`:

- The **real line boxes** of the Amazon Pay, Google Pay and PhonePe screenshots, each run with
  every rupee reading (`₹60`, `60`, `760`, `260`, `Z60`), with and without calibration:
  30 cases, amount, payee, date/time and reference all correct.
- Amounts that begin with 7 or 2 (₹250, ₹750) under every calibrated reading.
- Layouts written for Espere for Paytm, BHIM, CRED, WhatsApp Pay, a bank app (with an
  "Available Balance" line), money received on Google Pay and PhonePe, a failed payment, two
  competing big amounts (must stay empty), and a calibration contradicted by the app's font.

`test/receipt_parser_test.dart`: share texts (with links and helpline numbers), OCR text
without layout, Indian digit grouping, dates, failed / pending.

Run: `flutter test test/receipt_parser_test.dart test/receipt_scan_test.dart`.

## 4. Known limits (why it is not "100%")

- **Calibration missing and ₹ dropped and amount starts with 7 or 2.** If the probe could not
  tell how ₹ is read (very rare) and the app's OCR leaves ₹ out, "₹750" is read as `750`
  and taken as ₹50. With calibration (the normal case) this is handled.
- **Layouts never seen.** A new app version can move text around. Amounts still score through
  ₹ / hero / repetition; the payee is the field most likely to be missed.
- **Bad images.** Cropped screenshots without the amount, photos of a screen, very small text
  (ML Kit wants about 16x16 px per character), heavy dark-mode gradients.
- **Bills with many amounts** (restaurant bills, shopping carts): built for payment success
  screens, not itemised bills. Several competing amounts leave the field empty.

## 5. When a receipt is read wrong

1. In the form, tap **See text read from receipt → Copy**.
2. Add a test in `test/receipt_scan_test.dart` (layout) or `test/receipt_parser_test.dart`
   (text only) with that text and the right values. Use own names and numbers.
3. Fix `lib/services/receipt_parser.dart` until all tests pass.

## 6. Sources

- ML Kit Text Recognition v2 (scripts, Devanagari add-on, 16x16 px per character):
  https://developers.google.com/ml-kit/vision/text-recognition/v2
- ML Kit `Text.Symbol` (confidence and symbols not available in the unbundled library):
  https://developers.google.com/android/reference/com/google/mlkit/vision/text/Text.Symbol
- ₹ misread as 7 / 2 / 3 / % by OCR tools:
  https://www.mail-archive.com/tesseract-ocr@googlegroups.com/msg23167.html ,
  https://community.blueprism.com/t5/Product-Forum/How-to-read-amount-that-is-preceded-by-Indian-Rupee-character/td-p/96635
- English OCR model has no ₹; checking UPI screenshots (ProofCheck):
  https://github.com/Surge77/proofcheck
- Largest-text amount on payment screenshots (unmoney):
  https://github.com/bhatvikrant/unmoney/pull/118
- UPI screenshot extraction with PaddleOCR + regex:
  https://github.com/gautamraj8044/UPI-Transaction-Extractor
- RapidOCR, used offline to get line boxes of the test screenshots:
  https://github.com/RapidAI/RapidOCR
