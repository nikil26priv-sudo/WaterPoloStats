import SwiftUI

/// Writes box scores and stat tables to temporary files for the share sheet.
@MainActor
enum Exporter {
    // MARK: PDF

    static func boxScorePDF(game: Game, players: [Player]) -> URL? {
        let teamName = game.teamName
        let page = VStack(alignment: .leading, spacing: 24) {
            BoxScoreSheet(game: game, players: players)
            let marks = game.events.compactMap { event -> ShotMark? in
                guard event.kind == .shot, let location = event.location else { return nil }
                return ShotMark(id: event.id, point: location, outcome: event.outcome ?? .missed)
            }
            if !marks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shot chart")
                        .font(.headline)
                    PoolDiagram(marks: marks, markSize: 13)
                        .frame(width: 380)
                    ShotLegend()
                }
            }
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)

        return pdf(of: page, name: "\(teamName) vs \(game.opponent) \(dateStamp(game.date))")
    }

    /// The shot chart for some or all players, optionally for one period.
    static func shotChartPDF(game: Game, players: [Player], selected: Set<UUID>?, period: Int?) -> URL? {
        let shots = game.filtered(toPeriod: period).events.filter { event in
            event.kind == .shot && (selected == nil || event.playerID.map { selected!.contains($0) } ?? false)
        }
        let goals = shots.count(where: \.isGoal)
        let names = players.filter { selected?.contains($0.id) ?? false }.map(\.name)
        let page = VStack(alignment: .leading, spacing: 12) {
            Text("Shot chart: \(game.teamName) vs \(game.opponent)")
                .font(.title2.weight(.bold))
            Text([game.date.formatted(date: .long, time: .omitted), period.map { Game.periodName($0) } ?? "Whole game"].joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if selected != nil {
                Text("Players: \(names.isEmpty ? "none" : names.joined(separator: ", "))")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Shots attempted: \(shots.count) | Shots made: \(goals) | Percentage: \(Format.percent1(shots.isEmpty ? nil : Double(goals) / Double(shots.count)))")
                .font(.subheadline.weight(.semibold))
            PoolDiagram(marks: shots.compactMap { event in
                event.location.map { ShotMark(id: event.id, point: $0, outcome: event.outcome ?? .missed) }
            }, markSize: 15)
            ShotLegend()
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        return pdf(of: page, name: "\(game.teamName) vs \(game.opponent) \(dateStamp(game.date)) shot chart")
    }

    private static func pdf(of page: some View, name: String) -> URL? {
        let url = fileURL(name: name, ext: "pdf")
        let renderer = ImageRenderer(content: page)
        var succeeded = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            succeeded = true
        }
        return succeeded ? url : nil
    }

    /// Selected games in a file another copy of the app can read back in.
    static func backupFile(_ backup: Store.Backup) -> URL? {
        let url = fileURL(name: "Water polo games \(dateStamp(Date()))", ext: "json")
        do {
            try JSONEncoder().encode(backup).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: CSV

    static func gameStatsCSV(game: Game, players: [Player]) -> URL? {
        let teamName = game.teamName
        let roster = players.filter { game.rosterIDs.contains($0.id) }.sorted { $0.capNumber < $1.capNumber }
        let columns = StatColumn.season.filter { $0 != .games }
        let csv = statsCSV(players: roster, lines: game.playerLines(), team: game.teamLine, columns: columns)
        return write(csv, name: "\(teamName) vs \(game.opponent) \(dateStamp(game.date)) stats")
    }

    static func statsCSV(games: [Game], players: [Player], name: String) -> URL? {
        let lines = games.seasonLines()
        let roster = players.filter { lines[$0.id] != nil }.sorted { $0.capNumber < $1.capNumber }
        let csv = statsCSV(players: roster, lines: lines, team: games.seasonTeamLine(), columns: StatColumn.season)
        return write(csv, name: name)
    }

    static func playsCSV(game: Game, players: [Player]) -> URL? {
        let teamName = game.teamName
        let names = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        var rows = [["Period", "Time", "Cap", "Player", "Event", "Result", "Situation", "Assist", "Score"]]
        var ours = 0
        var theirs = 0
        for event in game.chronologicalEvents {
            if event.isGoal { ours += 1 }
            if event.kind == .goalAgainst { theirs += 1 }
            let player = event.playerID.flatMap { names[$0] }
            let hasSituation = event.kind == .shot || event.kind == .goalAgainst
            rows.append([
                Game.periodName(event.period),
                Format.clock(event.clock),
                player.map { String($0.capNumber) } ?? "",
                player?.name ?? "",
                event.kind.title,
                event.outcome?.title ?? "",
                hasSituation ? event.situation.title(defending: event.kind == .goalAgainst) : "",
                event.assistID.flatMap { names[$0] }?.label ?? "",
                "\(ours)-\(theirs)",
            ])
        }
        return write(csvText(rows), name: "\(teamName) vs \(game.opponent) \(dateStamp(game.date)) plays")
    }

    private static func statsCSV(players: [Player], lines: [UUID: StatLine], team: StatLine, columns: [StatColumn]) -> String {
        var rows = [["Cap", "Player"] + columns.map(\.title)]
        for player in players {
            let line = lines[player.id] ?? StatLine()
            rows.append([String(player.capNumber), player.name] + columns.map { cell($0, line) })
        }
        rows.append(["", "Team"] + columns.map { cell($0, team) })
        return csvText(rows)
    }

    /// Sprints go out as "won-lost" with a plain hyphen so spreadsheets don't choke on the dash.
    private static func cell(_ column: StatColumn, _ line: StatLine) -> String {
        column == .sprints ? "\(line.sprintsWon)-\(line.sprintsLost)" : column.text(line).replacingOccurrences(of: "–", with: "")
    }

    private static func csvText(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                var field = field
                // A leading =, +, - or @ would be run as a formula by spreadsheet apps.
                if let first = field.first, "=+-@".contains(first) { field = "'" + field }
                let needsQuotes = field.contains(",") || field.contains("\"") || field.contains("\n")
                return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Files

    private static func write(_ text: String, name: String) -> URL? {
        let url = fileURL(name: name, ext: "csv")
        do {
            // The byte-order mark makes Excel read accented names correctly.
            try Data(("\u{FEFF}" + text).utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func fileURL(name: String, ext: String) -> URL {
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return FileManager.default.temporaryDirectory.appending(path: "\(safe).\(ext)")
    }

    private static func dateStamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
