import SwiftUI
import SwiftData
import AVFoundation

/// Tracciamento manuale: il video scorre al rallentatore e l'allenatore tiene il dito
/// sul giocatore da seguire. Utile quando l'analisi automatica perde un giocatore
/// o per analizzare in dettaglio un'azione.
struct ManualTrackingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var match: Match

    @State private var player = AVPlayer()
    @State private var target: Player?
    @State private var rate: Float = 0.5
    @State private var isTracking = false
    @State private var touch: CGPoint?            // normalizzato rispetto al video
    @State private var recorded: [TrackPoint] = []
    @State private var timer: Timer?
    @State private var homography: Homography?
    @State private var savedMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            videoArea
            controls
            if recorded.count > 1 {
                TrajectoryView(points: recorded, pitch: match.pitch)
                    .frame(maxHeight: 160)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Tracciamento manuale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let url = match.videoURL { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            homography = match.calibration?.imageToPitch(pitch: match.pitch)
            player.isMuted = true
        }
        .onDisappear { stopTracking(); player.pause() }
    }

    private var videoArea: some View {
        GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: player)
                if let touch {
                    Circle().stroke(.yellow, lineWidth: 3).frame(width: 34, height: 34)
                        .position(x: rect.minX + touch.x * rect.width, y: rect.minY + touch.y * rect.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    touch = CGPoint(x: min(1, max(0, (g.location.x - rect.minX) / rect.width)),
                                    y: min(1, max(0, (g.location.y - rect.minY) / rect.height)))
                    if isTracking && player.rate == 0 { player.rate = rate }
                }
                .onEnded { _ in
                    touch = nil
                    // Se il dito si alza il video si ferma, così non si perdono posizioni
                    if isTracking { player.pause() }
                })
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Giocatore", selection: $target) {
                    Text("Scegli giocatore").tag(Player?.none)
                    ForEach(match.team?.sortedPlayers ?? []) { Text($0.displayName).tag(Player?.some($0)) }
                }
                Spacer()
                Picker("Velocità", selection: $rate) {
                    Text("0.25×").tag(Float(0.25))
                    Text("0.5×").tag(Float(0.5))
                    Text("1×").tag(Float(1))
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            HStack {
                Button { seek(-10) } label: { Image(systemName: "gobackward.10") }
                Button { seek(10) } label: { Image(systemName: "goforward.10") }
                Spacer()
                if isTracking {
                    Button("Ferma") { stopTracking() }.buttonStyle(.bordered)
                } else {
                    Button("Inizia") { startTracking() }
                        .buttonStyle(.borderedProminent)
                        .disabled(target == nil || homography == nil)
                }
                Button("Salva (\(recorded.count))") { save() }
                    .buttonStyle(.bordered)
                    .disabled(recorded.count < 5 || target == nil)
            }
            Text(isTracking ? "Tieni il dito sui piedi del giocatore: il video avanza solo mentre tocchi lo schermo."
                            : "Scegli il giocatore, posiziona il video e premi Inizia.")
                .font(.caption).foregroundStyle(.secondary)
            if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(.green) }
        }
    }

    private func videoRect(in size: CGSize) -> CGRect {
        let ps = player.currentItem?.presentationSize ?? .zero
        guard ps.width > 0, ps.height > 0 else { return CGRect(origin: .zero, size: size) }
        return AVMakeRect(aspectRatio: ps, insideRect: CGRect(origin: .zero, size: size))
    }

    private func seek(_ delta: Double) {
        let t = player.currentTime().seconds + delta
        player.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600))
    }

    private func startTracking() {
        isTracking = true
        savedMessage = nil
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in sample() }
        }
    }

    private func stopTracking() {
        isTracking = false
        timer?.invalidate()
        timer = nil
        player.pause()
    }

    @MainActor private func sample() {
        guard isTracking, player.rate > 0, let touch, let h = homography, let cal = match.calibration else { return }
        let t = player.currentTime().seconds
        if let last = recorded.last, t - last.t < 0.18 { return }  // ~5 campioni al secondo di video
        guard let p = cal.pitchPoint(fromNormalized: touch, pitch: match.pitch, using: h) else { return }
        recorded.append(TrackPoint(t: t, x: Double(p.x), y: Double(p.y), box: nil))
    }

    private func save() {
        stopTracking()
        let track = Track(source: "manual", points: recorded.sorted { $0.t < $1.t }, colorHex: "#FFD60A")
        context.insert(track)
        track.match = match
        track.player = target
        savedMessage = "Traccia salvata per \(target?.name ?? "")."
        recorded = []
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: LayerView, context: Context) {}

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
