#if DEBUG
import Foundation

/// A made-up team and three games, loaded by launching with `-sampleData`.
/// Used for previews and for trying the app without touching real data.
enum SampleData {
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let teamName = "Harbor Sharks"

    static func players() -> [Player] {
        let names = [
            ("Sam", "Okafor"), ("Alex", "Reyes"), ("Jordan", "Lindqvist"), ("Riley", "Tanaka"), ("Casey", "Moreau"),
            ("Morgan", "Bianchi"), ("Taylor", "Novak"), ("Quinn", "Haddad"), ("Avery", "Costa"), ("Rowan", "Petrov"),
            ("Skyler", "Mbeki"), ("Reese", "Oduya"), ("Drew", "Varga"),
        ]
        let positions: [Position] = [.goalkeeper, .driver, .center, .wing, .point, .centerBack, .driver, .wing, .utility, .driver, .center, .point, .goalkeeper]
        return names.enumerated().map { index, name in
            Player(
                firstName: name.0, lastName: name.1, capNumber: index + 1, position: positions[index],
                birthDate: Calendar.current.date(from: DateComponents(year: 2008 + index % 3, month: 1 + index % 12, day: 3 + index)),
                heightCm: 172 + (index * 7) % 22, weightKg: 64 + (index * 5) % 24
            )
        }
    }

    static func teams(players: [Player]) -> [Team] {
        [Team(name: teamName, playerIDs: players.map(\.id))]
    }

    static func games(players: [Player]) -> [Game] {
        var rng = Generator(state: 2026)
        let day: TimeInterval = 86_400
        return [
            game(opponent: "Riverside", daysAgo: 14, players: players, through: 4, final: true, rng: &rng),
            game(opponent: "Bay Aquatics", daysAgo: 7, players: players, through: 4, final: true, rng: &rng),
            game(opponent: "Northgate", daysAgo: 0, players: players, through: 2, final: false, rng: &rng),
        ].map { game in
            var game = game
            game.date = Calendar.current.startOfDay(for: game.date).addingTimeInterval(day * 0.7)
            return game
        }
    }

    private static func game(opponent: String, daysAgo: Int, players: [Player], through lastPeriod: Int, final: Bool, rng: inout Generator) -> Game {
        var game = Game(teamName: teamName, opponent: opponent, league: "Fall league", isHome: daysAgo != 7)
        game.date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        game.rosterIDs = players.map(\.id)
        let goalie = players.first { $0.isGoalie }
        game.goalieID = goalie?.id
        let field = players.filter { !$0.isGoalie }

        for period in 1...lastPeriod {
            let isCurrent = !final && period == lastPeriod
            let floor = isCurrent ? 300 : 5
            var clock = game.periodLength
            var events: [GameEvent] = []

            func add(_ kind: EventKind, _ player: Player?, at clock: Int) -> Int {
                events.append(GameEvent(kind: kind, period: period, clock: clock, playerID: player?.id))
                return events.count - 1
            }

            _ = add(Bool.random(using: &rng) ? .sprintWon : .sprintLost, field.randomElement(using: &rng), at: clock)
            var manUp = false
            var manDown = false

            while true {
                clock -= Int.random(in: 14...42, using: &rng)
                if clock <= floor { break }
                let shooter = field.randomElement(using: &rng)!
                switch Int.random(in: 0..<100, using: &rng) {
                case 0..<34:
                    let index = add(.shot, shooter, at: clock)
                    let roll = Int.random(in: 0..<100, using: &rng)
                    let outcome: ShotOutcome = roll < 40 ? .goal : roll < 70 ? .saved : roll < 82 ? .blocked : .missed
                    events[index].outcome = outcome
                    events[index].situation = manUp ? .powerPlay : .even
                    events[index].location = ShotPoint(x: Double.random(in: 0.15...0.85, using: &rng), y: Double.random(in: 0.12...0.62, using: &rng))
                    if outcome == .goal, Int.random(in: 0..<100, using: &rng) < 65 {
                        events[index].assistID = field.filter { $0.id != shooter.id }.randomElement(using: &rng)?.id
                    }
                    manUp = false
                case 34..<46:
                    _ = add(.steal, shooter, at: clock)
                case 46..<58:
                    _ = add(.turnover, shooter, at: clock)
                case 58..<63:
                    _ = add(.block, shooter, at: clock)
                case 63..<71:
                    _ = add(.exclusionDrawn, shooter, at: clock)
                    manUp = true
                case 71..<78:
                    _ = add(.exclusion, shooter, at: clock)
                    manDown = true
                case 78..<90:
                    _ = add(.save, goalie, at: clock)
                    manDown = false
                default:
                    let index = add(.goalAgainst, goalie, at: clock)
                    events[index].situation = manDown ? .powerPlay : .even
                    manDown = false
                }
            }

            if period == 3 {
                let drawn = add(.penaltyDrawn, field[2], at: 95)
                let shot = add(.shot, field[2], at: 95)
                events[shot].outcome = .goal
                events[shot].situation = .penalty
                events[shot].location = PoolGeometry.penaltySpot
                events[shot].createdAt = events[drawn].createdAt.addingTimeInterval(1)
            }

            game.events += events
            game.period = period
            game.clock = isCurrent ? Double(floor) + 12 : 0
        }
        game.isFinal = final
        return game
    }
}
#endif
