import SwiftUI
import SwiftData
import Charts

enum MatchPeriod: String, CaseIterable, Identifiable {
    case all = "Partita", first = "1° tempo", second = "2° tempo"
    var id: String { rawValue }

    func contains(_ t: Double, halfTime: Double?) -> Bool {
        guard let h = halfTime else { return true }
        switch self {
        case .all: return true
        case .first: return t < h
        case .second: return t >= h
        }
    }
}

extension Match {
    /// Posizioni (normalizzate nel verso d'attacco) di un giocatore in questa partita.
    func positions(of player: Player, period: MatchPeriod = .all) -> [TrackPoint] {
        let tracks = self.tracks.filter { $0.player?.persistentModelID == player.persistentModelID }
        return MovementAnalyzer.merge(tracks.map { $0.points.map(normalized) })
            .filter { period.contains($0.t, halfTime: halfTimeAt) }
    }

    var trackedPlayers: [Player] {
        var seen = Set<PersistentIdentifier>()
        return tracks.compactMap(\.player)
            .filter { seen.insert($0.persistentModelID).inserted }
            .sorted { $0.number < $1.number }
    }
}

// MARK: - Analisi singolo giocatore

struct PlayerAnalysisView: View {
    let match: Match
    let player: Player
    @State private var period: MatchPeriod = .all
    @State private var mode = 0

