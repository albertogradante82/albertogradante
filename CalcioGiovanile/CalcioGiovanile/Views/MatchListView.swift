import SwiftUI
import SwiftData
import PhotosUI

struct MatchListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Match.date, order: .reverse) private var matches: [Match]
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(matches) { m in
                    NavigationLink(value: m) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(.headline)
                                Text(m.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(m.isHome ? m.goalsFor : m.goalsAgainst) – \(m.isHome ? m.goalsAgainst : m.goalsFor)")
                                .font(.headline.monospacedDigit())
                            statusIcon(m)
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx {
                        VideoStorage.delete(matches[i].videoFileName)
                        context.delete(matches[i])
                    }
                }
            }
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView("Nessuna partita", systemImage: "sportscourt",
                                           description: Text("Tocca + per registrare o importare una partita."))
                }
            }
            .navigationTitle("Partite")
            .navigationDestination(for: Match.self) { MatchDetailView(match: $0) }
            .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showNew) { NewMatchSheet() }
        }
    }

    @ViewBuilder private func statusIcon(_ m: Match) -> some View {
        if m.analysisCompletedAt != nil {
            Image(systemName: "chart.xyaxis.line").foregroundStyle(.green)
        } else if m.videoFileName != nil {
            Image(systemName: "video").foregroundStyle(.secondary)
        }
    }
}

struct NewMatchSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var team: Team?
    @State private var opponent = ""
    @State private var location = ""
    @State private var isHome = true
    @State private var date = Date()
    @State private var pitch = PitchSize.nineVsNine

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Squadra", selection: $team) {
                        Text("—").tag(Team?.none)
                        ForEach(teams) { Text($0.name).tag(Team?.some($0)) }
                    }
                    TextField("Avversario", text: $opponent)
                    Toggle("In casa", isOn: $isHome)
                    TextField("Campo / luogo", text: $location)
                    DatePicker("Data", selection: $date)
                }
                Section("Campo (metri)") {
                    Picker("Formato", selection: $pitch) {
                        ForEach(PitchSize.presets) { Text($0.name).tag($0) }
                    }
                    Text("Lunghezza \(pitch.length, specifier: "%.0f") × larghezza \(pitch.width, specifier: "%.0f") m. Puoi correggere le misure esatte nella calibrazione.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nuova partita")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        let m = Match(date: date, opponent: opponent, location: location, isHome: isHome, pitch: pitch)
                        context.insert(m)
                        m.team = team
                        dismiss()
                    }
                    .disabled(opponent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { team = team ?? teams.first }
        }
    }
}
