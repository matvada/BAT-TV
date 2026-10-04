import SwiftUI
import UIKit
import WebKit
import Combine

enum BATBrand {
    static let purple = UIColor(red: 81/255, green: 42/255, blue: 125/255, alpha: 1)
    static let yellow = UIColor(red: 1, green: 254/255, blue: 15/255, alpha: 1)
}

@MainActor
final class BATOrientation: NSObject, UIApplicationDelegate {
    static var allowed: UIInterfaceOrientationMask = .landscape

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowed
    }

    static func showProducer() {
        change(to: .portrait)
    }

    static func showCamera(preferred: UIInterfaceOrientationMask) {
        allowed = .landscape
        request(preferred)
    }

    private static func change(to mask: UIInterfaceOrientationMask) {
        allowed = mask
        request(mask)
    }

    private static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            NSLog("BAT tv: orientamento richiesto non disponibile: %@", error.localizedDescription)
        }
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraEngine()
    @State private var showFacebookProducer = false
    @State private var showSplash = true
    @State private var cameraOrientation: UIInterfaceOrientationMask = .landscapeRight
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(view: camera.preview).ignoresSafeArea()
            BATHybridView(camera: camera, openFacebookProducer: {
                let sceneOrientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation
                cameraOrientation = sceneOrientation == .landscapeLeft ? .landscapeLeft : .landscapeRight
                camera.setProducerVisible(true)
                showFacebookProducer = true
                BATOrientation.showProducer()
            }).ignoresSafeArea()
            if showSplash {
                BATLaunchSplash()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
        }
        .fullScreenCover(isPresented: $showFacebookProducer, onDismiss: {
            camera.setProducerVisible(false)
            BATOrientation.showCamera(preferred: cameraOrientation)
            Task { await camera.updateCameraOrientation() }
        }) {
            FacebookProducerView(camera: camera) { showFacebookProducer = false }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            Task { await camera.updateCameraOrientation() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }
}

private struct BATLaunchSplash: View {
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 35/255, green: 10/255, blue: 61/255)
                Image("BATLaunchBanner")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                Text("BUILD \(build)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color(red: 1, green: 254/255, blue: 15/255))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityLabel("BAT tv, build \(build)")
    }
}

struct BATHybridView: UIViewRepresentable {
    let camera: CameraEngine
    let openFacebookProducer: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera, openFacebookProducer: openFacebookProducer) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "native")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        web.scrollView.bounces = false
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
        let openFacebookProducer: () -> Void
        weak var web: WKWebView?
        private var subscriptions = Set<AnyCancellable>()
        private var role = ""
        init(camera: CameraEngine, openFacebookProducer: @escaping () -> Void) {
            self.camera = camera
            self.openFacebookProducer = openFacebookProducer
        }
        func attach(_ web: WKWebView) {
            self.web = web
            camera.bridge.onEvent = { [weak self] event in self?.emit(event) }
            camera.bridge.$status.sink { [weak self] message in self?.emit(["type": "status", "message": message]) }.store(in: &subscriptions)
            camera.$message.sink { [weak self] message in if self?.role == "camera" { self?.emit(["type": "status", "message": message]) } }.store(in: &subscriptions)
            camera.$serverURL.combineLatest(camera.$streamKey).sink { [weak self] url, key in
                self?.emit(["type": "destination", "url": url, "key": key])
            }.store(in: &subscriptions)
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
                    web?.scrollView.isScrollEnabled = selected != "camera"
                    emit(["type": "role", "role": selected, "pin": camera.bridge.pin])
                    if selected == "camera" { camera.bridge.start() }
                    else if !selected.isEmpty { camera.bridge.startController() }
                }
            case "scan": camera.bridge.scan()
            case "connect": camera.bridge.connect(object["address"] as? String ?? "")
            case "pair": camera.bridge.sendCommand(object)
            case "cameraStart": Task { await camera.startCamera() }
            case "cameraStop": Task { await camera.stopCamera() }
            case "facebookProducer":
                guard role == "camera" else { return }
                openFacebookProducer()
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
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            emit(["type": "destination", "url": camera.serverURL, "key": camera.streamKey])
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

/// Live Producer remains in this app so the capture session can keep running while
/// the user confirms Facebook's separate Go Live action for a group broadcast.
struct FacebookProducerView: View {
    @ObservedObject var camera: CameraEngine
    let close: () -> Void
    @State private var notice = "Nel gruppo BAT TV seleziona Software di streaming (icona chiave), poi copia URL e chiave qui sopra."

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Chiudi") { close() }
                Spacer(minLength: 6)
                Text("Facebook Live Producer").font(.headline).lineLimit(1)
                Spacer(minLength: 6)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            HStack(spacing: 8) {
                Button("Usa URL copiato") { saveClipboard(isKey: false) }
                Button("Usa chiave copiata") { saveClipboard(isKey: true) }
                Button(camera.publishing ? "Invio attivo" : "Avvia invio") {
                    Task {
                        if !camera.cameraReady { await camera.startCamera() }
                        await camera.beginLive()
                    }
                }.disabled(camera.publishing || camera.connecting)
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .padding(.horizontal, 8)
            Text(notice)
                .font(.caption2).foregroundStyle(.white.opacity(0.8))
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.top, 4)
            if camera.message != "Camera spenta" {
                Text(camera.message)
                    .font(.caption).foregroundStyle(.yellow)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 5)
            }
            FacebookProducerBrowser()
        }
        .background(Color(red: 0.08, green: 0.04, blue: 0.12))
        .preferredColorScheme(.dark)
    }

    private func saveClipboard(isKey: Bool) {
        let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isKey {
            guard !value.isEmpty, !value.contains("rtmp://"), !value.contains("rtmps://") else {
                notice = "Copia prima la chiave da Facebook."; return
            }
            camera.streamKey = value
            notice = "Chiave salvata. Non condividerla."
        } else {
            guard let url = URL(string: value), url.scheme == "rtmps", url.host != nil else {
                notice = "Copia l’URL del server RTMPS da Facebook."; return
            }
            camera.serverURL = value
            notice = "Server salvato. Ora copia la chiave persistente."
        }
        camera.configureDestination()
    }
}

struct FacebookProducerBrowser: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let web = FacebookProducerSession.web
        web.removeFromSuperview()
        web.uiDelegate = context.coordinator
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate {
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

@MainActor
private enum FacebookProducerSession {
    // Keep the actual Live Producer form alive when the control panel is closed.
    // A new WKWebView loaded at /live/producer starts a new draft on the profile.
    static let web: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: URL(string: "https://www.facebook.com/live/producer")!))
        return web
    }()
}

@main
struct BATTVApp: App {
    @UIApplicationDelegateAdaptor(BATOrientation.self) private var orientation
    var body: some Scene { WindowGroup { ContentView() } }
}
