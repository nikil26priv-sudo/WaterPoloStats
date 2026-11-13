import SwiftUI

/// Every player, with height, weight, position and cap number.
struct PlayersView: View {
    @Environment(Store.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    let showsBack: Bool

    @State private var search = ""
    @State private var editing: Player?
    @State private var isEditing = false

    private var players: [Player] {
        let all = store.activePlayers
        let key = search.trimmingCharacters(in: .whitespaces).lowercased()
        return key.isEmpty ? all : all.filter { $0.name.lowercased().contains(key) || "\($0.capNumber)" == key }
    }

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Players", showsBack: showsBack) {
                Button("Add New Player") {
                    editing = Player(firstName: "", lastName: "", capNumber: store.nextCapNumber)
                }
            } trailing: {
                if isWide {
                    TextField("Search Players", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                }
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .disabled(store.activePlayers.isEmpty)
            }

            TablePanel {
                HStack(spacing: 0) {
                    Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                    if isWide {
                        Text("Height").frame(width: 120)
                        Text("Weight").frame(width: 130)
                    }
                    Text("Position").frame(width: isWide ? 160 : 60)
                    Text("#").frame(width: 44)
                }
            } content: {
                if players.isEmpty {
                    Text(store.activePlayers.isEmpty ? "No players yet. Tap Add New Player to start your roster." : "No players match the search.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
                ForEach(players) { player in
                    TableRow(isEditing: isEditing, onDelete: { store.remove(player) }, action: { editing = player }) {
                        HStack(spacing: 0) {
                            Text(player.name.isEmpty ? "Player \(player.capNumber)" : player.name)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if isWide {
                                Text(player.heightText).frame(width: 120)
                                Text(player.weightText).frame(width: 130)
                            }
                            Text(isWide ? player.position.title : player.position.short)
                                .frame(width: isWide ? 160 : 60)
                            Text("\(player.capNumber)")
                                .monospacedDigit()
                                .frame(width: 44)
                        }
                        .font(.footnote)
                        .lineLimit(1)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.chrome)
        .sheet(item: $editing) { player in
            PlayerEditor(player: player, isNew: !store.players.contains { $0.id == player.id }) { store.save($0) }
        }
    }
}

private struct PlayerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var player: Player
    let isNew: Bool
    var onSave: (Player) -> Void

    @FocusState private var firstNameFocused: Bool

    private static let defaultBirthDate = Calendar.current.date(from: DateComponents(year: 2008, month: 1, day: 1)) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First Name", text: $player.firstName)
                        .textInputAutocapitalization(.words)
                        .focused($firstNameFocused)
                    TextField("Last Name", text: $player.lastName)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    DatePicker(
                        "Date of birth",
                        selection: Binding(get: { player.birthDate ?? Self.defaultBirthDate }, set: { player.birthDate = $0 }),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    Picker("Position", selection: $player.position) {
                        ForEach(Position.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Cap number: \(player.capNumber)", value: $player.capNumber, in: 1...99)
                    LabeledContent("Height (cm)") {
                        TextField("optional", value: $player.heightCm, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weight (kg)") {
                        TextField("optional", value: $player.weightKg, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle(isNew ? "Add New Player" : "Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        player.firstName = player.firstName.trimmingCharacters(in: .whitespaces)
                        player.lastName = player.lastName.trimmingCharacters(in: .whitespaces)
                        onSave(player)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { firstNameFocused = isNew }
        }
    }
}
