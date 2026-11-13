import SwiftUI

/// The main menu on the left and the chosen section on the right.
/// On a phone the menu is the first screen and each section opens from it.
struct RootView: View {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case players, teams, games, statistics, share, about, help

        var id: String { rawValue }
        var title: String {
            switch self {
            case .players: "Players"
            case .teams: "Teams"
            case .games: "Games"
            case .statistics: "Statistics"
            case .share: "Share and backup"
            case .about: "About"
            case .help: "Help"
            }
        }

        static let main: [Section] = [.players, .teams, .games, .statistics, .share]
        static let info: [Section] = [.about, .help]
    }

    struct GameRef: Identifiable { let id: UUID }

    @Environment(Store.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section = Section(rawValue: LaunchOptions.tab ?? "") ?? .games
    @State private var path: [Section] = []
    @State private var openGame: GameRef?
    /// The team the statistics section should open on, set by a team's Stats button.
    @State private var statsTeam: UUID?

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    menu(selection: section) { section = $0 }
                        .frame(width: 305)
                    Theme.line.frame(width: 1)
                    content(section, showsBack: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                NavigationStack(path: $path) {
                    menu(selection: nil) { path = [$0] }
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: Section.self) { section in
                            content(section, showsBack: true)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                }
            }
        }
        .background(Theme.chrome.ignoresSafeArea())
        .fullScreenCover(item: $openGame) { game in
            GameScreen(gameID: game.id)
        }
        .onAppear(perform: openFromLaunchOptions)
    }

    // MARK: Menu

    private func menu(selection: Section?, select: @escaping (Section) -> Void) -> some View {
        VStack(spacing: 0) {
            Text("Water Polo Stats")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
            ScrollView {
                VStack(spacing: 20) {
                    menuCard(Section.main, selection: selection, select: select)
                    menuCard(Section.info, selection: selection, select: select)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(16)
            }
        }
        .background(Theme.chrome)
    }

    private func menuCard(_ sections: [Section], selection: Section?, select: @escaping (Section) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(sections) { item in
                Button { select(item) } label: {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, 20)
                        .background(item == selection ? Theme.rowSelected : Color.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == selection ? .isSelected : [])
                if item != sections.last {
                    Color.black.opacity(0.35).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Sections

    @ViewBuilder
    private func content(_ section: Section, showsBack: Bool) -> some View {
        switch section {
        case .players:
            PlayersView(showsBack: showsBack)
        case .teams:
            TeamsView(showsBack: showsBack) { team in
                statsTeam = team.id
                if showsBack { path = [.statistics] } else { self.section = .statistics }
            }
        case .games:
            GamesView(showsBack: showsBack) { openGame = GameRef(id: $0) }
        case .statistics:
            StatisticsView(showsBack: showsBack, teamID: $statsTeam)
        case .share:
            ShareBackupView(showsBack: showsBack)
        case .about:
            InfoView(showsBack: showsBack, title: "About", paragraphs: InfoView.about)
        case .help:
            InfoView(showsBack: showsBack, title: "Help", paragraphs: InfoView.help)
        }
    }

    private func openFromLaunchOptions() {
        guard openGame == nil, let open = LaunchOptions.open else { return }
        let wantsFinal = open == "final"
        if let game = store.gamesNewestFirst.first(where: { $0.isFinal == wantsFinal }) {
            openGame = GameRef(id: game.id)
        }
    }
}

/// Plain text pages: About and Help.
struct InfoView: View {
    let showsBack: Bool
    let title: String
    let paragraphs: [(heading: String, text: String)]

    static let about: [(heading: String, text: String)] = [
        ("Water Polo Stats", "Track water polo games live from the pool deck: goals, shots, assists, steals, blocks, exclusions, penalties, saves and sprints, with a shot chart for every game."),
        ("Your data", "Everything is stored on this device. Use Share and backup to send games to another device or keep a copy."),
    ]

    static let help: [(heading: String, text: String)] = [
        ("1. Add players", "Open Players and add everyone with their cap number and position. Goalkeepers are shown with a red cap."),
        ("2. Make a team", "Open Teams, add a team and move players onto it."),
        ("3. Start a game", "Open Games and add a new game. Pick your team to pull in its players, then tick who is playing."),
        ("4. Record", "Tap a player and a stat button, in either order. For a shot, then tap the pool where it was taken. Undo removes the last play; Edit in the play-by-play removes any play."),
        ("5. Review and send", "Box Score, Shot Chart, Sketch Board, Notes and Send Play by Play are at the top of the game screen."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: title, showsBack: showsBack) {} trailing: {}
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(paragraphs, id: \.heading) { paragraph in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paragraph.heading)
                                .font(.headline)
                            Text(paragraph.text)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(16)
        }
        .background(Theme.chrome)
    }
}
