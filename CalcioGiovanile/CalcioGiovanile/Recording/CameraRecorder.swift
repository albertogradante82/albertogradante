import Foundation
import AVFoundation
import UIKit
import SwiftUI

/// Gestisce la sessione fotocamera e la registrazione del video della partita.
@MainActor
final class CameraRecorder: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUltraWide = false
    @Published var useUltraWide = false { didSet { if oldValue != useUltraWide { reconfigureCamera() } } }
    @Published var zoom: CGFloat = 1 { didSet { applyZoom() } }
    @Published private(set) var freeSpaceGB: Double = 0

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var timer: Timer?
    private var startDate: Date?
    private var currentFileName: String?
    private var finishHandler: ((String?) -> Void)?
    weak var previewLayer: AVCaptureVideoPreviewLayer? { didSet { attachRotation() } }

    func start() async {
        guard await requestPermissions() else {
            errorMessage = "Consenti l'accesso a fotocamera e microfono nelle Impostazioni."
            return
        }
        hasUltraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
        configureSession()
        let session = self.session
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            sessionQueue.async { session.startRunning(); c.resume() }
        }
        isRunning = session.isRunning
        updateFreeSpace()
    }

    func stop() {
        let session = self.session
        sessionQueue.async { session.stopRunning() }
        isRunning = false
    }

    private func requestPermissions() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio) // l'audio è facoltativo
        return video
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        installVideoInput()

        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        if let conn = movieOutput.connection(with: .video) {
            // La stabilizzazione deforma l'immagine: meglio disattivarla, la camera deve stare su un treppiede
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .off }
        }
        if movieOutput.availableVideoCodecTypes.contains(.hevc), let conn = movieOutput.connection(with: .video) {
            movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: conn)
        }
    }

    private func installVideoInput() {
        if let old = videoInput { session.removeInput(old) }
        let type: AVCaptureDevice.DeviceType = (useUltraWide && hasUltraWide) ? .builtInUltraWideCamera : .builtInWideAngleCamera
        guard let device = AVCaptureDevice.default(type, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            errorMessage = "Fotocamera non disponibile."
            return
        }
        session.addInput(input)
        videoInput = input
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        attachRotation()
    }

    private func reconfigureCamera() {
        guard !isRecording else { return }
        session.beginConfiguration()
        installVideoInput()
        session.commitConfiguration()
        zoom = 1
    }

    private func attachRotation() {
        guard let previewLayer, let device = videoInput?.device else { return }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationObservation = rotationCoordinator?.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak previewLayer] coord, _ in
            let angle = coord.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                if let conn = previewLayer?.connection, conn.isVideoRotationAngleSupported(angle) {
                    conn.videoRotationAngle = angle
                }
            }
        }
    }

    private func applyZoom() {
        guard let device = videoInput?.device, (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(zoom, min(device.maxAvailableVideoZoomFactor, 6)))
        device.unlockForConfiguration()
    }

    // MARK: Registrazione

    func startRecording() {
        guard !isRecording else { return }
        let name = VideoStorage.newFileName()
        currentFileName = name
        if let conn = movieOutput.connection(with: .video), let coord = rotationCoordinator {
            let angle = coord.videoRotationAngleForHorizonLevelCapture
            if conn.isVideoRotationAngleSupported(angle) { conn.videoRotationAngle = angle }
        }
        movieOutput.startRecording(to: VideoStorage.url(for: name), recordingDelegate: self)
        isRecording = true
        startDate = Date()
        elapsed = 0
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
                if Int(self.elapsed) % 30 == 0 { self.updateFreeSpace() }
            }
        }
    }

    /// Ferma la registrazione; il callback riceve il nome del file salvato.
    func stopRecording(completion: @escaping (String?) -> Void) {
        guard isRecording else { completion(nil); return }
        finishHandler = completion
        movieOutput.stopRecording()
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func updateFreeSpace() {
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeSpaceGB = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000
    }
}

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // Con errori come "spazio esaurito" il file può essere comunque valido
        let success = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        Task { @MainActor in
            self.isRecording = false
            if !success { self.errorMessage = error?.localizedDescription }
            self.finishHandler?(success ? self.currentFileName : nil)
            self.finishHandler = nil
        }
    }
}

// MARK: - Anteprima

struct CameraPreview: UIViewRepresentable {
    let recorder: CameraRecorder

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = recorder.session
        v.previewLayer.videoGravity = .resizeAspect
        recorder.previewLayer = v.previewLayer
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
