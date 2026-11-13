import SwiftUI

/// Play-by-play, newest first. Swipe to delete an event, or tap one to fix it.
struct PlaysView: View {
    @Environment(Store.self) private var store
    @Binding var game: Game

    @State private var editing: GameEvent?

    var body: some View {
        let scores = runningScores()
        let periods = Set(game.events.map(\.period)).sorted(by: >)

        if game.events.isEmpty {
            ContentUnavailableView("No plays yet", systemImage: "list.bullet", description: Text("Everything you record shows up here."))
        } else {
            List {
                ForEach(periods, id: \.self) { period in
                    Section(Game.periodName(period)) {
                        ForEach(events(in: period)) { event in
                            Button { editing = event } label: {
                                row(event, score: scores[event.id])
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    game.events.removeAll { $0.id == event.id }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .sheet(item: $editing) { event in
                EventEditor(event: event, roster: store.roster(for: game)) { updated in
                    if let index = game.events.firstIndex(where: { $0.id == updated.id }) {
                        game.events[index] = updated
                    }
                }
            }
        }
    }

    private func events(in period: Int) -> [GameEvent] {
        game.chronologicalEvents.filter { $0.period == period }.reversed()
    }

    /// The score right after each goal.
    private func runningScores() -> [UUID: String] {
        var ours = 0
        var theirs = 0
        var scores: [UUID: String] = [:]
        for event in game.chronologicalEvents {
            if event.isGoal { ours += 1 } else if event.kind == .goalAgainst { theirs += 1 } else { continue }
            scores[event.id] = "\(ours)–\(theirs)"
        }
        return scores
    }

    private func row(_ event: GameEvent, score: String?) -> some View {
        HStack(spacing: 12) {
            Text(Format.clock(event.clock))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(event.summary(name: { store.playerLabel($0) }))
                .fontWeight(score == nil ? .regular : .semibold)
            Spacer(minLength: 8)
            if let score {
                Text(score)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(event.isGoal ? Color.green : Color.red)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Fixes for a recorded event: who it was, and for shots the result, situation and assist.
struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var event: GameEvent
    let roster: [Player]
    var onSave: (GameEvent) -> Void

    private var maxMinutes: Int { max(8, event.clock / 60) }

    var body: some View {
        NavigationStack {
            Form {
                Section(event.kind.title) {
                    if event.kind != .timeout {
                        Picker(event.kind == .goalAgainst ? "Goalie" : "Player", selection: $event.playerID) {
                            if !event.kind.needsPlayer { Text("None").tag(UUID?.none) }
                            ForEach(roster) { Text($0.label).tag(UUID?.some($0.id)) }
                        }
                    }
                    if event.kind == .shot {
                        Picker("Result", selection: Binding(get: { event.outcome ?? .missed }, set: { event.outcome = $0 })) {
                            ForEach(ShotOutcome.allCases) { Text($0.title).tag($0) }
                        }
                        if event.outcome == .goal {
                            Picker("Assist", selection: $event.assistID) {
                                Text("None").tag(UUID?.none)
                                ForEach(roster.filter { $0.id != event.playerID }) { Text($0.label).tag(UUID?.some($0.id)) }
                            }
                        }
                    }
                    if event.kind == .shot || event.kind == .goalAgainst {
                        Picker("Situation", selection: $event.situation) {
                            ForEach(Situation.allCases) { Text($0.title(defending: event.kind == .goalAgainst)).tag($0) }
                        }
                    }
                }

                Section("When") {
                    Stepper("Period: \(Game.periodName(event.period))", value: $event.period, in: 1...12)
                    Stepper("Minutes left: \(event.clock / 60)", value: Binding(
                        get: { event.clock / 60 },
                        set: { event.clock = $0 * 60 + event.clock % 60 }
                    ), in: 0...maxMinutes)
                    Stepper("Seconds: \(event.clock % 60)", value: Binding(
                        get: { event.clock % 60 },
                        set: { event.clock = (event.clock / 60) * 60 + $0 }
                    ), in: 0...59)
                }
            }
            .navigationTitle("Edit play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if event.outcome != .goal { event.assistID = nil }
                        if event.assistID == event.playerID { event.assistID = nil }
                        onSave(event)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