    var body: some View {
        let pts = match.positions(of: player, period: period)
        let s = MovementAnalyzer.stats(for: pts, pitch: match.pitch)
        let speed = MovementAnalyzer.speedSeries(pts, step: 15)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if match.halfTimeAt != nil {
                    Picker("Periodo", selection: $period) {
                        ForEach(MatchPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatTile(title: "Tracciato", value: "\(Int(s.playedSeconds / 60))'", systemImage: "clock")
                    StatTile(title: "Distanza", value: String(format: "%.2f km", s.distanceMeters / 1000), systemImage: "figure.run")
                    StatTile(title: "m/min", value: String(format: "%.0f", s.metersPerMinute), systemImage: "speedometer")
                    StatTile(title: "Vel. media", value: String(format: "%.1f", s.avgSpeedKmh), systemImage: "gauge.with.dots.needle.33percent")
                    StatTile(title: "Vel. max", value: String(format: "%.1f", s.maxSpeedKmh), systemImage: "bolt")
                    StatTile(title: "Sprint", value: "\(s.sprintCount)", systemImage: "hare")
                }

                Picker("Vista", selection: $mode) {
                    Text("Mappa di calore").tag(0)
                    Text("Percorso").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 {
                    HeatmapView(points: pts, pitch: match.pitch)
                } else {
                    TrajectoryView(points: pts, pitch: match.pitch)
                }
                Text("La squadra attacca sempre verso destra; la fascia in alto è la sinistra.")
                    .font(.caption2).foregroundStyle(.secondary)

                GroupBox("Distanza per intensità") {
                    let tot = max(1, s.distanceByZone.reduce(0, +))
                    ShareBar(parts: s.distanceByZone.map { $0 / tot }, names: MovementStats.zoneNames,
                             colors: [.gray, .blue, .orange, .red])
                    Text("Soglie: <\(Int(SpeedZones.walk)), <\(Int(SpeedZones.jog)), <\(Int(SpeedZones.run)), oltre \(Int(SpeedZones.run)) km/h")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                GroupBox("Zone del campo") {
                    VStack(alignment: .leading, spacing: 12) {
                        ShareBar(parts: s.thirds, names: ["Difesa", "Centro", "Attacco"], colors: [.blue, .green, .red])
                        ShareBar(parts: s.lanes, names: ["Sinistra", "Centro", "Destra"], colors: [.purple, .teal, .indigo])
                    }
                }
                if speed.count > 2 {
                    GroupBox("Velocità media ogni 15 s (km/h)") {
                        Chart(speed) { p in
                            AreaMark(x: .value("Minuto", p.t / 60), y: .value("km/h", p.kmh))
                                .foregroundStyle(.linearGradient(colors: [.orange.opacity(0.5), .orange.opacity(0.05)],
                                                                 startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Minuto", p.t / 60), y: .value("km/h", p.kmh))
                                .foregroundStyle(.orange)
                        }
                        .chartXAxisLabel("minuto del video")
                        .frame(height: 180)
                    }
                }
                if pts.isEmpty {
                    ContentUnavailableView("Nessun dato", systemImage: "figure.run",
                                           description: Text("Assegna almeno una traccia a questo giocatore."))
                }
            }
            .padding()
        }
        .navigationTitle(player.displayName)
    }
}

// MARK: - Analisi di squadra

struct PlayerRow: Identifiable {
    let player: Player
    let points: [TrackPoint]
    let stats: MovementStats
    var id: PersistentIdentifier { player.persistentModelID }
}

struct TeamAnalysisView: View {
    let match: Match
    @State private var excludeGoalkeeper = true
    @State private var period: MatchPeriod = .all

    var body: some View {
        let rows = match.trackedPlayers.map { p -> PlayerRow in
            let pts = match.positions(of: p, period: period)
            return PlayerRow(player: p, points: pts, stats: MovementAnalyzer.stats(for: pts, pitch: match.pitch))
        }
        let shapeInput = rows.filter { !(excludeGoalkeeper && $0.player.role == "Portiere") }.map(\.points)
        let shape = TeamShapeAnalyzer.shape(players: shapeInput)
        let dots = rows.filter { $0.stats.playedSeconds > 0 }.map { r -> AveragePositionsView.Dot in
            AveragePositionsView.Dot(id: "\(r.player.number)-\(r.player.name)", label: "\(r.player.number)",
                                     x: r.stats.averageX, y: r.stats.averageY,
                                     color: r.player.role == "Portiere" ? .orange : .blue)
        }

        List {
            if match.halfTimeAt != nil {
                Picker("Periodo", selection: $period) {
                    ForEach(MatchPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Posizioni medie") {
                AveragePositionsView(dots: dots, pitch: match.pitch)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            Section("Compattezza della squadra") {
                Toggle("Escludi il portiere", isOn: $excludeGoalkeeper)
                if shape.isEmpty {
                    Text("Servono almeno 3 giocatori tracciati nello stesso momento.").foregroundStyle(.secondary)
                } else {
                    let n = Double(shape.count)
                    LabeledContent("Ampiezza media", value: String(format: "%.1f m", shape.map(\.width).reduce(0, +) / n))
                    LabeledContent("Profondità media", value: String(format: "%.1f m", shape.map(\.depth).reduce(0, +) / n))
                    LabeledContent("Baricentro medio", value: String(format: "%.1f m dalla propria porta", shape.map(\.centroidX).reduce(0, +) / n))
                    Chart(shape) { s in
                        LineMark(x: .value("Minuto", s.t / 60), y: .value("m", s.centroidX), series: .value("Serie", "Baricentro"))
                            .foregroundStyle(by: .value("Serie", "Baricentro"))
                        LineMark(x: .value("Minuto", s.t / 60), y: .value("m", s.depth), series: .value("Serie", "Profondità"))
                            .foregroundStyle(by: .value("Serie", "Profondità"))
                        LineMark(x: .value("Minuto", s.t / 60), y: .value("m", s.width), series: .value("Serie", "Ampiezza"))
                            .foregroundStyle(by: .value("Serie", "Ampiezza"))
                    }
                    .frame(height: 200)
                }
            }
            Section("Classifica distanza") {
                ForEach(rows.sorted { $0.stats.distanceMeters > $1.stats.distanceMeters }) { row in
                    let p = row.player, s = row.stats
                    NavigationLink {
                        PlayerAnalysisView(match: match, player: p)
                    } label: {
                        HStack {
                            Text(p.displayName)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: "%.2f km", s.distanceMeters / 1000)).monospacedDigit()
                                Text(String(format: "%.0f m/min · %d sprint", s.metersPerMinute, s.sprintCount))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Squadra")
    }
}
