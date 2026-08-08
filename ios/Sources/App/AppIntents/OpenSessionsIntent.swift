import AppIntents

/// "Hey Siri, open TermVault sessions" / a Shortcuts action. iOS 16+'s
/// code-only `AppIntent` + `AppShortcutsProvider` — no legacy
/// `.intentdefinition` file or extension target needed, just app-target
/// Swift.
struct OpenSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sessions"
    static var description = IntentDescription("Opens TermVault to your active terminal sessions.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationRouter.shared.pendingTab = .sessions
        return .result()
    }
}

struct TermVaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSessionsIntent(),
            phrases: [
                "Open \(.applicationName) sessions",
                "Show my \(.applicationName) sessions"
            ],
            shortTitle: "Open Sessions",
            systemImageName: "terminal"
        )
    }
}
