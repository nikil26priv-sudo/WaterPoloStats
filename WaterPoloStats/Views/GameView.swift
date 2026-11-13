import SwiftUI

/// A game, opened full screen from the games list.
/// iPad gets the one-screen tracker with Box Score, Options and Settings along the top;
/// iPhone gets the same game split into Track, Box score, Shots and Plays.
struct GameScreen: View {
    enum Panel: String, Identifiable {
        case boxScore, shotChart, sketch, notes
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let gameID: UUID

    @State private var panel: Panel?
    @State private var showSettings = false
    @State private var sharedFile: SharedFile?

    var body: some View {
        let binding = store.gameBinding(gameID)
        let game = binding.wrappedValue

        Group {
            if sizeClass == .regular, verticalSizeClass == .regular {
                VStack(spacing: 0) {
                    TopBar(title: "") {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    } trailing: {
                        Button("Box Score") { panel = .boxScore }
                        Menu("Options") {
                            Button("Sketch Board") { panel = .sketch }
                            Button("Shot Chart") { panel = .shotChart }
                            Button("Notes") { panel = .notes }
                            Button("Send Play by Play") {
                                if let url = Exporter.playsCSV(game: game, players: store.players) {
                                    sharedFile = SharedFile(url: url)
                                }
                            }
                        }
                        Button("Settings") { showSettings = true }
                            .popover(isPresented: $showSettings) {
                                GameSettingsView(game: binding)
                            }
                    }
                    LiveGameView(game: binding)
                }
                .background(Theme.chrome.ignoresSafeArea())
            } else {
                NavigationStack {
                    CompactGameView(game: binding)
                }
            }
        }
        .fullScreenCover(item: $panel) { panel in
            switch panel {
            case .boxScore: BoxScoreScreen(game: game, players: store.players)
            case .shotChart: ShotChartScreen(game: game, players: store.roster(for: game))
            case .sketch: SketchBoardView(game: binding)
            case .notes: NotesScreen(game: binding)
            }
        }
        .sheet(item: $sharedFile) { ActivityView(items: [$0.url]) }
        .onAppear {
            if panel == nil, let requested = LaunchOptions.gameTab {
                panel = Panel(rawValue: requested)
            }
        }
    }
}

// MARK: - iPhone

/// The phone version of a game: live tracking plus its box score, shot chart and play-by-play.
struct CompactGameView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case track, box, shots, plays

        var id: String { rawValue }
        var title: String {
            switch self {
            case .track: "Track"
            case .box: "Box score"
            case .shots: "Shots"
            case .plays: "Plays"
            }
        }
    }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var game: Game

    @State private var tab = Tab.track
    @State private var sharedFile: SharedFile?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch tab {
            case .track:
                LiveGameView(game: $game)
            case .box:
                ScrollView {
                    BoxScoreSheet(game: game, players: store.players)
                        .padding()
                }
            case .shots:
                ShotChartView(games: [game], players: store.roster(for: game))
            case .plays:
                PlaysView(game: $game)
            }
        }
        .navigationTitle("vs \(game.opponent)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Share", systemImage: "square.and.arrow.up") {
                    Button("Box score (PDF)", systemImage: "doc.richtext") {
                        share(Exporter.boxScorePDF(game: game, players: store.players))
                    }
                    Button("Player stats (CSV)", systemImage: "tablecells") {
                        share(Exporter.gameStatsCSV(game: game, players: store.players))
                    }
                    Button("Play-by-play (CSV)", systemImage: "list.bullet") {
                        share(Exporter.playsCSV(game: game, players: store.players))
                    }
                }
            }
        }
        .sheet(item: $sharedFile) { ActivityView(items: [$0.url]) }
    }

    private func share(_ url: URL?) {
        if let url { sharedFile = SharedFile(url: url) }
    }
}

// MARK: - Box score

/// A segmented control for Q1, Q2, Q3, Q4, OT and All.
struct PeriodFilter: View {
    @Binding var period: Int?

    var body: some View {
        Picker("Period", selection: $period) {
            ForEach(1...4, id: \.self) { Text("Q\($0)").tag(Int?.some($0)) }
            Text("OT").tag(Int?.some(5))
            Text("All").tag(Int?.none)
        }
        .pickerStyle(.segmented)
    }
}

