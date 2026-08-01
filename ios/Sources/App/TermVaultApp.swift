import SwiftUI
import SwiftData

@main
struct TermVaultApp: App {
    @AppStorage("dev.termvault.settings.appearance") private var appearance = "system"
    @StateObject private var lockService = BiometricLockService()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var navigationStore = AppNavigationStore()
    @StateObject private var agentPresetStore = AgentPresetStore()
    @Environment(\.scenePhase) private var scenePhase

    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([Host.self, Identity.self, Snippet.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

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
