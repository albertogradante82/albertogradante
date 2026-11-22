import XCTest
import CoreGraphics
@testable import CalcioGiovanile

final class HomographyTests: XCTestCase {
    func testRecoversKnownHomography() throws {
        let truth = Homography(matrix: [0.9, 0.3, 0.05, 0.02, 0.6, 0.1, 0.4, 0.8, 1])
        let src = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.25), CGPoint(x: 0.05, y: 0.85), CGPoint(x: 0.95, y: 0.9)]
        let dst = src.compactMap { truth.apply($0) }
        let h = try XCTUnwrap(Homography(from: src, to: dst))
        for p in [CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.6, y: 0.1)] {
            let a = try XCTUnwrap(h.apply(p)), b = try XCTUnwrap(truth.apply(p))
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testCalibrationMapsCornersToPitch() throws {
        let pitch = PitchSize.nineVsNine
        // trapezio tipico di una ripresa dalla tribuna
        let cal = Calibration(points: [
            CalibrationPoint(landmark: .cornerTopLeft, imageX: 0.25, imageY: 0.3),
            CalibrationPoint(landmark: .cornerTopRight, imageX: 0.75, imageY: 0.3),
            CalibrationPoint(landmark: .cornerBottomLeft, imageX: 0.02, imageY: 0.95),
            CalibrationPoint(landmark: .cornerBottomRight, imageX: 0.98, imageY: 0.95),
        ], imageAspect: 16.0 / 9.0)
        let h = try XCTUnwrap(cal.imageToPitch(pitch: pitch))
        let center = try XCTUnwrap(cal.pitchPoint(fromNormalized: CGPoint(x: 0.5, y: 0.3), pitch: pitch, using: h))
        XCTAssertEqual(center.x, pitch.length / 2, accuracy: 1e-6)
        XCTAssertEqual(center.y, 0, accuracy: 1e-6)
        let back = try XCTUnwrap(cal.pitchToImage(pitch: pitch)?.apply(CGPoint(x: pitch.length, y: pitch.width)))
        XCTAssertEqual(back.x / (16.0 / 9.0), 0.98, accuracy: 1e-6)
    }

    func testCollinearPointsFail() {
        let src = (0..<4).map { CGPoint(x: Double($0), y: Double($0)) }
        XCTAssertNil(Homography(from: src, to: src.map { CGPoint(x: $0.x * 2, y: $0.y) }))
    }
}

final class MovementTests: XCTestCase {
    func testConstantSpeedRun() {
        // 5 m/s (18 km/h) per 20 secondi lungo x
        let pts = stride(from: 0.0, through: 20.0, by: 0.2).map { TrackPoint(t: $0, x: 5 + $0 * 5, y: 20) }
        let s = MovementAnalyzer.stats(for: pts, pitch: .elevenVsEleven)
        XCTAssertEqual(s.distanceMeters, 100, accuracy: 3)
        XCTAssertEqual(s.avgSpeedKmh, 18, accuracy: 0.5)
        XCTAssertEqual(s.sprintCount, 1)
    }

    func testGapsAreNotCountedAsDistance() {
        let a = (0..<10).map { TrackPoint(t: Double($0) * 0.2, x: 10, y: 10) }
        let b = (0..<10).map { TrackPoint(t: 30 + Double($0) * 0.2, x: 50, y: 10) }
        let s = MovementAnalyzer.stats(for: a + b, pitch: .elevenVsEleven)
        XCTAssertLessThan(s.distanceMeters, 1)
    }

    func testHeatmapPeakWherePlayerStays() {
        let pitch = PitchSize.nineVsNine
        let pts = stride(from: 0.0, to: 60, by: 0.5).map { TrackPoint(t: $0, x: 50, y: 10) }
        let h = Heatmap(points: pts, pitch: pitch, columns: 10, rows: 10, blurRadius: 1)
        let c = Int(50 / pitch.length * 10), r = Int(10 / pitch.width * 10)
        XCTAssertEqual(h.value(column: c, row: r), 1, accuracy: 1e-9)
    }
}

final class TrackerTests: XCTestCase {
    func testTwoPlayersCrossingKeepIdentityByColor() {
        let tracker = PlayerTracker()
        let red = SIMD3<Double>(0.9, 0.1, 0.1), blue = SIMD3<Double>(0.1, 0.1, 0.9)
        let box = NormalizedBox(x: 0, y: 0, w: 0.01, h: 0.03)
        for i in 0...50 {
            let t = Double(i) * 0.2
            tracker.update(time: t, detections: [
                Detection(pitchX: 10 + t * 2, pitchY: 20, box: box, color: red, confidence: 1),
                Detection(pitchX: 30 - t * 2, pitchY: 20.5, box: box, color: blue, confidence: 1),
            ])
        }
        let tracks = tracker.finish()
        XCTAssertEqual(tracks.count, 2)
        for tr in tracks {
            let first = tr.points.first!.x, last = tr.points.last!.x
            if tr.meanColor.x > 0.5 { XCTAssertGreaterThan(last, first) } else { XCTAssertLessThan(last, first) }
        }
    }

    func testKMeansSeparatesTeams() {
        let colors: [SIMD3<Double>] = [
            .init(0.9, 0.1, 0.1), .init(0.85, 0.15, 0.1), .init(0.95, 0.05, 0.12),
            .init(0.1, 0.1, 0.9), .init(0.12, 0.15, 0.85),
        ]
        let (labels, _) = TeamColorClassifier.cluster(colors, k: 2)
        XCTAssertEqual(Set(labels[0...2]).count, 1)
        XCTAssertEqual(Set(labels[3...4]).count, 1)
        XCTAssertNotEqual(labels[0], labels[3])
        XCTAssertEqual(labels[0], 0) // il gruppo più numeroso è lo 0
    }
}
