import SwiftUI

/// Calibrazione: l'utente indica sull'immagine almeno 4 punti noti del campo.
/// Da questi si calcola l'omografia che trasforma i pixel del video in metri sul campo.
struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var match: Match

    @State private var image: UIImage?
    @State private var duration: Double = 0
    @State private var frameTime: Double = 10
    @State private var placed: [PitchLandmark: CGPoint] = [:]   // normalizzati, origine in alto a sinistra
    @State private var selected: PitchLandmark = .cornerTopLeft
    @State private var dragging: PitchLandmark?
    @State private var loupePoint: CGPoint?
    @State private var length: Double = 0
    @State private var width: Double = 0
    @State private var boxDepth: Double = 0
    @State private var boxWidth: Double = 0

    private var pitch: PitchSize {
        PitchSize(name: "Campo", length: length, width: width, penaltyAreaDepth: boxDepth, penaltyAreaWidth: boxWidth)
    }

    private var calibration: Calibration? {
        guard let image, placed.count >= 4 else { return nil }
        return Calibration(points: placed.map { CalibrationPoint(landmark: $0.key, imageX: $0.value.x, imageY: $0.value.y) },
                           imageAspect: image.size.width / image.size.height)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scegli un punto di riferimento qui sotto e toccalo sull'immagine. Servono almeno 4 punti, ben distribuiti (es. i 4 angoli, oppure angoli + vertici dell'area). Trascina un punto per correggerlo.")
                    .font(.callout).foregroundStyle(.secondary)

                imageArea

                if duration > 0 {
                    HStack {
                        Text("Fotogramma").font(.caption)
                        Slider(value: $frameTime, in: 0...max(1, duration - 1), onEditingChanged: { editing in
                            if !editing { Task { await loadFrame() } }
                        })
                        Text(frameTime.clockString).font(.caption.monospacedDigit())
                    }
                }

                landmarkPicker

                GroupBox("Misure del campo (m)") {
                    VStack {
                        measureRow("Lunghezza", $length)
                        measureRow("Larghezza", $width)
                        measureRow("Profondità area", $boxDepth)
                        measureRow("Larghezza area", $boxWidth)
                    }
                }

                if let cal = calibration, cal.imageToPitch(pitch: pitch) == nil {
                    Label("I punti scelti sono allineati: aggiungine uno fuori linea.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if !match.tracks.filter({ $0.source == "auto" }).isEmpty {
                    Label("Se cambi la calibrazione, ripeti l'analisi automatica.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Calibrazione campo")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    match.pitch = pitch
                    match.calibration = calibration
                    dismiss()
                }
                .disabled(calibration?.imageToPitch(pitch: pitch) == nil)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Azzera punti", role: .destructive) { placed = [:] }
            }
        }
        .task {
            length = match.pitchLength; width = match.pitchWidth
            boxDepth = match.penaltyAreaDepth; boxWidth = match.penaltyAreaWidth
            if let cal = match.calibration {
                for p in cal.points { placed[p.landmark] = CGPoint(x: p.imageX, y: p.imageY) }
            }
            if let url = match.videoURL {
                duration = await VideoStorage.duration(of: url)
                frameTime = min(10, duration / 2)
                await loadFrame()
            }
        }
    }

    private func measureRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func loadFrame() async {
        guard let url = match.videoURL else { return }
        image = await VideoStorage.frame(of: url, at: frameTime)
    }

    // MARK: Immagine con punti e anteprima linee

    private var imageArea: some View {
        GeometryReader { geo in
            let rect = fittedRect(container: geo.size)
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let cal = calibration, let h = cal.pitchToImage(pitch: pitch) {
                    projectedLines(h: h, aspect: cal.imageAspect, rect: rect)
                        .stroke(.cyan, lineWidth: 1.5)
                }
                ForEach(Array(placed.keys), id: \.self) { lm in
                    if let p = placed[lm] {
                        let v = CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
                        ZStack {
                            Circle().stroke(lm == selected ? .yellow : .white, lineWidth: 2).frame(width: 18, height: 18)
                            Circle().fill(.red).frame(width: 4, height: 4)
                        }
                        .position(v)
                    }
                }
                if let lp = loupePoint, let image {
                    loupe(image: image, at: lp, rect: rect)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragging == nil {
                        dragging = nearest(to: g.startLocation, rect: rect) ?? selected
                    }
                    loupePoint = g.location
                    if let d = dragging { placed[d] = normalized(g.location, rect: rect) }
                }
                .onEnded { _ in
                    if let d = dragging, d == selected { advanceSelection() }
                    dragging = nil
                    loupePoint = nil
                })
        }
        .aspectRatio(image.map { $0.size.width / $0.size.height } ?? 16 / 9, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var landmarkPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Punto da posizionare").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
                ForEach(PitchLandmark.allCases) { lm in
                    Button { selected = lm } label: {
                        HStack(spacing: 4) {
                            Image(systemName: placed[lm] != nil ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(placed[lm] != nil ? .green : .secondary)
                            Text(lm.label).font(.caption).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(lm == selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
                    }
                    .tint(.primary)
                    .contextMenu {
                        if placed[lm] != nil { Button("Rimuovi", role: .destructive) { placed[lm] = nil } }
                    }
                }
            }
        }
    }

    private func loupe(image: UIImage, at p: CGPoint, rect: CGRect) -> some View {
        let zoom: CGFloat = 3, size: CGFloat = 110
        return Image(uiImage: image).resizable()
            .frame(width: rect.width * zoom, height: rect.height * zoom)
            .offset(x: -(p.x - rect.minX) * zoom + size / 2, y: -(p.y - rect.minY) * zoom + size / 2)
            .frame(width: size, height: size, alignment: .topLeading)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Image(systemName: "plus").foregroundStyle(.yellow))
            .position(x: p.x, y: max(size / 2, p.y - size))
            .allowsHitTesting(false)
    }

    // MARK: Geometria

    private func fittedRect(container: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return CGRect(origin: .zero, size: container) }
        let s = min(container.width / image.size.width, container.height / image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func normalized(_ p: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(x: min(1, max(0, (p.x - rect.minX) / rect.width)),
                y: min(1, max(0, (p.y - rect.minY) / rect.height)))
    }

    private func nearest(to p: CGPoint, rect: CGRect) -> PitchLandmark? {
        placed.min { a, b in
            dist(a.value, p, rect) < dist(b.value, p, rect)
        }.flatMap { dist($0.value, p, rect) < 28 ? $0.key : nil }
    }

    private func dist(_ n: CGPoint, _ p: CGPoint, _ rect: CGRect) -> CGFloat {
        hypot(rect.minX + n.x * rect.width - p.x, rect.minY + n.y * rect.height - p.y)
    }

    private func advanceSelection() {
        if let next = PitchLandmark.allCases.first(where: { placed[$0] == nil }) { selected = next }
    }

    /// Linee del campo proiettate sull'immagine per verificare la calibrazione.
    private func projectedLines(h: Homography, aspect: Double, rect: CGRect) -> Path {
        let L = pitch.length, W = pitch.width
        let bt = (W - pitch.penaltyAreaWidth) / 2, bb = bt + pitch.penaltyAreaWidth, d = pitch.penaltyAreaDepth
        let segments: [(CGPoint, CGPoint)] = [
            (.init(x: 0, y: 0), .init(x: L, y: 0)), (.init(x: L, y: 0), .init(x: L, y: W)),
            (.init(x: L, y: W), .init(x: 0, y: W)), (.init(x: 0, y: W), .init(x: 0, y: 0)),
            (.init(x: L / 2, y: 0), .init(x: L / 2, y: W)),
            (.init(x: 0, y: bt), .init(x: d, y: bt)), (.init(x: d, y: bt), .init(x: d, y: bb)), (.init(x: d, y: bb), .init(x: 0, y: bb)),
            (.init(x: L, y: bt), .init(x: L - d, y: bt)), (.init(x: L - d, y: bt), .init(x: L - d, y: bb)), (.init(x: L - d, y: bb), .init(x: L, y: bb)),
        ]
        func toView(_ p: CGPoint) -> CGPoint? {
            guard let q = h.apply(p) else { return nil }
            return CGPoint(x: rect.minX + q.x / aspect * rect.width, y: rect.minY + q.y * rect.height)
        }
        var path = Path()
        for (a, b) in segments {
            // Suddivido il segmento per evitare artefatti vicino all'orizzonte
            var prev: CGPoint?
            for i in 0...20 {
                let t = Double(i) / 20
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                guard let v = toView(p) else { prev = nil; continue }
                if let _ = prev { path.addLine(to: v) } else { path.move(to: v) }
                prev = v
            }
        }
        // cerchio di centrocampo
        let r = min(9.15, W * 0.13)
        var first = true
        for i in 0...48 {
            let a = Double(i) / 48 * 2 * .pi
            guard let v = toView(CGPoint(x: L / 2 + r * cos(a), y: W / 2 + r * sin(a))) else { continue }
            if first { path.move(to: v); first = false } else { path.addLine(to: v) }
        }
        return path
    }
}
