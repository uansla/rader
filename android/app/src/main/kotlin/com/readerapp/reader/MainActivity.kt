package com.readerapp.reader

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "reader/multicast"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireLock()
                        result.success(true)
                    }
                    "release" -> {
                        releaseLock()
                        result.success(true)
                    }
                    "getIp" -> {
                        result.success(getWifiIp())
                    }
                    "getDeviceName" -> {
                        result.success(android.os.Build.MODEL)
                    }
                    "copyAssetDir" -> {
                        val src = call.argument<String>("src") ?: ""
                        val dst = call.argument<String>("dst") ?: ""
                        result.success(copyAssetDir(src, dst))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 把原生 assets 目录递归拷贝到目标目录，返回文件数。 */
    private fun copyAssetDir(src: String, dst: String): Int {
        return try {
            val am = assets
            val destDir = java.io.File(dst)
            var count = 0
            fun copy(relative: String, destFile: java.io.File) {
                val childNames = am.list(relative)
                if (childNames != null && childNames.isNotEmpty()) {
                    // 目录
                    if (destFile.exists() && !destFile.isDirectory) destFile.delete()
                    destFile.mkdirs()
                    for (name in childNames) {
                        copy("$relative/$name", java.io.File(destFile, name))
                    }
                } else {
                    // 文件：清理可能残留的目录
                    if (destFile.isDirectory) destFile.deleteRecursively()
                    destFile.parentFile?.mkdirs()
                    am.open(relative).use { input ->
                        destFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    count++
                }
            }
            copy(src, destDir)
            count
        } catch (_: Exception) {
            -1
        }
    }

    private fun getWifiIp(): String? {        return try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val ipInt = wifiManager.connectionInfo?.ipAddress ?: 0
            if (ipInt == 0) {
                null
            } else {
                String.format(
                    "%d.%d.%d.%d",
                    ipInt and 0xff,
                    (ipInt shr 8) and 0xff,
                    (ipInt shr 16) and 0xff,
                    (ipInt shr 24) and 0xff,
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun acquireLock() {
        if (multicastLock != null) return
        try {
            val wifiManager =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock("reader-discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseLock() {
        try {
            multicastLock?.release()
        } catch (_: Exception) {
        }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }
}
