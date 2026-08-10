package dev.termvault.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dev.termvault.app.ui.AppRoot
import dev.termvault.app.ui.theme.TermVaultTheme

/**
 * Extends [FragmentActivity] (not a plain `ComponentActivity`) because
 * [dev.termvault.app.security.BiometricLockService] constructs a
 * `BiometricPrompt` against it, and `BiometricPrompt`'s constructor requires
 * a `FragmentActivity` — `FragmentActivity` itself extends
 * `androidx.activity.ComponentActivity`, so Compose's `setContent` still
 * works unchanged.
 */
class MainActivity : FragmentActivity() {
    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* no-op either way */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestNotificationPermissionIfNeeded()
        val app = TermVaultApplication.from(this)
        setContent {
            TermVaultTheme {
                AppRoot(app, this)
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}
