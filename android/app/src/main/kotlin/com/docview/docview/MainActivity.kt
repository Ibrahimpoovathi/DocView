package com.docview.docview

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridges "Open with" / "Share to DocView" intents into Flutter.
 *
 * Content URIs are copied into a private cache folder (we only have a
 * transient read grant) and handed to Dart as plain paths; file:// URIs are
 * passed through untouched. Dart imports the file and deletes the temporary
 * copy when it is done.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<Uri>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        collect(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "docview/open_with",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        val files = takePendingFiles()
                        result.success(files)
                        if (files.isNotEmpty()) {
                            // Wake Dart once after a cold-start handoff.
                            // (The initial call already returns the batch.)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        collect(intent)
        channel?.invokeMethod("onOpen", null)
    }

    private fun collect(intent: Intent?) {
        if (intent == null) return
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { add(it) }
            Intent.ACTION_SEND -> {
                val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (stream != null) add(stream)
                intent.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { add(it) }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val streams =
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                streams?.forEach { add(it) }
                intent.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { add(it) }
                }
            }
        }
    }

    private fun add(uri: Uri) {
        if (pending.none { it == uri }) pending.add(uri)
    }

    private fun takePendingFiles(): List<Map<String, Any?>> {
        val uris = pending.toList()
        pending.clear()
        return uris.mapNotNull { uri ->
            try {
                materialize(uri)
            } catch (e: Exception) {
                null
            }
        }
    }

    private fun materialize(uri: Uri): Map<String, Any?>? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            return mapOf(
                "path" to path,
                "name" to File(path).name,
                "temporary" to false,
            )
        }
        val name = displayName(uri) ?: uri.lastPathSegment ?: "shared-document"
        val safe = name.replace(Regex("[/\\\\:*?\"<>|]"), "_").ifBlank { "shared-document" }
        val dir = File(cacheDir, "open_with").apply { mkdirs() }
        val dest = File(dir, safe)
        contentResolver.openInputStream(uri)?.use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        return mapOf(
            "path" to dest.absolutePath,
            "name" to name,
            "temporary" to true,
        )
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme != "content") return null
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) return cursor.getString(index)
        }
        return null
    }
}
