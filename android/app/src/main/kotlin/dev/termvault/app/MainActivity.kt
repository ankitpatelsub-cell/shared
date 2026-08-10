package dev.termvault.app

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = TermVaultApplication.from(this)
        setContent {
            TermVaultTheme {
                AppRoot(app, this)
            }
        }
    }
}
