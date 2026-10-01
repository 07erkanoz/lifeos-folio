package com.erkanoz.evrak_convert

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The rich clipboard on Android: the same channel the desktop runners answer.
 *
 * Android's clipboard carries HTML beside plain text, and nothing richer, so
 * that is what Folio reads and writes. The plain text goes in as text: the
 * helper in quill_native_bridge puts the HTML markup there too, and a program
 * that pastes plain text would show the tags.
 */
class RichClipboard(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "lifeos_evrak/rich_clipboard")
    private val clipboard get() = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getRichData" -> {
                    val html = try {
                        clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.htmlText
                    } catch (error: SecurityException) {
                        // Android 10+ only lets the app in front read it.
                        null
                    }
                    if (html.isNullOrBlank()) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "candidates" to listOf(
                                    mapOf("format" to "html", "data" to html.toByteArray(Charsets.UTF_8)),
                                ),
                            ),
                        )
                    }
                }
                "setRichData" -> {
                    val text = call.argument<String>("text") ?: ""
                    val html = call.argument<ByteArray>("html")?.toString(Charsets.UTF_8)
                    val clip = if (html.isNullOrEmpty()) {
                        ClipData.newPlainText("Folio", text)
                    } else {
                        ClipData.newHtmlText("Folio", text, html)
                    }
                    clipboard.setPrimaryClip(clip)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
