import SwiftUI
import SwiftData

/// L'analisi produce "tracce" anonime: qui l'allenatore le collega ai propri giocatori.
/// Lo stesso giocatore può avere più tracce (il tracking si interrompe in mischie e contrasti).
struct TrackAssignmentView: View {
    @Environment(\.modelContext) private var context
    @Bindable var match: Match
    @State private var clusterFilter: Int? = nil
    @State private var onlyUnassigned = true
    @State private var selected: Track?
    @State private var confirmCleanup = false

    struct ClusterInfo: Identifiable {
        let id: Int
        let hex: String
        let count: Int
    }

    private var clusters: [ClusterInfo] {
        Dictionary(grouping: match.tracks.filter { $0.colorCluster >= 0 }, by: \.colorCluster)
            .map { ClusterInfo(id: $0.key, hex: $0.value.first?.colorHex ?? "#888888", count: $0.value.count) }
            .sorted { $0.id < $1.id }
    }

    private var filtered: [Track] {
        match.tracks
            .filter { clusterFilter == nil || $0.colorCluster == clusterFilter }
            .filter { !onlyUnassigned || $0.player == nil }
            .sorted { $0.duration > $1.duration }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip(title: "Tutte", color: nil, active: clusterFilter == nil) { clusterFilter = nil }
                        ForEach(clusters) { c in
                            chip(title: "Maglia \(c.id + 1) (\(c.count))", color: Color(hex: c.hex), active: clusterFilter == c.id) {
                                clusterFilter = c.id
                            }
                        }
                    }
                }
                Toggle("Solo da assegnare", isOn: $onlyUnassigned)
            } footer: {
                Text("Le tracce sono raggruppate per colore della maglia. Tocca una traccia per vederla nel video e assegnarla.")
            }

            Section("\(filtered.count) tracce") {
                ForEach(filtered) { t in
                    Button { selected = t } label: { row(t) }.tint(.primary)
                }
                .onDelete { idx in
                    let list = filtered
                    idx.forEach { context.delete(list[$0]) }
                }
            }

            Section {
                Button("Elimina tracce non assegnate più corte di 15 s", role: .destructive) { confirmCleanup = true }
            }
        }
        .navigationTitle("Assegna tracce")
        .sheet(item: $selected) { TrackDetailSheet(match: match, track: $0) }
        .confirmationDialog("Eliminare le tracce brevi non assegnate?", isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                match.tracks.filter { $0.player == nil && $0.duration < 15 }.forEach { context.delete($0) }
            }
        }
    }

    private func row(_ t: Track) -> some View {
        HStack {
            Circle().fill(Color(hex: t.colorHex)).frame(width: 22, height: 22)
                .overlay(Circle().stroke(.secondary, lineWidth: 0.5))
            VStack(alignment: .leading) {
                Text("\(t.startTime.clockString) → \(t.endTime.clockString)").font(.subheadline.monospacedDigit())
                Text("durata \(t.duration.clockString)\(t.source == "manual" ? " · manuale" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = t.player {
                Text(p.displayName).font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
    }

    private func chip(title: String, color: Color?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let color { Circle().fill(color).frame(width: 12, height: 12) }
                Text(title).font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

struct TrackDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let match: Match
    @Bindable var track: Track

    @State private var points: [TrackPoint] = []
    @State private var time: Double = 0
    @State private var frame: UIImage?
    @State private var loadTask: Task<Void, Never>?

    private var current: TrackPoint? {
        points.min { abs($0.t - time) < abs($1.t - time) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    frameView
                        .listRowInsets(EdgeInsets())
                    if track.duration > 0 {
                        Slider(value: $time, in: track.startTime...track.endTime, onEditingChanged: { editing in
                            if !editing { loadFrame() }
                        })
                        Text("Momento: \(time.clockString)").font(.caption.monospacedDigit())
                    }
                }
                Section("Percorso") {
                    TrajectoryView(points: points, pitch: match.pitch, color: Color(hex: track.colorHex))
                }
                Section("Giocatore") {
                    Picker("Assegna a", selection: $track.player) {
                        Text("Nessuno").tag(Player?.none)
                        ForEach(match.team?.sortedPlayers ?? []) { p in
                            Text(p.displayName).tag(Player?.some(p))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if match.team == nil {
                        Text("Collega una squadra alla partita per assegnare i giocatori.").font(.caption)
                    }
                }
                Section {
                    Button("Elimina traccia (arbitro, pubblico, avversario…)", role: .destructive) {
                        context.delete(track)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Traccia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .task {
                points = track.points
                time = (track.startTime + track.endTime) / 2
                loadFrame()
            }
        }
    }

    private var frameView: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(uiImage: frame).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                    if let box = current?.box {
                        let rect = fitted(frame.size, in: geo.size)
                        Rectangle()
                            .stroke(.yellow, lineWidth: 2)
                            .frame(width: box.w * rect.width + 8, height: box.h * rect.height + 8)
                            .position(x: rect.minX + (box.x + box.w / 2) * rect.width,
                                      y: rect.minY + (box.y + box.h / 2) * rect.height)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black)
    }

    private func fitted(_ img: CGSize, in c: CGSize) -> CGRect {
        let s = min(c.width / img.width, c.height / img.height)
        let w = img.width * s, h = img.height * s
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }

    private func loadFrame() {
        guard let url = match.videoURL else { return }
        loadTask?.cancel()
        let t = current?.t ?? time
        loadTask = Task { @MainActor in
            let img = await VideoStorage.frame(of: url, at: t)
            if !Task.isCancelled { frame = img }
        }
    }
}
