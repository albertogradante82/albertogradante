import SwiftUI
import Charts

/// Disegna un campo da calcio in scala e mette a disposizione la conversione metri -> punti.
struct PitchCanvas<Overlay: View>: View {
    let pitch: PitchSize
    @ViewBuilder var overlay: (_ toView: @escaping (Double, Double) -> CGPoint, _ size: CGSize) -> Overlay

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let toView: (Double, Double) -> CGPoint = { x, y in
                CGPoint(x: x / pitch.length * size.width, y: y / pitch.width * size.height)
            }
            ZStack {
                Canvas { ctx, size in
                    let rect = CGRect(origin: .zero, size: size)
                    ctx.fill(Path(rect), with: .color(Color(red: 0.17, green: 0.52, blue: 0.25)))
                    // strisce del prato
                    let stripes = 10
                    for i in stride(from: 0, to: stripes, by: 2) {
                        let w = size.width / CGFloat(stripes)
                        ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w, height: size.height)),
                                 with: .color(.white.opacity(0.04)))
                    }
                    var lines = Path()
                    lines.addRect(rect.insetBy(dx: 1, dy: 1))
                    lines.move(to: CGPoint(x: size.width / 2, y: 0))
                    lines.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    let rm = min(9.15, pitch.width * 0.13) // raggio cerchio di centrocampo (m)
                    let rx = rm / pitch.length * size.width, ry = rm / pitch.width * size.height
                    lines.addEllipse(in: CGRect(x: size.width / 2 - rx, y: size.height / 2 - ry, width: 2 * rx, height: 2 * ry))
                    let bw = pitch.penaltyAreaWidth / pitch.width * size.height
                    let bd = pitch.penaltyAreaDepth / pitch.length * size.width
                    lines.addRect(CGRect(x: 0, y: (size.height - bw) / 2, width: bd, height: bw))
                    lines.addRect(CGRect(x: size.width - bd, y: (size.height - bw) / 2, width: bd, height: bw))
                    ctx.stroke(lines, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                }
                overlay(toView, size)
            }
        }
        .aspectRatio(pitch.length / pitch.width, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Mappa di calore delle posizioni.
struct HeatmapView: View {
    let points: [TrackPoint]
    let pitch: PitchSize

    var body: some View {
        let heat = Heatmap(points: points, pitch: pitch)
        PitchCanvas(pitch: pitch) { _, size in
            Canvas { ctx, size in
                let cw = size.width / CGFloat(heat.columns), ch = size.height / CGFloat(heat.rows)
                for r in 0..<heat.rows {
                    for c in 0..<heat.columns {
                        let v = heat.value(column: c, row: r)
                        guard v > 0.04 else { continue }
                        ctx.fill(Path(CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw + 0.5, height: ch + 0.5)),
                                 with: .color(HeatmapView.color(v)))
                    }
                }
            }
            .blur(radius: 6)
            .allowsHitTesting(false)
            .frame(width: size.width, height: size.height)
        }
        .overlay(alignment: .bottomTrailing) { attackArrow }
    }

    static func color(_ v: Double) -> Color {
        // blu -> verde -> giallo -> rosso
        let hue = 0.66 * (1 - v)
        return Color(hue: hue, saturation: 0.9, brightness: 1).opacity(0.25 + 0.6 * v)
    }

    private var attackArrow: some View {
        Label("Attacco", systemImage: "arrow.right")
            .font(.caption2.bold())
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
    }
}

/// Traiettoria nel tempo, con colore che va dall'inizio (chiaro) alla fine (scuro).
struct TrajectoryView: View {
    let points: [TrackPoint]
    let pitch: PitchSize
    var range: ClosedRange<Double>? = nil
    var color: Color = .yellow

    var body: some View {
        let pts = MovementAnalyzer.smooth(points).filter { range?.contains($0.t) ?? true }
        PitchCanvas(pitch: pitch) { toView, _ in
            Canvas { ctx, _ in
                guard pts.count > 1 else { return }
                var path = Path()
                path.move(to: toView(pts[0].x, pts[0].y))
                for i in 1..<pts.count {
                    if pts[i].t - pts[i - 1].t > 2 {
                        path.move(to: toView(pts[i].x, pts[i].y))
                    } else {
                        path.addLine(to: toView(pts[i].x, pts[i].y))
                    }
                }
                ctx.stroke(path, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    let p = toView(last.x, last.y)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
        }
    }
}

/// Posizioni medie dei giocatori (disposizione in campo).
struct AveragePositionsView: View {
    struct Dot: Identifiable {
        let id: String
        let label: String
        let x: Double
        let y: Double
        let color: Color
    }
    let dots: [Dot]
    let pitch: PitchSize

    var body: some View {
        PitchCanvas(pitch: pitch) { toView, _ in
            ZStack {
                ForEach(dots) { d in
                    Text(d.label)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(d.color))
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .position(toView(d.x, d.y))
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

struct TrendChart: View {
    let values: [Double]
    let labels: [String]

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("Partita", labels[i]), y: .value("Valore", v))
                PointMark(x: .value("Partita", labels[i]), y: .value("Valore", v))
            }
        }
    }
}

/// Barra percentuale (terzi di campo, corsie, fasce di velocità).
struct ShareBar: View {
    let parts: [Double]
    let names: [String]
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { i in
                        Rectangle().fill(colors[i % colors.count])
                            .frame(width: max(0, geo.size.width * parts[i] - 2))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            HStack {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 3) {
                        Circle().fill(colors[i % colors.count]).frame(width: 8, height: 8)
                        Text("\(names[i]) \(Int((parts[i] * 100).rounded()))%")
                    }
                    .font(.caption2)
                    if i < parts.count - 1 { Spacer(minLength: 4) }
                }
            }
        }
    }
}
