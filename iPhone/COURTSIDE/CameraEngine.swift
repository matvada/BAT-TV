import AVFoundation
import Combine
import HaishinKit
import RTMPHaishinKit
import SwiftUI
import UIKit
import VideoToolbox

/// Keep the RTMP socket queue short when the mobile upload rate changes.
/// The library reports queued and sent bytes every second; its default leaves
/// encoded frames waiting, which can put the broadcast minutes behind reality.
actor BATLiveBitRateStrategy: StreamBitRateStrategy {
    private(set) var mamimumVideoBitRate = 3_000_000
    let mamimumAudioBitRate = 0
    private(set) var queuedSeconds = 0.0
    private var stableReports = 0

    func setCeiling(_ value: Int) { mamimumVideoBitRate = value; stableReports = 0 }

    func adjustBitrate(_ event: NetworkMonitorEvent, stream: some StreamConvertible) async {
        let report: NetworkMonitorReport
        switch event {
        case .status(let value), .publishInsufficientBWOccured(let value): report = value
        case .reset:
            queuedSeconds = 0
            stableReports = 0
            return
        }
        let bytesPerSecond = report.currentBytesOutPerSecond
        queuedSeconds = report.currentQueueBytesOut == 0 ? 0 :
            min(99, Double(report.currentQueueBytesOut) / Double(max(1, bytesPerSecond)))
        var settings = await stream.videoSettings
        let original = settings
        if queuedSeconds > 0.75 {
            stableReports = 0
            let sustainable = max(400_000, Int(Double(bytesPerSecond * 8) * 0.65) - 96_000)
            settings.bitRate = max(400_000, min(settings.bitRate * 3 / 4, sustainable))
            settings.frameInterval = queuedSeconds > 3 ? VideoCodecSettings.frameInterval01 :
                queuedSeconds > 1.5 ? VideoCodecSettings.frameInterval05 : VideoCodecSettings.frameInterval10
        } else if queuedSeconds < 0.25 {
            stableReports += 1
            if stableReports >= 10 {
                settings.bitRate = min(mamimumVideoBitRate, settings.bitRate + 150_000)
                stableReports = 0
            }
            settings.frameInterval = 0
        } else {
            stableReports = 0
        }
        if settings.bitRate != original.bitRate || settings.frameInterval != original.frameInterval {
            try? await stream.setVideoSettings(settings)
        }
    }
}

@ScreenActor
final class OverlayStage {
    static let shared = OverlayStage()
    private var object: ImageScreenObject?

    func install(on mixer: MediaMixer) {
        // The offscreen compositor defaults to 1280×720 even when capture and
        // encoding are 1920×1080. Match its canvas to the overlay and video.
        mixer.screen.size = CGSize(width: 1920, height: 1080)
        let image = ImageScreenObject()
        image.size = CGSize(width: 1920, height: 1080)
        image.horizontalAlignment = .left
        image.verticalAlignment = .top
        try? mixer.screen.addChild(image)
        object = image
    }

    func update(_ image: CGImage) { object?.cgImage = image }
}

@MainActor
final class CameraEngine: ObservableObject {
    @Published var cameraReady = false
    @Published var publishing = false
    @Published var connecting = false
    private var streamGeneration = 0
    @Published var message = "Camera spenta"
    @Published var game: Game?
    @Published var matchCode = ""
    @Published var serverURL = ""
    @Published var streamKey = ""
    @Published var loginVisible = true

    let bridge = MatchBridge()
    let preview = MTHKView(frame: .zero)

    private let mixer = MediaMixer()
    // Facebook can take longer than HaishinKit's 3-second default to acknowledge publish.
    private let connection = RTMPConnection(requestTimeout: 15_000)
    private lazy var stream = RTMPStream(connection: connection)
    private let bitrateStrategy = BATLiveBitRateStrategy()
    private let renderer = ScoreboardRenderer()
    private var subscriptions = Set<AnyCancellable>()
    private var clock: Task<Void, Never>?
    private var lastRevision = -1
    private var lastLiveCommand: Double?
    private var serverOffset = 0.0
    private var producerVisible = false
    private var lastLandscapeOrientation: AVCaptureVideoOrientation = .landscapeRight
    private var reportedQueueSeconds = 0
    private var captureDevice: AVCaptureDevice?
    @Published var quality = UserDefaults.standard.integer(forKey: "batVideoHeight") == 720 ? 720 :
        UserDefaults.standard.integer(forKey: "batVideoHeight") == 480 ? 480 : 1080

