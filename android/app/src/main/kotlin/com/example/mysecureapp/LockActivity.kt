package com.example.mysecureapp

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.text.InputFilter
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import java.security.MessageDigest

class LockActivity : Activity() {
    private val preferences by lazy {
        getSharedPreferences("app_locker_preferences", MODE_PRIVATE)
    }
    private lateinit var pinField: EditText
    private lateinit var message: TextView
    private lateinit var targetPackage: String
    private var isPinVisible = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        targetPackage = intent.getStringExtra(EXTRA_PACKAGE_NAME).orEmpty()
        if (targetPackage.isBlank()) {
            finish()
            return
        }
        showLockScreen()
    }

    private fun showLockScreen() {
        val appLabel = intent.getStringExtra(EXTRA_APP_LABEL).orEmpty()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(28), dp(28), dp(28))
            setBackgroundColor(Color.rgb(16, 24, 45))
        }

        val icon = TextView(this).apply {
            text = "●"
            textSize = 34f
            setTextColor(Color.rgb(83, 109, 254))
            gravity = Gravity.CENTER
        }
        root.addView(icon, fullWidthParams())

        val title = TextView(this).apply {
            text = "$appLabel is locked"
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(8))
        }
        root.addView(title, fullWidthParams())

        val subtitle = TextView(this).apply {
            text = "Enter your PIN to continue"
            textSize = 15f
            setTextColor(Color.rgb(190, 199, 219))
            gravity = Gravity.CENTER
        }
        root.addView(subtitle, fullWidthParams())

        pinField = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or
                InputType.TYPE_NUMBER_VARIATION_PASSWORD
            imeOptions = EditorInfo.IME_ACTION_DONE
            hint = "PIN"
            gravity = Gravity.CENTER
            textSize = 20f
            setTextColor(Color.WHITE)
            setHintTextColor(Color.rgb(160, 170, 192))
            setSingleLine(true)
            filters = arrayOf(InputFilter.LengthFilter(8))
            setPadding(dp(14), dp(12), dp(14), dp(12))
            setBackgroundColor(Color.rgb(36, 48, 76))
        }
        val pinEntry = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.rgb(36, 48, 76))
        }
        pinEntry.addView(
            pinField,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        val visibilityToggle = TextView(this).apply {
            text = "Show"
            textSize = 14f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(dp(12), dp(12), dp(16), dp(12))
            setOnClickListener {
                isPinVisible = !isPinVisible
                val selection = pinField.selectionStart.coerceAtLeast(0)
                pinField.inputType = if (isPinVisible) {
                    InputType.TYPE_CLASS_NUMBER
                } else {
                    InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
                }
                pinField.setTextColor(Color.WHITE)
                pinField.setSelection(selection.coerceAtMost(pinField.length()))
                text = if (isPinVisible) "Hide" else "Show"
            }
        }
        pinEntry.addView(
            visibilityToggle,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val fieldParams = fullWidthParams().apply {
            topMargin = dp(26)
        }
        root.addView(pinEntry, fieldParams)

        message = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.rgb(195, 46, 46))
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
        }
        root.addView(message, fullWidthParams())

        val unlockButton = Button(this).apply {
            text = "Unlock"
            setOnClickListener { tryUnlock() }
        }
        val buttonParams = fullWidthParams().apply {
            topMargin = dp(20)
        }
        root.addView(unlockButton, buttonParams)
        pinField.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                tryUnlock()
                true
            } else {
                false
            }
        }

        setContentView(root)
        pinField.requestFocus()
    }

    private fun tryUnlock() {
        val remainingSeconds = (
            preferences.getLong(KEY_LOCKOUT_UNTIL, 0L) -
                System.currentTimeMillis() + 999
        ).coerceAtLeast(0L) / 1000L
        if (remainingSeconds > 0) {
            message.text = "Too many attempts. Try again in $remainingSeconds seconds."
            return
        }

        val enteredPin = pinField.text.toString()
        val expectedHash = preferences.getString(MainActivity.KEY_PIN_HASH, null)
        val salt = preferences.getString(MainActivity.KEY_PIN_SALT, null)?.let {
            PinSecurity.run { it.hexToBytes() }
        }
        val isValid = expectedHash != null && salt != null && MessageDigest.isEqual(
            PinSecurity.run { expectedHash.hexToBytes() },
            PinSecurity.hash(enteredPin, salt)
        )
        if (isValid) {
            preferences.edit()
                .putString(MainActivity.KEY_TEMPORARILY_UNLOCKED, targetPackage)
                .putInt(KEY_FAILED_ATTEMPTS, 0)
                .putLong(KEY_LOCKOUT_UNTIL, 0L)
                .apply()
            finish()
            return
        }

        val attempts = preferences.getInt(KEY_FAILED_ATTEMPTS, 0) + 1
        val editor = preferences.edit()
        if (attempts >= MAX_FAILED_ATTEMPTS) {
            editor.putInt(KEY_FAILED_ATTEMPTS, 0)
                .putLong(KEY_LOCKOUT_UNTIL, System.currentTimeMillis() + LOCKOUT_MILLIS)
            editor.apply()
            message.text = "Too many attempts. Try again in $LOCKOUT_SECONDS seconds."
        } else {
            editor.putInt(KEY_FAILED_ATTEMPTS, attempts).apply()
            message.text = "Incorrect PIN. Try again."
        }
        pinField.text.clear()
    }

    override fun onBackPressed() = Unit

    private fun fullWidthParams() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    )

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_PACKAGE_NAME = "package_name"
        const val EXTRA_APP_LABEL = "app_label"
        private const val KEY_FAILED_ATTEMPTS = "failed_pin_attempts"
        private const val KEY_LOCKOUT_UNTIL = "pin_lockout_until"
        private const val MAX_FAILED_ATTEMPTS = 5
        private const val LOCKOUT_SECONDS = 30
        private const val LOCKOUT_MILLIS = LOCKOUT_SECONDS * 1000L
    }
}
