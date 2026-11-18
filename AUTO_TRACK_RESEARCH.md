# Auto-track payments: notification research

What payment notifications from Indian UPI apps and banks look like, which of them must
**never** become a transaction, and how Espere's parser
(`lib/services/notification_parser.dart`) handles each kind.

**Goal: no wrong entries.** When in doubt, the parser sends the payment to the Review list or
drops it. It never guesses.

## 1. How the parser was evaluated

- **Data.** 246 labelled bank SMS samples (expense, income, card spend, transfer, investment,
  "must not parse") from the test suite of the open-source PennyWise AI tracker, covering 23
  Indian banks: HDFC, ICICI, SBI, Axis, Kotak, IDFC FIRST, IndusInd, Bank of Baroda, Bank of
  India, PNB, Federal, Indian Bank, Central Bank, AU, YES, South Indian, IDBI, Equitas, Bandhan
  and others.
- **Licence.** That project is **AGPL-3.0**, so its code and sample texts were **not copied**
  into Espere. They were only run against Espere's parser locally to learn the formats. Every
  sample in `test/notification_parser_test.dart` was written for Espere, with its own values.
- **Results.**

  | Outcome | Before the research | After |
  |---|---|---|
  | Correct, added automatically (amount + type + reference) | 192 (mixed) | 103 |
  | Correct, sent to Review (no reference, or a review-only kind) | – | 118 + 5 |
  | **Wrong automatic entry** | **11** | **1** (intended, see §3, item 5) |
  | Wrong direction (expense ↔ income) | 2 | 0 |
  | Missed (no entry at all) | 41 | 19, all intended (see §5) |

## 2. What becomes an entry

| Kind | Example wording (own sample) | Result |
|---|---|---|
| UPI debit with a reference | "Rs.499.00 debited from A/c XX2211 to VPA shop@okhdfc. UPI Ref No 4312…" | **Added** (HIGH) |
| UPI app payment | "You paid ₹250 to Swiggy. UPI Ref No. 4312…" | **Added** (HIGH) |
| Money received with a reference | "Rs.750.00 Cr. to rahul@ybl … Ref:4312…" | **Added** if "Expenses + Income" is on |
| Card spend (usually no reference) | "INR 845 spent on Card XX3344 at PIZZA PALACE. Avl Lmt INR 41,155" | **Review** (LOW) |
| Short forms | "Dr INR 1,200.00", "Cr. to", "UPI debit:", "DEBIT:Rs.640", "Rs.2500credited" | Parsed |
| Balance or limit in the same SMS | "… Avl Bal / Avl Lmt / Avlbl Amt / Total Bal / Final balance is Rs …" | Ignored as the amount |

**HIGH confidence** means amount + direction + reference, or two sources confirming the same
payment. Everything else is **LOW** and waits in the Review list for one tap.

## 3. Traps: things that look like payments but are not spending

| # | Trap | Why it would be wrong | Handling |
|---|---|---|---|
| 1 | **Credit-card bill payment**: "Payment of Rs X received for your …CARD", "credited to your SBI Credit Card", "Paid ₹X to HDFC Credit Card" (CRED) | The purchases were already counted when the card was used. Counting the bill again doubles the spend. | **Rejected** |
| 2 | **Transfer between own accounts**: "Acct XX101 debited … & Acct XX202 credited", "Self transfer" | Not spending; the money stays with the user. | "Self transfer" wording is **rejected**. Two masked accounts go to **Review**, since one of them could be someone else's. |
| 3 | **Wallet or UPI Lite top-up**: "Rs.500 added to your Paytm Wallet", "loaded to UPI Lite" | Moving own money. The later wallet spend is the real expense. | **Rejected**. A "Use UPI Lite!" tagline on a normal debit is *not* rejected. |
| 4 | **Reversal of a failed payment**: the debit SMS comes first, then "UPI reversal: Rs X credited back … Ref <same>" | The first SMS would leave a wrong expense behind. | The reversal **deletes the auto entry with the same reference**, or the matching Review item (dedup rule f). Unmatched refunds go to Review (income on) or are ignored (expenses only). |
| 5 | **Wording describing the other side**: "Anil has received Rs 3000 from your A/c", "credited to the beneficiary account" | Contains "received"/"credited", but the user paid. | Parsed as **expense**. The dataset marks one such SMS "skip" because the bank also sends a debit SMS; Espere's dedup merges the two. |
| 6 | **NACH / ACH / ECS, SIP, mutual fund, insurance, EMI / loan** | Real outflows, but often investments or loan repayments the user may not count as spending. | **Review only** (never silent) |
| 7 | **ATM / cash withdrawal** | Cash spent later may be entered by hand, which would double count. | **Review only** |
| 8 | **Interest on a deposit, FD opened, closed or matured** | Not spending, and the direction is easy to get backwards. | **Rejected** |
| 9 | **Card statement / amount due / new bill fetched** | Only a reminder. | **Rejected** |
| 10 | **Refund initiated / "will be credited in 5–7 days"** | The money has not moved yet. | **Rejected**. The later "credited" message counts. |
| 11 | **Foreign currency** ("USD 20.00 spent …, Avl Limit INR …") | The rupee amount is unknown. Using the INR limit would be badly wrong. | **Rejected** |
| 12 | **OTP, collect / payment requests, reminders, failed / pending, offers, mandate or AutoPay setup** | Not completed payments. | **Rejected** |
| 13 | **Personal SMS / chats** | Privacy. Also, "I paid ₹500" is not a bank record. | Dropped natively before reading (sender-ID and WhatsApp chat filters) |

