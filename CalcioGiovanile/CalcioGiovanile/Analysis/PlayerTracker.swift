import Foundation

/// Un giocatore rilevato in un singolo fotogramma.
struct Detection {
    var pitchX: Double
    var pitchY: Double
    var box: NormalizedBox
    /// Colore medio della maglia (RGB 0…1)
    var color: SIMD3<Double>
    var confidence: Double
}

/// Traccia in costruzione durante l'analisi.
struct TrackBuilder {
    let id: Int
    var points: [TrackPoint] = []
    var colorSum = SIMD3<Double>(0, 0, 0)
    var colorCount = 0
    var lastSeen: Double
    var vx = 0.0, vy = 0.0

    var meanColor: SIMD3<Double> { colorCount > 0 ? colorSum / Double(colorCount) : .zero }
    var duration: Double { (points.last?.t ?? 0) - (points.first?.t ?? 0) }

    func predicted(at t: Double) -> (Double, Double) {
        guard let last = points.last else { return (0, 0) }
        let dt = min(t - last.t, 1.0)   // non estrapolare troppo
        return (last.x + vx * dt, last.y + vy * dt)
    }
}

/// Tracker multi-oggetto semplice: predizione a velocità costante + associazione greedy
/// su distanza in metri e somiglianza del colore maglia.
final class PlayerTracker {
    struct Config {
        /// Distanza massima (m) per associare una rilevazione a una traccia, per secondo trascorso
        var gateMetersPerSecond: Double = 9
        var minGate: Double = 1.5
        /// Peso della differenza colore nel costo di associazione
        var colorWeight: Double = 4
        /// Dopo quanti secondi senza rilevazioni una traccia viene chiusa
        var maxMissing: Double = 2.0
        /// Le tracce più corte di così vengono scartate
        var minDuration: Double = 3.0
    }

    var config: Config
    private(set) var active: [TrackBuilder] = []
    private(set) var finished: [TrackBuilder] = []
    private var nextID = 0

    init(config: Config = Config()) { self.config = config }

    func update(time t: Double, detections: [Detection]) {
        // 1. Costi traccia/rilevazione
        var pairs: [(cost: Double, ti: Int, di: Int)] = []
        for (ti, tr) in active.enumerated() {
            let (px, py) = tr.predicted(at: t)
            let elapsed = max(0.05, t - tr.lastSeen)
            let gate = max(config.minGate, config.gateMetersPerSecond * elapsed)
            for (di, d) in detections.enumerated() {
                let dist = hypot(d.pitchX - px, d.pitchY - py)
                guard dist <= gate else { continue }
                let colorDiff = tr.colorCount > 0 ? simdLength(tr.meanColor - d.color) : 0
                pairs.append((dist / gate + config.colorWeight * colorDiff, ti, di))
            }
        }
        pairs.sort { $0.cost < $1.cost }

        // 2. Assegnazione greedy
        var usedT = Set<Int>(), usedD = Set<Int>()
        for p in pairs where !usedT.contains(p.ti) && !usedD.contains(p.di) {
            usedT.insert(p.ti); usedD.insert(p.di)
            append(detections[p.di], to: &active[p.ti], at: t)
        }

        // 3. Nuove tracce per rilevazioni non associate
        for (di, d) in detections.enumerated() where !usedD.contains(di) {
            var tr = TrackBuilder(id: nextID, lastSeen: t)
            nextID += 1
            append(d, to: &tr, at: t)
            active.append(tr)
        }

        // 4. Chiudi le tracce perse
        var still: [TrackBuilder] = []
        for tr in active {
            if t - tr.lastSeen > config.maxMissing { close(tr) } else { still.append(tr) }
        }
        active = still
    }

    /// Chiude tutte le tracce e restituisce quelle valide.
    func finish() -> [TrackBuilder] {
        active.forEach(close)
        active = []
        return finished
    }

    private func close(_ tr: TrackBuilder) {
        if tr.duration >= config.minDuration { finished.append(tr) }
    }

    private func append(_ d: Detection, to tr: inout TrackBuilder, at t: Double) {
        if let last = tr.points.last, t > last.t {
            let dt = t - last.t
            let nvx = (d.pitchX - last.x) / dt, nvy = (d.pitchY - last.y) / dt
            tr.vx = 0.6 * tr.vx + 0.4 * nvx
            tr.vy = 0.6 * tr.vy + 0.4 * nvy
        }
        tr.points.append(TrackPoint(t: t, x: d.pitchX, y: d.pitchY, box: d.box))
        tr.colorSum += d.color
        tr.colorCount += 1
        tr.lastSeen = t
    }
}

func simdLength(_ v: SIMD3<Double>) -> Double {
    (v * v).sum().squareRoot()
}

// MARK: - Raggruppamento per colore maglia

enum TeamColorClassifier {
    /// K-means sui colori medi delle tracce. Restituisce l'indice di gruppo per ogni colore e i centri.
    static func cluster(_ colors: [SIMD3<Double>], k: Int = 3, iterations: Int = 20) -> (labels: [Int], centers: [SIMD3<Double>]) {
        guard !colors.isEmpty else { return ([], []) }
        let k = min(k, colors.count)

        // Inizializzazione k-means++ deterministica (punto più lontano)
        var centers: [SIMD3<Double>] = [colors[0]]
        while centers.count < k {
            var best = colors[0], bestD = -1.0
            for c in colors {
                let d = centers.map { simdLength($0 - c) }.min() ?? 0
                if d > bestD { bestD = d; best = c }
            }
            centers.append(best)
        }

        var labels = [Int](repeating: 0, count: colors.count)
        for _ in 0..<iterations {
            var changed = false
            for (i, c) in colors.enumerated() {
                var bi = 0, bd = Double.infinity
                for (j, ctr) in centers.enumerated() {
                    let d = simdLength(ctr - c)
                    if d < bd { bd = d; bi = j }
                }
                if labels[i] != bi { labels[i] = bi; changed = true }
            }
            var sums = [SIMD3<Double>](repeating: .zero, count: k)
            var counts = [Int](repeating: 0, count: k)
            for (i, c) in colors.enumerated() { sums[labels[i]] += c; counts[labels[i]] += 1 }
            for j in 0..<k where counts[j] > 0 { centers[j] = sums[j] / Double(counts[j]) }
            if !changed { break }
        }

        // Ordina i gruppi per numerosità (0 = gruppo più numeroso)
        var counts = [Int](repeating: 0, count: k)
        labels.forEach { counts[$0] += 1 }
        let order = (0..<k).sorted { counts[$0] > counts[$1] }
        var remap = [Int](repeating: 0, count: k)
        for (newIdx, old) in order.enumerated() { remap[old] = newIdx }
        return (labels.map { remap[$0] }, order.map { centers[$0] })
    }
}
