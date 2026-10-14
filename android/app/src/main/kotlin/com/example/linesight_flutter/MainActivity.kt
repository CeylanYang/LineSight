package com.example.linesight_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.net.Uri
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val saveRequest = 53145
    private val io = Executors.newSingleThreadExecutor()
    private var reply: MethodChannel.Result? = null
    private var source: File? = null
    private var expectedHash: String? = null
    @Volatile private var destroyed = false

    private fun scratchRoot(): File = File(cacheDir, "linesight_backups").apply { mkdirs() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linesight/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "scratchRoot" -> result.success(scratchRoot().absolutePath)
                "saveArchive" -> {
                    if (reply != null) {
                        result.error("busy", "请先完成当前文件保存", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(call.argument<String>("path")!!).canonicalFile
                        val root = scratchRoot().canonicalPath + File.separator
                        val name = call.argument<String>("name")!!
                        val digest = call.argument<String>("sha256")!!
                        require(file.path.startsWith(root) && file.isFile)
                        require(file.length() in 1..(256L * 1024 * 1024))
                        require(!name.contains('/') && !name.contains('\\'))
                        require(digest.matches(Regex("[0-9a-f]{64}")))
                        source = file
                        expectedHash = digest
                        reply = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (name.endsWith(".csv", ignoreCase = true)) "text/csv" else "application/octet-stream"
                            putExtra(Intent.EXTRA_TITLE, name)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, saveRequest)
                    } catch (error: Exception) {
                        reply = null; source = null; expectedHash = null
                        result.error("save_failed", "无法打开保存位置，请重试", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequest) return
        val result = reply ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            clearPending()
            result.success(false)
            return
        }
        val file = source!!
        val digest = expectedHash!!
        io.execute {
            try {
                copyAndVerify(file, uri, digest)
                runOnUiThread {
                    if (reply === result) { clearPending(); result.success(true) }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (reply === result) {
                        clearPending()
                        result.error("save_failed", "未确认文件完整保存，请检查所选位置", null)
                    }
                }
            }
        }
    }

    private fun copyAndVerify(file: File, uri: Uri, expected: String) {
        val copied = MessageDigest.getInstance("SHA-256")
        var size = 0L
        val buffer = ByteArray(64 * 1024)
        file.inputStream().use { input ->
            (contentResolver.openOutputStream(uri, "wt") ?: error("No output stream")).use { output ->
                while (true) {
                    check(!destroyed)
                    val n = input.read(buffer)
                    if (n < 0) break
                    size += n
                    check(size <= 256L * 1024 * 1024)
                    copied.update(buffer, 0, n)
                    output.write(buffer, 0, n)
                }
                output.flush()
            }
        }
        check(hex(copied.digest()) == expected)
        // Read back through the provider before reporting a successful save.
        val verified = MessageDigest.getInstance("SHA-256")
        var verifiedSize = 0L
        (contentResolver.openInputStream(uri) ?: error("No verification stream")).use { input ->
            while (true) {
                check(!destroyed)
                val n = input.read(buffer)
                if (n < 0) break
                verifiedSize += n
                check(verifiedSize <= size)
                verified.update(buffer, 0, n)
            }
        }
        check(verifiedSize == size && hex(verified.digest()) == expected)
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun clearPending() { reply = null; source = null; expectedHash = null }

    override fun onDestroy() {
        destroyed = true
        reply?.error("activity_closed", "文件保存窗口已关闭，请检查目标文件", null)
        clearPending()
        io.shutdown()
        super.onDestroy()
    }
}
