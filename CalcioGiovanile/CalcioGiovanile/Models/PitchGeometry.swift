import Foundation
import CoreGraphics

// MARK: - Dimensioni campo

struct PitchSize: Hashable, Identifiable {
    var name: String
    var length: Double
    var width: Double
    var penaltyAreaDepth: Double
    var penaltyAreaWidth: Double

    var id: String { name }

    // Valori indicativi: misura sempre il tuo campo e correggi i valori.
    static let fiveVsFive = PitchSize(name: "5 vs 5 (Piccoli Amici)", length: 40, width: 25, penaltyAreaDepth: 6, penaltyAreaWidth: 12)
    static let sevenVsSeven = PitchSize(name: "7 vs 7 (Pulcini)", length: 55, width: 35, penaltyAreaDepth: 9, penaltyAreaWidth: 20)
    static let nineVsNine = PitchSize(name: "9 vs 9 (Esordienti)", length: 65, width: 45, penaltyAreaDepth: 13, penaltyAreaWidth: 30)
    static let elevenVsEleven = PitchSize(name: "11 vs 11", length: 105, width: 68, penaltyAreaDepth: 16.5, penaltyAreaWidth: 40.32)

    static let presets: [PitchSize] = [.fiveVsFive, .sevenVsSeven, .nineVsNine, .elevenVsEleven]

    func contains(_ p: CGPoint, margin: Double = 0) -> Bool {
        p.x >= -margin && p.x <= length + margin && p.y >= -margin && p.y <= width + margin
    }
}

// MARK: - Punti di riferimento per la calibrazione

enum PitchLandmark: String, CaseIterable, Codable, Identifiable {
    case cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight
    case halfwayTop, halfwayBottom, centerSpot
    case leftBoxFrontTop, leftBoxFrontBottom, leftBoxGoalTop, leftBoxGoalBottom
    case rightBoxFrontTop, rightBoxFrontBottom, rightBoxGoalTop, rightBoxGoalBottom

    var id: String { rawValue }

    /// "top" = lato lontano dalla telecamera, "bottom" = lato vicino; "left"/"right" come si vede nel video.
    var label: String {
        switch self {
        case .cornerTopLeft: "Angolo lontano sinistro"
        case .cornerTopRight: "Angolo lontano destro"
        case .cornerBottomLeft: "Angolo vicino sinistro"
        case .cornerBottomRight: "Angolo vicino destro"
        case .halfwayTop: "Metà campo – lato lontano"
        case .halfwayBottom: "Metà campo – lato vicino"
        case .centerSpot: "Dischetto centrale"
        case .leftBoxFrontTop: "Area sx – vertice lontano"
        case .leftBoxFrontBottom: "Area sx – vertice vicino"
        case .leftBoxGoalTop: "Area sx – linea di fondo lontano"
        case .leftBoxGoalBottom: "Area sx – linea di fondo vicino"
        case .rightBoxFrontTop: "Area dx – vertice lontano"
        case .rightBoxFrontBottom: "Area dx – vertice vicino"
        case .rightBoxGoalTop: "Area dx – linea di fondo lontano"
        case .rightBoxGoalBottom: "Area dx – linea di fondo vicino"
        }
    }

    /// Coordinate in metri: x da 0 (porta sinistra) a length, y da 0 (lato lontano) a width.
    func position(in pitch: PitchSize) -> CGPoint {
        let L = pitch.length, W = pitch.width
        let boxTop = (W - pitch.penaltyAreaWidth) / 2
        let boxBottom = boxTop + pitch.penaltyAreaWidth
        let d = pitch.penaltyAreaDepth
        switch self {
        case .cornerTopLeft: return CGPoint(x: 0, y: 0)
        case .cornerTopRight: return CGPoint(x: L, y: 0)
        case .cornerBottomLeft: return CGPoint(x: 0, y: W)
        case .cornerBottomRight: return CGPoint(x: L, y: W)
        case .halfwayTop: return CGPoint(x: L / 2, y: 0)
        case .halfwayBottom: return CGPoint(x: L / 2, y: W)
        case .centerSpot: return CGPoint(x: L / 2, y: W / 2)
        case .leftBoxFrontTop: return CGPoint(x: d, y: boxTop)
        case .leftBoxFrontBottom: return CGPoint(x: d, y: boxBottom)
        case .leftBoxGoalTop: return CGPoint(x: 0, y: boxTop)
        case .leftBoxGoalBottom: return CGPoint(x: 0, y: boxBottom)
        case .rightBoxFrontTop: return CGPoint(x: L - d, y: boxTop)
        case .rightBoxFrontBottom: return CGPoint(x: L - d, y: boxBottom)
        case .rightBoxGoalTop: return CGPoint(x: L, y: boxTop)
        case .rightBoxGoalBottom: return CGPoint(x: L, y: boxBottom)
        }
    }
}

/// Corrispondenza tra un punto dell'immagine (normalizzato 0…1, origine in alto a sinistra) e un punto del campo.
struct CalibrationPoint: Codable, Hashable {
    var landmark: PitchLandmark
    var imageX: Double
    var imageY: Double
}

struct Calibration: Codable, Hashable {
    var points: [CalibrationPoint]
    /// Rapporto larghezza/altezza del fotogramma (serve per non distorcere le coordinate normalizzate)
    var imageAspect: Double

