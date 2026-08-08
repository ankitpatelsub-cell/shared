import SwiftUI
import SwiftData

@main
struct TermVaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("dev.termvault.settings.appearance") private var appearance = "system"
    @StateObject private var lockService = BiometricLockService()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var navigationStore = AppNavigationStore()
    @StateObject private var agentPresetStore = AgentPresetStore()
    @Environment(\.scenePhase) private var scenePhase

    private var sharedModelContainer: ModelContainer = Self.makeModelContainer()

    // Was a bare `fatalError` on any init failure — reachable by ordinary
    // user-side conditions (storage full at first launch, an on-disk store
    // corrupted by a prior force-quit mid-write, or a schema incompatible
    // with a prior app version after an update), turning any of those into
    // a permanent launch-crash loop. Now attempts to recreate the store,
    // and only gives up the saved data (falling back to in-memory) rather
    // than terminating the process.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([Host.self, Identity.self, Snippet.self, WorkspaceProject.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            ErrorLogger.shared.log(
                category: .general,
                message: "SwiftData store failed to load — attempting recovery",
                technicalDetails: "\(error)"
            )
            if FileManager.default.fileExists(atPath: configuration.url.path) {
                try? FileManager.default.removeItem(at: configuration.url)
            }
            if let recovered = try? ModelContainer(for: schema, configurations: [configuration]) {
                return recovered
            }
            ErrorLogger.shared.log(
                category: .general,
                message: "Falling back to in-memory storage — saved hosts and identities could not be recovered",
                technicalDetails: "\(error)"
            )
            let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let fallback = try? ModelContainer(for: schema, configurations: [inMemoryConfiguration]) else {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
            return fallback
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environmentObject(sessionStore)
                    .environmentObject(workspaceStore)
                    .environmentObject(navigationStore)
                    .environmentObject(agentPresetStore)
                    .environmentObject(lockService)

                if !lockService.isUnlocked {
                    LockScreenView()
                        .environmentObject(lockService)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: lockService.isUnlocked)
            .preferredColorScheme(preferredColorScheme)
            .task {
                await lockService.authenticateIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    lockService.lock()
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
