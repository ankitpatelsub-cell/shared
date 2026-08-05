import Foundation

/// Settings for auto-approval of SSH operations
final class AutoApproveSettings {
    static let shared = AutoApproveSettings()

    private let defaults: UserDefaults
    private let autoApproveHostKeysKey = "dev.termvault.autoApprove.hostKeys"
    private let autoApproveMultilinePasteKey = "dev.termvault.autoApprove.multilinePaste"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Auto-approve new SSH host keys (Trust-On-First-Use)
    var autoApproveHostKeys: Bool {
        get { defaults.bool(forKey: autoApproveHostKeysKey) }
        set { defaults.set(newValue, forKey: autoApproveHostKeysKey) }
    }

    /// Auto-approve multi-line paste operations
    var autoApproveMultilinePaste: Bool {
        get { defaults.bool(forKey: autoApproveMultilinePasteKey) }
        set { defaults.set(newValue, forKey: autoApproveMultilinePasteKey) }
    }
}
