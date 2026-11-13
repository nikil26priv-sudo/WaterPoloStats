import SwiftUI

@main
struct WaterPoloStatsApp: App {
    @State private var store: Store
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if LaunchOptions.useSampleData {
            let store = Store(fileURL: nil)
            store.players = SampleData.players()
            store.teams = SampleData.teams(players: store.players)
            store.games = SampleData.games(players: store.players)
            _store = State(initialValue: store)
            if LaunchOptions.exportTest, let game = store.games.last(where: \.isFinal) {
                // Writes every export to the temporary folder so they can be checked without tapping through the UI.
                _ = Exporter.boxScorePDF(game: game, players: store.players)
                _ = Exporter.gameStatsCSV(game: game, players: store.players)
                _ = Exporter.playsCSV(game: game, players: store.players)
                _ = Exporter.shotChartPDF(game: game, players: store.players, selected: nil, period: nil)
                _ = Exporter.statsCSV(games: store.games, players: store.players, name: "All stats")
                _ = Exporter.backupFile(store.backup(of: store.games))
            }
            return
        }
        #endif
        _store = State(initialValue: Store(fileURL: Store.defaultURL))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.orange)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.save() }
        }
    }
}

/// Launch arguments for opening the app on a particular screen with sample data.
/// Example: `-sampleData -open live -gameTab shots`
enum LaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static let useSampleData = arguments.contains("-sampleData")
    /// `live` or `final`: open that kind of game straight away.
    static let open = value(after: "-open")
    static let tab = value(after: "-tab")
    static let gameTab = value(after: "-gameTab")
    static let showShotSheet = arguments.contains("-shotSheet")
    static let exportTest = arguments.contains("-exportTest")
}
