import SwiftUI

/// Teams: named groups of players. A game is played under a team's name.
struct TeamsView: View {
    @Environment(Store.self) private var store
    let showsBack: Bool
    var showStats: (Team) -> Void

    @State private var editing: Team?
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Teams", showsBack: showsBack) {
                Button("Add New Team") { editing = Team(name: "") }
            } trailing: {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .disabled(store.teams.isEmpty)
            }

            TablePanel {
                HStack(spacing: 0) {
                    Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Nr. of players").frame(width: 110)
                    Text("Nr. of games").frame(width: 110)
                    Color.clear.frame(width: 70, height: 1)
                }
            } content: {
                if store.teams.isEmpty {
                    Text("No teams yet. Tap Add New Team, give it a name and add its players.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
                ForEach(store.teams) { team in
                    TableRow(isEditing: isEditing, onDelete: { store.teams.removeAll { $0.id == team.id } }, action: { editing = team }) {
                        HStack(spacing: 0) {
                            Text(team.name)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(store.players(in: team).count)").frame(width: 110)
                            Text("\(store.games(for: team).count)").frame(width: 110)
                            Button("Stats") { showStats(team) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(width: 70)
                        }
                        .font(.footnote)
                        .monospacedDigit()
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.chrome)
        .sheet(item: $editing) { team in
            TeamEditor(team: team, isNew: !store.teams.contains { $0.id == team.id })
        }
    }
}

/// Name a team and move players between "on the team" and "other players".
private struct TeamEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var team: Team
    let isNew: Bool

    @State private var showNameWarning = false

    var body: some View {
        let onTeam = store.players(in: team)
        let others = store.activePlayers.filter { !team.playerIDs.contains($0.id) }

        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Team Name")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Team Name", text: $team.name)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.words)
                    Rectangle().fill(.secondary).frame(height: 1)
                    if showNameWarning {
                        Text("Team has to have a name!")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 16) {
                    column("Players on the team", players: onTeam, button: "REMOVE") { player in
                        team.playerIDs.removeAll { $0 == player.id }
                    }
                    column("Other players", players: others, button: "ADD") { player in
                        team.playerIDs.append(player.id)
                    }
                }
            }
            .padding(20)
            .navigationTitle(isNew ? "New Team" : "Edit Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        team.name = team.name.trimmingCharacters(in: .whitespaces)
                        guard !team.name.isEmpty else {
                            showNameWarning = true
                            return
                        }
                        store.save(team)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func column(_ title: String, players: [Player], button: String, action: @escaping (Player) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(players) { player in
                        HStack {
                            Text("\(player.capNumber)  \(player.name)")
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Button(button) { action(player) }
                                .font(.caption2.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .frame(minHeight: 36)
                        .overlay(alignment: .bottom) { Color.black.opacity(0.08).frame(height: 1) }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
