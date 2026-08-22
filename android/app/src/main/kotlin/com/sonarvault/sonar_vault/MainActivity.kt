package com.sonarvault.sonar_vault

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val copyExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingOperation: PendingOperation? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_DOCUMENT_CHANNEL,
        ).setMethodCallHandler(::handleBackupDocumentMethod)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_PERMISSION_CHANNEL,
        ).setMethodCallHandler(::handleNotificationPermissionMethod)
    }

    private fun handleNotificationPermissionMethod(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "requestForPlayback") {
            result.notImplemented()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        val preferences = getSharedPreferences(PERMISSION_PREFERENCES, MODE_PRIVATE)
        if (preferences.getBoolean(NOTIFICATION_PERMISSION_REQUESTED, false)) {
            // A denied prompt is not repeated on every play. The user can
            // still grant notifications later from Android's app settings.
            result.success(false)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error(
                "notification_permission_busy",
                "A notification permission request is already in progress.",
                null,
            )
            return
        }
        preferences.edit().putBoolean(NOTIFICATION_PERMISSION_REQUESTED, true).apply()
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION,
        )
    }

    private fun handleBackupDocumentMethod(call: MethodCall, result: MethodChannel.Result) {
        if (pendingOperation != null || pendingResult != null) {
            result.error(
                "document_picker_busy",
                "A Sona backup document operation is already in progress.",
                null,
            )
            return
        }

        when (call.method) {
            "exportBackupDocument" -> startBackupExport(call, result)
            "importBackupDocument" -> startBackupImport(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startBackupExport(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val source = sourcePath?.let(::File)
        if (source == null || !isPrivateRegularFile(source)) {
            result.error(
                "invalid_source_path",
                "The backup export source is outside Sona's private storage.",
                null,
            )
            return
        }
        val suggestedName = sanitizeSuggestedName(
            call.argument<String>("suggestedName") ?: "Sona-library.sonabackup",
        )
        val mimeType = call.argument<String>("mimeType")
            ?.takeIf { it.isNotBlank() }
            ?: BACKUP_MIME_TYPE

        pendingOperation = PendingOperation.Export(source, suggestedName)
        pendingResult = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, suggestedName)
        }
        launchDocumentPicker(intent, REQUEST_EXPORT_BACKUP)
    }

    private fun startBackupImport(call: MethodCall, result: MethodChannel.Result) {
        val destinationPath = call.argument<String>("destinationPath")
        val destination = destinationPath?.let(::File)
        if (destination == null || !isPrivateDestination(destination)) {
            result.error(
                "invalid_destination_path",
                "The backup import destination is outside Sona's private storage.",
                null,
            )
            return
        }
        val requestedMimeTypes = call.argument<List<String>>("mimeTypes")
            ?.filter { it.isNotBlank() }
            ?.toTypedArray()
            ?.takeIf { it.isNotEmpty() }
            ?: arrayOf(BACKUP_MIME_TYPE, "application/octet-stream")

        pendingOperation = PendingOperation.Import(destination)
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, requestedMimeTypes)
        }
        launchDocumentPicker(intent, REQUEST_IMPORT_BACKUP)
    }

    private fun launchDocumentPicker(intent: Intent, requestCode: Int) {
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestCode)
        } catch (error: ActivityNotFoundException) {
            completeWithError(
                "document_picker_unavailable",
                "No Android document provider is available.",
                error,
            )
        } catch (error: RuntimeException) {
            completeWithError(
                "document_picker_failed",
                "Android could not open the document picker.",
                error,
            )
        }
    }

    @Deprecated("Deprecated in Android; required by Flutter's Activity result bridge.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_EXPORT_BACKUP && requestCode != REQUEST_IMPORT_BACKUP) {
            return
        }

        val operation = pendingOperation ?: return
        if (resultCode != Activity.RESULT_OK) {
            if (operation is PendingOperation.Import) {
                operation.destination.delete()
            }
            completeWithSuccess(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            completeWithError(
                "missing_document_uri",
                "Android did not return a document location.",
                null,
            )
            return
        }

        copyExecutor.execute {
            try {
                val displayName = when (operation) {
                    is PendingOperation.Export -> {
                        copyPrivateFileToDocument(operation.source, uri)
                        queryDisplayName(uri) ?: operation.suggestedName
                    }
                    is PendingOperation.Import -> {
                        copyDocumentToPrivateFile(uri, operation.destination)
                        queryDisplayName(uri) ?: "Sona-library.sonabackup"
                    }
                }
                completeWithSuccess(
                    mapOf(
                        "displayName" to displayName,
                        "externalLocation" to uri.toString(),
                    ),
                )
            } catch (error: Exception) {
                if (operation is PendingOperation.Import) {
                    operation.destination.delete()
                } else {
                    try {
                        contentResolver.delete(uri, null, null)
                    } catch (_: RuntimeException) {
                        // Some providers do not permit deleting a newly-created
                        // document. Its failed copy still cannot be mistaken
                        // for a valid backup because restore verifies hashes.
                    }
                }
                completeWithError(
                    "document_copy_failed",
                    "The selected backup document could not be copied.",
                    error,
                )
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermissionResult?.success(granted)
        pendingNotificationPermissionResult = null
    }

    private fun copyPrivateFileToDocument(source: File, destination: Uri) {
        contentResolver.openFileDescriptor(destination, "w")?.use { descriptor ->
            FileInputStream(source).use { input ->
                FileOutputStream(descriptor.fileDescriptor).use { output ->
                    copyBuffered(input, output)
                }
            }
        } ?: throw IOException("The selected document cannot be opened for writing.")
    }

    private fun copyDocumentToPrivateFile(source: Uri, destination: File) {
        destination.parentFile?.mkdirs()
        if (destination.exists() && !destination.delete()) {
            throw IOException("The previous import staging file cannot be removed.")
        }
        try {
            contentResolver.openInputStream(source)?.use { input ->
                FileOutputStream(destination).use { output ->
                    copyBuffered(input, output)
                    output.fd.sync()
                }
            } ?: throw IOException("The selected document cannot be opened for reading.")
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    private fun copyBuffered(input: java.io.InputStream, output: java.io.OutputStream) {
        val buffer = ByteArray(COPY_BUFFER_SIZE)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            output.write(buffer, 0, count)
        }
        output.flush()
    }

    private fun isPrivateRegularFile(file: File): Boolean {
        return try {
            file.isFile && isInsideFilesDirectory(file.canonicalFile)
        } catch (_: IOException) {
            false
        }
    }

    private fun isPrivateDestination(file: File): Boolean {
        return try {
            val canonical = file.canonicalFile
            canonical != filesDir.canonicalFile && isInsideFilesDirectory(canonical)
        } catch (_: IOException) {
            false
        }
    }

    private fun isInsideFilesDirectory(file: File): Boolean {
        val base = filesDir.canonicalFile.path
        val candidate = file.canonicalFile.path
        return candidate.startsWith(base + File.separator)
    }

    private fun queryDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index)?.takeIf { it.isNotBlank() } else null
            } else {
                null
            }
        } catch (_: RuntimeException) {
            null
        } finally {
            cursor?.close()
        }
    }

    private fun sanitizeSuggestedName(value: String): String {
        val sanitized = value
            .replace(Regex("[<>:\"/\\\\|?*\\u0000-\\u001f]"), "-")
            .trim()
            .take(160)
            .ifBlank { "Sona-library.sonabackup" }
        return if (sanitized.endsWith(".sonabackup", ignoreCase = true)) {
            sanitized
        } else {
            "$sanitized.sonabackup"
        }
    }

    private fun completeWithSuccess(value: Any?) {
        mainHandler.post {
            val result = pendingResult
            pendingOperation = null
            pendingResult = null
            result?.success(value)
        }
    }

    private fun completeWithError(code: String, message: String, error: Throwable?) {
        mainHandler.post {
            val result = pendingResult
            pendingOperation = null
            pendingResult = null
            result?.error(code, message, error?.message)
        }
    }

    override fun onDestroy() {
        copyExecutor.shutdown()
        super.onDestroy()
    }

    private sealed class PendingOperation {
        data class Export(val source: File, val suggestedName: String) : PendingOperation()
        data class Import(val destination: File) : PendingOperation()
    }

    companion object {
        private const val BACKUP_DOCUMENT_CHANNEL = "com.sonarvault.sona/backup_documents"
        private const val NOTIFICATION_PERMISSION_CHANNEL =
            "com.sonarvault.sona/notification_permission"
        private const val PERMISSION_PREFERENCES = "sona_permission_preferences"
        private const val NOTIFICATION_PERMISSION_REQUESTED =
            "notification_permission_requested"
        private const val BACKUP_MIME_TYPE = "application/vnd.sona.backup"
        private const val REQUEST_NOTIFICATION_PERMISSION = 0x5343
        private const val REQUEST_EXPORT_BACKUP = 0x5341
        private const val REQUEST_IMPORT_BACKUP = 0x5342
        private const val COPY_BUFFER_SIZE = 256 * 1024
    }
}
