import AVFoundation
import Combine
import HaishinKit
import RTMPHaishinKit
import SwiftUI
import UIKit
import VideoToolbox

@ScreenActor
final class OverlayStage {
    static let shared = OverlayStage()
    private var object: ImageScreenObject?

    func install(on mixer: MediaMixer) {
        let image = ImageScreenObject()
        image.size = CGSize(width: 1280, height: 720)
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
    private let renderer = ScoreboardRenderer()
    private var subscriptions = Set<AnyCancellable>()
    private var clock: Task<Void, Never>?
    private var lastRevision = -1
    private var lastLiveCommand: Double?
    private var serverOffset = 0.0
    private var producerVisible = false
    private var lastLandscapeOrientation: AVCaptureVideoOrientation = .landscapeRight

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
            videoSettings.videoSize = CGSize(width: 1280, height: 720)
            videoSettings.bitRate = 2_500_000
            videoSettings.profileLevel = kVTProfileLevel_H264_Baseline_AutoLevel as String
            try await stream.setVideoSettings(videoSettings)
            var mixerSettings = await mixer.videoMixerSettings
            mixerSettings.mode = .offscreen
            await mixer.setVideoMixerSettings(mixerSettings)
            await mixer.setVideoOrientation(captureOrientation())
            try await mixer.attachVideo(video)
            try await mixer.attachAudio(microphone)
            await mixer.addOutput(stream)
            await stream.addOutput(preview)
            await OverlayStage.shared.install(on: mixer)
            await mixer.startRunning()
            cameraReady = true
            message = "Camera pronta · tieni aperta questa schermata"
            bridge.setCameraStatus(ready: true, publishing: publishing)
            clock?.cancel()
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.drawOverlay()
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
        streamGeneration += 1
        connecting = false
        try? await stream.close()
        try? await connection.close()
        publishing = false
        bridge.setCameraStatus(ready: cameraReady, publishing: false)
        message = "Invio video fermato"
    }

    private func serverNow() -> Double { Date().timeIntervalSince1970 * 1000 + serverOffset }

    private func drawOverlay() async {
        guard let game, let image = renderer.image(for: game, at: serverNow()) else { return }
        await OverlayStage.shared.update(image)
    }
}

struct CameraPreview: UIViewRepresentable {
    let view: MTHKView
    func makeUIView(context: Context) -> MTHKView { view }
    func updateUIView(_ uiView: MTHKView, context: Context) {}
}
