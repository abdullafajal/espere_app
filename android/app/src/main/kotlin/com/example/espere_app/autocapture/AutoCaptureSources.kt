package com.example.espere_app.autocapture

/**
 * The only apps whose notifications auto-capture ever looks at. Anything not listed here is
 * dropped in PaymentNotificationListener before its extras are read.
 *
 * Each package belongs to a "group" that the user can switch off individually in the app.
 */
object AutoCaptureSources {

    data class Source(val group: String, val label: String)

    /** Groups shown as per-app toggles in the settings screen (order = display order). */
    val GROUPS: List<Pair<String, String>> = listOf(
        "gpay" to "Google Pay",
        "phonepe" to "PhonePe",
        "paytm" to "Paytm",
        "bhim" to "BHIM",
        "amazonpay" to "Amazon Pay",
        "cred" to "CRED",
        "whatsapp" to "WhatsApp Pay",
        "banks" to "Bank apps",
        "sms" to "Bank SMS (Messages)"
    )

    const val GROUP_SMS = "sms"
    const val GROUP_WHATSAPP = "whatsapp"

    val PACKAGES: Map<String, Source> = mapOf(
        // UPI apps
        "com.google.android.apps.nbu.paisa.user" to Source("gpay", "Google Pay"),
        "com.phonepe.app" to Source("phonepe", "PhonePe"),
        "net.one97.paytm" to Source("paytm", "Paytm"),
        "in.org.npci.upiapp" to Source("bhim", "BHIM"),
        "in.amazon.mShop.android.shopping" to Source("amazonpay", "Amazon Pay"),
        "com.dreamplug.androidapp" to Source("cred", "CRED"),
        "com.whatsapp" to Source("whatsapp", "WhatsApp"),

        // Major bank apps
        "com.snapwork.hdfc" to Source("banks", "HDFC Bank"),
        "com.sbi.lotusintouch" to Source("banks", "SBI YONO"),
        "com.sbi.SBIFreedomPlus" to Source("banks", "SBI YONO Lite"),
        "com.csam.icici.bank.imobile" to Source("banks", "ICICI iMobile"),
        "com.axis.mobile" to Source("banks", "Axis Bank"),
        "com.msf.kbank.mobile" to Source("banks", "Kotak Bank"),
        "com.bankofbaroda.mconnect" to Source("banks", "Bank of Baroda"),
        "com.idfcfirstbank.optimus" to Source("banks", "IDFC FIRST Bank"),
        "com.Version1" to Source("banks", "PNB ONE"),
        "com.canarabank.mobility" to Source("banks", "Canara Bank"),

        // Default SMS apps (only bank/UPI sender IDs are processed, see isBankSender)
        "com.google.android.apps.messaging" to Source(GROUP_SMS, "SMS"),
        "com.samsung.android.messaging" to Source(GROUP_SMS, "SMS")
    )

    /** Tokens that identify a bank / UPI / card issuer inside an SMS sender ID. */
    private val BANK_TOKENS = listOf(
        "HDFC", "SBI", "ICICI", "AXIS", "KOTAK", "KMB", "PAYTM", "PNB", "BOB", "BARODA",
        "CANARA", "CNRB", "UNION", "UBOI", "IDFC", "YESB", "INDUS", "FEDBK", "FEDERAL", "AUBANK",
        "RBL", "CITI", "AMEX", "SCB", "HSBC", "BOI", "CBOI", "IOB", "UCO", "PHONEPE", "GPAY",
        "AMAZON", "CRED", "NPCI", "BHIM", "JUPITER", "SLICE", "ONECARD", "IPPB", "DBS", "BANK"
    )

    /** "VM-HDFCBK", "AD-SBIINB", "JD-ICICIT-S", "HDFCBK". Personal numbers/names never match. */
    private val DLT_HEADER = Regex("^(?:[A-Z]{2}-)?([A-Z0-9]{5,9})(?:-[A-Z])?$")

    fun isBankSender(sender: String?): Boolean {
        val s = sender?.trim()?.uppercase() ?: return false
        val body = DLT_HEADER.matchEntire(s)?.groupValues?.get(1) ?: return false
        return BANK_TOKENS.any { body.contains(it) }
    }
}
