import SwiftUI

/// Every located shot from one or more games, with a filter by player.
struct ShotChartView: View {
    let games: [Game]
    let players: [Player]

    @State private var playerFilter: UUID?
    @State private var situationFilter: Situation?

    private var shots: [GameEvent] {
        games.flatMap(\.events).filter { event in
            event.kind == .shot
                && (playerFilter == nil || event.playerID == playerFilter)
                && (situationFilter == nil || event.situation == situationFilter)
        }
    }

    var body: some View {
        let shots = shots
        let located = shots.filter { $0.location != nil }
        let goals = shots.count(where: \.isGoal)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Player", selection: $playerFilter) {
                        Text("All players").tag(UUID?.none)
                        ForEach(players) { Text($0.label).tag(UUID?.some($0.id)) }
                    }
                    Picker("Situation", selection: $situationFilter) {
                        Text("All situations").tag(Situation?.none)
                        ForEach(Situation.allCases) { Text($0.title()).tag(Situation?.some($0)) }
                    }
                    Spacer(minLength: 0)
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(goals) goals on \(shots.count) shots")
                        .font(.title3.weight(.semibold))
                    Text(shots.isEmpty ? "No shots recorded yet." : "\(Format.percent(shots.isEmpty ? nil : Double(goals) / Double(shots.count))) shooting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PoolDiagram(marks: located.map { ShotMark(id: $0.id, point: $0.location!, outcome: $0.outcome ?? .missed) })
                    .frame(maxWidth: 640)

                ShotLegend()

                HStack(spacing: 8) {
                    ForEach(ShotOutcome.allCases) { outcome in
                        VStack(spacing: 2) {
                            Text("\(shots.count { $0.outcome == outcome })")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            Text(outcome.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: 640)

                if located.count < shots.count {
                    Text("\(shots.count - located.count) shots were recorded without a location and aren't on the chart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
