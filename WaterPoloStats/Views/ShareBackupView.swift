import SwiftUI
import UniformTypeIdentifiers

/// Pick games and send them as a file, or read in a file sent from another device.
struct ShareBackupView: View {
    @Environment(Store.self) private var store
    let showsBack: Bool

    @State private var selected: Set<UUID> = []
    @State private var sharedFile: SharedFile?
    @State private var isImporting = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Share and Backup", showsBack: showsBack) {
                Button("Receive Games") { isImporting = true }
            } trailing: {
                Button("Send", action: send)
                    .disabled(selected.isEmpty)
            }

            Text(message ?? "Select games that you want to share")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 8)

            TablePanel {
                Text("Game")
            } content: {
                if store.games.isEmpty {
                    Text("No games to share yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
                ForEach(store.games.reversed()) { game in
                    TableRow(action: { toggle(game.id) }) {
                        Image(systemName: selected.contains(game.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected.contains(game.id) ? Theme.orange : Color.secondary)
                        GameRow(game: game)
                    }
                    .accessibilityAddTraits(selected.contains(game.id) ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Theme.chrome)
        .sheet(item: $sharedFile) { ActivityView(items: [$0.url]) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            receive(result)
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func send() {
        let games = store.games.filter { selected.contains($0.id) }
        if let url = Exporter.backupFile(store.backup(of: games)) {
            sharedFile = SharedFile(url: url)
        }
    }

    private func receive(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try JSONDecoder().decode(Store.Backup.self, from: Data(contentsOf: url))
            let count = store.merge(backup)
            message = "Received \(count) \(count == 1 ? "game" : "games")."
        } catch {
            message = "That file isn't a games file from this app."
        }
    }
}
