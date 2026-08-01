import Foundation

enum RootTab: Hashable {
    case hosts
    case browser
    case sessions
    case keys
    case settings
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab: RootTab = .hosts
}
