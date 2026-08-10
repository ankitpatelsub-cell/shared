package com.termux.terminal;

/**
 * Vendored (Apache 2.0, from termux/termux-app's terminal-emulator module —
 * see android/THIRD_PARTY_NOTICES.md) and trimmed for TermVault: the
 * original interface's methods are typed against a {@code TerminalSession}
 * class (the one that spawns a local shell via JNI) that this app
 * deliberately does not use, since it drives the terminal from an SSH
 * channel instead of a local process. Verified against
 * {@code TerminalEmulator.java}'s actual `mClient.*` call sites that only
 * {@link #getTerminalCursorStyle()}, {@link #onTerminalCursorStateChange},
 * and the log* methods are ever invoked by the emulator itself — the
 * methods keyed to `TerminalSession` were only ever called *by*
 * `TerminalSession`, which this app never constructs. Removed rather than
 * stubbed out, so there's no unused, never-satisfiable `TerminalSession`
 * type dependency at all.
 */
public interface TerminalSessionClient {

    void onTerminalCursorStateChange(boolean state);

    Integer getTerminalCursorStyle();

    void logError(String tag, String message);

    void logWarn(String tag, String message);

    void logInfo(String tag, String message);

    void logDebug(String tag, String message);

    void logVerbose(String tag, String message);

    void logStackTraceWithMessage(String tag, String message, Exception e);

    void logStackTrace(String tag, Exception e);

}
