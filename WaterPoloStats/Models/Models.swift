import Foundation

enum Position: String, Codable, CaseIterable, Identifiable {
    case goalkeeper, center, centerBack, driver, wing, point, utility

    var id: String { rawValue }

    var short: String {
        switch self {
        case .goalkeeper: "GK"
        case .center: "C"
        case .centerBack: "CB"
        case .driver: "D"
        case .wing: "W"
        case .point: "P"
        case .utility: "U"
        }
    }

    var title: String {
        switch self {
        case .goalkeeper: "GK - Goalkeeper"
        case .center: "C - Center"
        case .centerBack: "CB - Center Back"
        case .driver: "D - Driver"
        case .wing: "W - Wing"
        case .point: "P - Point"
        case .utility: "U - Utility"
        }
    }
}

struct Player: Identifiable, Codable, Hashable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var capNumber: Int
    var position = Position.driver
    var birthDate: Date?
    var heightCm: Int?
    var weightKg: Int?
    /// Archived players stay in old games and totals but are hidden from the players list.
    var isArchived = false

    var isGoalie: Bool { position == .goalkeeper }

    /// "Johny Clore"
    var name: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "Clore J."
    var shortName: String {
        if lastName.isEmpty { return firstName }
        guard let initial = firstName.first else { return lastName }
        return "\(lastName) \(initial)."
    }

    var label: String { name.isEmpty ? "#\(capNumber)" : "#\(capNumber) \(name)" }

    var heightText: String {
        guard let heightCm else { return "–" }
        let inches = Int((Double(heightCm) / 2.54).rounded())
        return "\(heightCm) cm / \(inches / 12)-\(inches % 12)"
    }

    var weightText: String {
        guard let weightKg else { return "–" }
        return "\(weightKg) kg / \(Int((Double(weightKg) * 2.2046).rounded())) lbs"
    }
}

struct Team: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var playerIDs: [UUID] = []
}

/// One line drawn on the sketch board. Points are normalised to the board.
struct SketchStroke: Codable, Hashable {
    var color: Int
    var width: Double
    var points: [ShotPoint]
}

struct Sketch: Identifiable, Codable, Hashable {
    var id = UUID()
    var strokes: [SketchStroke]
    var createdAt = Date()
}

enum ShotOutcome: String, Codable, CaseIterable, Identifiable {
    case goal, saved, blocked, missed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .goal: "Goal"
        case .saved: "Saved"
        case .blocked: "Blocked"
        case .missed: "Missed"
        }
    }
}

/// The man-power situation when a shot was taken or a goal was conceded.
enum Situation: String, Codable, CaseIterable, Identifiable {
    case even, powerPlay, penalty

    var id: String { rawValue }

    /// `defending` is true for goals against, where a power play means we were a player down.
    func title(defending: Bool = false) -> String {
        switch self {
        case .even: "Even"
        case .powerPlay: defending ? "Man down" : "6 on 5"
        case .penalty: "Penalty"
        }
    }
}

enum EventKind: String, Codable, CaseIterable {
    case shot
    case steal, turnover, block
    case exclusion, exclusionDrawn
    case penaltyFoul, penaltyDrawn
    case save, goalAgainst
    case sprintWon, sprintLost
    case timeout

    var title: String {
        switch self {
        case .shot: "Shot"
        case .steal: "Steal"
        case .turnover: "Turnover"
        case .block: "Field block"
        case .exclusion: "Exclusion"
        case .exclusionDrawn: "Exclusion drawn"
        case .penaltyFoul: "Penalty foul"
        case .penaltyDrawn: "Penalty drawn"
        case .save: "Save"
        case .goalAgainst: "Opponent goal"
        case .sprintWon: "Sprint won"
        case .sprintLost: "Sprint lost"
        case .timeout: "Timeout"
        }
    }

    /// Whether the event has to be attributed to one of our players.
    var needsPlayer: Bool {
        switch self {
        case .shot, .steal, .turnover, .block, .exclusion, .exclusionDrawn, .penaltyFoul, .penaltyDrawn: true
        case .save, .goalAgainst, .sprintWon, .sprintLost, .timeout: false
        }
    }

    /// Exclusions and penalty fouls are personal fouls; three and the player is out for the game.
    var isPersonalFoul: Bool { self == .exclusion || self == .penaltyFoul }
}

/// A shot location on the attacking half, normalised to the pool diagram.
/// `x` runs left to right across the pool; `y` runs from the goal line (0) out to `PoolGeometry.depth` metres (1).
struct ShotPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

enum PoolGeometry {
    static let width = 20.0
    static let depth = 13.0
    static let goalWidth = 3.0
    static let penaltySpot = ShotPoint(x: 0.5, y: 5.0 / depth)
}

