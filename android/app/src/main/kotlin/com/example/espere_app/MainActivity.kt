package com.example.espere_app

import android.app.Activity
import android.content.Intent
import android.provider.MediaStore
import com.example.espere_app.autocapture.AutoCaptureBridge
import com.example.espere_app.receipt.ReceiptBridge
import com.example.espere_app.reminders.DailyReminder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.espere_app/image_picker"
    private val PICK_IMAGE_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Payment-notification auto-tracking (off until the user opts in)
        AutoCaptureBridge.register(this, flutterEngine.dartExecutor.binaryMessenger) { this }
        // Receipts shared from UPI apps / screenshots (Share -> Espere)
        ReceiptBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
        ReceiptBridge.handleIntent(this, intent)
        // Morning / night reminders scheduled on the phone (Settings -> Reminders)
        DailyReminder.register(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pickImage") {
                pendingResult = result
                val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                intent.type = "image/*"
                startActivityForResult(intent, PICK_IMAGE_REQUEST_CODE)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ReceiptBridge.handleIntent(this, intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_IMAGE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null && data.data != null) {
                try {
                    val uri = data.data!!
                    val inputStream: InputStream? = contentResolver.openInputStream(uri)
                    val tempFile = File(cacheDir, "picked_image_${System.currentTimeMillis()}.jpg")
                    val outputStream = FileOutputStream(tempFile)
                    inputStream?.copyTo(outputStream)
                    inputStream?.close()
                    outputStream.close()
                    pendingResult?.success(tempFile.absolutePath)
                } catch (e: Exception) {
                    pendingResult?.error("FILE_ERROR", "Failed to process image", null)
                }
            } else {
                pendingResult?.success(null)
            }
            pendingResult = null
        }
    }
}
