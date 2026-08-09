import Foundation

/// Bridges a notification tap (handled by `AppDelegate`, outside SwiftUI)
/// into the view hierarchy. `RootTabView` observes `pendingWorkspaceID` and
/// switches to that session's tab when it's set.
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    @Published var pendingWorkspaceID: UUID?
    // Set alongside `pendingWorkspaceID` only when a "finished" (not
    // "waiting") notification was tapped — the natural next action after
    // an agent finishes is almost always "show me what changed".
    @Published var pendingDiffWorkspaceID: UUID?
    // Set by App Intents (Shortcuts/Siri) to request a tab switch — a
    // second, simpler channel than `pendingWorkspaceID` since an intent
    // like "open my sessions" has no specific workspace to target.
    @Published var pendingTab: RootTab?

    private init() {}
}
