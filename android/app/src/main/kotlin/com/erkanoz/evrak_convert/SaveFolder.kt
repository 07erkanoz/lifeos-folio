package com.erkanoz.evrak_convert

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The folder a phone saves documents into, chosen once (ACTION_OPEN_DOCUMENT_TREE)
 * with a lasting grant to read and write it; no broad storage permission. A
 * save then writes the document there under its own name, over one of the
 * same name: the system's save screen asked again at every save, and a
 * document signed in Folio stayed in Folio's own folder, out of the file
 * manager's sight.
 */
class SaveFolder(private val activity: Activity) {
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null

    fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("FOLDER_BUSY", "Klasör seçimi zaten açık.", null)
            return
        }
        try {
            pending = result
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }, REQUEST_CODE)
        } catch (e: Exception) {
            pending = null
            result.error("SAVE_FOLDER", "Klasör seçimi açılamadı: ${e.message}", null)
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val tree = data?.data
        if (code != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            result.success(mapOf("uri" to tree.toString(), "name" to nameOf(tree)))
        } catch (e: Exception) {
            result.error("SAVE_FOLDER", "Klasöre yazma izni alınamadı: ${e.message}", null)
        }
        return true
    }

    /** Whether the folder's grant to write still stands. */
    fun usable(uri: String?): Boolean = uri != null && activity.contentResolver.persistedUriPermissions.any {
        it.uri.toString() == uri && it.isWritePermission
    }

    /**
     * [path], one of Folio's own saved copies, written into the folder [uri]
     * as [name]: over a document of that name, or as a new one.
     */
    fun write(uri: String?, path: String?, name: String?, mime: String?, result: MethodChannel.Result) {
        io.execute {
            try {
                val tree = Uri.parse(requireNotNull(uri) { "Kayıt klasörü seçilmedi." })
                require(usable(uri)) { "Kayıt klasörüne yazma izni yok; klasörü yeniden seçin." }
                val file = File(requireNotNull(path)).canonicalFile
                val root = File(activity.filesDir, "saved-documents").canonicalFile
                require(file.isFile && file.path.startsWith(root.path + File.separator)) {
                    "Kaydedilecek belge bulunamadı."
                }
                val title = safeName(name ?: file.name)
                val type = mime ?: "application/octet-stream"
                val target = childNamed(tree, title)
                    ?: DocumentsContract.createDocument(
                        activity.contentResolver,
                        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree)),
                        type,
                        title
                    )
                    ?: throw IllegalStateException("Klasörde belge oluşturulamadı.")
                val output = activity.contentResolver.openOutputStream(target, "wt")
                    ?: throw IllegalStateException("Kayıt klasörüne yazılamıyor.")
                output.use { destination ->
                    file.inputStream().use { it.copyTo(destination, 256 * 1024) }
                    destination.flush()
                }
                val shown = displayName(target) ?: title
                activity.runOnUiThread { result.success("${nameOf(tree)}/$shown") }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("SAVE_FOLDER", e.message ?: "Belge kaydedilemedi.", null)
                }
            }
        }
    }

    private fun childNamed(tree: Uri, title: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val fields = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        activity.contentResolver.query(children, fields, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == title && c.getString(2) != DocumentsContract.Document.MIME_TYPE_DIR) {
                    return DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0))
                }
            }
        }
        return null
    }

    private fun displayName(document: Uri): String? =
        activity.contentResolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }

    private fun nameOf(tree: Uri): String = try {
        displayName(DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree)))
            ?: "Klasör"
    } catch (_: Exception) {
        "Klasör"
    }

    private fun safeName(value: String): String =
        value.replace(Regex("[\\\\/\\x00-\\x1f]"), "_").let { if (it == "." || it == ".." || it.isBlank()) "belge" else it }

    fun dispose() {
        pending = null
        io.shutdown()
    }

    companion object { const val REQUEST_CODE = 4110 }
}
