import SwiftUI
import Observation

/// The app's data: players, teams and every game. Saved as a single JSON file on the device.
@MainActor @Observable
final class Store {
    var players: [Player] = []
    var teams: [Team] = []
    var games: [Game] = []

    private struct Snapshot: Codable {
        var players: [Player]
        var teams: [Team]?
        var games: [Game]
    }

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static var defaultURL: URL { URL.documentsDirectory.appending(path: "waterpolo-stats-v2.json") }

    /// Pass `nil` for a store that lives only in memory.
    init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
        observeChanges()
    }

    // MARK: Lookups

    func player(_ id: UUID?) -> Player? {
        guard let id else { return nil }
        return players.first { $0.id == id }
    }

    func playerLabel(_ id: UUID?) -> String {
        player(id)?.label ?? "Team"
    }

    /// "Johny Clore", or the fallback when the event has no player.
    func playerName(_ id: UUID?, fallback: String = "Team") -> String {
        guard let player = player(id) else { return fallback }
        return player.name.isEmpty ? "#\(player.capNumber)" : player.name
    }

    var activePlayers: [Player] {
        players.filter { !$0.isArchived }.sorted { ($0.capNumber, $0.lastName) < ($1.capNumber, $1.lastName) }
    }

    func roster(for game: Game) -> [Player] {
        game.rosterIDs.compactMap { player($0) }.sorted { $0.capNumber < $1.capNumber }
    }

    func players(in team: Team) -> [Player] {
        team.playerIDs.compactMap { player($0) }.filter { !$0.isArchived }.sorted { $0.capNumber < $1.capNumber }
    }

    func team(named name: String) -> Team? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return teams.first { $0.name.lowercased() == key }
    }

    func games(for team: Team) -> [Game] {
        let key = team.name.lowercased()
        return games.filter { $0.teamName.lowercased() == key }
    }

    var gamesNewestFirst: [Game] {
        games.sorted { $0.date > $1.date }
    }

    func gameBinding(_ id: UUID) -> Binding<Game> {
        Binding(
            get: { self.games.first { $0.id == id } ?? Game(opponent: "") },
            set: { updated in
                if let index = self.games.firstIndex(where: { $0.id == id }) {
                    self.games[index] = updated
                }
            }
        )
    }

    // MARK: Changes

    var nextCapNumber: Int {
        let used = Set(activePlayers.map(\.capNumber))
        return (1...99).first { !used.contains($0) } ?? 1
    }

    func save(_ player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index] = player
        } else {
            players.append(player)
        }
    }

    /// Players who appear in a saved game are archived so old box scores keep their names.
    func remove(_ player: Player) {
        for index in teams.indices {
            teams[index].playerIDs.removeAll { $0 == player.id }
        }
        let hasHistory = games.contains { $0.rosterIDs.contains(player.id) }
        if hasHistory, let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index].isArchived = true
        } else {
            players.removeAll { $0.id == player.id }
        }
    }

    func save(_ team: Team) {
        if let index = teams.firstIndex(where: { $0.id == team.id }) {
            teams[index] = team
        } else {
            teams.append(team)
        }
    }

    // MARK: Sharing

    /// Games with the players and teams they need, for sending to another device.
    struct Backup: Codable {
        var version = 1
        var players: [Player]
        var teams: [Team]
        var games: [Game]
    }

    func backup(of selected: [Game]) -> Backup {
        let playerIDs = Set(selected.flatMap(\.rosterIDs))
        let teamNames = Set(selected.map { $0.teamName.lowercased() })
        return Backup(
            players: players.filter { playerIDs.contains($0.id) },
            teams: teams.filter { teamNames.contains($0.name.lowercased()) },
            games: selected
        )
    }

    /// Adds what is new and updates games that already exist. Returns how many games came in.
    @discardableResult
    func merge(_ backup: Backup) -> Int {
        for player in backup.players where !players.contains(where: { $0.id == player.id }) {
            players.append(player)
        }
        for team in backup.teams where !teams.contains(where: { $0.id == team.id }) && self.team(named: team.name) == nil {
            teams.append(team)
        }
        for game in backup.games {
            if let index = games.firstIndex(where: { $0.id == game.id }) {
                games[index] = game
            } else {
                games.append(game)
            }
        }
        return backup.games.count
    }

    // MARK: Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            players = snapshot.players
            teams = snapshot.teams ?? []
            games = snapshot.games
        } catch {
            // Keep the unreadable file rather than overwrite it with empty data.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    func save() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(Snapshot(players: players, teams: teams, games: games))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Save failed: \(error)")
        }
    }

    /// Re-arms itself after every change, so any edit anywhere in the app is saved shortly after.
    private func observeChanges() {
        withObservationTracking {
            _ = players
            _ = teams
            _ = games
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleSave()
                self?.observeChanges()
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}
