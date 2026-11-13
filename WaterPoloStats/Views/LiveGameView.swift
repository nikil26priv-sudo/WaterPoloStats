import SwiftUI
import UIKit
import AudioToolbox

/// The live tracking screen.
///
/// iPad shows everything at once: scoreboard, play-by-play, stat pad, caps and the pool.
/// Pick a player and a stat in either order; for a shot, then tap the pool where it was taken.
///
/// iPhone shows one way of recording at a time. Pool: tap where a shot was taken, then say who
/// shot and what happened. Caps: tap a player, then tap what they did.
struct LiveGameView: View {
    enum EntryMode: String { case pool, caps }

    /// A stat button on the iPad pad that has been tapped and is waiting for its player or its spot.
    enum PadAction: Hashable {
        case shot(ShotOutcome, Situation)
        case event(EventKind)
        case assist
    }

    @Environment(Store.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Binding var game: Game

    /// Phones show one way of recording at a time; wide screens show the pool and the caps together.
    @AppStorage("entryMode") private var entryMode = EntryMode.pool
    @State private var selected: UUID?
    @State private var shotDraft: ShotDraft?
    @State private var askOpponentGoal = false
    /// Exclusions the scorer has dismissed, or that ended early because of a goal.
    @State private var cleared: Set<UUID> = []
    @State private var fouledOut: Player?
    @State private var feedback = 0
    @State private var armed: PadAction?
    @State private var notice: String?
    @State private var editing: GameEvent?
    @State private var isEditingPlays = false
    @AppStorage("shotChartEnabled") private var shotChartEnabled = true
    @AppStorage("soundsEnabled") private var soundsEnabled = true
    /// Read here so the screen redraws when the foul limit is changed in the settings.
    @AppStorage("foulLimit") private var foulLimit = 3

    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    /// iPad-sized layouts get the all-in-one dashboard.
    private var isWide: Bool { sizeClass == .regular && verticalSizeClass == .regular }

    var body: some View {
        let roster = store.roster(for: game)
        let lines = game.playerLines()

        Group {
            if isWide {
                GeometryReader { geometry in
                    dashboard(roster, lines, size: geometry.size)
                }
            } else {
                VStack(spacing: 0) {
                    Scoreboard(game: $game, teamName: game.teamName)
                    statusStrip(roster: roster)
                    VStack(spacing: 0) {
                        if entryMode == .pool {
                            ScrollView { poolMap.padding(12) }
                            Divider()
                            teamPad
                        } else {
                            ScrollView { playerGrid(roster, lines).padding(12) }
                            Divider()
                            actionPad
                        }
                    }
                    .overlay(alignment: .top) { exclusionChips }
                }
            }
        }
        .sheet(item: $shotDraft) { draft in
            ShotSheet(draft: draft, roster: roster, choosesShooter: draft.playerID == nil, onSave: saveShot)
        }
        .sheet(item: $editing) { event in
            EventEditor(event: event, roster: roster) { updated in
                if let index = game.events.firstIndex(where: { $0.id == updated.id }) {
                    game.events[index] = updated
                }
            }
        }
        .onChange(of: entryMode) { selected = nil }
        .confirmationDialog("Opponent goal", isPresented: $askOpponentGoal, titleVisibility: .visible) {
            Button("Even strength") { logOpponentGoal(.even) }
            Button("Man down (their 6 on 5)") { logOpponentGoal(.powerPlay) }
            Button("Penalty shot") { logOpponentGoal(.penalty) }
        } message: {
            Text("How did they score?")
        }
        .alert(
            "Fouled out",
            isPresented: Binding(get: { fouledOut != nil }, set: { if !$0 { fouledOut = nil } }),
            presenting: fouledOut
        ) { _ in
            Button("OK") {}
        } message: { player in
            Text("\(player.label) has \(Game.personalFoulLimit) personal fouls and can't return to the game.")
        }
        .onReceive(tick) { now in
            if game.isRunning, game.remaining(at: now) <= 0 { game.stopClock(at: now) }
        }
        .onChange(of: feedback) {
            if soundsEnabled { AudioServicesPlaySystemSound(1104) }
        }
        .sensoryFeedback(.impact, trigger: feedback)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if LaunchOptions.showShotSheet, shotDraft == nil {
                if isWide {
                    selected = roster.first { !$0.isGoalie }?.id
                    armed = .shot(.goal, .even)
                } else {
                    beginShot(at: ShotPoint(x: 0.62, y: 0.34))
                }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Status strip

    private func statusStrip(roster: [Player]) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Goalie in the cage", selection: $game.goalieID) {
                    Text("None").tag(UUID?.none)
                    ForEach(roster.sorted { $0.isGoalie && !$1.isGoalie }) { player in
                        Text(player.label).tag(UUID?.some(player.id))
                    }
                }
            } label: {
                Label(store.player(game.goalieID).map { "In goal: \($0.label)" } ?? "Choose goalie", systemImage: "hand.raised.fill")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Picker("Record with", selection: $entryMode) {
                Text("Pool").tag(EntryMode.pool)
                Text("Caps").tag(EntryMode.caps)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(.bar)
    }

    /// Countdown chips for running exclusions. They float over the top of the recording area
    /// so nothing underneath moves when one appears.
    private var exclusionChips: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 6) {
                ForEach(activeExclusions(at: context.date), id: \.event.id) { item in
                    exclusionChip(item.event, secondsLeft: item.secondsLeft)
                }
            }
            .padding(.top, 8)
        }
    }

    private func exclusionChip(_ event: GameEvent, secondsLeft: Int) -> some View {
        let isOurs = event.kind == .exclusion
        let title = isOurs ? "#\(store.player(event.playerID)?.capNumber ?? 0) out" : "6 on 5"
        return Button {
            cleared.insert(event.id)
        } label: {
            HStack(spacing: 4) {
                Text("\(title) \(Format.clock(secondsLeft))")
                    .monospacedDigit()
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(isOurs ? Color.orange : Color.green, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(secondsLeft) seconds left. Tap to clear.")
    }

    /// Exclusions in this period whose time has not run out on the game clock.
    private func activeExclusions(at now: Date) -> [(event: GameEvent, secondsLeft: Int)] {
        let remaining = game.remaining(at: now)
        return game.events.compactMap { event in
            guard event.kind == .exclusion || event.kind == .exclusionDrawn,
                  event.period == game.period,
                  !cleared.contains(event.id) else { return nil }
            let left = Double(game.exclusionLength) - (Double(event.clock) - remaining)
            guard left > 0 else { return nil }
            return (event, min(game.exclusionLength, Int(left.rounded(.up))))
        }
    }

    private func clearExclusions() {
        for event in game.events where event.kind == .exclusion || event.kind == .exclusionDrawn {
            cleared.insert(event.id)
        }
    }

    // MARK: Pool

    /// This game's shots so far. Tap anywhere on it to record a new one from that spot.
    private var livePool: some View {
        let marks = game.events.compactMap { event -> ShotMark? in
            guard event.kind == .shot, let location = event.location else { return nil }
            return ShotMark(id: event.id, point: location, outcome: event.outcome ?? .missed)
        }
        return PoolDiagram(marks: marks, markSize: 15) { poolTapped($0) }
    }

    private var poolMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            livePool
            Text("Tap the pool where a shot was taken, then pick who shot and what happened.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ShotLegend()
        }
        .frame(maxWidth: 640)
    }

    // MARK: Players

    private func playerGrid(_ roster: [Player], _ lines: [UUID: StatLine]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: isWide ? 70 : 62), spacing: 8)], spacing: 8) {
            ForEach(roster) { player in
                playerTile(player, line: lines[player.id] ?? StatLine())
            }
        }
    }

    private func playerTile(_ player: Player, line: StatLine) -> some View {
        let fouls = line.personalFouls
        let isOut = fouls >= Game.personalFoulLimit
        let isSelected = selected == player.id
        let cap = player.isGoalie ? Color.goalieCap : Theme.cap

        return Button {
            tapPlayer(player.id)
        } label: {
            VStack(spacing: 2) {
                Text("\(player.capNumber)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(isOut ? "Fouled out" : (player.firstName.isEmpty ? " " : player.firstName))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    ForEach(0..<Game.personalFoulLimit, id: \.self) { index in
                        Circle()
                            .fill(foulDotColor(filled: index < fouls, onCap: isSelected))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: isWide ? 64 : 70)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? AnyShapeStyle(cap) : AnyShapeStyle(cap.opacity(0.14)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if line.goals > 0 {
                    Text("\(line.goals)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .foregroundStyle(.white)
                        .background(.green, in: Capsule())
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if game.goalieID == player.id {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white : Color.goalieCap)
                        .padding(5)
                }
            }
            .opacity(isOut ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(player.label), \(line.goals) goals, \(fouls) personal fouls")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func foulDotColor(filled: Bool, onCap: Bool) -> Color {
        if onCap { return filled ? .white : .white.opacity(0.35) }
        return filled ? .orange : .primary.opacity(0.15)
    }

    // MARK: Stat pad

    /// What is selected, or the last thing recorded.
    private var statusLine: some View {
        HStack {
            if let player = store.player(selected) {
                Text("\(player.label): what happened?")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            } else if let last = game.events.last {
                Text("Last: \(Game.periodName(last.period)) \(Format.clock(last.clock)) · \(last.summary(name: { store.playerLabel($0) }))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing recorded yet.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .lineLimit(1)
    }

    /// The few things that don't need a spot on the pool, shown under the pool on phones.
    private var teamPad: some View {
        VStack(spacing: 10) {
            statusLine
            HStack(spacing: 8) {
                Button("Opp. goal") { askOpponentGoal = true }
                    .buttonStyle(PadButtonStyle(tint: .red, filled: true))
                Button("Save") { log(.save) }
                    .buttonStyle(PadButtonStyle())
                    .disabled(game.goalieID == nil)
                Button("Timeout") { log(.timeout) }
                    .buttonStyle(PadButtonStyle(tint: .secondary))
                Button("Undo", action: undo)
                    .buttonStyle(PadButtonStyle(tint: .secondary))
                    .disabled(game.events.isEmpty)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var actionPad: some View {
        VStack(spacing: 10) {
            statusLine

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Button("Goal") { beginShot(.goal) }
                        .buttonStyle(PadButtonStyle(tint: .green, filled: true))
                        .disabled(selected == nil)
                    playerButton("No goal") { beginShot(.saved) }
                    playerButton("Steal") { log(.steal) }
                    playerButton("Block") { log(.block) }
                }
                GridRow {
                    playerButton("Turnover") { log(.turnover) }
                    playerButton("Ex. drawn") { log(.exclusionDrawn) }
                    playerButton("Pen. drawn") { log(.penaltyDrawn) }
                    Button("Save") { log(.save) }
                        .buttonStyle(PadButtonStyle())
                        .disabled(selected == nil && game.goalieID == nil)
                }
                GridRow {
                    playerButton("Exclusion", tint: .orange) { log(.exclusion) }
                    playerButton("Pen. foul", tint: .orange) { log(.penaltyFoul) }
                    Button("Sprint won") { log(.sprintWon) }
                        .buttonStyle(PadButtonStyle())
                    Button("Sprint lost") { log(.sprintLost) }
                        .buttonStyle(PadButtonStyle())
                }
                GridRow {
                    Button("Opponent goal") { askOpponentGoal = true }
                        .buttonStyle(PadButtonStyle(tint: .red, filled: true))
                        .gridCellColumns(2)
                    Button("Timeout") { log(.timeout) }
                        .buttonStyle(PadButtonStyle(tint: .secondary))
                    Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                        .labelStyle(.titleOnly)
                        .buttonStyle(PadButtonStyle(tint: .secondary))
                        .disabled(game.events.isEmpty)
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func playerButton(_ title: String, tint: Color = Theme.cap, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PadButtonStyle(tint: tint))
            .disabled(selected == nil)
    }

    // MARK: Logging

    private func log(_ kind: EventKind) {
        var player = kind == .timeout ? nil : selected
        if kind == .save, player == nil { player = game.goalieID }
        if kind.needsPlayer, player == nil { return }

        game.log(kind, player: player)
        if kind == .timeout || kind == .penaltyFoul || kind == .penaltyDrawn { game.stopClock() }
        notice = nil
        if kind.isPersonalFoul, let player, game.personalFouls(for: player) >= Game.personalFoulLimit {
            fouledOut = store.player(player)
        }
        selected = nil
        feedback += 1
    }

    /// A penalty right after one was drawn, 6 on 5 while their player is out, otherwise even.
    private var likelySituation: Situation {
        if game.events.last?.kind == .penaltyDrawn { return .penalty }
        if activeExclusions(at: .now).contains(where: { $0.event.kind == .exclusionDrawn }) { return .powerPlay }
        return .even
    }

    /// Caps first: the player is already selected, the spot is added in the sheet.
    private func beginShot(_ outcome: ShotOutcome) {
        guard let selected else { return }
        // The time is taken now, so filling in the details doesn't push the event later.
        shotDraft = ShotDraft(playerID: selected, outcome: outcome, situation: likelySituation, period: game.period, clock: game.clockSeconds())
    }

    /// Pool first: the spot is known, the sheet asks who shot and what happened.
    private func beginShot(at point: ShotPoint) {
        shotDraft = ShotDraft(playerID: selected, outcome: nil, situation: likelySituation, period: game.period, clock: game.clockSeconds(), location: point)
    }

    private func saveShot(_ draft: ShotDraft) {
        guard let shooter = draft.playerID, let outcome = draft.outcome else { return }
        var event = GameEvent(kind: .shot, period: draft.period, clock: draft.clock, playerID: shooter)
        event.outcome = outcome
        event.situation = draft.situation
        event.assistID = outcome == .goal ? draft.assistID : nil
        event.location = draft.location ?? (draft.situation == .penalty ? PoolGeometry.penaltySpot : nil)
        game.events.append(event)
        if outcome == .goal {
            game.stopClock()
            clearExclusions()
        }
        selected = nil
        armed = nil
        notice = nil
        feedback += 1
    }

    private func logOpponentGoal(_ situation: Situation) {
        var event = game.log(.goalAgainst, player: game.goalieID)
        event.situation = situation
        game.events[game.events.count - 1] = event
        game.stopClock()
        clearExclusions()
        selected = nil
        armed = nil
        notice = nil
        feedback += 1
    }

    private func undo() {
        guard !game.events.isEmpty else { return }
        game.events.removeLast()
        feedback += 1
    }
}

// MARK: - Dashboard (iPad)

extension LiveGameView {
    private var waitingForSpot: Bool {
        if case .shot = armed, selected != nil { return true }
        return false
    }

    /// One screen with everything: play-by-play, scoreboard and the player table across the top,
    /// the stat buttons and player tiles bottom left, the pool bottom right.
    private func dashboard(_ roster: [Player], _ lines: [UUID: StatLine], size: CGSize) -> some View {
        let gap: CGFloat = 10
        let inner = size.width - gap * 3
        let leftWidth = (inner * 0.62).rounded()
        let rightWidth = inner - leftWidth
        let playsWidth = (leftWidth * 0.54).rounded()
        let topHeight = min(214, size.height * 0.32)

        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                playByPlayPanel
                    .frame(width: playsWidth)
                scoreboardPanel(roster: roster)
                    .frame(width: leftWidth - playsWidth - gap)
                playerTable(roster, lines)
                    .frame(width: rightWidth)
            }
            .frame(height: topHeight)

            HStack(alignment: .top, spacing: gap) {
                padPanel(roster, lines)
                    .frame(width: leftWidth)
                poolPanel
                    .frame(width: rightWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(gap)
        .background(Theme.chrome)
    }

    // MARK: Play by play

    /// Everything recorded so far, newest first. Undo removes the latest; Edit shows a delete button on every play.
    private var playByPlayPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Play by Play")
                Spacer()
                Button(isEditingPlays ? "Done" : "Edit") { isEditingPlays.toggle() }
                    .buttonStyle(.plain)
                    .disabled(game.events.isEmpty && !isEditingPlays)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.24)], startPoint: .top, endPoint: .bottom))

            ScrollView {
                LazyVStack(spacing: 0) {
                    if game.events.isEmpty {
                        Text("Nothing recorded yet.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 24)
                    }
                    let events = Array(game.events.reversed())
                    ForEach(events) { event in
                        HStack(spacing: 8) {
                            if isEditingPlays {
                                Button("Delete", systemImage: "minus.circle.fill") {
                                    game.events.removeAll { $0.id == event.id }
                                }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.red)
                                .buttonStyle(.plain)
                            } else {
                                Text(Game.periodName(event.period))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 26, alignment: .leading)
                            }
                            Text(playText(event))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if !isEditingPlays, event.id == events.first?.id {
                                Button("Undo", action: undo)
                                    .font(.footnote)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                        .onTapGesture { if !isEditingPlays { editing = event } }
                        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                    }
                }
            }
            .background(Theme.raised)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// "Johny Clore - Goal (6 on 5)", "Hill 2025 - Goal".
    private func playText(_ event: GameEvent) -> String {
        let who = event.kind == .goalAgainst
            ? game.opponent
            : store.playerName(event.playerID, fallback: game.teamName.isEmpty ? "Team" : game.teamName)
        var what: String
        switch event.kind {
        case .shot:
            what = event.outcome == .goal ? "Goal" : "Shot \((event.outcome ?? .missed).title)"
            if event.situation != .even { what += " (\(event.situation.title()))" }
            if event.outcome == .goal, let assist = event.assistID { what += ", assist \(store.playerName(assist))" }
        case .goalAgainst:
            what = "Goal"
            if event.situation != .even { what += " (\(event.situation.title()))" }
        default:
            what = event.kind.title
        }
        return "\(who) - \(what)"
    }

    // MARK: Scoreboard

    private func scoreboardPanel(roster: [Player]) -> some View {
        let team = game.events.teamLine()
        return VStack(spacing: 6) {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Text(game.teamName.isEmpty ? "Home" : game.teamName)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(game.opponent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                DotMatrixText(text: "\(game.goalsFor):\(game.goalsAgainst)", dot: 6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 3))
                    .accessibilityLabel("Score \(game.goalsFor) to \(game.goalsAgainst)")

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { period in
                        let isCurrent = period == 5 ? game.period >= 5 : game.period == period
                        Button(period == 5 ? "OT" : "Q\(period)") { game.goToPeriod(period) }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(isCurrent ? Color.white.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
            }
            .padding(8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))

            VStack(spacing: 3) {
                infoRow("Quarter score:", "\(game.goalsFor(inPeriod: game.period)):\(game.goalsAgainst(inPeriod: game.period))")
                infoRow("Exclusions:", "\(team.personalFouls)   Drawn: \(team.exclusionsDrawn + team.penaltiesDrawn)")
                HStack(spacing: 6) {
                    Button {
                        if game.isRunning { game.stopClock() } else { game.startClock() }
                    } label: {
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            Label(Format.clock(game.clockSeconds(at: context.date)), systemImage: game.isRunning ? "pause.fill" : "play.fill")
                                .monospacedDigit()
                                .foregroundStyle(game.isRunning ? Color.green : Color.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(game.isRunning ? "Stop clock" : "Start clock")
                    Menu {
                        Button("Add 10 seconds") { game.adjustClock(by: 10) }
                        Button("Add 1 second") { game.adjustClock(by: 1) }
                        Button("Remove 1 second") { game.adjustClock(by: -1) }
                        Button("Remove 10 seconds") { game.adjustClock(by: -10) }
                        Button("Reset clock") { game.resetClock() }
                    } label: {
                        Image(systemName: "plusminus.circle")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel("Adjust clock")
                    Spacer(minLength: 4)
                    Menu {
                        Picker("Goalie in the cage", selection: $game.goalieID) {
                            Text("None").tag(UUID?.none)
                            ForEach(roster.sorted { $0.isGoalie && !$1.isGoalie }) { player in
                                Text(player.label).tag(UUID?.some(player.id))
                            }
                        }
                    } label: {
                        Text(store.player(game.goalieID).map { "In goal: #\($0.capNumber)" } ?? "Goalie?")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .foregroundStyle(.white)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
    }

    // MARK: Player table

    private func playerTable(_ roster: [Player], _ lines: [UUID: StatLine]) -> some View {
        TablePanel {
            HStack(spacing: 0) {
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                Text("G").frame(width: 34)
                Text("SH").frame(width: 34)
                Text("AST").frame(width: 34)
                Text("FOULS").frame(width: 58)
            }
        } content: {
            ForEach(roster) { player in
                let line = lines[player.id] ?? StatLine()
                HStack(spacing: 0) {
                    Text(player.shortName.isEmpty ? "#\(player.capNumber)" : player.shortName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(line.goals)").frame(width: 34)
                    Text("\(line.shots)").frame(width: 34)
                    Text("\(line.assists)").frame(width: 34)
                    HStack(spacing: 3) {
                        ForEach(0..<Game.personalFoulLimit, id: \.self) { index in
                            Circle()
                                .fill(index < line.personalFouls ? Color.black : Color.black.opacity(0.15))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(width: 58)
                    .accessibilityLabel("\(line.personalFouls) fouls")
                }
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(selected == player.id ? Theme.rowSelected : Color.clear)
                .overlay(alignment: .bottom) { Color.black.opacity(0.08).frame(height: 1) }
            }
        }
    }

    // MARK: Stat pad

    private func padPanel(_ roster: [Player], _ lines: [UUID: StatLine]) -> some View {
        let spacing: CGFloat = 8
        return VStack(spacing: 8) {
            // Six equal columns: a made / missed pair for each situation, then sprints and the other stats.
            Grid(horizontalSpacing: spacing, verticalSpacing: 4) {
                GridRow {
                    ForEach(Situation.allCases) { situation in
                        GroupLabel(title: situation == .even ? "Even strength" : situation.title())
                            .gridCellColumns(2)
                    }
                }
                GridRow {
                    ForEach(Situation.allCases) { situation in
                        shotButton(.goal, situation)
                        shotButton(.missed, situation)
                    }
                }
                GridRow {
                    GroupLabel(title: "Sprints")
                        .gridCellColumns(2)
                    GroupLabel(title: "Other stats")
                        .gridCellColumns(4)
                }
                .padding(.top, 4)
                GridRow {
                    armButton("Won", .event(.sprintWon))
                    armButton("Lost", .event(.sprintLost))
                    armButton("Block", .event(.block))
                    armButton("Assist", .assist)
                    armButton("Steal", .event(.steal))
                    armButton("Turnover", .event(.turnover))
                }
            }

            GeometryReader { geometry in
                let column = (geometry.size.width - spacing * 5) / 6
                HStack(alignment: .top, spacing: spacing) {
                    playerTiles(roster, lines, height: geometry.size.height)
                        .frame(width: column * 4 + spacing * 3)
                    sidePad
                        .frame(width: column * 2 + spacing)
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .top) { exclusionChips }
    }

    private func shotButton(_ outcome: ShotOutcome, _ situation: Situation) -> some View {
        let action = PadAction.shot(outcome, situation)
        return Button { tapAction(action) } label: {
            VStack(spacing: 0) {
                Text(situation == .even ? "Even" : situation.title())
                    .font(.system(size: 9, weight: .bold))
                Text(outcome == .goal ? "Goal" : "Missed")
            }
        }
        .buttonStyle(GlossButtonStyle(color: outcome == .goal ? Theme.made : Theme.missed, selected: armed == action))
        .accessibilityLabel("\(situation.title()) \(outcome == .goal ? "goal" : "missed shot")")
        .accessibilityAddTraits(armed == action ? .isSelected : [])
    }

    private func armButton(_ title: String, _ action: PadAction, color: Color = Theme.steel, height: CGFloat = 46) -> some View {
        Button(title) { tapAction(action) }
            .buttonStyle(GlossButtonStyle(color: color, selected: armed == action, height: height))
            .accessibilityAddTraits(armed == action ? .isSelected : [])
    }

    /// Player tiles, four across, with empty tiles filling out the last rows.
    private func playerTiles(_ roster: [Player], _ lines: [UUID: StatLine], height: CGFloat) -> some View {
        let spacing: CGFloat = 8
        let slots = max(12, Int((Double(roster.count) / 4).rounded(.up)) * 4)
        let rows = CGFloat(slots / 4)
        let tileHeight = max(54, (height - spacing * (rows - 1)) / rows)
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 4), spacing: spacing) {
                ForEach(0..<slots, id: \.self) { index in
                    if index < roster.count {
                        dashboardTile(roster[index], line: lines[roster[index].id] ?? StatLine(), height: tileHeight)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.tile.opacity(0.75), Theme.tile.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .frame(height: tileHeight)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func dashboardTile(_ player: Player, line: StatLine, height: CGFloat) -> some View {
        let isSelected = selected == player.id
        let isOut = line.personalFouls >= Game.personalFoulLimit
        return Button { tapPlayer(player.id) } label: {
            VStack(spacing: 0) {
                Text("\(player.capNumber)")
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                Text(isOut ? "Fouled out" : (player.lastName.isEmpty ? player.firstName : player.lastName))
                    .font(.caption.weight(.medium))
                if !isOut, !player.lastName.isEmpty {
                    Text(player.firstName)
                        .font(.caption.weight(.medium))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(player.isGoalie ? Color(red: 1, green: 0.72, blue: 0.72) : Color.white)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: isSelected ? 0.55 : 0.42), Color(white: isSelected ? 0.40 : 0.28)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Color.black.opacity(0.4), lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isOut ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(player.label), \(line.goals) goals, \(line.personalFouls) fouls")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Fouls, opponent goals and goalie buttons beside the player tiles.
    private var sidePad: some View {
        let spacing: CGFloat = 8
        return VStack(spacing: 5) {
            GroupLabel(title: "Personal fouls")
            HStack(spacing: spacing) {
                armButton("Committed", .event(.exclusion), height: 42)
                armButton("Forced", .event(.exclusionDrawn), height: 42)
            }
            HStack(spacing: spacing) {
                armButton("Penalty foul", .event(.penaltyFoul), height: 36)
                armButton("Penalty drawn", .event(.penaltyDrawn), height: 36)
            }
            GroupLabel(title: "Opponent goal")
                .padding(.top, 3)
            HStack(spacing: spacing) {
                opponentButton("Even", .even)
                opponentButton("6 on 5", .powerPlay)
            }
            HStack(spacing: spacing) {
                opponentButton("Penalty", .penalty)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
            GroupLabel(title: "Goalie and team")
                .padding(.top, 3)
            HStack(spacing: spacing) {
                armButton("Save", .event(.save), color: Color(white: 0.34), height: 36)
                armButton("Timeout", .event(.timeout), color: Color(white: 0.34), height: 36)
            }
            Spacer(minLength: 0)
            Text(promptText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.orange)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private func opponentButton(_ title: String, _ situation: Situation) -> some View {
        Button(title) { logOpponentGoal(situation) }
            .buttonStyle(GlossButtonStyle(color: Color(white: 0.34), height: 36))
            .accessibilityLabel("Opponent goal, \(situation.title(defending: true))")
    }

    /// What the pad is waiting for.
    private var promptText: String {
        let player = store.player(selected)
        switch (armed, player) {
        case (.shot?, let player?):
            return "\(player.shortName): tap the pool"
        case (.shot?, nil):
            return "Now pick the shooter"
        case (.event(let kind)?, nil):
            return "\(kind.title): pick the player"
        case (.assist?, nil):
            return "Assist: pick the player"
        case (nil, let player?):
            return "\(player.shortName): pick a stat"
        default:
            return notice ?? ""
        }
    }

    // MARK: Pool

    /// The pool, lit up while a shot is waiting for its spot.
    private var poolPanel: some View {
        VStack(spacing: 8) {
            livePool
                .overlay {
                    if waitingForSpot {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.yellow, lineWidth: 4)
                            .allowsHitTesting(false)
                    } else if shotChartEnabled {
                        Color.black.opacity(armed == nil && selected == nil ? 0 : 0.25)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottom) {
                    if waitingForSpot {
                        Text("Tap where the shot was taken")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.yellow, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                ShotLegend()
                Spacer(minLength: 8)
                if waitingForSpot {
                    Button("No spot") { recordArmedShot(at: nil) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(minHeight: 30)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Pad logic

    func tapPlayer(_ id: UUID) {
        selected = selected == id ? nil : id
        notice = nil
        if isWide { resolveArmed() }
    }

    private func tapAction(_ action: PadAction) {
        notice = nil
        armed = armed == action ? nil : action
        resolveArmed()
    }

    /// Records the armed stat as soon as it has everything it needs.
    /// Shots are the exception: they wait for a tap on the pool, unless the shot chart is off.
    private func resolveArmed() {
        switch armed {
        case .event(let kind)?:
            if kind.needsPlayer, selected == nil { return }
            armed = nil
            log(kind)
        case .assist?:
            guard let player = selected else { return }
            armed = nil
            selected = nil
            addAssist(player)
        case .shot?:
            if !shotChartEnabled, selected != nil { recordArmedShot(at: nil) }
        case nil:
            break
        }
    }

    /// Credits the assist on the most recent goal.
    private func addAssist(_ player: UUID) {
        guard let index = game.events.lastIndex(where: \.isGoal) else {
            notice = "No goal to add an assist to yet"
            return
        }
        guard game.events[index].playerID != player else {
            notice = "The scorer can't assist their own goal"
            return
        }
        game.events[index].assistID = player
        notice = "Assist added to \(store.playerName(game.events[index].playerID))'s goal"
        feedback += 1
    }

    func poolTapped(_ point: ShotPoint) {
        guard isWide else {
            if !game.isFinal { beginShot(at: point) }
            return
        }
        if waitingForSpot {
            recordArmedShot(at: point)
            return
        }
        // Not everything is picked yet, so ask for the rest in the sheet.
        var outcome: ShotOutcome?
        var situation = Situation.even
        if case .shot(let armedOutcome, let armedSituation)? = armed {
            outcome = armedOutcome
            situation = armedSituation
        }
        shotDraft = ShotDraft(playerID: selected, outcome: outcome, situation: situation, period: game.period, clock: game.clockSeconds(), location: point)
        armed = nil
    }

    private func recordArmedShot(at point: ShotPoint?) {
        guard case .shot(let outcome, let situation)? = armed, let shooter = selected else { return }
        saveShot(ShotDraft(playerID: shooter, outcome: outcome, situation: situation, period: game.period, clock: game.clockSeconds(), location: point))
    }
}

// MARK: - Scoreboard

struct Scoreboard: View {
    @Binding var game: Game
    let teamName: String

    private var periodOver: Bool { !game.isRunning && game.clock <= 0 }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                score(teamName, game.goalsFor)
                VStack(spacing: 2) {
                    Text(Game.periodName(game.period))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Button(action: toggleClock) {
                        TimelineView(.periodic(from: .now, by: 0.2)) { context in
                            Text(Format.clock(game.clockSeconds(at: context.date)))
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(game.isRunning ? Color.green : Color.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(game.isRunning ? "Stop clock" : "Start clock")
                    Text(periodOver ? "Period over" : game.isRunning ? "Running · tap to stop" : "Stopped · tap to start")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(minWidth: 150)
                score(game.opponent, game.goalsAgainst)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { controls }
                VStack(spacing: 8) { controls }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.poolDeep)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var controls: some View {
                if periodOver {
                    Button(game.period >= Game.regulationPeriods ? "Start overtime" : "Start \(Game.periodName(game.period + 1))") {
                        game.advancePeriod()
                    }
                    .buttonStyle(.borderedProminent)
                    if game.period >= Game.regulationPeriods {
                        Button("End game") { game.finish() }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                    }
                }
                Menu {
                    Button("Add 1 second") { game.adjustClock(by: 1) }
                    Button("Add 10 seconds") { game.adjustClock(by: 10) }
                    Button("Remove 1 second") { game.adjustClock(by: -1) }
                    Button("Remove 10 seconds") { game.adjustClock(by: -10) }
                    Divider()
                    Button("Reset period clock") { game.resetClock() }
                    Button("End period now") { game.adjustClock(by: -Double(game.length(ofPeriod: game.period))); game.stopClock() }
                    if game.period > 1 {
                        Button("Go back to \(Game.periodName(game.period - 1))") {
                            game.period -= 1
                            game.runningSince = nil
                            game.clock = 0
                        }
                    }
                } label: {
                    Label("Adjust clock", systemImage: "clock.arrow.circlepath")
                        .font(.footnote.weight(.semibold))
                }
                .tint(.white)
    }

    private func score(_ name: String, _ goals: Int) -> some View {
        VStack(spacing: 0) {
            Text(name.uppercased())
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white.opacity(0.75))
            Text("\(goals)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func toggleClock() {
        if game.isRunning { game.stopClock() } else { game.startClock() }
    }
}
