import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// Esporta riepilogo e posizioni grezze di una partita in CSV (apribile con Excel/Numbers).
enum CSVExporter {
    static func export(match: Match) throws -> URL {
        var lines: [String] = []
        lines.append("RIEPILOGO;\(match.title);\(match.date.formatted(date: .numeric, time: .omitted))")
        lines.append("giocatore;numero;minuti;distanza_m;m_al_minuto;vel_media_kmh;vel_max_kmh;sprint;dist_sprint_m;difesa_%;centrocampo_%;attacco_%;pos_media_x;pos_media_y")

        let byPlayer = Dictionary(grouping: match.tracks.filter { $0.player != nil }, by: { $0.player!.persistentModelID })
        let groups = byPlayer.values.sorted { ($0.first?.player?.number ?? 0) < ($1.first?.player?.number ?? 0) }
        for tracks in groups {
            guard let p = tracks.first?.player else { continue }
            let pts = MovementAnalyzer.merge(tracks.map { $0.points.map(match.normalized) })
            let s = MovementAnalyzer.stats(for: pts, pitch: match.pitch)
            lines.append([
                p.name, "\(p.number)", f(s.playedSeconds / 60, 1), f(s.distanceMeters, 0), f(s.metersPerMinute, 1),
                f(s.avgSpeedKmh, 1), f(s.maxSpeedKmh, 1), "\(s.sprintCount)", f(s.sprintDistance, 0),
                f(s.thirds[0] * 100, 0), f(s.thirds[1] * 100, 0), f(s.thirds[2] * 100, 0),
                f(s.averageX, 1), f(s.averageY, 1),
            ].joined(separator: ";"))
        }

        lines.append("")
        lines.append("POSIZIONI")
        lines.append("giocatore;traccia;tempo_s;x_m;y_m")
        for t in match.tracks.sorted(by: { $0.startTime < $1.startTime }) {
            let name = t.player?.name ?? "non assegnata"
            let short = String(t.id.uuidString.prefix(8))
            for pt in t.points.map(match.normalized) {
                lines.append("\(name);\(short);\(f(pt.t, 2));\(f(pt.x, 2));\(f(pt.y, 2))")
            }
        }

        let safeTitle = match.title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeTitle).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func f(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }
}

struct MatchCSV: Transferable {
    let match: Match

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            SentTransferredFile(try CSVExporter.export(match: csv.match))
        }
    }
}