    init() {
        preview.videoGravity = .resizeAspectFill
        streamKey = Secrets.load()
        // The address itself is not a credential. Keep the Facebook key in Keychain.
        serverURL = UserDefaults.standard.string(forKey: "facebookRTMPSURL") ?? ""
        game = bridge.game
        bridge.$game.sink { [weak self] game in self?.game = game }.store(in: &subscriptions)
        bridge.onLiveCommand = { [weak self] start in
            Task { @MainActor in if start { await self?.beginLive() } else { await self?.endLive() } }
        }
    }

    func configureDestination() {
        Secrets.save(streamKey.trimmingCharacters(in: .whitespacesAndNewlines))
        UserDefaults.standard.set(serverURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "facebookRTMPSURL")
    }

    private func captureOrientation() -> AVCaptureVideoOrientation {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.interfaceOrientation
        if orientation == .landscapeLeft { lastLandscapeOrientation = .landscapeLeft }
        if orientation == .landscapeRight { lastLandscapeOrientation = .landscapeRight }
        return lastLandscapeOrientation
    }

    func setProducerVisible(_ visible: Bool) {
        if visible { _ = captureOrientation() }
        producerVisible = visible
    }

    func updateCameraOrientation() async {
        guard cameraReady, !producerVisible else { return }
        await mixer.setVideoOrientation(captureOrientation())
    }

    func setQuality(_ height: Int) async {
        guard [480, 720, 1080].contains(height), !publishing, !connecting else {
            message = "Ferma l’invio prima di cambiare risoluzione"; return
        }
        let restart = cameraReady
        if restart { await stopCamera() }
        quality = height
        UserDefaults.standard.set(height, forKey: "batVideoHeight")
        if restart { await startCamera() }
    }

