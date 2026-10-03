import SwiftUI
import UIKit
import WebKit
import Combine

enum BATBrand {
    static let purple = UIColor(red: 81/255, green: 42/255, blue: 125/255, alpha: 1)
    static let yellow = UIColor(red: 1, green: 254/255, blue: 15/255, alpha: 1)
}

struct ContentView: View {
    @StateObject private var camera = CameraEngine()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(view: camera.preview).ignoresSafeArea()
            BATHybridView(camera: camera).ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

struct BATHybridView: UIViewRepresentable {
    let camera: CameraEngine
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "native")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        web.uiDelegate = context.coordinator; web.navigationDelegate = context.coordinator
        context.coordinator.attach(web)
        if let root = Bundle.main.url(forResource: "BATWeb", withExtension: nil) {
            web.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
        }
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "native")
        coordinator.camera.bridge.onEvent = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        let camera: CameraEngine
        weak var web: WKWebView?
        private var subscriptions = Set<AnyCancellable>()
        private var role = ""
        init(camera: CameraEngine) { self.camera = camera }
        func attach(_ web: WKWebView) {
            self.web = web
            camera.bridge.onEvent = { [weak self] event in self?.emit(event) }
            camera.bridge.$status.sink { [weak self] message in self?.emit(["type": "status", "message": message]) }.store(in: &subscriptions)
            camera.$message.sink { [weak self] message in if self?.role == "camera" { self?.emit(["type": "status", "message": message]) } }.store(in: &subscriptions)
        }
        func emit(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object), let json = String(data: data, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.receive(\(json))", completionHandler: nil)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let object = message.body as? [String: Any], let type = object["type"] as? String else { return }
            switch type {
            case "role":
                guard !camera.publishing, !camera.connecting else { emit(["type": "status", "message": "Ferma prima l’invio video per cambiare ruolo"]); return }
                let selected = object["role"] as? String ?? ""
                guard ["", "camera", "regia", "scores"].contains(selected) else { return }
                Task { @MainActor in
                    await camera.stopCamera(); camera.bridge.stop(); role = selected
                    emit(["type": "role", "role": selected, "pin": camera.bridge.pin])
                    if selected == "camera" { camera.bridge.start() }
                    else if !selected.isEmpty { camera.bridge.startController() }
                }
            case "scan": camera.bridge.scan()
            case "connect": camera.bridge.connect(object["address"] as? String ?? "")
            case "pair": camera.bridge.sendCommand(object)
            case "cameraStart": Task { await camera.startCamera() }
            case "cameraStop": Task { await camera.stopCamera() }
            case "destination":
                camera.serverURL = object["url"] as? String ?? ""
                camera.streamKey = object["key"] as? String ?? ""
                camera.configureDestination()
                emit(["type": "status", "message": "Destinazione salvata nel Portachiavi di questo iPhone"])
            case "command":
                if role == "camera" { camera.bridge.localCommand(object) }
                else if camera.bridge.linked { camera.bridge.sendCommand(object) }
                else { emit(["type": "status", "message": "Collega e abbina prima la Camera"]) }
            default: break
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }), let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { completionHandler(nil); return }
            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(alert, animated: true)
        }
    }
}

@main
struct BATTVApp: App { var body: some Scene { WindowGroup { ContentView() } } }
