package dev.termvault.app.util

/** POSIX single-quote escaping for interpolating a value into a remote shell command. */
object ShellQuote {
    fun quote(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}
