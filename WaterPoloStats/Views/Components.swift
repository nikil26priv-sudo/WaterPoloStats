import SwiftUI
import UIKit

extension Color {
    static let poolWater = Color(red: 0.10, green: 0.52, blue: 0.80)
    static let poolDeep = Color(red: 0.03, green: 0.13, blue: 0.26)
    static let goalieCap = Color(red: 0.80, green: 0.14, blue: 0.16)
}

/// The system share sheet, for sending an exported file.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// A round water polo cap with the player's number on it.
struct CapBadge: View {
    let player: Player
    var size: CGFloat = 30

    var body: some View {
        Text("\(player.capNumber)")
            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(player.isGoalie ? Color.goalieCap : Theme.cap, in: Circle())
            .accessibilityLabel("Cap \(player.capNumber)")
    }
}

/// A large tap target for the stat pad.
struct PadButtonStyle: ButtonStyle {
    var tint: Color = Theme.cap
    var filled = false
    /// Leave nil for the default: taller on iPad than on iPhone.
    var minHeight: CGFloat?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        // Tinted text on a faint tint is unreadable on a dark background, so dark mode uses white on a stronger tint.
        let isDark = colorScheme == .dark
        configuration.label
            .font((sizeClass == .regular && minHeight == nil ? Font.body : Font.subheadline).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: minHeight ?? (sizeClass == .regular ? 68 : 48))
            .padding(.horizontal, 6)
            .foregroundStyle(filled || isDark ? Color.white : tint)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(isDark ? 0.5 : 0.14)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
