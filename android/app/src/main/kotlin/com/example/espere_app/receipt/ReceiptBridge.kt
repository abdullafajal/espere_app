package com.example.espere_app.receipt

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
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
                    // One line per text line, top to bottom, so "label / value" pairs stay together.
                    val lines = visionText.textBlocks
                        .flatMap { it.lines }
                        .sortedWith(
                            compareBy<Text.Line>({ it.boundingBox?.top ?: 0 }, { it.boundingBox?.left ?: 0 })
                        )
                        .joinToString("\n") { it.text }
                    result.success(lines)
                    recognizer.close()
                }
                .addOnFailureListener { e ->
                    result.error("OCR", e.javaClass.simpleName, e.message)
                    recognizer.close()
                }
        } catch (e: Exception) {
            result.error("OCR", e.javaClass.simpleName, e.message)
        }
    }
}
