import Foundation

/// Soglie di velocità (km/h) pensate per il settore giovanile.
struct SpeedZones {
    static let walk: Double = 7       // < 7 camminata
    static let jog: Double = 13       // 7–13 corsa lenta
    static let run: Double = 17       // 13–17 corsa
    // > 17 sprint
    static let sprintMinDuration: Double = 1.0
    /// Velocità oltre la quale il dato è considerato un errore di tracking
    static let maxPlausible: Double = 32
}

struct MovementStats: Hashable {
    var playedSeconds: Double = 0
    var distanceMeters: Double = 0
    var maxSpeedKmh: Double = 0
    var avgSpeedKmh: Double = 0
    var sprintCount: Int = 0
    var sprintDistance: Double = 0
    /// Distanza percorsa nelle 4 fasce di velocità
    var distanceByZone: [Double] = [0, 0, 0, 0]
    /// Percentuale di tempo in difesa / centrocampo / attacco
    var thirds: [Double] = [0, 0, 0]
    /// Percentuale di tempo in fascia sinistra / centro / destra (verso d'attacco)
    var lanes: [Double] = [0, 0, 0]
    var averageX: Double = 0
    var averageY: Double = 0
    /// Distanza al minuto
    var metersPerMinute: Double { playedSeconds > 0 ? distanceMeters / (playedSeconds / 60) : 0 }

    static let zoneNames = ["Camminata", "Corsa lenta", "Corsa", "Sprint"]
}

enum MovementAnalyzer {

    /// Media mobile centrata su finestra temporale (riduce il "tremolio" del tracking).
    static func smooth(_ pts: [TrackPoint], window: Double = 1.0) -> [TrackPoint] {
        guard pts.count > 2 else { return pts }
        var out: [TrackPoint] = []
        out.reserveCapacity(pts.count)
        var lo = 0, hi = 0
        var sx = 0.0, sy = 0.0
        for i in pts.indices {
            let t = pts[i].t
            while hi < pts.count && pts[hi].t <= t + window / 2 {
                sx += pts[hi].x; sy += pts[hi].y; hi += 1
            }
            while lo < hi && pts[lo].t < t - window / 2 {
                sx -= pts[lo].x; sy -= pts[lo].y; lo += 1
            }
            let n = Double(hi - lo)
            out.append(TrackPoint(t: t, x: sx / n, y: sy / n, box: pts[i].box))
        }
        return out
    }

    /// Unisce più tracce dello stesso giocatore ordinandole nel tempo.
    static func merge(_ tracks: [[TrackPoint]]) -> [TrackPoint] {
        tracks.flatMap { $0 }.sorted { $0.t < $1.t }
    }

    static func stats(for raw: [TrackPoint], pitch: PitchSize, maxGap: Double = 2.0) -> MovementStats {
        var s = MovementStats()
        let pts = smooth(raw)
        guard pts.count > 1 else { return s }

        var thirdTime = [0.0, 0.0, 0.0]
        var laneTime = [0.0, 0.0, 0.0]
        var sumX = 0.0, sumY = 0.0, sumW = 0.0
        var sprintRun = 0.0, sprintRunDist = 0.0

        func closeSprint() {
            if sprintRun >= SpeedZones.sprintMinDuration {
                s.sprintCount += 1
                s.sprintDistance += sprintRunDist
            }
            sprintRun = 0; sprintRunDist = 0
        }

        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dt = b.t - a.t
            guard dt > 0 else { continue }
            if dt > maxGap { closeSprint(); continue }

            let d = hypot(b.x - a.x, b.y - a.y)
            let kmh = d / dt * 3.6
            guard kmh <= SpeedZones.maxPlausible else { closeSprint(); continue }

            s.playedSeconds += dt
            s.distanceMeters += d
            s.maxSpeedKmh = max(s.maxSpeedKmh, kmh)

            let zone: Int
            switch kmh {
            case ..<SpeedZones.walk: zone = 0
            case ..<SpeedZones.jog: zone = 1
            case ..<SpeedZones.run: zone = 2
            default: zone = 3
            }
            s.distanceByZone[zone] += d
            if zone == 3 { sprintRun += dt; sprintRunDist += d } else { closeSprint() }

            let mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2
            let third = min(2, max(0, Int(mx / (pitch.length / 3))))
            thirdTime[third] += dt
            // y = 0 è il lato lontano: attaccando verso destra il lato lontano è la sinistra
            let lane = min(2, max(0, Int(my / (pitch.width / 3))))
            laneTime[lane] += dt
            sumX += mx * dt; sumY += my * dt; sumW += dt
        }
        closeSprint()

        if s.playedSeconds > 0 {
            s.avgSpeedKmh = s.distanceMeters / s.playedSeconds * 3.6
            s.thirds = thirdTime.map { $0 / s.playedSeconds }
            s.lanes = laneTime.map { $0 / s.playedSeconds }
        }
        if sumW > 0 { s.averageX = sumX / sumW; s.averageY = sumY / sumW }
        return s
    }

    struct SpeedSample: Hashable, Identifiable {
        var t: Double
        var kmh: Double
        var id: Double { t }
    }

    /// Velocità (km/h) nel tempo, utile per i grafici.
    static func speedSeries(_ raw: [TrackPoint], step: Double = 5) -> [SpeedSample] {
        let pts = smooth(raw)
        guard pts.count > 1 else { return [] }
        var out: [SpeedSample] = []
        var bucketStart = pts[0].t, dist = 0.0, time = 0.0
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let dt = b.t - a.t
            if dt > 0 && dt <= 2 {
                let d = hypot(b.x - a.x, b.y - a.y)
                if d / dt * 3.6 <= SpeedZones.maxPlausible { dist += d; time += dt }
            }
            if b.t - bucketStart >= step {
                out.append(SpeedSample(t: bucketStart, kmh: time > 0 ? dist / time * 3.6 : 0))
                bucketStart = b.t; dist = 0; time = 0
            }
        }
        return out
    }
}

// MARK: - Analisi di squadra

struct TeamShapeSample: Hashable, Identifiable {
    var id: Double { t }
    var t: Double
    var centroidX: Double
    var centroidY: Double
    var width: Double
    var depth: Double
}

enum TeamShapeAnalyzer {
    /// Calcola baricentro, ampiezza e profondità della squadra a intervalli regolari.
    /// Il portiere va escluso dal chiamante se non lo si vuole considerare.
    static func shape(players: [[TrackPoint]], step: Double = 2, minPlayers: Int = 3) -> [TeamShapeSample] {
        let series = players.map { MovementAnalyzer.smooth($0) }.filter { !$0.isEmpty }
        guard let start = series.compactMap({ $0.first?.t }).min(),
              let end = series.compactMap({ $0.last?.t }).max(), end > start else { return [] }

        var cursors = [Int](repeating: 0, count: series.count)
        var out: [TeamShapeSample] = []
        var t = start
        while t <= end {
            var xs: [Double] = [], ys: [Double] = []
            for (i, s) in series.enumerated() {
                while cursors[i] + 1 < s.count && s[cursors[i] + 1].t <= t { cursors[i] += 1 }
                let p = s[cursors[i]]
                if abs(p.t - t) <= 1.5 { xs.append(p.x); ys.append(p.y) }
            }
            if xs.count >= minPlayers, let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                out.append(TeamShapeSample(t: t,
                                           centroidX: xs.reduce(0, +) / Double(xs.count),
                                           centroidY: ys.reduce(0, +) / Double(ys.count),
                                           width: maxY - minY,
                                           depth: maxX - minX))
            }
            t += step
        }
        return out
    }
}