struct BoxScoreScreen: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let players: [Player]

    @State private var period: Int?
    @State private var sharedFile: SharedFile?

    var body: some View {
        let shown = game.filtered(toPeriod: period)

        VStack(spacing: 0) {
            ZStack {
                PeriodFilter(period: $period)
                    .frame(width: 300)
                HStack {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Send Box Score") {
                        if let url = Exporter.boxScorePDF(game: shown, players: players) {
                            sharedFile = SharedFile(url: url)
                        }
                    }
                }
                .font(.callout)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }

            ScrollView {
                BoxScoreSheet(game: shown, players: players)
                    .padding(20)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(16)
        }
        .background(Theme.chrome.ignoresSafeArea())
        .sheet(item: $sharedFile) { ActivityView(items: [$0.url]) }
    }
}

// MARK: - Shot chart

/// The pool with every shot, a list of players to include, and a period filter.
struct ShotChartScreen: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    let players: [Player]

    @State private var selected: Set<UUID> = []
    @State private var period: Int?
    @State private var sharedFile: SharedFile?

    var body: some View {
        let shots = game.filtered(toPeriod: period).events.filter { event in
            event.kind == .shot && event.playerID.map(selected.contains) == true
        }
        let goals = shots.count(where: \.isGoal)
        let percent = Format.percent1(shots.isEmpty ? nil : Double(goals) / Double(shots.count))

        VStack(spacing: 0) {
            TopBar(title: "Shot Chart") {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            } trailing: {
                Button("Send Shot Chart") {
                    if let url = Exporter.shotChartPDF(game: game, players: players, selected: selected, period: period) {
                        sharedFile = SharedFile(url: url)
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    PoolDiagram(marks: shots.compactMap { event in
                        event.location.map { ShotMark(id: event.id, point: $0, outcome: event.outcome ?? .missed) }
                    }, markSize: 20)
                    Text("Shots attempted: \(shots.count)  |  Shots made: \(goals)  |  Percentage: \(percent)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                    ShotLegend()
                    let unplaced = shots.count { $0.location == nil }
                    if unplaced > 0 {
                        Text("\(unplaced) shots were recorded without a spot and aren't on the chart.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(players) { player in
                                Button {
                                    if selected.contains(player.id) { selected.remove(player.id) } else { selected.insert(player.id) }
                                } label: {
                                    HStack {
                                        Text(player.name.isEmpty ? "Player \(player.capNumber)" : player.name)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(.black)
                                        Spacer()
                                        if selected.contains(player.id) {
                                            Image(systemName: "checkmark")
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Theme.orange)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 38)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected.contains(player.id) ? .isSelected : [])
                                .overlay(alignment: .bottom) { Color.black.opacity(0.08).frame(height: 1) }
                            }
                        }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    HStack {
                        Button("Select All") { selected = Set(players.map(\.id)) }
                        Spacer()
                        Button("Deselect All") { selected = [] }
                    }
                    .font(.callout)
                    PeriodFilter(period: $period)
                }
                .frame(width: 340)
            }
            .padding(16)
        }
        .background(Theme.chrome.ignoresSafeArea())
        .sheet(item: $sharedFile) { ActivityView(items: [$0.url]) }
        .onAppear { selected = Set(players.map(\.id)) }
    }
}

// MARK: - Notes and settings

struct NotesScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var game: Game

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Notes") {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            } trailing: {}
            TextEditor(text: $game.notes)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .topLeading) {
                    if game.notes.isEmpty {
                        Text("Notes about this game")
                            .foregroundStyle(.gray)
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }
                .padding(16)
        }
        .background(Theme.chrome.ignoresSafeArea())
    }
}

/// The settings popover on the game screen.
struct GameSettingsView: View {
    @Binding var game: Game
    @AppStorage("foulLimit") private var foulLimit = 3
    @AppStorage("shotChartEnabled") private var shotChartEnabled = true
    @AppStorage("soundsEnabled") private var soundsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
            HStack {
                Text("Number of fouls")
                Spacer()
                Picker("Number of fouls", selection: $foulLimit) {
                    ForEach([3, 4, 5], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            HStack {
                Text("Quarter length")
                Spacer()
                Picker("Quarter length", selection: Binding(
                    get: { game.periodLength / 60 },
                    set: { minutes in
                        let wasFull = !game.isRunning && Int(game.clock) == game.length(ofPeriod: game.period)
                        game.periodLength = minutes * 60
                        if wasFull { game.resetClock() }
                    }
                )) {
                    ForEach([5, 6, 7, 8], id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.menu)
            }
            Toggle("Shot chart enabled:", isOn: $shotChartEnabled)
            Toggle("Sounds enabled:", isOn: $soundsEnabled)
            Text("With the shot chart off, shots are recorded as soon as you pick the player, without asking for a spot on the pool.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 320)
        .tint(Theme.orange)
        .presentationCompactAdaptation(.popover)
    }
}
