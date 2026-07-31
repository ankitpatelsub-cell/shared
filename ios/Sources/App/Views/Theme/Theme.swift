import SwiftUI

/// Shared design tokens. One place to change corner radii, spacing, and
/// status colors instead of magic numbers scattered across every view —
/// the difference between a screen that was styled once and a UI that
/// reads as one coherent system.
enum Theme {
    static let cornerRadius: CGFloat = 16
    static let controlCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12

    enum Status {
        static func color(for status: ConnectionStatus) -> Color {
            switch status {
            case .connected: return .green
            case .connecting: return .yellow
            case .disconnected: return .secondary
            case .failed: return .red
            }
        }
    }
}

extension View {
    /// The card surface used for host rows, identity rows, and anywhere
    /// else content needs to read as a distinct, tappable unit rather than
    /// a bare list row.
    func cardBackground() -> some View {
        self
            .padding(Theme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(.background.secondary)
            )
    }
}

/// A deterministic colored initials badge, the same visual shorthand
/// Termius/Blink/most modern host managers use so a long list of servers
/// is scannable at a glance instead of a wall of identical icons. Same
/// host label always produces the same color — no state, no persistence
/// needed, just a stable hash.
struct HostAvatarView: View {
    let label: String
    var size: CGFloat = 40

    private var initials: String {
        let words = label
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let result = String(words).uppercased()
        return result.isEmpty ? "?" : result
    }

    private var gradient: LinearGradient {
        let hue = Self.hue(for: label)
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.62, brightness: 0.78),
                Color(hue: hue, saturation: 0.72, brightness: 0.56),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Circle()
            .fill(gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    private static func hue(for label: String) -> Double {
        var hasher = Hasher()
        hasher.combine(label)
        let hashValue = abs(hasher.finalize())
        return Double(hashValue % 360) / 360.0
    }
}
