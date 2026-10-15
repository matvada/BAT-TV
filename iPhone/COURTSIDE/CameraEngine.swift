import AVFoundation
import Combine
import CoreMedia
import HaishinKit
import RTMPHaishinKit
import SwiftUI
import UIKit
import VideoToolbox
import OSLog

/// Keep the RTMP socket queue short when the mobile upload rate changes.
/// The library reports queued and sent bytes every second; its default leaves
/// encoded frames waiting, which can put the broadcast minutes behind reality.
actor BATLiveBitRateStrategy: StreamBitRateStrategy {
    nonisolated let mamimumVideoBitRate = 3_000_000
    let mamimumAudioBitRate = 0
    private var ceiling = 3_000_000
    private(set) var queuedSeconds = 0.0
    private var stableReports = 0
    private(set) var lastReportTime = ProcessInfo.processInfo.systemUptime
    private(set) var sentBitsPerSecond = 0
    private(set) var congestedReports = 0

    func setCeiling(_ value: Int) {
        ceiling = value; stableReports = 0; queuedSeconds = 0; congestedReports = 0
        lastReportTime = ProcessInfo.processInfo.systemUptime
    }

    func adjustBitrate(_ event: NetworkMonitorEvent, stream: some StreamConvertible) async {
        let report: NetworkMonitorReport
        switch event {
        case .status(let value), .publishInsufficientBWOccured(let value): report = value
        case .reset:
            queuedSeconds = 0
            stableReports = 0
            congestedReports = 0
            lastReportTime = ProcessInfo.processInfo.systemUptime
            return
        }
        let bytesPerSecond = report.currentBytesOutPerSecond
        lastReportTime = ProcessInfo.processInfo.systemUptime
        sentBitsPerSecond = bytesPerSecond * 8
        queuedSeconds = report.currentQueueBytesOut == 0 ? 0 :
            min(99, Double(report.currentQueueBytesOut) / Double(max(1, bytesPerSecond)))
        var settings = await stream.videoSettings
        let original = settings
        settings.bitRate = BATStreamPolicy.bitrate(current: settings.bitRate, ceiling: ceiling,
            queue: queuedSeconds, bytesPerSecond: bytesPerSecond, stable: &stableReports)
        // Reduce compression bitrate, not basketball motion to 1–5 fps.
        settings.frameInterval = 0
        congestedReports = queuedSeconds > 4 ? congestedReports + 1 : 0
        if settings.bitRate != original.bitRate || settings.frameInterval != original.frameInterval {
            try? await stream.setVideoSettings(settings)
        }
    }
}

@ScreenActor
final class OverlayStage {
    static let shared = OverlayStage()
    private var object: ImageScreenObject?

