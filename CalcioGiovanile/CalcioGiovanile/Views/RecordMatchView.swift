import SwiftUI
import SwiftData

/// Registrazione dal vivo: anteprima fotocamera, cronometro e pulsanti rapidi per gli eventi.
struct RecordMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var match: Match
    @StateObject private var recorder = CameraRecorder()
    @State private var pendingEvents: [(Double, EventKind)] = []
    @State private var flash: String?
    @State private var confirmStop = false

    private let quickEvents: [EventKind] = [.goalFor, .goalAgainst, .shot, .chance, .recovery, .loss, .foul, .corner, .secondHalf, .note]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(recorder: recorder).ignoresSafeArea()

            // Linee guida per inquadrare il campo
            if !recorder.isRecording {
                GeometryReader { g in
                    Path { p in
                        p.move(to: CGPoint(x: g.size.width / 3, y: 0)); p.addLine(to: CGPoint(x: g.size.width / 3, y: g.size.height))
                        p.move(to: CGPoint(x: 2 * g.size.width / 3, y: 0)); p.addLine(to: CGPoint(x: 2 * g.size.width / 3, y: g.size.height))
                        p.move(to: CGPoint(x: 0, y: g.size.height / 3)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 3))
                        p.move(to: CGPoint(x: 0, y: 2 * g.size.height / 3)); p.addLine(to: CGPoint(x: g.size.width, y: 2 * g.size.height / 3))
                    }
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                }
                .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                if let flash {
                    Text(flash)
                        .font(.headline)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                }
                bottomBar
            }
            .padding()
        }
        .task { await recorder.start() }
        .onDisappear { recorder.stop() }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .confirmationDialog("Terminare la registrazione?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Termina e salva", role: .destructive) { stopAndSave() }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if recorder.isRecording { confirmStop = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(recorder.isRecording ? .red : .gray).frame(width: 10, height: 10)
                Text(recorder.elapsed.clockString).font(.title3.monospacedDigit().bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Text("\(recorder.freeSpaceGB, specifier: "%.0f") GB liberi")
                .font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if recorder.isRecording {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickEvents) { kind in
                            Button { tag(kind) } label: {
                                Label(kind.rawValue, systemImage: kind.symbol)
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    }
                }
            } else {
                HStack {
                    if recorder.hasUltraWide {
                        Toggle("Grandangolo 0.5×", isOn: $recorder.useUltraWide)
                            .toggleStyle(.button)
                    }
                    if !recorder.useUltraWide {
                        Slider(value: $recorder.zoom, in: 1...4) { Text("Zoom") }
                            .frame(maxWidth: 200)
                        Text("\(Double(recorder.zoom), specifier: "%.1f")×").font(.caption.monospacedDigit())
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                if recorder.isRecording { confirmStop = true } else { recorder.startRecording() }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: recorder.isRecording ? 6 : 30)
                        .fill(.red)
                        .frame(width: recorder.isRecording ? 30 : 60, height: recorder.isRecording ? 30 : 60)
                }
            }
            .disabled(!recorder.isRunning)

            if let err = recorder.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .foregroundStyle(.white)
    }

    private func tag(_ kind: EventKind) {
        let t = recorder.elapsed
        pendingEvents.append((t, kind))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { flash = "\(kind.rawValue) · \(t.clockString)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { flash = nil } }
    }

    private func stopAndSave() {
        recorder.stopRecording { fileName in
            if let fileName {
                VideoStorage.delete(match.videoFileName)
                match.videoFileName = fileName
                match.calibration = nil
                for (t, kind) in pendingEvents {
                    let e = MatchEvent(time: t, kind: kind)
                    context.insert(e)
                    e.match = match
                    if kind == .secondHalf { match.halfTimeAt = t }
                    if kind == .goalFor { match.goalsFor += 1 }
                    if kind == .goalAgainst { match.goalsAgainst += 1 }
                }
            }
            dismiss()
        }
    }
}
