package com.erkanoz.evrak_convert

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/**
 * Android has no settings page for assigning arbitrary document MIME types.
 * Let the user pick a real document, then invoke the system ACTION_VIEW
 * resolver. When another app already owns the association, open that app's
 * details so its default can be cleared before retrying.
 */
class DefaultViewerSetup(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun start(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("DEFAULT_BUSY", "Belge seçimi zaten açık.", null)
            return
        }
        pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, supportedMimeTypes)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }, REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            finishError("Android belge seçicisi bulunamadı: ${error.message}")
        } catch (error: Exception) {
            finishError("Belge seçimi açılamadı: ${error.message}")
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        if (code == Activity.RESULT_CANCELED) {
            result.success("Belge seçimi iptal edildi; varsayılan değiştirilmedi.")
            return true
        }
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            result.error("DEFAULT_VIEWER", "Android geçerli bir belge döndürmedi.", null)
            return true
        }

        val mime = activity.contentResolver.getType(uri) ?: "application/octet-stream"
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            clipData = ClipData.newUri(activity.contentResolver, "LifeOS Folio", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            val packageManager = activity.packageManager
            val handlers = packageManager.queryIntentActivities(view, 0)
            if (handlers.none { it.activityInfo.packageName == activity.packageName }) {
                result.error(
                    "UNSUPPORTED_TYPE",
                    "Seçilen belge türü LifeOS Folio ile ilişkilendirilemiyor.",
                    null,
                )
                return true
            }

            val resolved = packageManager.resolveActivity(view, 0)?.activityInfo
            val resolvedPackage = resolved?.packageName
            val resolvedName = resolved?.name.orEmpty()
            val resolverVisible = resolvedPackage == null ||
                resolvedPackage == "android" ||
                resolvedName.contains("ResolverActivity") ||
                resolvedName.contains("ChooserActivity")

            when {
                resolvedPackage == activity.packageName -> {
                    result.success(
                        "LifeOS Folio bu belge türü için zaten varsayılan. Belge Folio’da açıldı.",
                    )
                    activity.startActivity(view)
                }
                !resolverVisible && handlers.size > 1 -> {
                    val label = resolved?.loadLabel(packageManager)?.toString() ?: resolvedPackage
                    activity.startActivity(Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$resolvedPackage"),
                    ))
                    result.success(
                        "$label bu belge türü için zaten varsayılan. Açılan ekranda " +
                            "“Varsayılan olarak aç” bölümünden varsayılanları temizleyin; " +
                            "sonra Folio’ya dönüp tekrar deneyin.",
                    )
                }
                else -> {
                    // Do not wrap this in ACTION_CHOOSER: Android documents that
                    // a chooser cannot save an app as the default handler.
                    activity.startActivity(view)
                    result.success(
                        "Android uygulama seçimi açıldı. LifeOS Folio’yu seçip “Her zaman”a dokunun.",
                    )
                }
            }
        } catch (error: ActivityNotFoundException) {
            result.error("DEFAULT_VIEWER", "Bu belgeyi açabilecek uygulama bulunamadı.", null)
        } catch (error: Exception) {
            result.error("DEFAULT_VIEWER", "Varsayılan seçim açılamadı: ${error.message}", null)
        }
        return true
    }

    fun dispose() {
        pending?.error("DEFAULT_VIEWER", "Uygulama kapatıldığı için belge seçimi iptal edildi.", null)
        pending = null
    }

    private fun finishError(message: String) {
        pending?.error("DEFAULT_VIEWER", message, null)
        pending = null
    }

    companion object {
        const val REQUEST_CODE = 4109
        val supportedMimeTypes = arrayOf(
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "application/vnd.oasis.opendocument.text",
            "application/x-uyap-udf",
            "application/udf",
            "application/x-udf",
            "application/octet-stream",
            "text/plain",
            "text/html",
            "text/markdown",
            "text/csv",
            "text/tab-separated-values",
            "application/json",
            "application/xml",
            "text/xml",
            "image/png",
            "image/jpeg",
            "image/tiff",
            "image/webp",
            "image/gif",
            "image/bmp",
            "image/svg+xml",
        )
    }
}
