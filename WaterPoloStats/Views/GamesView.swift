import SwiftUI

/// Every game, with its score. Tap one to open the game screen.
struct GamesView: View {
    enum SortOrder: String { case entry, date }

    @Environment(Store.self) private var store
    let showsBack: Bool
    var open: (UUID) -> Void

    @State private var showNewGame = false
    @State private var isEditing = false
    @State private var pendingDelete: Game?
    @AppStorage("gameSort") private var sort = SortOrder.entry

    private var games: [Game] {
        sort == .entry ? Array(store.games.reversed()) : store.gamesNewestFirst
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Games", showsBack: showsBack) {
                Button("Add New Game") { showNewGame = true }
            } trailing: {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .disabled(store.games.isEmpty)
            }

            TablePanel {
                ZStack {
                    Text("Game")
                    HStack {
                        Spacer()
                        Button("Sort by: \(sort.rawValue)") { sort = sort == .entry ? .date : .entry }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
            } content: {
                if games.isEmpty {
                    Text(store.activePlayers.isEmpty ? "Add your players first, then tap Add New Game." : "No games yet. Tap Add New Game to start one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
                ForEach(games) { game in
                    TableRow(isEditing: isEditing, onDelete: { pendingDelete = game }, action: { open(game.id) }) {
                        GameRow(game: game)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.chrome)
        .sheet(isPresented: $showNewGame) {
            NewGameSheet { game in
                store.games.append(game)
                open(game.id)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.teamName ?? "") vs \(pendingDelete?.opponent ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete game", role: .destructive) {
                if let pendingDelete { store.games.removeAll { $0.id == pendingDelete.id } }
                pendingDelete = nil
            }
        } message: {
            Text("Its stats will be removed from the statistics. This can't be undone.")
        }
    }
}

/// "22 : 5" with the team names underneath and the date on the right.
struct GameRow: View {
    let game: Game

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 8) {
                side(score: game.goalsFor, name: game.teamName, leads: game.goalsFor > game.goalsAgainst, alignment: .trailing)
                Text(":")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.black.opacity(0.7))
                side(score: game.goalsAgainst, name: game.opponent, leads: game.goalsAgainst > game.goalsFor, alignment: .leading)
            }
            HStack(spacing: 6) {
                Spacer()
                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func side(score: Int, name: String, leads: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("\(score)")
                .font(.system(size: 28, weight: .ultraLight))
                .monospacedDigit()
                .foregroundStyle(Theme.scoreRed)
            Text(name.isEmpty ? "Team" : name)
                .font(.footnote.weight(leads ? .bold : .regular))
                .lineLimit(1)
        }
        .frame(width: 130, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// Your team, the opponent, the date and who is playing.
struct NewGameSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onCreate: (Game) -> Void

    @State private var teamName = ""
    @State private var opponent = ""
    @State private var date = Date()
    @State private var league = ""
    @State private var isHome = true
    @State private var periodMinutes = 8
    @State private var selected: Set<UUID> = []

    /// The picked team's players first; everyone if the name matches no team.
    private var candidates: [Player] {
        guard let team = store.team(named: teamName) else { return store.activePlayers }
        return store.players(in: team)
    }

    private var canSave: Bool {
        !teamName.trimmingCharacters(in: .whitespaces).isEmpty
            && !opponent.trimmingCharacters(in: .whitespaces).isEmpty
            && !selected.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Your Team", text: $teamName)
                            .textInputAutocapitalization(.words)
                        if !store.teams.isEmpty {
                            Menu("Teams") {
                                ForEach(store.teams) { team in
                                    Button(team.name) { pick(team) }
                                }
                            }
                        }
                    }
                    TextField("Opposing Team", text: $opponent)
                        .textInputAutocapitalization(.words)
                    DatePicker("Game Date", selection: $date, displayedComponents: .date)
                    TextField("League (optional)", text: $league)
                    Picker("Venue", selection: $isHome) {
                        Text("Home").tag(true)
                        Text("Away").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Picker("Quarter length", selection: $periodMinutes) {
                        ForEach([5, 6, 7, 8], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                }

                Section {
                    ForEach(candidates) { player in
                        Button {
                            if selected.contains(player.id) { selected.remove(player.id) } else { selected.insert(player.id) }
                        } label: {
                            HStack(spacing: 10) {
                                CapBadge(player: player, size: 26)
                                Text(player.name.isEmpty ? "Player \(player.capNumber)" : player.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(player.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.orange)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if candidates.isEmpty {
                        Text("No players yet. Add them under Players first.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Select players for this game")
                } footer: {
                    HStack {
                        Text("\(selected.count) \(selected.count == 1 ? "player" : "players") selected")
                        Spacer()
                        Button("Select All") { selected = Set(candidates.map(\.id)) }
                        Button("Deselect All") { selected = [] }
                            .padding(.leading, 12)
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle("Add New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: create)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let team = store.teams.first, teamName.isEmpty {
                    pick(team)
                } else if selected.isEmpty {
                    selected = Set(candidates.map(\.id))
                }
            }
        }
    }

    private func pick(_ team: Team) {
        teamName = team.name
        selected = Set(store.players(in: team).map(\.id))
    }

    private func create() {
        var game = Game(
            teamName: teamName.trimmingCharacters(in: .whitespaces),
            opponent: opponent.trimmingCharacters(in: .whitespaces),
            league: league.trimmingCharacters(in: .whitespaces),
            isHome: isHome
        )
        game.date = date
        game.periodLength = periodMinutes * 60
        game.clock = Double(game.periodLength)
        let roster = store.activePlayers.filter { selected.contains($0.id) }
        game.rosterIDs = roster.map(\.id)
        game.goalieID = roster.first(where: \.isGoalie)?.id
        onCreate(game)
        dismiss()
    }
}