    func install(on mixer: MediaMixer, size: CGSize) {
        // The offscreen compositor defaults to 1280×720 even when capture and
        // encoding are 1920×1080. Match its canvas to the overlay and video.
        mixer.screen.removeChild(object)
        mixer.screen.size = size
        let image = ImageScreenObject()
        image.size = size
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

    private let mixer = MediaMixer(multiTrackAudioMixingEnabled: true)
    private var soundTask: Task<Void, Never>?
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
    private var startingCamera = false
    private var reconnectTask: Task<Void, Never>?
    private var lastHealthCheck = 0.0
    private var lastOverlayKey = ""
    private var lastDiagnostic = 0.0
    private var recoveryTimes: [Double] = []
    private let log = Logger(subsystem: "it.battv", category: "Streaming")
    @Published var quality = UserDefaults.standard.integer(forKey: "batVideoHeight") == 720 ? 720 :
        UserDefaults.standard.integer(forKey: "batVideoHeight") == 480 ? 480 : 1080

    init() {
        preview.videoGravity = .resizeAspect
        streamKey = Secrets.load()
        // The address itself is not a credential. Keep the Facebook key in Keychain.
        serverURL = UserDefaults.standard.string(forKey: "facebookRTMPSURL") ?? ""
        game = bridge.game
        bridge.$game.sink { [weak self] game in self?.game = game }.store(in: &subscriptions)
        bridge.onLiveCommand = { [weak self] start in
            Task { @MainActor in if start { await self?.beginLive() } else { await self?.endLive() } }
        }
        bridge.onSoundCommand = { [weak self] name in self?.playSound(name) ?? false }
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
        let bounds = preview.bounds.size
        let scale = min(bounds.width / 1280, bounds.height / 720)
        guard scale > 0 else { return }
        let nx = (x * bounds.width - (bounds.width - 1280 * scale) / 2) / (1280 * scale)
        let ny = (y * bounds.height - (bounds.height - 720 * scale) / 2) / (720 * scale)
        guard (0...1).contains(nx), (0...1).contains(ny) else { return }
        let point = captureOrientation() == .landscapeLeft ? CGPoint(x: ny, y: 1 - nx) : CGPoint(x: 1 - ny, y: nx)
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
        guard !cameraReady, !startingCamera else { return }
        startingCamera = true
        defer { startingCamera = false }
        do {
            let videoPermission = await AVCaptureDevice.requestAccess(for: .video)
            let audioPermission = await AVCaptureDevice.requestAccess(for: .audio)
            guard videoPermission && audioPermission else { throw CameraIssue.noCamera }
            guard let video = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let microphone = AVCaptureDevice.default(for: .audio) else { throw CameraIssue.noCamera }
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setPreferredSampleRate(48_000)
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
            videoSettings.frameInterval = 0
            videoSettings.dataRateLimits = [0, 0]
            try await stream.setVideoSettings(videoSettings)
            try await stream.setAudioSettings(AudioCodecSettings(bitRate: 96_000, sampleRate: 48_000))
            await stream.setVideoInputBufferCounts(1)
            await stream.setBitRateStrategy(bitrateStrategy)
            await bitrateStrategy.setCeiling(bitRate)
            var mixerSettings = await mixer.videoMixerSettings
            mixerSettings.mode = .offscreen
            await mixer.setVideoMixerSettings(mixerSettings)
            await mixer.setSessionPreset(quality == 1080 ? .hd1920x1080 : quality == 720 ? .hd1280x720 : .iFrame960x540)
            await mixer.setVideoOrientation(captureOrientation())
            try await mixer.attachVideo(video) { device in try device.setFrameRate(30) }
            try await mixer.setFrameRate(30)
            try await mixer.attachAudio(microphone)
            var audioMix = AudioMixerSettings(sampleRate: 48_000, channels: 1)
            audioMix.tracks[1] = .default
            await mixer.setAudioMixerSettings(audioMix)
            await mixer.addOutput(stream)
            await stream.addOutput(preview)
            renderer.outputSize = dimensions
            lastOverlayKey = ""
            await OverlayStage.shared.install(on: mixer, size: dimensions)
            await mixer.startRunning()
            captureDevice = video
            cameraReady = true
            UIApplication.shared.isIdleTimerDisabled = true
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
            await mixer.stopRunning()
            message = "Camera: \(error.localizedDescription)"
        }
    }

    func stopCamera() async {
        soundTask?.cancel()
        await endLive()
        clock?.cancel()
        await mixer.stopRunning()
        captureDevice = nil
        cameraReady = false
        UIApplication.shared.isIdleTimerDisabled = false
        bridge.setCameraStatus(ready: false, publishing: false)
        message = "Camera spenta"
    }

    func beginLive() async {
        guard cameraReady, !publishing, !connecting, reconnectTask == nil else { return }
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), url.scheme == "rtmps", url.host != nil else {
            message = CameraIssue.invalidURL.localizedDescription; return
        }
        guard !key.isEmpty else { message = CameraIssue.noKey.localizedDescription; return }
        configureDestination()
        recoveryTimes = []
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
            await bitrateStrategy.setCeiling(quality == 480 ? 900_000 : quality == 720 ? 1_800_000 : 3_000_000)
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
        soundTask?.cancel()
        let finishedMatch = publishing || reconnectTask != nil
        streamGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        connecting = true
        publishing = false
        try? await stream.close()
        try? await connection.close()
        connecting = false
        publishing = false
        bridge.setCameraStatus(ready: cameraReady, publishing: false)
        if finishedMatch { bridge.finishMatch() }
        message = "Invio video fermato"
    }

