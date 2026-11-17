package com.example.espere_app.autocapture

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Candidate payment notifications waiting for Dart to parse them.
 *
 * - Kept in memory plus one encrypted, app-private file in noBackupFilesDir (never backed up).
 * - Encryption: AES-256-GCM with a non-exportable key in the Android Keystore (the same
 *   scheme androidx EncryptedFile uses; that library is deprecated, so it is done directly).
 * - Each event is deleted as soon as Dart acknowledges it; anything older than 24 hours is
 *   dropped on every read/write. Raw text is never logged.
 */
object AutoCaptureQueue {
    private const val KEY_ALIAS = "espere_auto_capture_v1"
    private const val MAX_EVENTS = 200
    private const val MAX_AGE_MS = 24L * 60 * 60 * 1000
    private const val GCM_IV_BYTES = 12
    private const val GCM_TAG_BITS = 128

    private var cache: MutableList<JSONObject>? = null

    private fun file(context: Context): File =
        File(context.applicationContext.noBackupFilesDir, "auto_capture/queue.bin")

    @Synchronized
    fun add(context: Context, event: JSONObject) {
        val list = load(context)
        // The exact same post (same key + same text) is already waiting: keep one.
        val dup = list.any {
            it.optString("key") == event.optString("key") &&
                it.optString("text") == event.optString("text") &&
                it.optString("bigText") == event.optString("bigText")
        }
        if (!dup) list.add(event)
        while (list.size > MAX_EVENTS) list.removeAt(0)
        save(context, list)
    }

    @Synchronized
    fun pending(context: Context): List<JSONObject> {
        val list = load(context)
        save(context, list) // persists the 24h pruning
        return list.toList()
    }

    @Synchronized
    fun ack(context: Context, ids: Collection<String>) {
        if (ids.isEmpty()) return
        val list = load(context)
        list.removeAll { it.optString("id") in ids }
        save(context, list)
    }

    @Synchronized
    fun clear(context: Context) {
        cache = mutableListOf()
        file(context).delete()
        try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        } catch (_: Exception) {
        }
    }

    // ─── internals ──────────────────────────────────────────────────────────────

    private fun load(context: Context): MutableList<JSONObject> {
        val list = cache ?: readFile(context).also { cache = it }
        val cutoff = System.currentTimeMillis() - MAX_AGE_MS
        list.removeAll { it.optLong("postTime", 0L) < cutoff }
        return list
    }

    private fun readFile(context: Context): MutableList<JSONObject> {
        val f = file(context)
        if (!f.exists()) return mutableListOf()
        return try {
            val bytes = f.readBytes()
            if (bytes.size <= GCM_IV_BYTES) return mutableListOf()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE, key(),
                GCMParameterSpec(GCM_TAG_BITS, bytes.copyOfRange(0, GCM_IV_BYTES))
            )
            val json = String(cipher.doFinal(bytes.copyOfRange(GCM_IV_BYTES, bytes.size)), Charsets.UTF_8)
            val arr = JSONArray(json)
            MutableList(arr.length()) { arr.getJSONObject(it) }
        } catch (_: Exception) {
            // Unreadable (e.g. key was reset): start clean rather than keep stale data.
            f.delete()
            mutableListOf()
        }
    }

    private fun save(context: Context, list: List<JSONObject>) {
        val f = file(context)
        if (list.isEmpty()) {
            f.delete()
            return
        }
        try {
            f.parentFile?.mkdirs()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val plain = JSONArray(list).toString().toByteArray(Charsets.UTF_8)
            val out = cipher.iv + cipher.doFinal(plain)
            val tmp = File(f.parentFile, "queue.bin.tmp")
            tmp.writeBytes(out)
            if (!tmp.renameTo(f)) {
                f.delete()
                tmp.renameTo(f)
            }
        } catch (_: Exception) {
            // If encryption is unavailable we keep the events in memory only.
        }
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }
}
