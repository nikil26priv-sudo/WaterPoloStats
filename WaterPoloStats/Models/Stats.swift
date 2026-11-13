import Foundation

/// Counting stats for one player (or the whole team) over any set of events.
struct StatLine: Hashable {
    var games = 0
    var goals = 0
    var shots = 0
    var assists = 0
    var steals = 0
    var turnovers = 0
    var blocks = 0
    var exclusions = 0
    var exclusionsDrawn = 0
    var penaltyFouls = 0
    var penaltiesDrawn = 0
    var saves = 0
    var goalsAgainst = 0
    var sprintsWon = 0
    var sprintsLost = 0

    var points: Int { goals + assists }
    var personalFouls: Int { exclusions + penaltyFouls }
    var shotPct: Double? { shots > 0 ? Double(goals) / Double(shots) : nil }
    var savePct: Double? {
        let faced = saves + goalsAgainst
        return faced > 0 ? Double(saves) / Double(faced) : nil
    }
    var isGoalieLine: Bool { saves + goalsAgainst > 0 }

    /// Counts the event for whoever it is attributed to. Assists are counted separately,
    /// because they belong to a different player than the goal.
    mutating func count(_ event: GameEvent) {
        switch event.kind {
        case .shot:
            shots += 1
            if event.outcome == .goal { goals += 1 }
        case .steal: steals += 1
        case .turnover: turnovers += 1
        case .block: blocks += 1
        case .exclusion: exclusions += 1
        case .exclusionDrawn: exclusionsDrawn += 1
        case .penaltyFoul: penaltyFouls += 1
        case .penaltyDrawn: penaltiesDrawn += 1
        case .save: saves += 1
        case .goalAgainst: goalsAgainst += 1
        case .sprintWon: sprintsWon += 1
        case .sprintLost: sprintsLost += 1
        case .timeout: break
        }
    }

    static func + (a: StatLine, b: StatLine) -> StatLine {
        var out = a
        out.games += b.games
        out.goals += b.goals
        out.shots += b.shots
        out.assists += b.assists
        out.steals += b.steals
        out.turnovers += b.turnovers
        out.blocks += b.blocks
        out.exclusions += b.exclusions
        out.exclusionsDrawn += b.exclusionsDrawn
        out.penaltyFouls += b.penaltyFouls
        out.penaltiesDrawn += b.penaltiesDrawn
        out.saves += b.saves
        out.goalsAgainst += b.goalsAgainst
        out.sprintsWon += b.sprintsWon
        out.sprintsLost += b.sprintsLost
        return out
    }
}

extension Sequence where Element == GameEvent {
    /// One line per player who appears in these events.
    func playerLines() -> [UUID: StatLine] {
        var lines: [UUID: StatLine] = [:]
        for event in self {
            if let player = event.playerID {
                lines[player, default: StatLine()].count(event)
            }
            if event.isGoal, let assist = event.assistID {
                lines[assist, default: StatLine()].assists += 1
            }
        }
        return lines
    }

    func teamLine() -> StatLine {
        var line = StatLine()
        for event in self {
            line.count(event)
            if event.isGoal, event.assistID != nil { line.assists += 1 }
        }
        return line
    }
}

/// Man-up, man-down and penalty numbers for the team.
struct SituationSummary {
    var manUpGoals = 0
    var manUpChances = 0
    var manDownGoalsAgainst = 0
    var manDownChances = 0
    var penaltyGoals = 0
    var penaltyShots = 0
    var penaltyGoalsAgainst = 0
    var penaltiesConceded = 0
    var timeouts = 0

    init(_ events: some Sequence<GameEvent>) {
        for event in events {
            switch event.kind {
            case .shot:
                if event.situation == .powerPlay, event.outcome == .goal { manUpGoals += 1 }
                if event.situation == .penalty {
                    penaltyShots += 1
                    if event.outcome == .goal { penaltyGoals += 1 }
                }
            case .exclusionDrawn: manUpChances += 1
            case .exclusion: manDownChances += 1
            case .penaltyFoul: penaltiesConceded += 1
            case .goalAgainst:
                if event.situation == .powerPlay { manDownGoalsAgainst += 1 }
                if event.situation == .penalty { penaltyGoalsAgainst += 1 }
            case .timeout: timeouts += 1
            default: break
            }
        }
    }
}

extension Game {
    func playerLines() -> [UUID: StatLine] {
        var lines = events.playerLines()
        for id in rosterIDs { lines[id, default: StatLine()].games = 1 }
        return lines
    }

    var teamLine: StatLine {
        var line = events.teamLine()
        line.games = 1
        return line
    }

    func personalFouls(for player: UUID) -> Int {
        events.count { $0.playerID == player && $0.kind.isPersonalFoul }
    }
}

