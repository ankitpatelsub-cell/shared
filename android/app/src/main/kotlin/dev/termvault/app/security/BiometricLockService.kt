package dev.termvault.app.security

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * App-level lock gating the whole UI, independent of any per-connection
 * auth — mirrors iOS `BiometricLockService.swift`. Uses
 * [BiometricManager.Authenticators.BIOMETRIC_WEAK or DEVICE_CREDENTIAL] so a
 * device with no biometric enrolled still gets a PIN/pattern/password
 * fallback, matching the iOS behavior of falling back to the passcode.
 */
class BiometricLockService(private val context: Context) {
    private val prefs = context.getSharedPreferences("dev.termvault.settings", Context.MODE_PRIVATE)

    private val _isUnlocked = MutableStateFlow(false)
    val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()

    var isBiometricLockEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    private val authenticators =
        BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL

    suspend fun authenticateIfNeeded(activity: FragmentActivity) {
        if (!isBiometricLockEnabled) {
            _isUnlocked.value = true
            return
        }
        authenticate(activity)
    }

    suspend fun authenticate(activity: FragmentActivity) {
        val manager = BiometricManager.from(context)
        if (manager.canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            // No biometrics/passcode configured on this device — don't lock
            // the user out of an app they have no way to unlock.
            _isUnlocked.value = true
            return
        }

        val success = suspendCoroutine { continuation ->
            val executor = ContextCompat.getMainExecutor(context)
            val prompt = BiometricPrompt(
                activity,
                executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        continuation.resume(true)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        continuation.resume(false)
                    }

                    override fun onAuthenticationFailed() {
                        // A single failed attempt (e.g. wrong fingerprint) —
                        // let the prompt keep retrying rather than resolving.
                    }
                },
            )
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Unlock TermVault")
                .setAllowedAuthenticators(authenticators)
                .build()
            prompt.authenticate(info)
        }

        _isUnlocked.value = success
    }

    fun lock() {
        if (isBiometricLockEnabled) {
            _isUnlocked.value = false
        }
    }

    companion object {
        private const val KEY_ENABLED = "dev.termvault.settings.biometricLockEnabled"
    }
}