struct GameEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: EventKind
    var period: Int
    /// Seconds left in the period when the event happened.
    var clock: Int
    var playerID: UUID?
    var outcome: ShotOutcome?
    var situation: Situation = .even
    var assistID: UUID?
    var location: ShotPoint?
    var createdAt = Date()

    var isGoal: Bool { kind == .shot && outcome == .goal }
}

struct Game: Identifiable, Codable, Hashable {
    /// Personal fouls before a player is out for the game. Three by rule; changeable in the game settings.
    static var personalFoulLimit: Int {
        let stored = UserDefaults.standard.integer(forKey: "foulLimit")
        return stored == 0 ? 3 : stored
    }
    static let regulationPeriods = 4

    var id = UUID()
    var date = Date()
    /// Our team's name for this game.
    var teamName = ""
    var opponent: String
    var location = ""
    var league = ""
    var isHome = true
    var notes = ""
    var sketches: [Sketch] = []
    var periodLength = 8 * 60
    var overtimeLength = 3 * 60
    var exclusionLength = 20
    /// Players dressed for this game.
    var rosterIDs: [UUID] = []
    /// The goalie currently in the cage; saves and goals against are credited to them.
    var goalieID: UUID?
    var events: [GameEvent] = []
    var period = 1
    /// Seconds left in the period as of the last time the clock was stopped.
    var clock: TimeInterval = 8 * 60
    /// Set while the clock is running.
    var runningSince: Date?
    var isFinal = false

    // MARK: Periods and clock

    static func periodName(_ period: Int) -> String {
        period <= regulationPeriods ? "Q\(period)" : "OT\(period - regulationPeriods)"
    }

    func length(ofPeriod period: Int) -> Int {
        period <= Game.regulationPeriods ? periodLength : overtimeLength
    }

    var isRunning: Bool { runningSince != nil }

    func remaining(at now: Date = .now) -> TimeInterval {
        guard let runningSince else { return clock }
        return max(0, clock - now.timeIntervalSince(runningSince))
    }

    func clockSeconds(at now: Date = .now) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    mutating func startClock(at now: Date = .now) {
        guard runningSince == nil, clock > 0, !isFinal else { return }
        runningSince = now
    }

    mutating func stopClock(at now: Date = .now) {
        clock = remaining(at: now)
        runningSince = nil
    }

    mutating func adjustClock(by delta: TimeInterval, at now: Date = .now) {
        let wasRunning = isRunning
        stopClock(at: now)
        clock = min(Double(length(ofPeriod: period)), max(0, clock + delta))
        if wasRunning { startClock(at: now) }
    }

    mutating func resetClock() {
        runningSince = nil
        clock = Double(length(ofPeriod: period))
    }

    mutating func advancePeriod() {
        period += 1
        resetClock()
    }

    mutating func finish(at now: Date = .now) {
        stopClock(at: now)
        isFinal = true
    }

    /// Jumps straight to a period, as the period buttons on the scoreboard do.
    mutating func goToPeriod(_ newPeriod: Int) {
        guard newPeriod != period else { return }
        period = newPeriod
        resetClock()
    }

    /// The same game with only one period's events, for the box score and shot chart filters.
    func filtered(toPeriod period: Int?) -> Game {
        guard let period else { return self }
        var copy = self
        copy.events = events.filter { period > Game.regulationPeriods ? $0.period > Game.regulationPeriods : $0.period == period }
        return copy
    }

    /// Every period that has been started or has an event in it.
    var periodsPlayed: [Int] {
        Array(1...max(period, events.map(\.period).max() ?? 1, Game.regulationPeriods))
    }

    // MARK: Logging

    @discardableResult
    mutating func log(_ kind: EventKind, player: UUID? = nil, at now: Date = .now) -> GameEvent {
        let event = GameEvent(kind: kind, period: period, clock: clockSeconds(at: now), playerID: player, createdAt: now)
        events.append(event)
        return event
    }

    // MARK: Score

    var goalsFor: Int { events.count(where: \.isGoal) }
    var goalsAgainst: Int { events.count { $0.kind == .goalAgainst } }

    func goalsFor(inPeriod period: Int) -> Int {
        events.count { $0.isGoal && $0.period == period }
    }

    func goalsAgainst(inPeriod period: Int) -> Int {
        events.count { $0.kind == .goalAgainst && $0.period == period }
    }

    enum Result: String { case win = "W", loss = "L", tie = "T" }

    var result: Result? {
        guard isFinal else { return nil }
        if goalsFor == goalsAgainst { return .tie }
        return goalsFor > goalsAgainst ? .win : .loss
    }

    /// Events in the order they happened in the game.
    var chronologicalEvents: [GameEvent] {
        events.sorted {
            if $0.period != $1.period { return $0.period < $1.period }
            if $0.clock != $1.clock { return $0.clock > $1.clock }
            return $0.createdAt < $1.createdAt
        }
    }
}