extension Array where Element == Game {
    func seasonLines() -> [UUID: StatLine] {
        reduce(into: [:]) { totals, game in
            for (id, line) in game.playerLines() {
                totals[id] = (totals[id] ?? StatLine()) + line
            }
        }
    }

    func seasonTeamLine() -> StatLine {
        reduce(StatLine()) { $0 + $1.teamLine }
    }
}

/// A column in a stats table. Shared by the box score, the season table and the CSV exports.
enum StatColumn: String, CaseIterable, Identifiable {
    case games, goals, shots, shotPct, assists, points, steals, turnovers, blocks
    case exclusions, exclusionsDrawn, saves, goalsAgainst, savePct, sprints

    var id: String { rawValue }

    static let fieldBox: [StatColumn] = [.goals, .shots, .assists, .steals, .turnovers, .blocks, .exclusions, .exclusionsDrawn]
    static let goalieBox: [StatColumn] = [.saves, .goalsAgainst, .savePct]
    static let season: [StatColumn] = [.games, .goals, .shots, .shotPct, .assists, .points, .steals, .turnovers, .blocks, .exclusions, .exclusionsDrawn, .saves, .goalsAgainst, .savePct, .sprints]

    var header: String {
        switch self {
        case .games: "GP"
        case .goals: "G"
        case .shots: "Sh"
        case .shotPct: "Sh%"
        case .assists: "A"
        case .points: "Pts"
        case .steals: "Stl"
        case .turnovers: "TO"
        case .blocks: "Blk"
        case .exclusions: "Ex"
        case .exclusionsDrawn: "DEx"
        case .saves: "Sv"
        case .goalsAgainst: "GA"
        case .savePct: "Sv%"
        case .sprints: "Spr"
        }
    }

    var title: String {
        switch self {
        case .games: "Games played"
        case .goals: "Goals"
        case .shots: "Shots"
        case .shotPct: "Shooting %"
        case .assists: "Assists"
        case .points: "Points (goals + assists)"
        case .steals: "Steals"
        case .turnovers: "Turnovers"
        case .blocks: "Field blocks"
        case .exclusions: "Exclusions and penalty fouls"
        case .exclusionsDrawn: "Exclusions and penalties drawn"
        case .saves: "Saves"
        case .goalsAgainst: "Goals against"
        case .savePct: "Save %"
        case .sprints: "Sprints won–lost"
        }
    }

    /// Averages only make sense for counting stats.
    var isCounting: Bool {
        switch self {
        case .games, .shotPct, .savePct, .sprints: false
        default: true
        }
    }

    func value(_ line: StatLine) -> Double {
        switch self {
        case .games: Double(line.games)
        case .goals: Double(line.goals)
        case .shots: Double(line.shots)
        case .shotPct: line.shotPct ?? -1
        case .assists: Double(line.assists)
        case .points: Double(line.points)
        case .steals: Double(line.steals)
        case .turnovers: Double(line.turnovers)
        case .blocks: Double(line.blocks)
        case .exclusions: Double(line.personalFouls)
        case .exclusionsDrawn: Double(line.exclusionsDrawn + line.penaltiesDrawn)
        case .saves: Double(line.saves)
        case .goalsAgainst: Double(line.goalsAgainst)
        case .savePct: line.savePct ?? -1
        case .sprints: Double(line.sprintsWon)
        }
    }

    func text(_ line: StatLine, perGame: Bool = false) -> String {
        switch self {
        case .shotPct: return Format.percent(line.shotPct)
        case .savePct: return Format.percent(line.savePct)
        case .sprints: return "\(line.sprintsWon)–\(line.sprintsLost)"
        default:
            if perGame, isCounting {
                return line.games > 0 ? String(format: "%.1f", value(line) / Double(line.games)) : "–"
            }
            return String(Int(value(line)))
        }
    }
}

enum Format {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.0f%%", value * 100)
    }

    static func percent1(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f%%", value * 100)
    }

    static func ratio(_ made: Int, _ attempts: Int) -> String {
        "\(made)/\(attempts)"
    }
}

extension GameEvent {
    /// A one-line description for the play-by-play. `name` turns a player ID into a label.
    func summary(name: (UUID?) -> String) -> String {
        let who = name(playerID)
        switch kind {
        case .shot:
            var text = outcome == .goal ? "\(who) goal" : "\(who) shot \((outcome ?? .missed).title.lowercased())"
            if situation != .even { text += " (\(situation.title().lowercased()))" }
            if outcome == .goal, let assistID { text += ", assist \(name(assistID))" }
            return text
        case .goalAgainst:
            var text = "Opponent goal"
            if situation != .even { text += " (\(situation.title(defending: true).lowercased()))" }
            return text
        case .timeout:
            return "Timeout"
        case .save, .sprintWon, .sprintLost:
            return playerID == nil ? kind.title : "\(who) \(kind.title.lowercased())"
        default:
            return "\(who) \(kind.title.lowercased())"
        }
    }
}
