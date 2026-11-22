import Foundation

/// Griglia di densità (tempo trascorso per cella) sul campo.
struct Heatmap {
    let columns: Int
    let rows: Int
    private(set) var values: [Double]

    init(points: [TrackPoint], pitch: PitchSize, columns: Int = 30, rows: Int = 20, blurRadius: Int = 2) {
        self.columns = columns
        self.rows = rows
        var grid = [Double](repeating: 0, count: columns * rows)
        if points.count > 1 {
            for i in 1..<points.count {
                let dt = points[i].t - points[i - 1].t
                guard dt > 0, dt < 2 else { continue }
                let p = points[i]
                let c = Int(p.x / pitch.length * Double(columns))
                let r = Int(p.y / pitch.width * Double(rows))
                guard c >= 0, c < columns, r >= 0, r < rows else { continue }
                grid[r * columns + c] += dt
            }
        }
        values = Heatmap.gaussianBlur(grid, columns: columns, rows: rows, radius: blurRadius)
        if let mx = values.max(), mx > 0 { values = values.map { $0 / mx } }
    }

    func value(column: Int, row: Int) -> Double { values[row * columns + column] }

    private static func gaussianBlur(_ g: [Double], columns: Int, rows: Int, radius: Int) -> [Double] {
        guard radius > 0 else { return g }
        let sigma = Double(radius) / 1.5
        let kernel = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let ksum = kernel.reduce(0, +)
        var tmp = [Double](repeating: 0, count: g.count)
        var out = [Double](repeating: 0, count: g.count)
        for r in 0..<rows {
            for c in 0..<columns {
                var acc = 0.0
                for k in -radius...radius {
                    let cc = min(columns - 1, max(0, c + k))
                    acc += g[r * columns + cc] * kernel[k + radius]
                }
                tmp[r * columns + c] = acc / ksum
            }
        }
        for r in 0..<rows {
            for c in 0..<columns {
                var acc = 0.0
                for k in -radius...radius {
                    let rr = min(rows - 1, max(0, r + k))
                    acc += tmp[rr * columns + c] * kernel[k + radius]
                }
                out[r * columns + c] = acc / ksum
            }
        }
        return out
    }
}
