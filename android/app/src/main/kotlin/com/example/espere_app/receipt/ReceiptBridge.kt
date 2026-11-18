package com.example.espere_app.receipt

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receipts the user shares with Espere (UPI app "Share" button, screenshots) and on-device
 * text recognition for screenshots.
 *
 * MethodChannel "com.example.espere_app/receipt":
 *   takePendingShare -> {text, subject, imagePath} or null
 *   recognizeText(path) -> String (ML Kit, on device; the image never leaves the phone)
 * Native -> Dart: "onShare" when a share arrives while the app is running.
 *
 * Shared images are copied into the app's cache (receipts/) and deleted by Dart once read.
 */
object ReceiptBridge {
    private const val CHANNEL = "com.example.espere_app/receipt"
    private const val MAX_IMAGE_BYTES = 15L * 1024 * 1024

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var pending: Map<String, String?>? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingShare" -> {
                        result.success(pending)
                        pending = null
                    }
                    "recognizeText" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("RECEIPT", "no path", null)
                        } else {
                            recognize(app, path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Returns true when the intent was a share meant for Espere. */
    fun handleIntent(context: Context, intent: Intent?): Boolean {
        if (intent == null || intent.action != Intent.ACTION_SEND) return false
        val type = intent.type ?: return false
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val stream: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        // Consume the share so a configuration change does not deliver it twice.
        intent.action = null

        val app = context.applicationContext
        Thread {
            val imagePath = if (stream != null && type.startsWith("image/")) copyImage(app, stream) else null
            if (text.isNullOrBlank() && imagePath == null) return@Thread
            main.post {
                pending = mapOf("text" to text, "subject" to subject, "imagePath" to imagePath)
                channel?.invokeMethod("onShare", null)
            }
        }.start()
        return true
    }

    private fun copyImage(context: Context, uri: Uri): String? = try {
        val dir = File(context.cacheDir, "receipts").apply { mkdirs() }
        // Old leftovers (e.g. the app was killed before Dart deleted them).
        dir.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 3_600_000) it.delete() }
        val out = File(dir, "shared_${System.currentTimeMillis()}.img")
        context.contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output ->
                val buf = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_IMAGE_BYTES) throw IllegalStateException("too large")
                    output.write(buf, 0, n)
                }
            }
        }
        if (out.length() > 0) out.absolutePath else null
    } catch (_: Exception) {
        null
    }

    private fun recognize(context: Context, path: String, result: MethodChannel.Result) {
        try {
            val image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val lines = visionText.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                        val b = line.boundingBox ?: return@mapNotNull null
                        mapOf("t" to line.text, "l" to b.left, "tp" to b.top, "r" to b.right, "b" to b.bottom)
                    }
                    val payload = mapOf(
                        "w" to image.width,
                        "h" to image.height,
                        "lines" to lines
                    )
                    // How this phone's OCR model writes the rupee sign (it has no "₹"): learned once
                    // from a bitmap we draw ourselves, then cached.
                    rupeeReading(context, recognizer) { rupee ->
                        result.success(payload + ("rupee" to rupee))
                        recognizer.close()
                    }
                }
                .addOnFailureListener { e ->
                    result.error("OCR", e.javaClass.simpleName, e.message)
                    recognizer.close()
                }
        } catch (e: Exception) {
            result.error("OCR", e.javaClass.simpleName, e.message)
        }
    }

    // ─── Rupee-sign calibration ───────────────────────────────────────────────

    private const val PREFS = "receipt_ocr"
    private const val KEY_RUPEE = "rupee_reading"
    private const val KEY_RUPEE_AT = "rupee_reading_at"
    private const val RUPEE_MAX_AGE_MS = 14L * 24 * 3600 * 1000 // models update via Play services

    /** Known amounts drawn on the probe bitmap, one per row. */
    private val PROBE = listOf("60", "140", "1,232", "85")

    /**
     * Returns how the OCR model reads "₹": "keep" (reads ₹), "drop" (leaves it out), a single
     * character such as "7" or "2" (reads it as that character), or null if unknown.
     */
    private fun rupeeReading(
        context: Context,
        recognizer: com.google.mlkit.vision.text.TextRecognizer,
        done: (String?) -> Unit
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cached = prefs.getString(KEY_RUPEE, null)
        val at = prefs.getLong(KEY_RUPEE_AT, 0L)
        if (cached != null && System.currentTimeMillis() - at < RUPEE_MAX_AGE_MS) {
            done(cached.ifEmpty { null })
            return
        }
        try {
            val rowH = 170
            val bmp = android.graphics.Bitmap.createBitmap(900, rowH * PROBE.size + 40, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bmp)
            canvas.drawColor(android.graphics.Color.WHITE)
            val faces = listOf(
                android.graphics.Typeface.DEFAULT_BOLD,
                android.graphics.Typeface.DEFAULT,
                android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL),
                android.graphics.Typeface.DEFAULT_BOLD
            )
            PROBE.forEachIndexed { i, amount ->
                val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    color = android.graphics.Color.BLACK
                    textSize = 110f
                    typeface = faces[i % faces.size]
                }
                canvas.drawText("\u20B9$amount", 60f, (rowH * (i + 1)).toFloat() - 30f, paint)
            }
            recognizer.process(InputImage.fromBitmap(bmp, 0))
                .addOnSuccessListener { text ->
                    val reading = classifyRupee(text.textBlocks.flatMap { it.lines }.map { it.text })
                    prefs.edit().putString(KEY_RUPEE, reading ?: "")
                        .putLong(KEY_RUPEE_AT, System.currentTimeMillis()).apply()
                    done(reading)
                }
                .addOnFailureListener { done(null) }
        } catch (_: Exception) {
            done(null)
        }
    }

    private fun classifyRupee(lines: List<String>): String? {
        val votes = mutableMapOf<String, Int>()
        for (amount in PROBE) {
            val digits = amount.replace(",", "")
            val line = lines.firstOrNull { it.replace(",", "").replace(" ", "").contains(digits) } ?: continue
            val t = line.replace(" ", "")
            val idx = t.replace(",", "").indexOf(digits)
            val prefix = t.replace(",", "").substring(0, idx)
            val vote = when {
                t.contains('\u20B9') -> "keep"
                prefix.isEmpty() -> "drop"
                prefix.length == 1 -> prefix
                else -> null
            } ?: continue
            votes[vote] = (votes[vote] ?: 0) + 1
        }
        val best = votes.maxByOrNull { it.value } ?: return null
        return if (best.value >= 2) best.key else null
    }
}
