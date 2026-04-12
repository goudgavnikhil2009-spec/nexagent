package com.vesta.agent.vesta

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.vesta.agent/service"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val service = VestaAccessibilityService.instance

                when (call.method) {
                    // ─── Accessibility Service Status ───
                    "isServiceEnabled" -> {
                        result.success(service != null)
                    }

                    // ─── Screen Capture ───
                    "takeScreenshot" -> {
                        if (service != null) {
                            service.captureScreen { bytes ->
                                if (bytes != null) result.success(bytes)
                                else result.error("UNAVAILABLE", "Screenshot null", null)
                            }
                        } else {
                            result.error("UNAVAILABLE", "Accessibility Service not active.", null)
                        }
                    }

                    // ─── UI Node Tree Observation ───
                    "getScreenNodes" -> {
                        if (service != null) {
                            result.success(service.getScreenNodes())
                        } else {
                            result.error("UNAVAILABLE", "Accessibility Service not active.", null)
                        }
                    }

                    // ─── Gestures ───
                    "performClick" -> {
                        if (service != null) {
                            val x = call.argument<Double>("x")?.toFloat() ?: 0f
                            val y = call.argument<Double>("y")?.toFloat() ?: 0f
                            result.success(service.performClickAt(x, y))
                        } else {
                            result.error("UNAVAILABLE", "Accessibility Service not active.", null)
                        }
                    }
                    "performSwipe" -> {
                        if (service != null) {
                            val x1 = call.argument<Double>("x1")?.toFloat() ?: 0f
                            val y1 = call.argument<Double>("y1")?.toFloat() ?: 0f
                            val x2 = call.argument<Double>("x2")?.toFloat() ?: 0f
                            val y2 = call.argument<Double>("y2")?.toFloat() ?: 0f
                            result.success(service.performSwipe(x1, y1, x2, y2))
                        } else {
                            result.error("UNAVAILABLE", "Accessibility Service not active.", null)
                        }
                    }
                    "typeText" -> {
                        if (service != null) {
                            val text = call.argument<String>("text") ?: ""
                            result.success(service.typeText(text))
                        } else {
                            result.error("UNAVAILABLE", "Accessibility Service not active.", null)
                        }
                    }
                    "performBack" -> {
                        result.success(service?.performBack() ?: false)
                    }
                    "performHome" -> {
                        result.success(service?.performHome() ?: false)
                    }
                    "performRecents" -> {
                        result.success(service?.performRecents() ?: false)
                    }

                    // ─── File System ───
                    "readDirectory" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            val file = java.io.File(path)
                            if (file.exists() && file.isDirectory) {
                                val list = file.list()?.toList() ?: emptyList<String>()
                                result.success(list)
                            } else {
                                result.error("INVALID_PATH", "Not a valid directory", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Phone / Telecom ───
                    "answerCall" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val tm = getSystemService(Context.TELECOM_SERVICE) as android.telecom.TelecomManager
                                if (checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        tm.acceptRingingCall()
                                    }
                                    result.success(true)
                                } else {
                                    result.error("PERMISSION_DENIED", "ANSWER_PHONE_CALLS not granted", null)
                                }
                            } else {
                                result.error("API_LEVEL", "Requires API 26+", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Wi-Fi ───
                    "setWifi" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                // Android 10+: Use Settings Panel Intent (direct toggle was removed)
                                val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
                                panelIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                startActivity(panelIntent)
                                result.success(true)
                            } else {
                                @Suppress("DEPRECATION")
                                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                @Suppress("DEPRECATION")
                                wm.isWifiEnabled = enable
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Flashlight ───
                    "setFlashlight" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        try {
                            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                            val cameraId = cm.cameraIdList.firstOrNull() ?: ""
                            cm.setTorchMode(cameraId, enable)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Volume ───
                    "setVolume" -> {
                        val level = call.argument<Int>("level") ?: 50 // 0..100
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val targetVol = (level / 100.0 * maxVol).toInt().coerceIn(0, maxVol)
                            am.setStreamVolume(AudioManager.STREAM_MUSIC, targetVol, 0)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "getVolume" -> {
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val current = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            result.success((current.toDouble() / max * 100).toInt())
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Brightness ───
                    "setBrightness" -> {
                        val level = call.argument<Int>("level") ?: 50 // 0..100
                        try {
                            val brightnessVal = (level / 100.0 * 255).toInt().coerceIn(0, 255)
                            // Set auto-brightness off
                            Settings.System.putInt(contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS_MODE,
                                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                            Settings.System.putInt(contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS, brightnessVal)
                            // Also update window layout params immediately
                            val lp = window.attributes
                            lp.screenBrightness = brightnessVal / 255.0f
                            window.attributes = lp
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Battery ───
                    "getBatteryStatus" -> {
                        try {
                            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                            val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                            val isCharging = bm.isCharging
                            result.success(mapOf("level" to level, "isCharging" to isCharging))
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Storage ───
                    "getStorageStatus" -> {
                        try {
                            val stat = android.os.StatFs(android.os.Environment.getExternalStorageDirectory().path)
                            val free = stat.availableBlocksLong * stat.blockSizeLong
                            val total = stat.blockCountLong * stat.blockSizeLong
                            result.success(mapOf(
                                "freeBytes" to free,
                                "totalBytes" to total,
                                "freeGB" to String.format("%.1f", free / 1_073_741_824.0),
                                "totalGB" to String.format("%.1f", total / 1_073_741_824.0)
                            ))
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── App Management ───
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            if (intent != null) {
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("NOT_FOUND", "App $packageName not found", null)
                            }
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "getForegroundApp" -> {
                        if (service != null) {
                            val root = service.rootInActiveWindow
                            result.success(root?.packageName?.toString() ?: "unknown")
                        } else {
                            result.error("UNAVAILABLE", "Accessibility Service not active.", null)
                        }
                    }
                    "forceStopApp" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            intent.data = android.net.Uri.parse("package:$packageName")
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                            // Note: cannot directly force stop without system/root, but we can open the settings page
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }

                    // ─── Bluetooth Settings ───
                    "openBluetoothSettings" -> {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        })
                        result.success(true)
                    }

                    // ─── Permissions/Settings ───
                    "openWriteSettingsPermission" -> {
                        startActivity(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        })
                        result.success(true)
                    }

                    // ─── Media Controls ───
                    "mediaPlay" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                        result.success(true)
                    }
                    "mediaNext" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_NEXT))
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_NEXT))
                        result.success(true)
                    }
                    "mediaPrevious" -> {
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
