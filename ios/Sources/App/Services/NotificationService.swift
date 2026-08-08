import Foundation
import UserNotifications

enum NotificationService {
    static let waitingCategoryID = "AGENT_WAITING"
    static let finishedCategoryID = "AGENT_FINISHED"
    static let continueActionID = "AGENT_CONTINUE_ACTION"
    static let cancelActionID = "AGENT_CANCEL_ACTION"

    static let workspaceIDKey = "workspaceID"
    static let hostIDKey = "hostID"
    static let tmuxNameKey = "tmuxName"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Registers the action buttons a "waiting" notification can carry
    /// (Continue → Enter, Cancel → Esc) directly on the tmux pane, without
    /// requiring the app to be foregrounded — as long as the process is
    /// still alive with an existing SSH connection to that host. Call once
    /// at launch, before any notification using these categories is shown.
    static func registerCategories() {
        let continueAction = UNNotificationAction(
            identifier: continueActionID, title: "Continue", options: []
        )
        let cancelAction = UNNotificationAction(
            identifier: cancelActionID, title: "Cancel", options: [.destructive]
        )
        let waiting = UNNotificationCategory(
            identifier: waitingCategoryID,
            actions: [continueAction, cancelAction],
            intentIdentifiers: [],
            options: []
        )
        let finished = UNNotificationCategory(
            identifier: finishedCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([waiting, finished])
    }

    static func agentFinished(_ workspace: WorkspaceSession) async {
        let content = UNMutableNotificationContent()
        content.title = "\(workspace.tool.title) finished"
        content.body = "\(workspace.displayName) on \(workspace.hostLabel) is ready to review."
        content.sound = .default
        content.categoryIdentifier = finishedCategoryID
        content.userInfo = [
            workspaceIDKey: workspace.id.uuidString,
            hostIDKey: workspace.hostID.uuidString,
            tmuxNameKey: workspace.tmuxName
        ]
        let request = UNNotificationRequest(identifier: "workspace-finished-\(workspace.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func agentWaiting(_ workspace: WorkspaceSession) async {
        let content = UNMutableNotificationContent()
        content.title = "\(workspace.tool.title) is waiting for you"
        content.body = "\(workspace.displayName) on \(workspace.hostLabel) has gone idle \u{2014} it may need your input."
        content.sound = .default
        content.categoryIdentifier = waitingCategoryID
        content.userInfo = [
            workspaceIDKey: workspace.id.uuidString,
            hostIDKey: workspace.hostID.uuidString,
            tmuxNameKey: workspace.tmuxName
        ]
        let request = UNNotificationRequest(identifier: "workspace-waiting-\(workspace.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Sends the key implied by a notification action straight into the
    /// tmux pane over a plain exec command — this deliberately doesn't go
    /// through the interactive `SSHSessionManager`/`TerminalViewModel` pty
    /// session, since the action can fire without that session being open;
    /// `RemoteCommandService` only needs *some* existing SSH connection to
    /// the host to already be alive in this process.
    static func handleAction(_ actionID: String, userInfo: [AnyHashable: Any]) async {
        guard let hostIDString = userInfo[hostIDKey] as? String,
              let hostID = UUID(uuidString: hostIDString),
              let tmuxName = userInfo[tmuxNameKey] as? String else { return }
        let key: String
        switch actionID {
        case continueActionID: key = "Enter"
        case cancelActionID: key = "Escape"
        default: return
        }
        let name = shellQuote(tmuxName)
        _ = try? await RemoteCommandService.shared.run(
            hostID: hostID,
            command: "tmux send-keys -t \(name) \(key) 2>/dev/null || true"
        )
    }

    // Duplicated rather than reusing ProjectDashboardViewModel.quote: that
    // type is @MainActor-isolated, and handleAction() runs off the main
    // actor (invoked from AppDelegate's notification-response callback).
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