    /// Omografia immagine (normalizzata, x scalata per l'aspect) -> campo (metri)
    func imageToPitch(pitch: PitchSize) -> Homography? {
        let src = points.map { CGPoint(x: $0.imageX * imageAspect, y: $0.imageY) }
        let dst = points.map { $0.landmark.position(in: pitch) }
        return Homography(from: src, to: dst)
    }

    /// Omografia campo -> immagine normalizzata (per disegnare le linee di verifica)
    func pitchToImage(pitch: PitchSize) -> Homography? {
        let src = points.map { $0.landmark.position(in: pitch) }
        let dst = points.map { CGPoint(x: $0.imageX * imageAspect, y: $0.imageY) }
        return Homography(from: src, to: dst)
    }

    /// Converte un punto immagine normalizzato in coordinate campo.
    func pitchPoint(fromNormalized p: CGPoint, pitch: PitchSize, using h: Homography) -> CGPoint? {
        h.apply(CGPoint(x: p.x * imageAspect, y: p.y))
    }
}

// MARK: - Omografia (trasformazione prospettica piano-piano)

struct Homography: Hashable {
    /// Matrice 3x3 in ordine riga, h[8] = 1
    let m: [Double]

    init(matrix: [Double]) {
        precondition(matrix.count == 9)
        m = matrix
    }

    /// Stima l'omografia con DLT ai minimi quadrati (servono almeno 4 punti non allineati).
    init?(from src: [CGPoint], to dst: [CGPoint]) {
        guard src.count == dst.count, src.count >= 4 else { return nil }

        // Normalizzazione di Hartley per stabilità numerica
        let (srcN, tS) = Homography.normalize(src)
        let (dstN, tD) = Homography.normalize(dst)

        // A h = b con h = [h0..h7], h8 = 1
        var ata = [Double](repeating: 0, count: 64)
        var atb = [Double](repeating: 0, count: 8)
        for i in 0..<srcN.count {
            let x = Double(srcN[i].x), y = Double(srcN[i].y)
            let u = Double(dstN[i].x), v = Double(dstN[i].y)
            let rows: [([Double], Double)] = [
                ([x, y, 1, 0, 0, 0, -u * x, -u * y], u),
                ([0, 0, 0, x, y, 1, -v * x, -v * y], v),
            ]
            for (r, b) in rows {
                for j in 0..<8 {
                    atb[j] += r[j] * b
                    for k in 0..<8 { ata[j * 8 + k] += r[j] * r[k] }
                }
            }
        }
        guard let h = Homography.solve(ata, atb, n: 8) else { return nil }
        let hn = h + [1]

        // H = T_dst^-1 * Hn * T_src
        guard let tDinv = Homography.invert3x3(tD) else { return nil }
        var full = Homography.mul3x3(tDinv, Homography.mul3x3(hn, tS))
        let s = full[8]
        guard abs(s) > 1e-12 else { return nil }
        full = full.map { $0 / s }
        self.m = full
    }

    func apply(_ p: CGPoint) -> CGPoint? {
        let x = Double(p.x), y = Double(p.y)
        let w = m[6] * x + m[7] * y + m[8]
        guard abs(w) > 1e-12 else { return nil }
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w,
                       y: (m[3] * x + m[4] * y + m[5]) / w)
    }

    var inverse: Homography? {
        Homography.invert3x3(m).map { Homography(matrix: $0) }
    }

    // MARK: Algebra

    private static func normalize(_ pts: [CGPoint]) -> ([CGPoint], [Double]) {
        let n = Double(pts.count)
        let cx = pts.reduce(0) { $0 + Double($1.x) } / n
        let cy = pts.reduce(0) { $0 + Double($1.y) } / n
        let meanDist = pts.reduce(0) { $0 + hypot(Double($1.x) - cx, Double($1.y) - cy) } / n
        let s = meanDist > 1e-12 ? sqrt(2) / meanDist : 1
        let t: [Double] = [s, 0, -s * cx,
                           0, s, -s * cy,
                           0, 0, 1]
        let out = pts.map { CGPoint(x: (Double($0.x) - cx) * s, y: (Double($0.y) - cy) * s) }
        return (out, t)
    }

    /// Eliminazione di Gauss con pivot parziale
    static func solve(_ a: [Double], _ b: [Double], n: Int) -> [Double]? {
        var a = a, b = b
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<max(col + 1, n) where abs(a[r * n + col]) > abs(a[pivot * n + col]) { pivot = r }
            guard abs(a[pivot * n + col]) > 1e-12 else { return nil }
            if pivot != col {
                for k in 0..<n { a.swapAt(col * n + k, pivot * n + k) }
                b.swapAt(col, pivot)
            }
            for r in 0..<n where r != col {
                let f = a[r * n + col] / a[col * n + col]
                if f == 0 { continue }
                for k in col..<n { a[r * n + k] -= f * a[col * n + k] }
                b[r] -= f * b[col]
            }
        }
        return (0..<n).map { b[$0] / a[$0 * n + $0] }
    }

    static func mul3x3(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { r[i * 3 + j] += a[i * 3 + k] * b[k * 3 + j] } } }
        return r
    }

    static func invert3x3(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        guard abs(det) > 1e-15 else { return nil }
        let D = -(b * i - c * h), E = a * i - c * g, F = -(a * h - b * g)
        let G = b * f - c * e, H = -(a * f - c * d), I = a * e - b * d
        return [A, D, G, B, E, H, C, F, I].map { $0 / det }
    }
}
