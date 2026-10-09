import SwiftUI
import WebKit
import UserNotifications

/// Shows the Daybloom web app, which is bundled inside the iPhone app in the "Web" folder.
struct WebContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebViewController { WebViewController() }
    func updateUIViewController(_ controller: WebViewController, context: Context) {}
}

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let background = UIColor(red: 0.071, green: 0.043, blue: 0.149, alpha: 1)

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()   // keeps sign-in and saved events between launches
        config.userContentController.add(WeakMessageHandler(self), name: "daybloom")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        webView.scrollView.contentInsetAdjustmentBehavior = .never   // the page handles the notch and home bar itself
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            assertionFailure("The web app was not copied into the app bundle")
            return
        }
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    }

    // MARK: Links

    // Web links (like the privacy policy) open in Safari instead of replacing the app.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url,
           ["http", "https", "mailto"].contains(url.scheme ?? ""),
           navigationAction.targetFrame?.isMainFrame ?? true {
            await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // The page was unloaded by the system (for example, low memory). Reload it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    #if DEBUG
    // Test builds only: `simctl launch ... -DaybloomDebugJS "<script>"` runs a script once the page loads
    // and logs what it returns, plus the notifications waiting to go off. Never part of the App Store build.
    private var ranDebugScript = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !ranDebugScript, let script = UserDefaults.standard.string(forKey: "DaybloomDebugJS"), !script.isEmpty else { return }
        ranDebugScript = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                let text: String
                switch result {
                case .success(let value): text = String(describing: value)
                case .failure(let error): text = "ERROR \(error)"
                }
                NSLog("DAYBLOOM_DEBUG result: %@", text)
                UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                    let list = requests.map { "\($0.identifier) | \($0.content.title) | \($0.content.body)" }.joined(separator: " ;; ")
                    NSLog("DAYBLOOM_DEBUG pending(%d): %@", requests.count, list)
                }
            }
        }
    }
    #endif

    // MARK: Messages from the web app

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "haptic":
            Haptics.play(body["style"] as? String ?? "light")
        case "share":
            share(text: body["text"] as? String ?? "", url: (body["url"] as? String).flatMap(URL.init(string:)))
        case "reminders":
            let items = body["items"] as? [[String: Any]] ?? []
            let sound = body["sound"] as? Bool ?? true
            Task { await Reminders.schedule(items, sound: sound) }
        case "timer":
            let at = (body["at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            Task { await Reminders.scheduleTimer(at: at, body: body["body"] as? String ?? "Your timer finished") }
        case "openSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        default:
            break
        }
    }

    private func share(text: String, url: URL?) {
        let sheet = UIActivityViewController(activityItems: [text] + (url.map { [$0] } ?? []), applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(sheet, animated: true)
    }
}

/// WKUserContentController keeps a strong reference to its handlers; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

enum Haptics {
    static func play(_ style: String) {
        switch style {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