    private func playSound(_ name: String) -> Bool {
        guard publishing, ["horn", "crowd", "drums"].contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "BATWeb"),
              let data = try? Data(contentsOf: url), data.count > 44 else { return false }
        let pcm = Data(data.dropFirst(44))
        soundTask?.cancel()
        soundTask = Task { [weak self] in
            guard let self,
                  let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 32_000,
                                             channels: 1, interleaved: true) else { return }
            var description: CMAudioFormatDescription?
            var asbd = format.streamDescription.pointee
            guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                 asbd: &asbd, layoutSize: 0, layout: nil,
                                                 magicCookieSize: 0, magicCookie: nil,
                                                 extensions: nil, formatDescriptionOut: &description) == noErr,
                  let description else { return }
            let bytesPerChunk = 640 * 2 // 20 ms at 32 kHz, 16-bit mono.
            let soundStart = CMClockGetTime(CMClockGetHostTimeClock())
            let soundUptime = ProcessInfo.processInfo.systemUptime
            for offset in stride(from: 0, to: pcm.count - 1, by: bytesPerChunk) {
                if Task.isCancelled || !self.publishing { break }
                let chunk = Data(pcm[offset..<min(offset + bytesPerChunk, pcm.count)])
                let frames = chunk.count / 2
                var block: CMBlockBuffer?
                guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                    memoryBlock: nil, blockLength: frames * 2, blockAllocator: kCFAllocatorDefault,
                    customBlockSource: nil, offsetToData: 0, dataLength: frames * 2,
                    flags: 0, blockBufferOut: &block) == noErr, let block,
                    chunk.withUnsafeBytes({ ptr in
                        CMBlockBufferReplaceDataBytes(with: ptr.baseAddress!, blockBuffer: block,
                                                      offsetIntoDestination: 0, dataLength: frames * 2)
                    }) == noErr else { break }
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 32_000),
                                                presentationTimeStamp: CMTimeAdd(soundStart, CMTime(value: Int64(offset / 2), timescale: 32_000)),
                                                decodeTimeStamp: .invalid)
                var sample: CMSampleBuffer?
                var size = 2
                guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                    formatDescription: description, sampleCount: frames, sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
                    sampleBufferOut: &sample) == noErr, let sample else { break }
                await self.mixer.append(sample, track: 1)
                let deadline = soundUptime + Double(offset / 2 + frames) / 32_000
                let delay = deadline - ProcessInfo.processInfo.systemUptime
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            }
        }
        return true
    }

    private func serverNow() -> Double { Date().timeIntervalSince1970 * 1000 + serverOffset }

    private func drawOverlay() async {
        guard let game else { return }
        let now = serverNow()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let state = (try? encoder.encode(game).base64EncodedString()) ?? ""
        let overlay = game.visibleOverlay(at: now)
        let tick = overlay == "glitter" ? Int(now / 250) : game.remaining(at: now)
        let key = "\(state)|\(overlay)|\(tick)|\(quality)"
        guard key != lastOverlayKey,
              let image = renderer.image(for: game, at: now) else { return }
        lastOverlayKey = key
        await OverlayStage.shared.update(image)
    }

    private func reportUploadQueue() async {
        guard publishing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHealthCheck >= 1 else { return }
        lastHealthCheck = now
        let seconds = await bitrateStrategy.queuedSeconds
        let connected = await connection.connected
        let lastReport = await bitrateStrategy.lastReportTime
        let congested = await bitrateStrategy.congestedReports
        if !connected || now - lastReport > 15 || congested >= 3 {
            recoverStream()
            return
        }
        if now - lastDiagnostic >= 10 {
            lastDiagnostic = now
            let sent = await bitrateStrategy.sentBitsPerSecond / 1000
            let target = await stream.videoSettings.bitRate / 1000
            let thermal = ProcessInfo.processInfo.thermalState.rawValue
            log.info("health height=\(self.quality) targetKbps=\(target) sentKbps=\(sent) queueSeconds=\(seconds) thermal=\(thermal)")
            message = "Invio \(quality)p · \(sent) kb/s · coda \(String(format: "%.1f", seconds)) s" +
                (thermal >= 2 ? " · iPhone caldo: raffreddalo o passa a 480p dopo aver fermato l’invio" : "")
        }
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

    /// Recovery never calls endLive(): a network failure must not erase the match.
    private func recoverStream() {
        guard publishing, reconnectTask == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        recoveryTimes.removeAll { now - $0 > 300 }
        publishing = false
        connecting = true
        bridge.setCameraStatus(ready: cameraReady, publishing: false)
        let generation = streamGeneration
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == self.streamGeneration {
                    self.connecting = false
                    self.reconnectTask = nil
                }
            }
            // Closing flushes stale audio/video; retaining queued media would keep the delay.
            try? await self.stream.close()
            try? await self.connection.close()
            for attempt in 0..<5 {
                guard !Task.isCancelled, generation == self.streamGeneration, self.cameraReady else { return }
                guard self.recoveryTimes.count < 5 else { break }
                self.recoveryTimes.append(ProcessInfo.processInfo.systemUptime)
                self.message = "Segnale interrotto · riconnessione \(attempt + 1)/5 · punteggi conservati"
                do {
                    try await Task.sleep(for: .seconds(Double(1 << attempt)))
                    guard !Task.isCancelled, generation == self.streamGeneration else { return }
                    var settings = await self.stream.videoSettings
                    settings.bitRate = min(settings.bitRate, 900_000)
                    settings.frameInterval = 0
                    try await self.stream.setVideoSettings(settings)
                    await self.bitrateStrategy.setCeiling(self.quality == 480 ? 900_000 : self.quality == 720 ? 1_800_000 : 3_000_000)
                    try await self.connection.connect(address)
                    guard !Task.isCancelled, generation == self.streamGeneration else { return }
                    try await self.stream.publish(key)
                    guard !Task.isCancelled, generation == self.streamGeneration else { return }
                    await self.bitrateStrategy.setCeiling(self.quality == 480 ? 900_000 : self.quality == 720 ? 1_800_000 : 3_000_000)
                    self.publishing = true
                    self.bridge.setCameraStatus(ready: true, publishing: true)
                    self.message = "Invio ripristinato · verifica che Facebook abbia ripreso la diretta"
                    self.log.info("RTMP recovery succeeded")
                    return
                } catch {
                    guard !Task.isCancelled, generation == self.streamGeneration else { return }
                    // Never log server URLs or stream keys.
                    self.log.error("RTMP recovery attempt failed")
                    try? await self.connection.close()
                }
            }
            self.message = "Invio non recuperato: controlla rete e Facebook, poi riprova. Punteggi conservati."
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let view: MTHKView
    func makeUIView(context: Context) -> MTHKView { view }
    func updateUIView(_ uiView: MTHKView, context: Context) {}
}
