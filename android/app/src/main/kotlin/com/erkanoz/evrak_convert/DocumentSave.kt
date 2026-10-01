package com.erkanoz.evrak_convert

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** SAF grants access to the chosen document; no broad storage permission. */
class DocumentSave(private val activity: Activity) {
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var source: File? = null

    fun start(path: String?, mime: String?, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("SAVE_BUSY", "Dosya kaydetme ekranı zaten açık.", null)
            return
        }
        try {
            val file = File(requireNotNull(path)).canonicalFile
            val root = File(activity.filesDir, "saved-documents").canonicalFile
            require(file.isFile && file.path.startsWith(root.path + File.separator)) {
                "Kaydedilecek belge bulunamadı."
            }
            pending = result
            source = file
            // Do not preflight resolveActivity: package visibility can hide the
            // system picker even though startActivityForResult can launch it.
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime ?: "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, file.name)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }, REQUEST_CODE)
        } catch (e: Exception) {
            pending = null
            source = null
            result.error("SAVE_DOCUMENT", "Kaydetme ekranı açılamadı: ${e.message}", null)
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST_CODE) return false
        val result = pending ?: return true
        val file = source
        if (code == Activity.RESULT_CANCELED) {
            pending = null
            source = null
            result.success(null)
            return true
        }
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null || file == null) {
            pending = null
            source = null
            result.error("SAVE_DOCUMENT", "Android geçerli bir kayıt konumu döndürmedi.", null)
            return true
        }
        io.execute {
            try {
                val output = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("Seçilen konuma yazılamıyor.")
                output.use { destination ->
                    file.inputStream().use { it.copyTo(destination, 256 * 1024) }
                    destination.flush()
                }
                activity.runOnUiThread {
                    pending = null
                    source = null
                    result.success(uri.toString())
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    pending = null
                    source = null
                    result.error("SAVE_DOCUMENT", "Belge kaydedilemedi: ${e.message}", null)
                }
            }
        }
        return true
    }

    fun dispose() {
        pending = null
        source = null
        io.shutdown()
    }

    companion object { const val REQUEST_CODE = 4108 }
}
