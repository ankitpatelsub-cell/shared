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
    private(set) var previousTab: RootTab = .hosts

    func navigate(to tab: RootTab) {
        guard tab != selectedTab else { return }
        previousTab = selectedTab
        selectedTab = tab
    }

    func goBack(fallback: RootTab = .hosts) {
        let destination = previousTab == .sessions ? fallback : previousTab
        previousTab = selectedTab
        selectedTab = destination
    }
}
