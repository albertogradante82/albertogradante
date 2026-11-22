import Foundation
import AVFoundation
import UIKit
import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

enum VideoStorage {
    static var directory: URL {
        let dir = URL.documentsDirectory.appending(path: "Videos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    static func newFileName(ext: String = "mov") -> String {
        "partita-\(UUID().uuidString).\(ext)"
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Fotogramma orientato correttamente al tempo indicato.
    static func frame(of url: URL, at seconds: Double, maxSize: CGSize = CGSize(width: 1920, height: 1920)) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = maxSize
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let (cg, _) = try await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        let d = (try? await asset.load(.duration)) ?? .zero
        return d.seconds.isFinite ? d.seconds : 0
    }
}

/// Video importato dal Rullino tramite PhotosPicker.
struct ImportedMovie: Transferable {
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(VideoStorage.url(for: movie.fileName))
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let name = VideoStorage.newFileName(ext: ext)
            let dest = VideoStorage.url(for: name)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ImportedMovie(fileName: name)
        }
    }
}

extension Double {
    /// 75.4 -> "01:15"
    var clockString: String {
        guard isFinite else { return "--:--" }
        let s = Int(self.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}

func hexString(r: Double, g: Double, b: Double) -> String {
    func c(_ v: Double) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
    return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
}