    func focus(x: Double, y: Double) {
        guard cameraReady, let device = captureDevice else { return }
        // Camera sensor coordinates are portrait even when the preview is landscape.
        let point = captureOrientation() == .landscapeLeft ? CGPoint(x: y, y: 1 - x) : CGPoint(x: 1 - y, y: x)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
                device.exposureMode = .continuousAutoExposure
            }
        } catch { message = "Messa a fuoco non disponibile" }
    }

    func zoom(by ratio: Double) {
        guard cameraReady, let device = captureDevice, ratio.isFinite else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = min(min(device.activeFormat.videoMaxZoomFactor, 6), max(1, device.videoZoomFactor * CGFloat(ratio)))
        } catch { message = "Zoom non disponibile" }
    }

    func startCamera() async {
        guard !cameraReady else { return }
        do {
            let videoPermission = await AVCaptureDevice.requestAccess(for: .video)
            let audioPermission = await AVCaptureDevice.requestAccess(for: .audio)
            guard videoPermission && audioPermission else { throw CameraIssue.noCamera }
            guard let video = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let microphone = AVCaptureDevice.default(for: .audio) else { throw CameraIssue.noCamera }
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            var videoSettings = await stream.videoSettings
            let dimensions = quality == 480 ? CGSize(width: 854, height: 480) :
                quality == 720 ? CGSize(width: 1280, height: 720) : CGSize(width: 1920, height: 1080)
            let bitRate = quality == 480 ? 900_000 : quality == 720 ? 1_800_000 : 3_000_000
            videoSettings.videoSize = dimensions
            // Keep headroom on mobile uplinks so the RTMP send queue can stay near real time.
            videoSettings.bitRate = bitRate
            videoSettings.expectedFrameRate = 30
            videoSettings.maxKeyFrameIntervalDuration = 2
            videoSettings.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
            videoSettings.allowFrameReordering = false
            try await stream.setVideoSettings(videoSettings)
            await stream.setVideoInputBufferCounts(1)
            await stream.setBitRateStrategy(bitrateStrategy)
            await bitrateStrategy.setCeiling(bitRate)
            var mixerSettings = await mixer.videoMixerSettings
            mixerSettings.mode = .offscreen
            await mixer.setVideoMixerSettings(mixerSettings)
            await mixer.setSessionPreset(.hd1920x1080)
            await mixer.setVideoOrientation(captureOrientation())
            try await mixer.attachVideo(video)
            try await mixer.attachAudio(microphone)
            await mixer.addOutput(stream)
            await stream.addOutput(preview)
            await OverlayStage.shared.install(on: mixer)
            await mixer.startRunning()
            captureDevice = video
            cameraReady = true
            message = "Camera pronta · tieni aperta questa schermata"
            bridge.setCameraStatus(ready: true, publishing: publishing)
            clock?.cancel()
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.drawOverlay()
                    await self?.reportUploadQueue()
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        } catch {
            message = "Camera: \(error.localizedDescription)"
        }
    }

    func stopCamera() async {
        await endLive()
        clock?.cancel()
        await mixer.stopRunning()
        captureDevice = nil
        cameraReady = false
        bridge.setCameraStatus(ready: false, publishing: false)
        message = "Camera spenta"
    }

    func beginLive() async {
        guard cameraReady, !publishing, !connecting else { return }
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), url.scheme == "rtmps", url.host != nil else {
            message = CameraIssue.invalidURL.localizedDescription; return
        }
        guard !key.isEmpty else { message = CameraIssue.noKey.localizedDescription; return }
        configureDestination()
        connecting = true
        let generation = streamGeneration
        defer { if generation == streamGeneration { connecting = false } }
        do {
            message = "Collegamento a Facebook…"
            try await connection.connect(address)
            guard generation == streamGeneration, cameraReady else { return }
            try await stream.publish(key)
            guard generation == streamGeneration, cameraReady else { return }
            publishing = true
            bridge.setCameraStatus(ready: cameraReady, publishing: true)
            message = "Segnale inviato. Completa i dettagli del post e premi Trasmetti in diretta su Facebook."
        } catch RTMPStream.Error.requestFailed(let response) {
            guard generation == streamGeneration else { return }
            publishing = false
            let code = response.status?.code ?? "risposta non disponibile"
            message = "Facebook ha rifiutato l’invio (\(code)). Seleziona Software di streaming e ricopia URL e chiave."
            try? await connection.close()
        } catch RTMPStream.Error.requestTimedOut {
            guard generation == streamGeneration else { return }
            publishing = false
            message = "Facebook non ha risposto all’invio. Controlla Software di streaming, URL, chiave e connessione."
            try? await connection.close()
        } catch RTMPConnection.Error.requestFailed(let response) {
            guard generation == streamGeneration else { return }
            publishing = false
            let code = response.status?.code ?? "risposta non disponibile"
            message = "Connessione Facebook rifiutata (\(code)). Controlla l’URL del server."
            try? await connection.close()
        } catch {
            guard generation == streamGeneration else { return }
            publishing = false
            message = "Invio non riuscito: \(error.localizedDescription). Controlla URL, chiave e connessione."
            try? await connection.close()
        }
    }

    func endLive() async {
        guard publishing || connecting else { return }
        let finishedMatch = publishing
        streamGeneration += 1
        connecting = false
        try? await stream.close()
        try? await connection.close()
        publishing = false
        bridge.setCameraStatus(ready: cameraReady, publishing: false)
        if finishedMatch { bridge.finishMatch() }
        message = "Invio video fermato"
    }

    private func serverNow() -> Double { Date().timeIntervalSince1970 * 1000 + serverOffset }

    private func drawOverlay() async {
        guard let game, let image = renderer.image(for: game, at: serverNow()) else { return }
        await OverlayStage.shared.update(image)
    }

    private func reportUploadQueue() async {
        guard publishing else { return }
        let seconds = await bitrateStrategy.queuedSeconds
        if seconds > 2 {
            let rounded = min(99, Int(seconds.rounded(.up)))
            if rounded != reportedQueueSeconds {
                reportedQueueSeconds = rounded
                message = "Rete lenta: invio circa \(rounded) s in coda · qualità ridotta automaticamente"
            }
        } else if reportedQueueSeconds != 0 && seconds < 0.5 {
            reportedQueueSeconds = 0
            message = "Invio tornato in tempo reale"
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let view: MTHKView
    func makeUIView(context: Context) -> MTHKView { view }
    func updateUIView(_ uiView: MTHKView, context: Context) {}
}
