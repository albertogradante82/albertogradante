import Foundation
import SwiftData

// MARK: - Squadra e giocatori

@Model
final class Team {
    var name: String
    var category: String          // es. "Under 12 – Esordienti"
    var season: String
    @Relationship(deleteRule: .cascade, inverse: \Player.team)
    var players: [Player] = []

    init(name: String, category: String, season: String = "") {
        self.name = name
        self.category = category
        self.season = season
    }

    var sortedPlayers: [Player] {
        players.sorted { $0.number == $1.number ? $0.name < $1.name : $0.number < $1.number }
    }
}

@Model
final class Player {
    var name: String
    var number: Int
    var role: String              // Portiere, Difensore, Centrocampista, Attaccante
    var birthYear: Int?
    var team: Team?
    @Relationship(deleteRule: .nullify, inverse: \Track.player)
    var tracks: [Track] = []
    @Relationship(deleteRule: .nullify, inverse: \MatchEvent.player)
    var events: [MatchEvent] = []

    init(name: String, number: Int, role: String, birthYear: Int? = nil) {
        self.name = name
        self.number = number
        self.role = role
        self.birthYear = birthYear
    }

    var displayName: String { "\(number) · \(name)" }

    static let roles = ["Portiere", "Difensore", "Centrocampista", "Attaccante"]
}

// MARK: - Partita

@Model
final class Match {
    var id: UUID
    var date: Date
    var opponent: String
    var location: String
    var isHome: Bool
    var goalsFor: Int
    var goalsAgainst: Int
    var notes: String
    var team: Team?

    /// Nome del file video dentro Documents/Videos
    var videoFileName: String?

    // Dimensioni del campo (metri)
    var pitchLength: Double
    var pitchWidth: Double
    var penaltyAreaDepth: Double
    var penaltyAreaWidth: Double

    /// Calibrazione campo (JSON di `Calibration`)
    var calibrationData: Data?

    /// Secondo del video in cui inizia il secondo tempo (per invertire il verso d'attacco)
    var halfTimeAt: Double?
    /// true se nel primo tempo la nostra squadra attacca verso destra (rispetto all'inquadratura)
    var attacksRightFirstHalf: Bool

    var analysisCompletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Track.match)
    var tracks: [Track] = []
    @Relationship(deleteRule: .cascade, inverse: \MatchEvent.match)
    var events: [MatchEvent] = []

    init(date: Date = .now,
         opponent: String,
         location: String = "",
         isHome: Bool = true,
         pitch: PitchSize = .nineVsNine) {
        self.id = UUID()
        self.date = date
        self.opponent = opponent
        self.location = location
        self.isHome = isHome
        self.goalsFor = 0
        self.goalsAgainst = 0
        self.notes = ""
        self.pitchLength = pitch.length
        self.pitchWidth = pitch.width
        self.penaltyAreaDepth = pitch.penaltyAreaDepth
        self.penaltyAreaWidth = pitch.penaltyAreaWidth
        self.attacksRightFirstHalf = true
    }

    var pitch: PitchSize {
        get { PitchSize(name: "Personalizzato", length: pitchLength, width: pitchWidth,
                        penaltyAreaDepth: penaltyAreaDepth, penaltyAreaWidth: penaltyAreaWidth) }
        set {
            pitchLength = newValue.length
            pitchWidth = newValue.width
            penaltyAreaDepth = newValue.penaltyAreaDepth
            penaltyAreaWidth = newValue.penaltyAreaWidth
        }
    }

    var calibration: Calibration? {
        get { calibrationData.flatMap { try? JSONDecoder().decode(Calibration.self, from: $0) } }
        set { calibrationData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var videoURL: URL? {
        videoFileName.map { VideoStorage.url(for: $0) }
    }

    var title: String {
        let team = self.team?.name ?? "Noi"
        return isHome ? "\(team) – \(opponent)" : "\(opponent) – \(team)"
    }

    var sortedEvents: [MatchEvent] { events.sorted { $0.time < $1.time } }

    /// Normalizza una posizione in modo che la nostra squadra attacchi sempre verso x crescente.
    func normalized(_ p: TrackPoint) -> TrackPoint {
        let secondHalf = halfTimeAt.map { p.t >= $0 } ?? false
        let attacksRight = secondHalf ? !attacksRightFirstHalf : attacksRightFirstHalf
        guard !attacksRight else { return p }
        return TrackPoint(t: p.t, x: pitchLength - p.x, y: pitchWidth - p.y, box: p.box)
    }
}

// MARK: - Traccia (sequenza di posizioni di un giocatore)

@Model
final class Track {
    var id: UUID
    /// "auto" (rilevata dall'analisi video) oppure "manual" (tracciata a dito)
    var source: String
    /// Indice del gruppo colore maglia (k-means). -1 = non classificata
    var colorCluster: Int
    var colorHex: String
    var startTime: Double
    var endTime: Double
    var pointsData: Data
    var match: Match?
    var player: Player?

    init(source: String, points: [TrackPoint], colorHex: String = "#888888", colorCluster: Int = -1) {
        self.id = UUID()
        self.source = source
        self.colorCluster = colorCluster
        self.colorHex = colorHex
        self.startTime = points.first?.t ?? 0
        self.endTime = points.last?.t ?? 0
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
    }

    var points: [TrackPoint] {
        (try? JSONDecoder().decode([TrackPoint].self, from: pointsData)) ?? []
    }

    var duration: Double { endTime - startTime }
}

/// Posizione campionata. x lungo la lunghezza del campo, y lungo la larghezza (metri).
struct TrackPoint: Codable, Hashable {
    var t: Double
    var x: Double
    var y: Double
    /// Riquadro normalizzato (origine in alto a sinistra) del giocatore nel fotogramma, se disponibile
    var box: NormalizedBox?
}

struct NormalizedBox: Codable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

// MARK: - Eventi

@Model
final class MatchEvent {
    var time: Double
    var kind: String
    var note: String
    var match: Match?
    var player: Player?

    init(time: Double, kind: EventKind, note: String = "") {
        self.time = time
        self.kind = kind.rawValue
        self.note = note
    }

    var eventKind: EventKind { EventKind(rawValue: kind) ?? .note }
}

enum EventKind: String, CaseIterable, Identifiable, Codable {
    case goalFor = "Gol fatto"
    case goalAgainst = "Gol subito"
    case shot = "Tiro"
    case chance = "Occasione"
    case recovery = "Recupero"
    case loss = "Palla persa"
    case foul = "Fallo"
    case corner = "Angolo"
    case secondHalf = "Inizio 2° tempo"
    case note = "Nota"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .goalFor: "soccerball"
        case .goalAgainst: "soccerball.inverse"
        case .shot: "scope"
        case .chance: "star"
        case .recovery: "arrow.uturn.backward.circle"
        case .loss: "xmark.circle"
        case .foul: "exclamationmark.triangle"
        case .corner: "flag"
        case .secondHalf: "clock.arrow.circlepath"
        case .note: "note.text"
        }
    }
}