## 4. Rules that came out of the research

- **Decimal points are not sentence ends.** Patterns like "payment … received … card" must
  survive "Rs 6000.00". The parser uses "any character except a full stop that ends a
  sentence" instead of `[^.]`.
- **Direction words need letter boundaries, not word boundaries**, so that "Rs.2500credited"
  and "DEBIT:Rs.640" are recognised.
- **The first direction word wins** ("debited … credited to VPA x" is an expense), with
  explicit overrides for "has received … from your A/c" and "credited to the beneficiary".
- **Exactly one payment amount.** Balances and limits right after Bal / Avl / Lmt / Avlbl Amt /
  Limit are excluded. If two different amounts remain, the message is dropped.
- **SMS sender filter.** Only DLT headers containing a bank or UPI token (`VM-HDFCBK`,
  `AD-SBIINB`, `JD-ICICIT-S`, …). Promotional senders such as `AD-SWIGGY` and personal numbers
  are never read.

## 5. Known gaps (deliberately not handled)

- **Exact UPI app wording is not public.** Google Pay, PhonePe and Paytm do not document their
  notification text, and it changes with app versions. The labels also differ: PhonePe says
  "UPI Ref No", Google Pay "Transaction ID", Paytm "UTR". All three are recognised. Before
  release, collect a few real notifications from each app on a test phone (amount + wording
  only) and add them as tests.
- **Small UPI payments may have no bank SMS.** HDFC Bank, for example, stopped SMS alerts for
  UPI debits up to ₹100 (from June 2024). Those payments can only be captured from the UPI
  app's own notification.
- **Some apps post no notification at all.** Amazon Pay, for example, only shows an in-app
  "Thank You" screen after a UPI payment. For these, the user taps **Share** on the success
  screen and picks **Espere** (text or screenshot), or uses **Scan receipt** in the Add
  Transaction form. Screenshots are read on device (ML Kit) and parsed by
  `lib/services/receipt_parser.dart`; the result always opens in the form for a check.
- **Missing references.** Many card-spend and some bank SMS carry no reference, so they go to
  Review. This is the price of never guessing.
- **Missed on purpose:** foreign-currency spends, card bill payments, "refund initiated",
  bill-due alerts, and AutoPay activation test debits.

## 6. Sources

- PennyWise AI tracker: parser test suite, used only for study (AGPL-3.0):
  https://github.com/sarim2000/pennywiseai-tracker
- transaction-sms-parser (regex approach, generic fallback):
  https://github.com/saurabhgupta050890/transaction-sms-parser
- Double counting of card payments and transfers in expense trackers:
  https://finanjo.com/personal-finance/track-expenses-without-double-counting ,
  https://www.mintlify.com/we-promise/sure/features/transactions
- HDFC Bank stops SMS alerts for UPI payments up to ₹100:
  https://theprint.in/economy/hdfc-bank-to-stop-sms-alerts-for-upi-transactions-up-to-rs-100/2106054
- UPI failed-payment reversals ("UPI REVERSAL / REFUND / REV", same amount):
  https://blog.jumpp.finance/financial-wellness/upi/upi-transaction-failed-but-amount-debited/ ,
  https://www.npci.org.in/PDF/npci/upi/circular/2017/Circular-17-Debit-Reversals-and-Deemed-Approval_0.pdf
- Reference labels by app (UPI Ref No / Transaction ID / UTR) and NotificationListener approach:
  https://dhanrakhapp.pages.dev/blog/auto-track-gpay-phonpe-paytm-upi-transactions ,
  https://androxus.com/blogs/upi-payment-voice-alerts-without-soundbox
