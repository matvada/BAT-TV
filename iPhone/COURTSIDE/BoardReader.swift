import UIKit
import AVFoundation
import Vision
import CoreImage

/// Silent camera and OCR on the Punteggi device only. No network image transport.
final class BoardReader: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onEvent: (([String: Any]) -> Void)?
    var onReading: (([String: Int], Double) -> Void)?
    private let queue = DispatchQueue(label: "BAT.board.reader", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let context = CIContext()
    private var regions: [String: [Double]] = [:]
    private var previous: [String: Int] = [:]
    private var counts: [String: Int] = [:]
    private var active = false
    private var lastFrame = 0.0
    private var generation = 0

    private func emit(_ event: [String: Any]) { DispatchQueue.main.async { [weak self] in self?.onEvent?(event) } }
    func configure(_ value: [String: [Double]]) { queue.async { self.regions = value; self.previous = [:]; self.counts = [:]; self.generation += 1 } }
    func start(orientation: AVCaptureVideoOrientation) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { self.emit(["type": "readerStatus", "message": "Consenti la fotocamera nelle Impostazioni"]); return }
            self.queue.async {
                guard !self.active else { return }
                do {
                    self.session.beginConfiguration(); self.session.sessionPreset = .hd1280x720
                    self.session.inputs.forEach { self.session.removeInput($0) }; self.session.outputs.forEach { self.session.removeOutput($0) }
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraIssue.noCamera }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else { throw CameraIssue.noCamera }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { throw CameraIssue.noCamera }
                    self.session.addOutput(output)
                    if let connection = output.connection(with: .video), connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
                    self.session.commitConfiguration(); self.active = true; self.session.startRunning()
                    self.emit(["type": "readerStarted"])
                } catch {
                    self.session.commitConfiguration()
                    self.emit(["type": "readerStatus", "message": "Fotocamera non disponibile: \(error.localizedDescription)"])
                }
            }
        }
    }
    func stop() { queue.async { self.active = false; self.generation += 1; self.previous = [:]; self.counts = [:]; self.session.stopRunning(); self.emit(["type": "readerStopped"]) } }
    static func parse(_ field: String, _ raw: String) -> Int? {
        let text = raw.components(separatedBy: .whitespacesAndNewlines).joined()
        let value: Int
        if field == "clock" {
            if text.range(of: "^[0-9]{1,2}:[0-5][0-9]$", options: .regularExpression) != nil {
                let parts = text.split(separator: ":"); value = (Int(parts[0]) ?? 0) * 60 + (Int(parts[1]) ?? 0)
            } else if text.range(of: "^[0-5]?[0-9][.,][0-9]$", options: .regularExpression) != nil, let decimal = Double(text.replacingOccurrences(of: ",", with: ".")) { value = Int(ceil(decimal)) }
            else { return nil }
        } else {
            guard text.range(of: "^[0-9]{1,3}$", options: .regularExpression) != nil, let number = Int(text) else { return nil }; value = number
        }
        return BoardState.valid(field, value) ? value : nil
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = ProcessInfo.processInfo.systemUptime
        guard active, time - lastFrame >= 0.22, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = time
        let capturedAt = Date().timeIntervalSince1970 * 1000
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(ci, from: ci.extent) else { return }
        if let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.5) { emit(["type": "readerFrame", "image": "data:image/jpeg;base64," + jpeg.base64EncodedString()]) }
        var values: [String: Int] = [:], raw: [String: String] = [:]
        for key in BoardState.fields {
            guard let r = regions[key], r.count == 4, r.allSatisfy({ $0.isFinite }), r[0] >= 0, r[1] >= 0, r[2] >= 0.01, r[3] >= 0.01, r[0] + r[2] <= 1.001, r[1] + r[3] <= 1.001 else { continue }
            let rect = CGRect(x: r[0] * Double(image.width), y: r[1] * Double(image.height), width: r[2] * Double(image.width), height: r[3] * Double(image.height))
            guard let crop = image.cropping(to: rect) else { continue }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false; request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.05
            do { try VNImageRequestHandler(cgImage: crop, orientation: .up).perform([request]) } catch { previous.removeValue(forKey: key); counts.removeValue(forKey: key); continue }
            let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            let text = candidates.allSatisfy({ $0.confidence >= 0.55 }) ? candidates.map(\.string).joined(separator: " ") : ""
            raw[key] = text
            guard let number = Self.parse(key, text) else { previous.removeValue(forKey: key); counts.removeValue(forKey: key); continue }
            counts[key] = previous[key] == number ? (counts[key] ?? 0) + 1 : 1; previous[key] = number
            if (counts[key] ?? 0) >= (key == "clock" ? 2 : 3) { values[key] = number }
        }
        emit(["type": "readerValues", "values": values, "raw": raw])
        if Date().timeIntervalSince1970 * 1000 - capturedAt < 2000 {
            let result = values
            DispatchQueue.main.async { [weak self] in self?.onReading?(result, capturedAt) }
        }
    }
}
