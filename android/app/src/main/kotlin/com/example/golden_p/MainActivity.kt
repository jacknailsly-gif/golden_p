package com.example.golden_p

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.golden_p/network_guard"
    private var methodChannel: MethodChannel? = null
    private var wifiReceiver: BroadcastReceiver? = null
    private var connectivityCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isEmulator" -> {
                    result.success(checkIsEmulator())
                }
                "isWifiConnected" -> {
                    result.success(checkIsWifiConnected())
                }
                "openWifiSettings" -> {
                    openWifiSettings()
                    result.success(true)
                }
                "disableWifi" -> {
                    val success = disableWifi()
                    result.success(success)
                }
                "startBackgroundService" -> {
                    result.success(startBotService())
                }
                "stopBackgroundService" -> {
                    result.success(stopBotService())
                }
                "isBackgroundServiceRunning" -> {
                    result.success(BotBackgroundService.isRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        registerWifiWatchdog()
    }

    override fun onDestroy() {
        unregisterWifiWatchdog()
        super.onDestroy()
    }

    private fun registerWifiWatchdog() {
        // 1. Dynamic BroadcastReceiver for WifiManager.WIFI_STATE_CHANGED_ACTION (Detects WIFI_STATE_ENABLING)
        try {
            val filter = IntentFilter().apply {
                addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
                addAction(ConnectivityManager.CONNECTIVITY_ACTION)
            }
            wifiReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent == null || checkIsEmulator()) return
                    val action = intent.action
                    if (action == WifiManager.WIFI_STATE_CHANGED_ACTION) {
                        val state = intent.getIntExtra(WifiManager.EXTRA_WIFI_STATE, WifiManager.WIFI_STATE_UNKNOWN)
                        // 🛡️ ดักจับทันทีเมื่อผู้ใช้แตะเปิด Wi-Fi (WIFI_STATE_ENABLING = 2) หรือเปิดแล้ว (WIFI_STATE_ENABLED = 3)
                        if (state == WifiManager.WIFI_STATE_ENABLING || state == WifiManager.WIFI_STATE_ENABLED) {
                            disableWifi()
                            notifyFlutterWifiChanged(true)
                        } else if (state == WifiManager.WIFI_STATE_DISABLED) {
                            notifyFlutterWifiChanged(false)
                        }
                    } else {
                        if (checkIsWifiConnected()) {
                            disableWifi()
                            notifyFlutterWifiChanged(true)
                        }
                    }
                }
            }
            registerReceiver(wifiReceiver, filter)
        } catch (e: Exception) {
            android.util.Log.e("NetworkGuard", "Error registering wifiReceiver: ${e.message}")
        }

        // 2. ConnectivityManager.NetworkCallback for Android 7+ (API 24+)
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .build()
                connectivityCallback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        super.onAvailable(network)
                        if (!checkIsEmulator()) {
                            disableWifi()
                            notifyFlutterWifiChanged(true)
                        }
                    }

                    override fun onLost(network: Network) {
                        super.onLost(network)
                        notifyFlutterWifiChanged(false)
                    }
                }
                cm.registerNetworkCallback(request, connectivityCallback!!)
            }
        } catch (e: Exception) {
            android.util.Log.e("NetworkGuard", "Error registering networkCallback: ${e.message}")
        }
    }

    private fun unregisterWifiWatchdog() {
        try {
            if (wifiReceiver != null) {
                unregisterReceiver(wifiReceiver)
                wifiReceiver = null
            }
        } catch (_: Exception) {}

        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm != null && connectivityCallback != null) {
                cm.unregisterNetworkCallback(connectivityCallback!!)
                connectivityCallback = null
            }
        } catch (_: Exception) {}
    }

    private fun notifyFlutterWifiChanged(isBlocked: Boolean) {
        if (checkIsEmulator() && isBlocked) return // 🛡️ บน Emulator ไม่ส่ง event บล็อก Wi-Fi
        runOnUiThread {
            try {
                methodChannel?.invokeMethod("onWifiStateChanged", isBlocked)
            } catch (_: Exception) {}
        }
    }

    private fun getSystemProperty(key: String): String {
        return try {
            val clazz = Class.forName("android.os.SystemProperties")
            val getMethod = clazz.getMethod("get", String::class.java)
            (getMethod.invoke(null, key) as? String) ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun checkIsEmulator(): Boolean {
        // 1. CPU ABI detection (x86 / x86_64 architecture used in LDPlayer and PC emulators)
        if (Build.SUPPORTED_ABIS.any { it.contains("x86", ignoreCase = true) }) return true
        @Suppress("DEPRECATION")
        if (Build.CPU_ABI.contains("x86", ignoreCase = true) || Build.CPU_ABI2.contains("x86", ignoreCase = true)) return true

        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val device = Build.DEVICE.lowercase()
        val product = Build.PRODUCT.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        val board = Build.BOARD.lowercase()

        // 2. Hardware / Board / Product / Device x86 markers
        if (hardware.contains("x86") || board.contains("x86") || product.contains("x86") || device.contains("x86")) return true

        val isBasicEmu = (brand.startsWith("generic") && device.startsWith("generic"))
                || fingerprint.startsWith("generic")
                || fingerprint.startsWith("unknown")
                || hardware.contains("goldfish")
                || hardware.contains("ranchu")
                || model.contains("google_sdk")
                || model.contains("emulator")
                || model.contains("android sdk built for x86")
                || manufacturer.contains("genymotion")
                || manufacturer.contains("ldplayer")
                || manufacturer.contains("changwan")
                || model.contains("ldplayer")
                || hardware.contains("ttvm")
                || product.contains("cancro")
                || product.contains("sdk_google")
                || product.contains("google_sdk")
                || product.contains("sdk")
                || product.contains("sdk_x86")
                || product.contains("vbox86p")
                || product.contains("emulator")
                || product.contains("simulator")
                || board.contains("nox")
                || hardware.contains("nox")
                || product.contains("nox")
                || hardware.contains("vbox86")
                || model.contains("bluestacks")
                || manufacturer.contains("bluestacks")
                || hardware.contains("bluestacks")

        if (isBasicEmu) return true

        // 3. SystemProperties check for LDPlayer (ro.ld.version, ro.build.version.incremental, ro.product.model.device / ro.product.device)
        val roLdVersion = getSystemProperty("ro.ld.version").lowercase()
        if (roLdVersion.isNotEmpty()) return true

        val roIncremental = getSystemProperty("ro.build.version.incremental").lowercase()
        if (roIncremental.contains("ld")) return true

        val roModelDevice = getSystemProperty("ro.product.model.device").lowercase()
        if (roModelDevice.contains("xuanzhi") || roModelDevice.contains("ld")) return true

        val roProductDevice = getSystemProperty("ro.product.device").lowercase()
        if (roProductDevice.contains("xuanzhi")) return true

        // 4. File-based emulator detection (qemu, nox, bluestacks, ldplayer pipes & drivers)
        val emuFiles = listOf(
            "/dev/socket/qemud",
            "/dev/qemu_pipe",
            "/system/bin/nox-prop",
            "/system/bin/androVM-prop",
            "/system/bin/microvirtd",
            "/system/lib/libc_orig.so",
            "/system/bin/ttVM-prop",
            "/data/data/com.vphone.launcher",
            "/system/bin/ldprop",
            "/system/bin/ldinit",
            "/system/bin/ldmount",
            "/system/etc/ld.prop",
            "/dev/ld_pipe",
            "/dev/socket/ld_pipe",
            "/dev/vboxguest",
            "/dev/vboxuser",
            "/sys/module/vboxguest",
            "/system/lib/hw/audio.r_submix.ld.so",
            "/system/lib/hw/gralloc.ld.so",
            "/system/app/ldAppStore",
            "/data/data/com.android.ld.appstore",
            "/system/bin/microvirt-prop"
        )
        for (path in emuFiles) {
            try {
                if (java.io.File(path).exists()) return true
            } catch (_: Exception) {}
        }

        return false
    }

    private fun checkIsWifiConnected(): Boolean {
        if (checkIsEmulator()) {
            return false // 🛡️ บน Emulator ให้ถือว่าผ่าน ไม่นับว่ามี Wi-Fi ต้องห้าม เพื่อให้บอททำงานได้ตามปกติ
        }
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val network = cm.activeNetwork
                    if (network != null) {
                        val capabilities = cm.getNetworkCapabilities(network)
                        if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                            return true
                        }
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val networkInfo = cm.activeNetworkInfo
                    @Suppress("DEPRECATION")
                    if (networkInfo != null && networkInfo.isConnected && networkInfo.type == ConnectivityManager.TYPE_WIFI) {
                        return true
                    }
                }
            }
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            wm?.isWifiEnabled == true
        } catch (_: Exception) {
            false
        }
    }

    private fun openWifiSettings() {
        try {
            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun disableWifi(): Boolean {
        if (checkIsEmulator()) return true

        var disabled = false

        // 1. WifiManager.setWifiEnabled(false) (Enabled via targetSdk 28 + CHANGE_WIFI_STATE)
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            if (wm != null && wm.isWifiEnabled) {
                val res = wm.setWifiEnabled(false)
                if (res) disabled = true
            }
        } catch (e: Exception) {
            android.util.Log.e("NetworkGuard", "setWifiEnabled failed: ${e.message}")
        }

        // 2. Direct shell commands / Root fallback
        val commands = listOf(
            arrayOf("su", "-c", "svc wifi disable"),
            arrayOf("su", "-c", "cmd wifi set-wifi-enabled disabled"),
            arrayOf("svc", "wifi", "disable"),
            arrayOf("cmd", "wifi", "set-wifi-enabled", "disabled")
        )

        for (cmd in commands) {
            try {
                val proc = Runtime.getRuntime().exec(cmd)
                val exitCode = proc.waitFor()
                if (exitCode == 0) {
                    disabled = true
                    break
                }
            } catch (_: Exception) {}
        }

        return disabled
    }

    private fun startBotService(): Boolean {
        return try {
            val intent = Intent(this, BotBackgroundService::class.java).apply {
                action = BotBackgroundService.ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to start BotBackgroundService: ${e.message}")
            false
        }
    }

    private fun stopBotService(): Boolean {
        return try {
            val intent = Intent(this, BotBackgroundService::class.java).apply {
                action = BotBackgroundService.ACTION_STOP
            }
            startService(intent)
            true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to stop BotBackgroundService: ${e.message}")
            false
        }
    }
}
