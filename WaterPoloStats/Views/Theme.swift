import SwiftUI

/// Colours and shared building blocks for the dark, panel-based look.
enum Theme {
    static let chrome = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let raised = Color(red: 0.17, green: 0.17, blue: 0.20)
    static let line = Color.white.opacity(0.12)
    static let orange = Color(red: 0.96, green: 0.48, blue: 0.22)
    static let made = Color(red: 0.40, green: 0.60, blue: 0.30)
    static let missed = Color(red: 0.66, green: 0.20, blue: 0.20)
    static let steel = Color(red: 0.22, green: 0.36, blue: 0.48)
    static let tile = Color(red: 0.26, green: 0.27, blue: 0.30)
    static let cap = Color(red: 0.0, green: 0.42, blue: 0.78)
    static let rowSelected = Color(red: 0.83, green: 0.86, blue: 0.91)
    static let scoreRed = Color(red: 0.86, green: 0.36, blue: 0.40)
}

/// The bar across the top of a section: an action on the left, the title in the middle, actions on the right.
struct TopBar<Leading: View, Trailing: View>: View {
    let title: String
    var showsBack = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 18) {
                if showsBack {
                    Button("Back", systemImage: "chevron.left") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                leading
                Spacer(minLength: 120)
                trailing
            }
            .font(.callout)
            .tint(Theme.orange)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

/// A white table with a dark header strip, sitting on the dark background.
struct TablePanel<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.30)], startPoint: .top, endPoint: .bottom))
            ScrollView {
                LazyVStack(spacing: 0) { content }
            }
            .background(Color.white)
        }
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }
}

/// One row of a `TablePanel`, with the optional red delete button shown while editing.
struct TableRow<Content: View>: View {
    var isEditing = false
    var onDelete: (() -> Void)?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            if isEditing, let onDelete {
                Button("Delete", systemImage: "minus.circle.fill", action: onDelete)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
            }
            content
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(LinearGradient(colors: [.white, Color(white: 0.94)], startPoint: .top, endPoint: .bottom))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .overlay(alignment: .bottom) { Color.black.opacity(0.08).frame(height: 1) }
    }
}

/// The raised, coloured buttons of the stat pad.
struct GlossButtonStyle: ButtonStyle {
    var color: Color = Theme.steel
    var selected = false
    var height: CGFloat = 46
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.78), color], startPoint: .top, endPoint: .bottom))
                    .brightness(configuration.isPressed ? -0.12 : (selected ? 0.12 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.white : Color.black.opacity(0.35), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// A small heading with a rule on each side, used between groups of buttons.
struct GroupLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Theme.line.frame(height: 1)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize()
            Theme.line.frame(height: 1)
        }
    }
}

/// Text drawn as lit dots on a dark board, like a pool-side scoreboard.
struct DotMatrixText: View {
    let text: String
    var dot: CGFloat = 4

    // 5 x 7 glyphs, one string per row.
    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
    ]

    var body: some View {
        let glyphs = text.compactMap { Self.glyphs[$0] }
        let columns = glyphs.reduce(0) { $0 + $1[0].count + 1 } - 1
        Canvas { context, _ in
            var x = 0
            for glyph in glyphs {
                for (row, line) in glyph.enumerated() {
                    for (column, bit) in line.enumerated() {
                        let rect = CGRect(x: CGFloat(x + column) * dot, y: CGFloat(row) * dot, width: dot, height: dot).insetBy(dx: dot * 0.12, dy: dot * 0.12)
                        context.fill(Path(ellipseIn: rect), with: .color(bit == "1" ? .white : Color.white.opacity(0.07)))
                    }
                }
                x += glyph[0].count + 1
            }
        }
        .frame(width: CGFloat(max(columns, 0)) * dot, height: 7 * dot)
        .accessibilityLabel(text)
    }
}
