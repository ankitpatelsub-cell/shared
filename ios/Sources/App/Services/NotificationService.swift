import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func agentFinished(_ workspace: WorkspaceSession) async {
        let content = UNMutableNotificationContent()
        content.title = "\(workspace.tool.title) finished"
        content.body = "\(workspace.displayName) on \(workspace.hostLabel) is ready to review."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "workspace-finished-\(workspace.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func agentWaiting(_ workspace: WorkspaceSession) async {
        let content = UNMutableNotificationContent()
        content.title = "\(workspace.tool.title) is waiting for you"
        content.body = "\(workspace.displayName) on \(workspace.hostLabel) has gone idle \u{2014} it may need your input."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "workspace-waiting-\(workspace.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
