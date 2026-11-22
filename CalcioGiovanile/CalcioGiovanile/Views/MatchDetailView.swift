import SwiftUI
import SwiftData
import PhotosUI
import AVKit

struct MatchDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var match: Match

    @State private var showRecorder = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?
    @State private var player: AVPlayer?
    @State private var showDeleteVideo = false

    var body: some View {
        List {
            infoSection
            videoSection
            if match.videoFileName != nil { analysisSection }
            if !match.tracks.isEmpty { resultsSection }
            eventsSection
            Section("Note") {
                TextField("Note dell'allenatore", text: $match.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationTitle(match.opponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: MatchCSV(match: match),
                      preview: SharePreview("Dati \(match.title).csv")) {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .fullScreenCover(isPresented: $showRecorder) { RecordMatchView(match: match) }
        .onChange(of: pickerItem) { _, item in importVideo(item) }
        .onChange(of: match.videoFileName, initial: true) { _, _ in
            player = match.videoURL.map { AVPlayer(url: $0) }
        }
        .alert("Errore", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: { Text(importError ?? "") }
    }

    // MARK: Sezioni

    private var infoSection: some View {
        Section {
            LabeledContent("Data", value: match.date.formatted(date: .long, time: .shortened))
            if !match.location.isEmpty { LabeledContent("Luogo", value: match.location) }
            Stepper("Gol fatti: \(match.goalsFor)", value: $match.goalsFor, in: 0...50)
            Stepper("Gol subiti: \(match.goalsAgainst)", value: $match.goalsAgainst, in: 0...50)
        }
    }

    @ViewBuilder private var videoSection: some View {
        Section("Video") {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .listRowInsets(EdgeInsets())
                Button(role: .destructive) { showDeleteVideo = true } label: {
                    Label("Elimina video", systemImage: "trash")
                }
                .confirmationDialog("Eliminare il video? Le tracce già calcolate restano salvate.",
                                    isPresented: $showDeleteVideo, titleVisibility: .visible) {
                    Button("Elimina", role: .destructive) {
                        VideoStorage.delete(match.videoFileName)
                        match.videoFileName = nil
                    }
                }
            } else {
                Button { showRecorder = true } label: {
                    Label("Registra la partita", systemImage: "record.circle")
                }
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label(importing ? "Importazione…" : "Importa video dal Rullino", systemImage: "photo.on.rectangle")
                }
                .disabled(importing)
                Text("Per l'analisi dei movimenti usa un treppiede fisso, in posizione rialzata, con tutto il campo inquadrato.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var analysisSection: some View {
        Section("Analisi movimenti") {
            NavigationLink {
                CalibrationView(match: match)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text("1 · Calibra il campo")
                        Text(match.calibration == nil ? "Da fare" : "Completata")
                            .font(.caption).foregroundStyle(match.calibration == nil ? .orange : .green)
                    }
                } icon: { Image(systemName: "viewfinder") }
            }
            NavigationLink {
                AnalysisRunView(match: match)
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text("2 · Analisi automatica")
                        Text(match.analysisCompletedAt.map { "Eseguita il \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Rileva e traccia tutti i giocatori")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "wand.and.stars") }
            }
            .disabled(match.calibration == nil)
            NavigationLink {
                TrackAssignmentView(match: match)
            } label: {
                let unassigned = match.tracks.filter { $0.player == nil }.count
                Label {
                    VStack(alignment: .leading) {
                        Text("3 · Assegna le tracce ai giocatori")
                        Text("\(match.tracks.count) tracce, \(unassigned) da assegnare")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "person.crop.rectangle.stack") }
            }
            .disabled(match.tracks.isEmpty)
            NavigationLink {
                ManualTrackingView(match: match)
            } label: {
                Label("Tracciamento manuale di un giocatore", systemImage: "hand.draw")
            }
            .disabled(match.calibration == nil)
            Toggle("Nel 1° tempo attacchiamo verso destra", isOn: $match.attacksRightFirstHalf)
            if let h = match.halfTimeAt {
                LabeledContent("Inizio 2° tempo nel video", value: h.clockString)
            }
        }
    }

    private var resultsSection: some View {
        Section("Risultati") {
            NavigationLink {
                TeamAnalysisView(match: match)
            } label: { Label("Squadra: posizioni medie e compattezza", systemImage: "person.3.sequence") }
            let assigned = Dictionary(grouping: match.tracks.filter { $0.player != nil }, by: { $0.player!.persistentModelID })
            let players = assigned.values.compactMap { $0.first?.player }.sorted { $0.number < $1.number }
            ForEach(players) { p in
                NavigationLink {
                    PlayerAnalysisView(match: match, player: p)
                } label: { Label(p.displayName, systemImage: "figure.run") }
            }
        }
    }

    private var eventsSection: some View {
        Section("Eventi") {
            if match.events.isEmpty {
                Text("Nessun evento. Puoi segnarli durante la registrazione.").foregroundStyle(.secondary)
            }
            ForEach(match.sortedEvents) { e in
                Button {
                    player?.seek(to: CMTime(seconds: max(0, e.time - 5), preferredTimescale: 600))
                    player?.play()
                } label: {
                    HStack {
                        Image(systemName: e.eventKind.symbol).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(e.kind)
                            if let p = e.player { Text(p.displayName).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(e.time.clockString).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .onDelete { idx in
                let list = match.sortedEvents
                idx.forEach { context.delete(list[$0]) }
            }
        }
    }

    private func importVideo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        importing = true
        Task {
            defer { importing = false; pickerItem = nil }
            do {
                if let movie = try await item.loadTransferable(type: ImportedMovie.self) {
                    VideoStorage.delete(match.videoFileName)
                    match.videoFileName = movie.fileName
                    match.calibration = nil
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
