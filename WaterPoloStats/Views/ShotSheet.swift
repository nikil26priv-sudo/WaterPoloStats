import SwiftUI

/// A shot that is being entered but not saved yet.
/// Started from the pool it has a location but no shooter; started from a cap it is the other way round.
struct ShotDraft: Identifiable {
    let id = UUID()
    var playerID: UUID?
    var outcome: ShotOutcome?
    var situation: Situation
    var period: Int
    var clock: Int
    var assistID: UUID?
    var location: ShotPoint?
}

/// Details for a shot: who took it, the result, the situation, who assisted and where it was from.
struct ShotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: ShotDraft
    let roster: [Player]
    /// True when the shot was started by tapping the pool, so the shooter still has to be picked.
    let choosesShooter: Bool
    var onSave: (ShotDraft) -> Void

    private var shooter: Player? { roster.first { $0.id == draft.playerID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if choosesShooter {
                        section("Who shot?") {
                            CapPicker(players: roster, selection: $draft.playerID)
                        }
                    }

                    section("What happened?") {
                        HStack(spacing: 8) {
                            ForEach(ShotOutcome.allCases) { outcome in
                                ChoiceButton(title: outcome.title, isOn: draft.outcome == outcome, tint: outcome == .goal ? .green : Theme.cap) {
                                    draft.outcome = outcome
                                }
                            }
                        }
                    }

                    Picker("Situation", selection: $draft.situation) {
                        ForEach(Situation.allCases) { Text($0.title()).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if draft.outcome == .goal {
                        section("Assist") {
                            CapPicker(players: roster.filter { $0.id != draft.playerID }, selection: $draft.assistID, allowsNone: true)
                        }
                    }

                    section(choosesShooter ? "Shot from" : "Where was the shot from?") {
                        PoolDiagram(marks: currentMark, markSize: 22) { draft.location = $0 }
                        Text(draft.location == nil ? "Tap the pool to place it, or skip this." : "Tap the pool to move it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("\(shooter?.label ?? "Shot") · \(Game.periodName(draft.period)) \(Format.clock(draft.clock))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.assistID == draft.playerID { draft.assistID = nil }
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.playerID == nil || draft.outcome == nil)
                }
            }
        }
    }

    private var currentMark: [ShotMark] {
        guard let location = draft.location else { return [] }
        return [ShotMark(id: draft.id, point: location, outcome: draft.outcome ?? .saved)]
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }
}

/// A grid of caps to pick one player from.
private struct CapPicker: View {
    let players: [Player]
    @Binding var selection: UUID?
    var allowsNone = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 8)], spacing: 8) {
            if allowsNone {
                ChoiceButton(title: "None", isOn: selection == nil) { selection = nil }
            }
            ForEach(players) { player in
                ChoiceButton(
                    title: "\(player.capNumber)",
                    subtitle: player.name,
                    isOn: selection == player.id,
                    tint: player.isGoalie ? .goalieCap : Theme.cap
                ) {
                    selection = player.id
                }
                .accessibilityLabel(player.label)
            }
        }
    }
}

private struct ChoiceButton: View {
    let title: String
    var subtitle: String?
    let isOn: Bool
    var tint: Color = Theme.cap
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline)
                    .monospacedDigit()
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isOn || isDark ? Color.white : tint)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(isDark ? 0.35 : 0.14)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isOn, isDark {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
