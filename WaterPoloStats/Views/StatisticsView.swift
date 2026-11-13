import SwiftUI

/// Totals for every player across all games, or for one team's games.
struct StatisticsView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All Stats"
        case team = "Team Stats"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    let showsBack: Bool
    /// The team to show. Set from the Teams section's Stats button.
    @Binding var teamID: UUID?

    @State private var scope = Scope.all
    @State private var showMore = false
    @State private var search = ""
    @State private var sort = StatColumn.goals
    @State private var sharedFile: SharedFile?

    private static let basic: [StatColumn] = [.goals, .shots, .assists, .steals, .turnovers, .blocks, .exclusions, .games]
    private static let extended: [StatColumn] = [.goals, .shots, .shotPct, .assists, .points, .steals, .turnovers, .blocks, .exclusions, .exclusionsDrawn, .saves, .goalsAgainst, .savePct, .sprints, .games]

    private var team: Team? { store.teams.first { $0.id == teamID } ?? store.teams.first }

    private var games: [Game] {
        guard scope == .team, let team else { return store.games }
        return store.games(for: team)
    }

    var body: some View {
        let games = games
        let lines = games.seasonLines()
        let columns = showMore ? Self.extended : Self.basic
        let key = search.trimmingCharacters(in: .whitespaces).lowercased()
        let players = store.players
            .filter { lines[$0.id] != nil && (key.isEmpty || $0.name.lowercased().contains(key)) }
            .sorted { a, b in
                let x = sort.value(lines[a.id] ?? StatLine()), y = sort.value(lines[b.id] ?? StatLine())
                return x == y ? a.capNumber < b.capNumber : x > y
            }

        VStack(spacing: 0) {
            TopBar(title: "Stats", showsBack: showsBack) {
                Button(showMore ? "Show Less" : "Show More") { showMore.toggle() }
            } trailing: {
                if sizeClass == .regular {
                    TextField("Search stats", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }
                Button("Send") {
                    let name = scope == .team ? "\(team?.name ?? "Team") stats" : "All stats"
                    if let url = Exporter.statsCSV(games: games, players: store.players, name: name) {
                        sharedFile = SharedFile(url: url)
                    }
                }
                .disabled(players.isEmpty)
            }

            ScrollView(.horizontal) {
                TablePanel {
                    HStack(spacing: 0) {
                        Text("Player").frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                        ForEach(columns) { column in
                            Button(column.header) { sort = column }
                                .buttonStyle(.plain)
                                .underline(sort == column)
                                .frame(width: width(of: column))
                                .accessibilityLabel("Sort by \(column.title)")
                        }
                    }
                } content: {
                    if players.isEmpty {
                        Text("No stats yet. They appear here once you've recorded a game.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(30)
                    }
                    ForEach(players) { player in
                        TableRow {
                            HStack(spacing: 0) {
                                Text(player.name.isEmpty ? "Player \(player.capNumber)" : player.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
                                let line = lines[player.id] ?? StatLine()
                                ForEach(columns) { column in
                                    Text(column.text(line))
                                        .frame(width: width(of: column))
                                }
                            }
                            .font(.footnote)
                            .monospacedDigit()
                        }
                    }
                }
                .frame(minWidth: 170 + columns.reduce(0) { $0 + width(of: $1) } + 24)
                .containerRelativeFrame(.horizontal) { length, _ in max(length - 32, 0) }
                .padding(16)
            }

            HStack(spacing: 12) {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                if scope == .team {
                    if store.teams.isEmpty {
                        Text("No teams yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Team", selection: Binding(get: { team?.id }, set: { teamID = $0 })) {
                            ForEach(store.teams) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .background(Theme.chrome)
        .sheet(item: $sharedFile) { ActivityView(items: [$0.url]) }
        .onChange(of: teamID, initial: true) { _, newValue in
            if newValue != nil { scope = .team }
        }
    }

    private func width(of column: StatColumn) -> CGFloat {
        switch column {
        case .games: 56
        case .shotPct, .savePct, .sprints: 54
        default: 46
        }
    }
}
