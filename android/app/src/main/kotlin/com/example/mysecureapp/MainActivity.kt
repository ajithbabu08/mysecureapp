package com.example.mysecureapp

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.SecureRandom

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.mysecureapp/app_locker"
    private val preferences by lazy {
        getSharedPreferences("app_locker_preferences", MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getApps" -> result.success(getLaunchableApps())
                    "getLockedPackages" -> result.success(
                        preferences.getStringSet(KEY_LOCKED_PACKAGES, emptySet())
                            .orEmpty()
                            .toList()
                    )
                    "setLockedPackages" -> {
                        val packages = call.argument<List<String>>("packages")
                        if (packages == null) {
                            result.error("INVALID_ARGUMENT", "Expected a package list.", null)
                        } else {
                            preferences.edit()
                                .putStringSet(KEY_LOCKED_PACKAGES, packages.toSet())
                                .apply()
                            result.success(null)
                        }
                    }
                    "hasPin" -> result.success(preferences.contains(KEY_PIN_HASH))
                    "setPin" -> {
                        val pin = call.argument<String>("pin")
                        if (pin == null || !PIN_PATTERN.matches(pin)) {
                            result.error("INVALID_PIN", "PIN must contain 4 to 8 digits.", null)
                        } else {
                            savePin(pin)
                            result.success(null)
                        }
                    }
                    "verifyPin" -> {
                        val pin = call.argument<String>("pin")
                        if (pin == null) {
                            result.error("INVALID_ARGUMENT", "Expected a PIN.", null)
                        } else {
                            result.success(verifyPin(pin))
                        }
                    }
                    "hasAccessibilityPermission" -> result.success(
                        isAppLockServiceEnabled()
                    )
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getLaunchableApps(): List<Map<String, String>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = packageManager.queryIntentActivities(
            launcherIntent,
            PackageManager.MATCH_DEFAULT_ONLY
        )
        return apps
            .asSequence()
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { info ->
                mapOf(
                    "packageName" to info.packageName,
                    "name" to info.loadLabel(packageManager).toString()
                        .ifBlank { info.packageName }
                )
            }
            .sortedBy { it["name"]?.lowercase() }
            .toList()
    }

    private fun isAppLockServiceEnabled(): Boolean {
        val expected = ComponentName(this, AppLockAccessibilityService::class.java)
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ).orEmpty()
        return enabledServices.split(':')
            .mapNotNull(ComponentName::unflattenFromString)
            .contains(expected)
    }

    private fun savePin(pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        preferences.edit()
            .putString(KEY_PIN_SALT, PinSecurity.run { salt.toHex() })
            .putString(
                KEY_PIN_HASH,
                PinSecurity.run { hash(pin, salt).toHex() }
            )
            .putInt(KEY_FAILED_ATTEMPTS, 0)
            .putLong(KEY_LOCKOUT_UNTIL, 0L)
            .apply()
    }

    private fun verifyPin(pin: String): Map<String, Any> {
        val remainingSeconds = (
            preferences.getLong(KEY_LOCKOUT_UNTIL, 0L) - System.currentTimeMillis() + 999
        ).coerceAtLeast(0L) / 1000L
        if (remainingSeconds > 0) {
            return mapOf("success" to false, "retryAfterSeconds" to remainingSeconds.toInt())
        }

        val expectedHash = preferences.getString(KEY_PIN_HASH, null)
        val salt = preferences.getString(KEY_PIN_SALT, null)?.let {
            PinSecurity.run { it.hexToBytes() }
        }
        val isValid = expectedHash != null && salt != null && java.security.MessageDigest.isEqual(
            PinSecurity.run { expectedHash.hexToBytes() },
            PinSecurity.hash(pin, salt)
        )
        if (isValid) {
            preferences.edit()
                .putInt(KEY_FAILED_ATTEMPTS, 0)
                .putLong(KEY_LOCKOUT_UNTIL, 0L)
                .apply()
            return mapOf("success" to true, "retryAfterSeconds" to 0)
        }

        val attempts = preferences.getInt(KEY_FAILED_ATTEMPTS, 0) + 1
        val editor = preferences.edit()
        if (attempts >= MAX_FAILED_ATTEMPTS) {
            editor.putInt(KEY_FAILED_ATTEMPTS, 0)
                .putLong(KEY_LOCKOUT_UNTIL, System.currentTimeMillis() + LOCKOUT_MILLIS)
            editor.apply()
            return mapOf("success" to false, "retryAfterSeconds" to LOCKOUT_SECONDS)
        }
        editor.putInt(KEY_FAILED_ATTEMPTS, attempts).apply()
        return mapOf("success" to false, "retryAfterSeconds" to 0)
    }

    companion object {
        internal const val KEY_LOCKED_PACKAGES = "locked_packages"
        internal const val KEY_PIN_HASH = "pin_hash"
        internal const val KEY_PIN_SALT = "pin_salt"
        internal const val KEY_TEMPORARILY_UNLOCKED = "temporarily_unlocked_package"
        private const val KEY_FAILED_ATTEMPTS = "failed_pin_attempts"
        private const val KEY_LOCKOUT_UNTIL = "pin_lockout_until"
        private const val MAX_FAILED_ATTEMPTS = 5
        private const val LOCKOUT_SECONDS = 30
        private const val LOCKOUT_MILLIS = LOCKOUT_SECONDS * 1000L
        private val PIN_PATTERN = Regex("\\d{4,8}")
    }
}
