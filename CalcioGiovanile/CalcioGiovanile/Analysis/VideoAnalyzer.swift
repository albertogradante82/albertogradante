import Foundation
import AVFoundation
import Vision
import CoreImage
import ImageIO

/// Analizza il video: rileva le persone con Vision, le proietta sul campo tramite
/// la calibrazione e costruisce le tracce dei giocatori.
final class VideoAnalyzer {

    struct Options {
        /// Fotogrammi analizzati al secondo
        var sampleFPS: Double = 5
        /// Divide il fotogramma in riquadri sovrapposti per trovare giocatori lontani (più lento)
        var highPrecision: Bool = true
        /// Tolleranza (m) fuori dalle linee per considerare un giocatore "in campo"
        var pitchMargin: Double = 1.5
        var minConfidence: Float = 0.3
        var startTime: Double = 0
        var endTime: Double?
    }

    struct TrackData {
        var points: [TrackPoint]
        var colorHex: String
        var cluster: Int
    }

    struct Result {
        var tracks: [TrackData]
        var clusterColors: [String]
    }

    enum AnalysisError: LocalizedError {
        case noVideoTrack, calibrationInvalid, readerFailed(String)
        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "Il file non contiene una traccia video."
            case .calibrationInvalid: "Calibrazione del campo non valida: ripeti la calibrazione."
            case .readerFailed(let m): "Impossibile leggere il video: \(m)"
            }
        }
    }

    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    func analyze(url: URL,
                 calibration: Calibration,
                 pitch: PitchSize,
                 options: Options = Options(),
                 progress: @escaping (Double) -> Void) async throws -> Result {

        guard let homography = calibration.imageToPitch(pitch: pitch) else { throw AnalysisError.calibrationInvalid }

        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw AnalysisError.noVideoTrack }
        let duration = try await asset.load(.duration).seconds
        let transform = try await videoTrack.load(.preferredTransform)
        let orientation = VideoAnalyzer.orientation(from: transform)

        let reader = try AVAssetReader(asset: asset)
        let end = min(options.endTime ?? duration, duration)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: options.startTime, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw AnalysisError.readerFailed(reader.error?.localizedDescription ?? "errore sconosciuto")
        }

        let tracker = PlayerTracker()
        let interval = 1.0 / options.sampleFPS
        var nextSample = options.startTime
        let total = max(0.001, end - options.startTime)
        var lastReported = -1.0

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard t + 1e-3 >= nextSample, let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            nextSample = t + interval

            autoreleasepool {
                let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
                let normalizedImage = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,
                                                                               y: -image.extent.minY))
                let detections = detect(in: normalizedImage, calibration: calibration, homography: homography,
                                        pitch: pitch, options: options)
                tracker.update(time: t, detections: detections)
            }
            let fraction = min(1, (t - options.startTime) / total)
            if fraction - lastReported >= 0.005 {
                lastReported = fraction
                progress(fraction)
            }
        }

        if reader.status == .failed {
            throw AnalysisError.readerFailed(reader.error?.localizedDescription ?? "errore sconosciuto")
        }

        let builders = tracker.finish()
        let (labels, centers) = TeamColorClassifier.cluster(builders.map(\.meanColor), k: 3)
        let centerHex = centers.map { hexString(r: $0.x, g: $0.y, b: $0.z) }

        let tracks = builders.enumerated().map { i, b -> TrackData in
            let c = b.meanColor
            return TrackData(points: b.points,
                             colorHex: hexString(r: c.x, g: c.y, b: c.z),
                             cluster: labels.indices.contains(i) ? labels[i] : -1)
        }
        progress(1)
        return Result(tracks: tracks, clusterColors: centerHex)
    }

    // MARK: - Rilevazione in un fotogramma

    private func detect(in image: CIImage,
                        calibration: Calibration,
                        homography: Homography,
                        pitch: PitchSize,
                        options: Options) -> [Detection] {
        let W = image.extent.width, H = image.extent.height
        var tiles: [CGRect] = [image.extent]
        if options.highPrecision {
            // Griglia 3x2 con sovrapposizione del 20%: aiuta con i giocatori lontani e piccoli
            let cols = 3, rows = 2, overlap = 0.2
            let tw = W / (CGFloat(cols) - CGFloat(cols - 1) * overlap)
            let th = H / (CGFloat(rows) - CGFloat(rows - 1) * overlap)
            for r in 0..<rows {
                for c in 0..<cols {
                    tiles.append(CGRect(x: CGFloat(c) * tw * (1 - overlap),
                                        y: CGFloat(r) * th * (1 - overlap),
                                        width: tw, height: th).intersection(image.extent))
                }
            }
        }

        // Riquadri in coordinate immagine normalizzate con origine in alto a sinistra
        var boxes: [(CGRect, Float)] = []
        for tile in tiles {
            let cropped = image.cropped(to: tile)
                .transformed(by: CGAffineTransform(translationX: -tile.minX, y: -tile.minY))
            let request = VNDetectHumanRectanglesRequest()
            request.upperBodyOnly = false
            let handler = VNImageRequestHandler(ciImage: cropped, options: [:])
            try? handler.perform([request])
            for obs in request.results ?? [] where obs.confidence >= options.minConfidence {
                let b = obs.boundingBox // normalizzato nel riquadro, origine in basso a sinistra
                let x = (tile.minX + b.minX * tile.width) / W
                let yBottomUp = (tile.minY + b.minY * tile.height) / H
                let w = b.width * tile.width / W
                let h = b.height * tile.height / H
                let topLeft = CGRect(x: x, y: 1 - yBottomUp - h, width: w, height: h)
                boxes.append((topLeft, obs.confidence))
            }
        }
        boxes = VideoAnalyzer.nonMaxSuppression(boxes, iouThreshold: 0.45)

        var detections: [Detection] = []
        for (box, conf) in boxes {
            // Il punto di contatto col terreno è il centro del lato inferiore del riquadro
            let foot = CGPoint(x: box.midX, y: box.maxY)
            guard let p = calibration.pitchPoint(fromNormalized: foot, pitch: pitch, using: homography),
                  pitch.contains(p, margin: options.pitchMargin) else { continue }
            let color = jerseyColor(in: image, box: box)
            detections.append(Detection(pitchX: Double(p.x), pitchY: Double(p.y),
                                        box: NormalizedBox(x: box.minX, y: box.minY, w: box.width, h: box.height),
                                        color: color, confidence: Double(conf)))
        }
        return detections
    }

    /// Colore medio della zona del busto (dove c'è la maglia).
    private func jerseyColor(in image: CIImage, box: CGRect) -> SIMD3<Double> {
        let W = image.extent.width, H = image.extent.height
        // busto: dal 20% al 45% dell'altezza del riquadro, parte centrale in larghezza
        let torsoTop = box.minY + box.height * 0.2
        let torsoBottom = box.minY + box.height * 0.45
        let rect = CGRect(x: (box.minX + box.width * 0.3) * W,
                          y: (1 - torsoBottom) * H,
                          width: box.width * 0.4 * W,
                          height: (torsoBottom - torsoTop) * H).integral.intersection(image.extent)
        guard rect.width >= 1, rect.height >= 1,
              let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: rect)]),
              let out = filter.outputImage else { return SIMD3(0.5, 0.5, 0.5) }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        return SIMD3(Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255)
    }

    // MARK: - Utility

    static func nonMaxSuppression(_ boxes: [(CGRect, Float)], iouThreshold: CGFloat) -> [(CGRect, Float)] {
        let sorted = boxes.sorted { $0.1 > $1.1 }
        var kept: [(CGRect, Float)] = []
        for b in sorted {
            if kept.allSatisfy({ iou($0.0, b.0) < iouThreshold && !contains($0.0, b.0) }) { kept.append(b) }
        }
        return kept
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    /// true se un riquadro è quasi interamente contenuto nell'altro (duplicati tra riquadri adiacenti)
    static func contains(_ a: CGRect, _ b: CGRect) -> Bool {
        let i = a.intersection(b)
        guard !i.isNull else { return false }
        let inter = i.width * i.height
        return inter > 0.8 * min(a.width * a.height, b.width * b.height)
    }

    static func orientation(from t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
