import SwiftUI

/// The full box score for one game. Built without scroll views or lists so the same view
/// can be shown on screen and rendered to a PDF.
struct BoxScoreSheet: View {
    let game: Game
    let players: [Player]

    private var teamName: String { game.teamName }

    var body: some View {
        let lines = game.playerLines()
        let roster = players.filter { game.rosterIDs.contains($0.id) }.sorted { $0.capNumber < $1.capNumber }
        let goalies = roster.filter { $0.isGoalie || (lines[$0.id]?.isGoalieLine ?? false) }
        let team = game.teamLine

        VStack(alignment: .leading, spacing: 22) {
            header
            lineScore
            TeamStatTiles(team: team, situations: SituationSummary(game.events))

            section("Players") {
                StatTable(players: roster, lines: lines, columns: StatColumn.fieldBox, totals: team)
            }
            if !goalies.isEmpty {
                section("Goalies") {
                    StatTable(players: goalies, lines: lines, columns: StatColumn.goalieBox, totals: nil, columnWidth: 46)
                }
            }

            Text("G goals · Sh shots · A assists · Stl steals · TO turnovers · Blk field blocks · Ex exclusions and penalty fouls · DEx exclusions and penalties drawn · Sv saves · GA goals against")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(teamName) \(game.goalsFor), \(game.opponent) \(game.goalsAgainst)")
                .font(.title2.weight(.bold))
            Text([
                game.date.formatted(date: .long, time: .omitted),
                game.location,
                game.isFinal ? "Final" : "In progress, \(Game.periodName(game.period))",
            ].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var lineScore: some View {
        let periods = game.periodsPlayed
        return Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(periods, id: \.self) { Text(Game.periodName($0)).frame(minWidth: 36, alignment: .trailing) }
                Text("T").frame(minWidth: 40, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)

            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text(teamName).fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(periods, id: \.self) { Text("\(game.goalsFor(inPeriod: $0))") }
                Text("\(game.goalsFor)").fontWeight(.bold)
            }
            .padding(.vertical, 6)

            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text(game.opponent).fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(periods, id: \.self) { Text("\(game.goalsAgainst(inPeriod: $0))") }
                Text("\(game.goalsAgainst)").fontWeight(.bold)
            }
            .padding(.vertical, 6)
        }
        .font(.subheadline)
        .monospacedDigit()
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

/// Six headline team numbers: shooting, man-up, man-down, penalties, saves and sprints.
struct TeamStatTiles: View {
    let team: StatLine
    let situations: SituationSummary

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                tile("Shooting", Format.ratio(team.goals, team.shots), Format.percent(team.shotPct))
                tile("6 on 5", Format.ratio(situations.manUpGoals, situations.manUpChances), "goals / chances")
                tile("Man down", Format.ratio(situations.manDownGoalsAgainst, situations.manDownChances), "allowed / chances")
            }
            GridRow {
                tile("Penalties", Format.ratio(situations.penaltyGoals, situations.penaltyShots), "scored / taken")
                tile("Saves", "\(team.saves)", Format.percent(team.savePct))
                tile("Sprints", "\(team.sprintsWon)–\(team.sprintsLost)", "won–lost")
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A table with one row per player and one column per stat.
struct StatTable: View {
    let players: [Player]
    let lines: [UUID: StatLine]
    let columns: [StatColumn]
    var totals: StatLine?
    var perGame = false
    var columnWidth: CGFloat = 30
    /// When false the name column only takes the room it needs, for use inside a horizontal scroll view.
    var fillsWidth = true

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("#")
                name("Player")
                ForEach(columns) { column in
                    Text(column.header)
                        .frame(minWidth: column.isCounting ? columnWidth : max(columnWidth, 46), alignment: .trailing)
                        .accessibilityLabel(column.title)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 5)

            ForEach(players) { player in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("\(player.capNumber)")
                        .foregroundStyle(player.isGoalie ? Color.goalieCap : Color.primary)
                        .fontWeight(.semibold)
                    name(player.name.isEmpty ? "Player \(player.capNumber)" : player.name)
                    let line = lines[player.id] ?? StatLine()
                    ForEach(columns) { column in
                        Text(column.text(line, perGame: perGame))
                    }
                }
                .padding(.vertical, 6)
            }

            if let totals {
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text("")
                    name("Team")
                    ForEach(columns) { column in
                        Text(column.text(totals, perGame: perGame))
                    }
                }
                .fontWeight(.bold)
                .padding(.vertical, 6)
            }
        }
        .font(.footnote)
        .monospacedDigit()
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .padding(.leading, 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .gridColumnAlignment(.leading)
    }
}
