import UIKit
import UserNotifications

/// Two things SwiftUI's `App` protocol has no hook for:
///   1. Local notifications are silently swallowed while the app is in the
///      foreground unless a `UNUserNotificationCenterDelegate` explicitly
///      opts back in via `willPresent`. Since agent-completion notifications
///      are fired from a poll loop that only runs while the app itself is
///      foregrounded (see `WorkspaceStore.checkForCompletions`), without
///      this delegate those notifications had no path to ever be seen.
///   2. Handling a tap or action button on a delivered notification.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // The user tapped the notification body itself (not an action
            // button) — route to that workspace's session if it's open.
            if let idString = userInfo[NotificationService.workspaceIDKey] as? String,
               let id = UUID(uuidString: idString) {
                Task { @MainActor in NotificationRouter.shared.pendingWorkspaceID = id }
            }
        case NotificationService.continueActionID, NotificationService.cancelActionID:
            Task { await NotificationService.handleAction(response.actionIdentifier, userInfo: userInfo) }
        default:
            break
        }
        completionHandler()
    }
}
