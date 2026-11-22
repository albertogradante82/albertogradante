import SwiftUI
import SwiftData

struct TeamListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.name) private var teams: [Team]
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(teams) { team in
                    NavigationLink(value: team) {
                        VStack(alignment: .leading) {
                            Text(team.name).font(.headline)
                            Text("\(team.category) · \(team.players.count) giocatori")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in idx.map { teams[$0] }.forEach { context.delete($0) } }
            }
            .overlay {
                if teams.isEmpty {
                    ContentUnavailableView("Nessuna squadra", systemImage: "person.3",
                                           description: Text("Crea la tua squadra e inserisci la rosa."))
                }
            }
            .navigationTitle("Squadre")
            .navigationDestination(for: Team.self) { TeamDetailView(team: $0) }
            .toolbar {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showNew) { NewTeamSheet() }
        }
    }
}

struct NewTeamSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "Esordienti (U12)"
    @State private var season = "2026/27"

    static let categories = ["Piccoli Amici (U8)", "Pulcini (U10)", "Esordienti (U12)",
                             "Giovanissimi (U14)", "Allievi (U16)", "Juniores (U18)"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome squadra", text: $name)
                Picker("Categoria", selection: $category) {
                    ForEach(Self.categories, id: \.self) { Text($0) }
                }
                TextField("Stagione", text: $season)
            }
            .navigationTitle("Nuova squadra")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        context.insert(Team(name: name, category: category, season: season))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct TeamDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var team: Team
    @State private var editingPlayer: Player?
    @State private var showNewPlayer = false

    var body: some View {
        List {
            Section("Squadra") {
                TextField("Nome", text: $team.name)
                Picker("Categoria", selection: $team.category) {
                    ForEach(NewTeamSheet.categories, id: \.self) { Text($0) }
                }
                TextField("Stagione", text: $team.season)
            }
            Section("Rosa") {
                ForEach(team.sortedPlayers) { p in
                    Button { editingPlayer = p } label: {
                        HStack {
                            Text("\(p.number)")
                                .font(.headline.monospacedDigit())
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text(p.role).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
                .onDelete { idx in
                    let list = team.sortedPlayers
                    idx.map { list[$0] }.forEach { context.delete($0) }
                }
                Button { showNewPlayer = true } label: { Label("Aggiungi giocatore", systemImage: "plus") }
            }
            Section {
                NavigationLink {
                    SeasonPlayersView(team: team)
                } label: {
                    Label("Statistiche stagionali", systemImage: "chart.bar")
                }
            }
        }
        .navigationTitle(team.name)
        .sheet(item: $editingPlayer) { PlayerEditor(team: team, player: $0) }
        .sheet(isPresented: $showNewPlayer) { PlayerEditor(team: team, player: nil) }
    }
}

struct PlayerEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let team: Team
    let player: Player?
    @State private var name = ""
    @State private var number = 1
    @State private var role = Player.roles[2]
    @State private var birthYear = Calendar.current.component(.year, from: .now) - 11

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome e cognome", text: $name)
                Stepper("Numero maglia: \(number)", value: $number, in: 1...99)
                Picker("Ruolo", selection: $role) { ForEach(Player.roles, id: \.self) { Text($0) } }
                Stepper("Anno di nascita: \(String(birthYear))", value: $birthYear, in: 2000...2025)
            }
            .navigationTitle(player == nil ? "Nuovo giocatore" : "Modifica")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let player {
                    name = player.name; number = player.number; role = player.role
                    birthYear = player.birthYear ?? birthYear
                } else {
                    number = (team.players.map(\.number).max() ?? 0) + 1
                }
            }
        }
    }

    private func save() {
        if let player {
            player.name = name; player.number = number; player.role = role; player.birthYear = birthYear
        } else {
            let p = Player(name: name, number: number, role: role, birthYear: birthYear)
            context.insert(p)
            p.team = team
        }
    }
}

/// Riepilogo stagionale per giocatore (somma di tutte le partite analizzate).
struct SeasonPlayersView: View {
    let team: Team

    var body: some View {
        List(team.sortedPlayers) { p in
            let stats = MatchStatsRow.rows(for: p).map(\.stats)
            NavigationLink {
                PlayerSeasonDetail(player: p)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.displayName).font(.headline)
                    if stats.isEmpty {
                        Text("Nessuna partita analizzata").font(.caption).foregroundStyle(.secondary)
                    } else {
                        let km = stats.map(\.distanceMeters).reduce(0, +) / 1000
                        let mpm = stats.map(\.metersPerMinute).reduce(0, +) / Double(stats.count)
                        let top = stats.map(\.maxSpeedKmh).max() ?? 0
                        Text("\(stats.count) partite · \(km, specifier: "%.1f") km · \(mpm, specifier: "%.0f") m/min · max \(top, specifier: "%.1f") km/h")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Stagione")
    }
}

struct MatchStatsRow: Identifiable {
    let match: Match
    let stats: MovementStats
    var id: UUID { match.id }

    /// Statistiche di un giocatore partita per partita.
    static func rows(for player: Player) -> [MatchStatsRow] {
        let byMatch = Dictionary(grouping: player.tracks.filter { $0.match != nil }, by: { $0.match!.id })
        return byMatch.values.compactMap { tracks -> MatchStatsRow? in
            guard let m = tracks.first?.match else { return nil }
            let pts = MovementAnalyzer.merge(tracks.map { $0.points.map(m.normalized) })
            return MatchStatsRow(match: m, stats: MovementAnalyzer.stats(for: pts, pitch: m.pitch))
        }
        .sorted { $0.match.date < $1.match.date }
    }
}

struct PlayerSeasonDetail: View {
    let player: Player

    var body: some View {
        let rows = MatchStatsRow.rows(for: player)
        List {
            if rows.count > 1 {
                Section("Andamento distanza (m/min)") {
                    TrendChart(values: rows.map { $0.stats.metersPerMinute },
                               labels: rows.map { $0.match.date.formatted(.dateTime.day().month(.abbreviated)) })
                        .frame(height: 160)
                }
            }
            Section("Partite") {
                ForEach(rows) { row in
                    let s = row.stats
                    VStack(alignment: .leading) {
                        Text(row.match.title).font(.headline)
                        Text(row.match.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                        Text("\(s.distanceMeters / 1000, specifier: "%.2f") km · \(s.metersPerMinute, specifier: "%.0f") m/min · \(s.sprintCount) sprint · max \(s.maxSpeedKmh, specifier: "%.1f") km/h")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(player.name)
    }
}
