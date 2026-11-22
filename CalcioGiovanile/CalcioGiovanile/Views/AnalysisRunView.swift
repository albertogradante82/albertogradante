import SwiftUI
import SwiftData

struct AnalysisRunView: View {
    @Environment(\.modelContext) private var context
    @Bindable var match: Match

    @State private var fps: Double = 5
    @State private var highPrecision = true
    @State private var onlySegment = false
    @State private var segmentStart: Double = 0
    @State private var segmentEnd: Double = 600
    @State private var duration: Double = 0
    @State private var progress: Double = 0
    @State private var running = false
    @State private var task: Task<Void, Never>?
    @State private var message: String?
    @State private var startedAt: Date?

    var body: some View {
        Form {
            Section {
                Text("L'analisi riconosce le persone nel video, calcola la loro posizione sul campo e le segue nel tempo. Su una partita intera può richiedere diversi minuti: tieni l'iPhone in carica e l'app aperta.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Impostazioni") {
                Picker("Campionamento", selection: $fps) {
                    Text("2 fotogrammi/s (veloce)").tag(2.0)
                    Text("5 fotogrammi/s (consigliato)").tag(5.0)
                    Text("10 fotogrammi/s (preciso)").tag(10.0)
                }
                Toggle("Alta precisione (giocatori lontani)", isOn: $highPrecision)
                Toggle("Analizza solo una parte", isOn: $onlySegment)
                if onlySegment && duration > 0 {
                    LabeledContent("Da \(segmentStart.clockString)") {
                        Slider(value: $segmentStart, in: 0...duration)
                    }
                    LabeledContent("A \(segmentEnd.clockString)") {
                        Slider(value: $segmentEnd, in: 0...duration)
                    }
                }
            }
            Section {
                if running {
                    VStack(alignment: .leading) {
                        ProgressView(value: progress)
                        HStack {
                            Text("\(Int(progress * 100))%")
                            Spacer()
                            if let eta { Text("circa \(eta) rimanenti") }
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Button("Interrompi", role: .destructive) { task?.cancel() }
                } else {
                    Button {
                        start()
                    } label: {
                        Label(match.analysisCompletedAt == nil ? "Avvia analisi" : "Ripeti analisi", systemImage: "play.fill")
                    }
                    .disabled(match.calibration == nil || match.videoURL == nil)
                }
                if let message { Text(message).font(.callout) }
            }
        }
        .navigationTitle("Analisi automatica")
        .task {
            if let url = match.videoURL {
                duration = await VideoStorage.duration(of: url)
                segmentEnd = duration
            }
        }
        .onDisappear { if running { task?.cancel() } }
    }

    private var eta: String? {
        guard let startedAt, progress > 0.02 else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = elapsed / progress * (1 - progress)
        return remaining.clockString
    }

    @MainActor private func start() {
        guard let url = match.videoURL, let cal = match.calibration else { return }
        running = true
        progress = 0
        message = nil
        startedAt = Date()
        UIApplication.shared.isIdleTimerDisabled = true

        var options = VideoAnalyzer.Options()
        options.sampleFPS = fps
        options.highPrecision = highPrecision
        if onlySegment {
            options.startTime = min(segmentStart, segmentEnd)
            options.endTime = max(segmentStart, segmentEnd)
        }
        let pitch = match.pitch

        task = Task { @MainActor in
            defer {
                running = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                // analyze è nonisolated: il lavoro pesante gira fuori dal main thread
                let result = try await VideoAnalyzer().analyze(url: url, calibration: cal, pitch: pitch, options: options) { p in
                    Task { @MainActor in progress = p }
                }

                // Sostituisce le tracce automatiche precedenti (mantiene quelle manuali)
                for t in match.tracks where t.source == "auto" { context.delete(t) }
                for d in result.tracks {
                    let t = Track(source: "auto", points: d.points, colorHex: d.colorHex, colorCluster: d.cluster)
                    context.insert(t)
                    t.match = match
                }
                match.analysisCompletedAt = Date()
                try? context.save()
                message = "Trovate \(result.tracks.count) tracce. Ora assegnale ai giocatori della tua squadra."
            } catch is CancellationError {
                message = "Analisi interrotta."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
