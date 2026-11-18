package com.example.mysecureapp

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import android.util.Log

class AppLockAccessibilityService : AccessibilityService() {
    private val preferences by lazy {
        getSharedPreferences("app_locker_preferences", MODE_PRIVATE)
    }
    private var keyboardPackages: Set<String> = emptySet()

    override fun onServiceConnected() {
        super.onServiceConnected()
        val inputMethodManager = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        keyboardPackages = inputMethodManager.enabledInputMethodList
            .map { it.packageName }
            .toSet()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val openedPackage = event?.packageName?.toString() ?: return
        if (openedPackage in keyboardPackages) return

        if (openedPackage == packageName) {
            val isLockScreen = event.className?.toString()
                ?.contains("LockActivity") == true
            if (!isLockScreen) {
                preferences.edit().remove(MainActivity.KEY_TEMPORARILY_UNLOCKED).apply()
            }
            return
        }

        val lockedPackages = preferences.getStringSet(
            MainActivity.KEY_LOCKED_PACKAGES,
            emptySet()
        ).orEmpty()
        val temporarilyUnlocked = preferences.getString(
            MainActivity.KEY_TEMPORARILY_UNLOCKED,
            null
        )
        if (temporarilyUnlocked != null) {
            if (temporarilyUnlocked == openedPackage) return
            preferences.edit().remove(MainActivity.KEY_TEMPORARILY_UNLOCKED).apply()
        }

        if (openedPackage !in lockedPackages ||
            !preferences.contains(MainActivity.KEY_PIN_HASH)
        ) {
            return
        }

        val label = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(openedPackage, 0)
            ).toString()
        } catch (error: PackageManager.NameNotFoundException) {
            Log.w(TAG, "Could not read label for protected app $openedPackage", error)
            openedPackage
        }

        startActivity(
            Intent(this, LockActivity::class.java)
                .putExtra(LockActivity.EXTRA_PACKAGE_NAME, openedPackage)
                .putExtra(LockActivity.EXTRA_APP_LABEL, label)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        )
    }

    override fun onInterrupt() = Unit

    companion object {
        private const val TAG = "AppLockService"
    }
}
