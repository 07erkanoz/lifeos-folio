package com.erkanoz.evrak_convert

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val previewIo = Executors.newSingleThreadExecutor()
    private var fileActions: FileActions? = null
    private var documentSave: DocumentSave? = null
    private var defaultViewerSetup: DefaultViewerSetup? = null
    private var richClipboard: RichClipboard? = null
    private lateinit var channel: MethodChannel
    private val observers = mutableMapOf<String, ContentObserver>()
    private var ready = false
    private val pending = mutableListOf<Pair<String, Any>>()
    private var folderResult: MethodChannel.Result? = null
    private var folderInPlace = false
    private var pictureResult: MethodChannel.Result? = null
    private var microphoneResult: MethodChannel.Result? = null
    private val extensions = setOf("udf", "pdf", "docx", "xlsx", "txt", "odt", "rtf", "doc", "html", "htm", "md", "markdown", "csv", "tsv", "json", "xml", "log", "svg", "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff")
    private val preferences by lazy { getSharedPreferences("indexed_trees", MODE_PRIVATE) }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        fileActions = FileActions(this, engine.dartExecutor.binaryMessenger)
        documentSave = DocumentSave(this)
        defaultViewerSetup = DefaultViewerSetup(this)
        richClipboard = RichClipboard(this, engine.dartExecutor.binaryMessenger)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "lifeos_evrak/documents")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    ready = true
                    preferences.all.forEach { (path, uri) -> if (uri is String) observe(path, Uri.parse(uri)) }
                    pending.toList().forEach { channel.invokeMethod(it.first, it.second) }
                    pending.clear()
                    result.success(null)
                }
                "saveDocument" -> documentSave!!.start(call.argument<String>("path"), call.argument<String>("mimeType"), result)
                "configureDefaultViewer" -> defaultViewerSetup!!.start(result)
                // The gallery asks for this one: the chosen folder is read
                // where it is when that is possible, because a camera roll is
                // gigabytes and copying it would fill the phone twice.
                "pickPictureFolder" -> {
                    if (folderResult != null) { result.error("BUSY", "Klasör seçimi açık", null) }
                    else {
                        folderInPlace = true
                        folderResult = result
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        }, 4107)
                    }
                }
                "pickFolder" -> {
                    if (folderResult != null) { result.error("BUSY", "Klasör seçimi açık", null) }
                    else {
                        folderInPlace = false
                        folderResult = result
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        }, 4107)
                    }
                }
                "syncFolders" -> background(result) {
                    (call.arguments as? List<*>)?.filterIsInstance<String>()?.forEach { path ->
                        preferences.getString(path, null)?.let { syncTree(Uri.parse(it), File(path)) }
                    }
                    null
                }
                // The phone's own picture folders, read where they are. The
                // indexed-folder path copies what it is given, which is right
                // for a document shared in from another app and quite wrong for
                // a camera roll of several gigabytes.
                "pictureFolders" -> {
                    if (pictureResult != null) { result.error("BUSY", "İzin isteği açık", null) }
                    else if (hasMediaPermission()) { result.success(pictureFolders()) }
                    else {
                        pictureResult = result
                        requestPermissions(arrayOf(mediaPermission()), 4108)
                    }
                }
                // iPhone photographs. Android has decoded HEIF since Android 9;
                // Flutter has never been able to, so the system does it and the
                // rest of the application sees an ordinary JPEG.
                "decodeHeif" -> background(result) {
                    val source = call.argument<String>("source")
                    val target = call.argument<String>("target")
                    if (source == null || target == null) false
                    else decodeHeif(File(source), File(target))
                }
                // The microphone, asked for when a voice message is first
                // recorded: without it the recorder cannot start.
                "microphone" -> {
                    if (microphoneResult != null) { result.error("BUSY", "İzin isteği açık", null) }
                    else if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        microphoneResult = result
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4109)
                    }
                }
                "forgetFolder" -> {
                    // Forget only the permission mapping; never delete source documents.
                    val path = call.arguments as String
                    observers.remove(path)?.let { contentResolver.unregisterContentObserver(it) }
                    preferences.edit().remove(path).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun decodeHeif(source: File, target: File): Boolean {
        if (Build.VERSION.SDK_INT < 28) return false
        val bitmap = BitmapFactory.decodeFile(source.absolutePath) ?: return false
        return try {
            val partial = File(target.parentFile, ".${target.name}.partial")
            partial.outputStream().use { out ->
                // 92 keeps a photograph indistinguishable at any zoom the
                // viewer allows, at a fraction of a lossless copy.
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)) return false
            }
            partial.renameTo(target)
        } finally {
            bitmap.recycle()
        }
    }

    /// The real path behind a document tree on the phone's own storage, when
    /// there is one. Returns null for a cloud provider or an SD card, where
    /// the only way in is the provider itself.
    private fun externalPath(tree: Uri): String? {
        if (tree.authority != "com.android.externalstorage.documents") return null
        val id = DocumentsContract.getTreeDocumentId(tree) ?: return null
        val parts = id.split(':', limit = 2)
        if (parts.size != 2 || parts[0] != "primary") return null
        val file = File(Environment.getExternalStorageDirectory(), parts[1])
        return if (file.isDirectory && file.canRead()) file.absolutePath else null
    }

    private fun mediaPermission() =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES
        else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun hasMediaPermission() =
        checkSelfPermission(mediaPermission()) == PackageManager.PERMISSION_GRANTED

    /// The standard picture folders that exist and hold something.
    private fun pictureFolders(): List<String> {
        val names = listOf(
            Environment.DIRECTORY_DCIM,
            Environment.DIRECTORY_PICTURES,
            Environment.DIRECTORY_SCREENSHOTS.takeIf { Build.VERSION.SDK_INT >= 29 },
        )
        return names.filterNotNull().mapNotNull { name ->
            val directory = Environment.getExternalStoragePublicDirectory(name)
            if (directory != null && directory.isDirectory && directory.canRead()) directory.absolutePath else null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4109) {
            val asked = microphoneResult ?: return
            microphoneResult = null
            asked.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            return
        }
        if (requestCode != 4108) return
        val result = pictureResult ?: return
        pictureResult = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(if (granted) pictureFolders() else emptyList<String>())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        accept(intent)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        accept(intent)
    }
    private fun emit(method: String, value: Any) = runOnUiThread {
        if (ready) channel.invokeMethod(method, value) else pending.add(method to value)
    }
    private fun accept(received: Intent?) {
        val intent = received ?: return
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(intent.data ?: streamOf(intent))
            // Several documents shared at once: each one kept, all opened.
            Intent.ACTION_SEND_MULTIPLE -> streamsOf(intent)
            else -> emptyList()
        }
        if (uris.isEmpty()) return
        previewIo.execute {
            val opened = mutableListOf<String>()
            val failed = mutableListOf<String>()
            for (uri in uris) {
                try {
                    opened.add(keep(uri))
                } catch (e: Exception) {
                    failed.add(e.message ?: "bilinmeyen hata")
                }
            }
            if (opened.isNotEmpty()) emit("openFiles", opened)
            if (failed.isNotEmpty()) emit("openError", "Belge açılamadı: ${failed.joinToString("; ")}")
        }
    }
    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)
    @Suppress("DEPRECATION")
    private fun streamsOf(intent: Intent): List<Uri> =
        intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.toList() ?: emptyList()
    /** [uri] copied into Folio's cache under its own name; its path. */
    private fun keep(uri: Uri): String {
        var name = uri.lastPathSegment ?: "belge"
        if (uri.scheme == "content") contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0) ?: name
        }
        name = safeName(name)
        if (!extensions.contains(name.substringAfterLast('.', "").lowercase())) {
            // Providers occasionally omit the extension from DISPLAY_NAME.
            val ext = android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(contentResolver.getType(uri))
            if (ext != null && extensions.contains(ext)) name += ".$ext"
            else throw IllegalArgumentException("Bu belge türü desteklenmiyor: $name")
        }
        val directory = File(cacheDir, "incoming/${hash(uri.toString())}").apply { mkdirs() }
        val target = File(directory, name)
        copy(uri, target)
        return target.absolutePath
    }
    @Deprecated("Android callback retained for Flutter Activity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documentSave?.onActivityResult(requestCode, resultCode, data) == true) return
        if (defaultViewerSetup?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4107) return
        val result = folderResult ?: return
        folderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        val inPlace = folderInPlace
        folderInPlace = false
        background(result) {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // A folder on the phone's own storage can be read directly once
            // the media permission is held; there is nothing to copy.
            if (inPlace) {
                val direct = externalPath(uri)
                if (direct != null && hasMediaPermission()) return@background direct
            }
            val rootId = DocumentsContract.getTreeDocumentId(uri)
            val document = DocumentsContract.buildDocumentUriUsingTree(uri, rootId)
            var name = "Arşiv"
            contentResolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) name = it.getString(0) ?: name
            }
            val target = File(filesDir, "archives/${hash(uri.toString())}/${safeName(name)}")
            syncTree(uri, target)
            preferences.edit().putString(target.absolutePath, uri.toString()).commit()
            runOnUiThread { observe(target.absolutePath, uri) }
            target.absolutePath
        }
    }
    private fun syncTree(tree: Uri, root: File) {
        root.mkdirs()
        val seen = mutableSetOf<String>()
        val visited = mutableSetOf<String>()
        fun walk(id: String, destination: File) {
            if (!visited.add(id)) return
            if (visited.size > 100000) throw IllegalStateException("Klasör sayısı sınırı aşıldı")
            destination.mkdirs()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            val fields = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val cursor = contentResolver.query(children, fields, null, null, null)
                ?: throw IllegalStateException("Klasöre erişilemiyor")
            cursor.use {
                while (it.moveToNext()) {
                    val childId = it.getString(0)
                    val name = safeName(it.getString(1) ?: "belge")
                    if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        walk(childId, File(destination, name))
                    } else if (extensions.contains(name.substringAfterLast('.', "").lowercase())) {
                        val target = File(destination, name)
                        val size = it.getLong(3)
                        val modified = it.getLong(4)
                        seen.add(target.absolutePath)
                        if (!target.exists() || modified == 0L || target.length() != size || target.lastModified() != modified) {
                            copy(DocumentsContract.buildDocumentUriUsingTree(tree, childId), target)
                            if (modified > 0) target.setLastModified(modified)
                        }
                    }
                }
            }
        }
        walk(DocumentsContract.getTreeDocumentId(tree), root)
        // Only prune after a completely successful enumeration. Source files are
        // never touched; these are app-private, byte-identical preview copies.
        root.walkBottomUp().filter { it.isFile && it.absolutePath !in seen }.forEach { it.delete() }
    }
    private fun observe(path: String, uri: Uri) {
        if (observers.containsKey(path)) return
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { if (ready) emit("foldersChanged", true) }
        }
        try {
            contentResolver.registerContentObserver(uri, true, observer)
            observers[path] = observer
        } catch (_: Exception) { /* Foreground periodic scan remains available. */ }
    }
    private fun copy(uri: Uri, target: File) {
        val temp = File(target.parentFile, ".${target.name}.partial")
        try {
            val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("Belge okunamıyor")
            input.use { source -> temp.outputStream().use { source.copyTo(it, 256 * 1024) } }
            if (!temp.renameTo(target)) throw IllegalStateException("Belge kopyası kaydedilemiyor")
        } finally { temp.delete() }
    }
    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        io.execute {
            try { val value = action(); runOnUiThread { result.success(value) } }
            catch (e: Exception) { runOnUiThread { result.error("DOCUMENT_ACCESS", e.message, null) } }
        }
    }
    private fun safeName(value: String): String = value.replace(Regex("[\\\\/\\x00-\\x1f]"), "_").let { if (it == "." || it == ".." || it.isBlank()) "belge" else it }
    private fun hash(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).take(12).joinToString("") { "%02x".format(it) }
    override fun onDestroy() { defaultViewerSetup?.dispose(); defaultViewerSetup = null; documentSave?.dispose(); documentSave = null; fileActions?.dispose(); fileActions = null; observers.values.forEach { contentResolver.unregisterContentObserver(it) }; observers.clear(); ready = false; io.shutdown(); previewIo.shutdown(); super.onDestroy() }
}
