package dev.termvault.app.data.model

enum class HostAuthMethod(val rawValue: String, val displayName: String) {
    PASSWORD("password", "Password"),
    PRIVATE_KEY("privateKey", "SSH Key"),
    NONE("none", "None");

    companion object {
        fun from(rawValue: String): HostAuthMethod =
            entries.firstOrNull { it.rawValue == rawValue } ?: PASSWORD
    }
}

enum class IdentityKeyType(val rawValue: String, val displayName: String) {
    RSA4096("rsa4096", "RSA 4096"),
    ED25519("ed25519", "Ed25519");

    companion object {
        fun from(rawValue: String): IdentityKeyType =
            entries.firstOrNull { it.rawValue == rawValue } ?: ED25519
    }
}

enum class AgentTool(val rawValue: String, val title: String, val executable: String?) {
    CODEX("codex", "Codex", "codex"),
    CLAUDE("claude", "Claude", "claude"),
    HERMES("hermes", "Hermes", "hermes"),
    SHELL("shell", "Shell", null);

    companion object {
        fun from(rawValue: String): AgentTool =
            entries.firstOrNull { it.rawValue == rawValue } ?: SHELL
    }
}

enum class SyncDirection(val rawValue: String, val displayName: String) {
    LOCAL_TO_REMOTE("l2r", "Local → Remote"),
    REMOTE_TO_LOCAL("r2l", "Remote → Local"),
    BIDIRECTIONAL("both", "Bidirectional");

    companion object {
        fun from(rawValue: String): SyncDirection =
            entries.firstOrNull { it.rawValue == rawValue } ?: BIDIRECTIONAL
    }
}
