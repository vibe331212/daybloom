import LocalAuthentication
import WebKit

/// Lets the web app ask for Face ID (or Touch ID) and get an answer back:
/// `await webkit.messageHandlers.daybloomAsync.postMessage({type: "biometry"})`
final class AsyncMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            replyHandler(nil, "Bad message"); return
        }
        switch type {
        case "biometry":
            replyHandler(Biometry.info(), nil)
        case "biometryAuth":
            Biometry.check(reason: body["reason"] as? String ?? "Open Settings") { replyHandler($0, nil) }
        default:
            replyHandler(nil, "Unknown message")
        }
    }
}

enum Biometry {
    /// Whether Face ID / Touch ID can be used, which one, and a fingerprint of the enrolled faces/fingers
    /// (it changes when someone adds a new face, so the app can stop trusting Face ID until the passcode is typed).
    static func info() -> [String: Any] {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let kind = context.biometryType == .faceID ? "faceID" : context.biometryType == .touchID ? "touchID"
                 : context.biometryType == .none ? "none" : "other"
        return ["available": available, "kind": kind,
                "state": context.evaluatedPolicyDomainState?.base64EncodedString() ?? ""]
    }

    /// Shows the Face ID prompt. result is "ok", "fallback" (tapped Use Passcode), "cancel" or "failed".
    static func check(reason: String, done: @escaping ([String: Any]) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, error in
            let code = (error as? LAError)?.code
            let result = ok ? "ok"
                : code == .userFallback ? "fallback"
                : (code == .userCancel || code == .systemCancel || code == .appCancel) ? "cancel" : "failed"
            let state = context.evaluatedPolicyDomainState?.base64EncodedString() ?? ""
            DispatchQueue.main.async { done(["result": result, "state": state]) }
        }
    }
}
