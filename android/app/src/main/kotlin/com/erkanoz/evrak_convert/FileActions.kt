package com.erkanoz.evrak_convert

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Only explicitly selected copies inside outgoing/ can be shared. */
class FileActions(private val activity: Activity, messenger: BinaryMessenger) {
    private val io = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "lifeos_evrak/file_actions")

    init {
        channel.setMethodCallHandler { call, result ->
            val action = call.method
            if (action == "shareMany") {
                shareMany(call.argument<List<String>>("paths") ?: emptyList(), result)
                return@setMethodCallHandler
            }
            if (action !in setOf("openDefault", "openWith", "share")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
            if (path == null) { result.error("FILE_ACTION", "Belge yolu eksik.", null); return@setMethodCallHandler }
            io.execute {
                try {
                    val source = File(path)
                    require(source.isFile) { "Belge bulunamadı." }
                    val root = File(activity.cacheDir, "outgoing").apply { mkdirs() }
                    // Keep recent shares available to receiving apps, prune only old copies.
                    val cutoff = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
                    root.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.deleteRecursively() }
                    val folder = File(root, UUID.randomUUID().toString()).apply { mkdirs() }
                    val copy = File(folder, source.name)
                    source.copyTo(copy, bufferSize = 256 * 1024)
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.outgoing", copy)
                    activity.runOnUiThread {
                        try {
                            val intent = Intent(if (action == "share") Intent.ACTION_SEND else Intent.ACTION_VIEW).apply {
                                if (action == "share") {
                                    type = mime
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_SUBJECT, source.name)
                                } else setDataAndType(uri, mime)
                                clipData = ClipData.newUri(activity.contentResolver, source.name, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            val ownDefault = intent.resolveActivity(activity.packageManager)?.packageName == activity.packageName
                            val chooser = action != "openDefault" || ownDefault
                            val launch = if (chooser) Intent.createChooser(intent, if (action == "share") "Belgeyi paylaş" else "Birlikte aç").apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                if (Build.VERSION.SDK_INT >= 24) putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(ComponentName(activity, MainActivity::class.java)))
                            } else intent
                            activity.startActivity(launch)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("FILE_ACTION", "Uygulama açılamadı: ${e.message}", null)
                        }
                    }
                } catch (e: Exception) {
                    activity.runOnUiThread { result.error("FILE_ACTION", e.message, null) }
                }
            }
        }
    }

    /** Several files at once (the gallery's chosen photographs), each copied into outgoing/ first. */
    private fun shareMany(paths: List<String>, result: MethodChannel.Result) {
        io.execute {
            try {
                require(paths.isNotEmpty()) { "Paylaşılacak dosya yok." }
                val root = File(activity.cacheDir, "outgoing").apply { mkdirs() }
                val folder = File(root, UUID.randomUUID().toString()).apply { mkdirs() }
                val uris = ArrayList<android.net.Uri>()
                for (path in paths) {
                    val source = File(path)
                    require(source.isFile) { "Belge bulunamadı." }
                    var copy = File(folder, source.name)
                    var n = 2
                    while (copy.exists()) copy = File(folder, "${source.nameWithoutExtension} ($n).${source.extension}").also { n++ }
                    source.copyTo(copy, bufferSize = 256 * 1024)
                    uris.add(FileProvider.getUriForFile(activity, "${activity.packageName}.outgoing", copy))
                }
                val images = paths.all { it.lowercase().matches(Regex(".*\\.(jpe?g|png|webp|gif|bmp|heic|heif)$")) }
                activity.runOnUiThread {
                    try {
                        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                            type = if (images) "image/*" else "*/*"
                            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                            val clip = ClipData.newUri(activity.contentResolver, "Folio", uris.first())
                            for (uri in uris.drop(1)) clip.addItem(ClipData.Item(uri))
                            clipData = clip
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        activity.startActivity(Intent.createChooser(intent, "Paylaş").apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (Build.VERSION.SDK_INT >= 24) putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(ComponentName(activity, MainActivity::class.java)))
                        })
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("FILE_ACTION", "Paylaşılamadı: ${e.message}", null)
                    }
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("FILE_ACTION", e.message, null) }
            }
        }
    }

    fun dispose() { channel.setMethodCallHandler(null); io.shutdown() }
}
