package dev.termvault.app.terminal

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import com.termux.terminal.KeyHandler
import com.termux.terminal.TerminalEmulator
import com.termux.view.TerminalRenderer
import dev.termvault.app.ssh.SshSessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.max

/**
 * Custom [View] hosting one vendored [TerminalEmulator], rendered via the
 * vendored [TerminalRenderer] and fed bytes from a live SSH shell. Mirrors
 * iOS's `SwiftTerm`-backed `TerminalHostingView`, but on top of Termux's
 * pure-Java VT100 engine instead.
 *
 * Scrollback browsing (dragging to view prior output) is out of scope for
 * this pass — [topRow] is always 0 (bottom of the live screen), matching
 * the default state of iOS's terminal view before a user scrolls up.
 */
class TerminalEmulatorView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private var emulator: TerminalEmulator? = null
    private var terminalOutput: SshTerminalOutput? = null
    private var renderer: TerminalRenderer = TerminalRenderer(DEFAULT_TEXT_SIZE_PX, Typeface.MONOSPACE)
    private val mainHandler = Handler(Looper.getMainLooper())

    // TerminalRenderer's own font-metric fields are package-private to
    // com.termux.view, so cell size is measured independently here with an
    // identically-configured Paint rather than modifying vendored source.
    private val metricsPaint = Paint().apply {
        isAntiAlias = true
        typeface = Typeface.MONOSPACE
    }
    private var fontWidthPx: Float = 1f
    private var fontLineSpacingPx: Int = 1

    private var connectionId: UUID? = null
    private var sessionManager: SshSessionManager? = null
    private var scope: CoroutineScope? = null

    var textSizePx: Int = DEFAULT_TEXT_SIZE_PX
        set(value) {
            field = value
            renderer = TerminalRenderer(value, Typeface.MONOSPACE)
            updateMetrics()
            requestResize()
            invalidate()
        }

    private fun updateMetrics() {
        metricsPaint.textSize = textSizePx.toFloat()
        fontWidthPx = metricsPaint.measureText("X")
        fontLineSpacingPx = kotlin.math.ceil(metricsPaint.fontSpacing).toInt().coerceAtLeast(1)
    }

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        updateMetrics()
    }

    /** Wires this view up to a live (already-connected) SSH session. */
    fun attach(
        connectionId: UUID,
        sessionManager: SshSessionManager,
        scope: CoroutineScope,
        onTitleChanged: (String) -> Unit = {},
        onBell: () -> Unit = {},
    ) {
        this.connectionId = connectionId
        this.sessionManager = sessionManager
        this.scope = scope

        val output = SshTerminalOutput(context.applicationContext, connectionId, sessionManager, scope, onTitleChanged, onBell)
        terminalOutput = output

        val columns = max(1, (width / fontWidthPx).toInt())
        val rows = max(1, height / fontLineSpacingPx)
        emulator = TerminalEmulator(output, columns, rows, 0, 0, 10_000, TermVaultTerminalClient())
        requestFocus()
        invalidate()
    }

    fun detach() {
        emulator = null
        terminalOutput = null
        connectionId = null
        sessionManager = null
        scope = null
    }

    /** Feeds incoming SSH stdout/stderr bytes into the emulator. Safe to call from any thread. */
    fun feed(data: ByteArray) {
        mainHandler.post {
            emulator?.append(data, data.size)
            invalidate()
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        requestResize()
    }

    private fun requestResize() {
        val em = emulator ?: return
        val columns = max(1, (width / fontWidthPx).toInt())
        val rows = max(1, height / fontLineSpacingPx)
        if (columns == em.mColumns && rows == em.mRows) return
        em.resize(columns, rows, 0, 0)
        val id = connectionId
        val manager = sessionManager
        scope?.launch {
            if (id != null && manager != null) {
                runCatching { manager.resize(id, columns, rows) }
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        val em = emulator ?: return
        renderer.render(em, canvas, 0, -1, -1, -1, -1)
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = EditorInfo.TYPE_NULL
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_FLAG_NO_EXTRACT_UI
        return object : BaseInputConnection(this, true) {
            override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean {
                sendRaw(text.toString())
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                repeat(beforeLength) { sendRaw("") }
                return true
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean {
                if (event.action == KeyEvent.ACTION_DOWN) return dispatchKeyEvent(event)
                return true
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return super.dispatchKeyEvent(event)
        val em = emulator ?: return super.dispatchKeyEvent(event)

        var keyMod = 0
        if (event.isShiftPressed) keyMod = keyMod or KeyHandler.KEYMOD_SHIFT
        if (event.isCtrlPressed) keyMod = keyMod or KeyHandler.KEYMOD_CTRL
        if (event.isAltPressed) keyMod = keyMod or KeyHandler.KEYMOD_ALT

        val code = KeyHandler.getCode(event.keyCode, keyMod, em.isCursorKeysApplicationMode, em.isKeypadApplicationMode)
        if (code != null) {
            sendRaw(code)
            return true
        }

        if (event.isCtrlPressed && event.keyCode in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) {
            val letterIndex = event.keyCode - KeyEvent.KEYCODE_A
            sendRaw((letterIndex + 1).toChar().toString())
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    /** Sends raw already-encoded terminal input (typed text or an escape sequence) to the SSH shell. */
    fun sendRaw(text: String) {
        val id = connectionId ?: return
        val manager = sessionManager ?: return
        scope?.launch { runCatching { manager.send(id, text) } }
    }

    companion object {
        private const val DEFAULT_TEXT_SIZE_PX = 32
    }
}
