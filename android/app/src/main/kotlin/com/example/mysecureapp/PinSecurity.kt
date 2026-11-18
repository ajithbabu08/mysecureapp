package com.example.mysecureapp

import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

internal object PinSecurity {
    private const val ITERATIONS = 120_000
    private const val KEY_LENGTH_BITS = 256

    fun hash(pin: String, salt: ByteArray): ByteArray {
        val keySpec = PBEKeySpec(pin.toCharArray(), salt, ITERATIONS, KEY_LENGTH_BITS)
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA1")
                .generateSecret(keySpec)
                .encoded
        } finally {
            keySpec.clearPassword()
        }
    }

    fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    fun String.hexToBytes(): ByteArray {
        require(length % 2 == 0) { "Invalid hexadecimal value." }
        return chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }
}
