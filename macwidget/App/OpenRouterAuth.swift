import CryptoKit
import Foundation
import SwiftUI
import WebKit

enum OpenRouterAuthError: Error, LocalizedError {
    case exchangeFailed(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .exchangeFailed(let status):
            return "OpenRouter 拒绝了授权码（HTTP \(status)）"
        case .invalidResponse:
            return "OpenRouter 返回了无法解析的响应"
        }
    }
}

/// The official "Sign in with OpenRouter" OAuth PKCE flow.
///
/// No client id or secret is involved: the PKCE verifier is the only proof, the
/// user authorizes in a web view, and OpenRouter hands back an API key that the
/// app stores in the Keychain as a normal credential.
///
/// Flow: `openrouter.ai/auth` → redirect with `?code=` → `POST /api/v1/auth/keys`.
enum OpenRouterAuth {
    static let authorizeURL = URL(string: "https://openrouter.ai/auth")!
    static let keysURL = URL(string: "https://openrouter.ai/api/v1/auth/keys")!
    /// Where the web view is expected to land after the user authorizes.
    static let callbackURL = URL(string: "https://quotawidget.invalid/openrouter/callback")!

    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authorizationURL(challenge: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// Returns the `code` when the web view lands on the callback URL.
    static func authorizationCode(from url: URL, callback: URL = callbackURL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == callback.host,
              components.path == callback.path else {
            return nil
        }
        return components.queryItems?.first { $0.name == "code" }?.value
    }

    /// Exchanges the authorization code for an API key.
    static func exchange(code: String, verifier: String, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: keysURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "code_verifier": verifier,
            "code_challenge_method": "S256",
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterAuthError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw OpenRouterAuthError.exchangeFailed(http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["key"] as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterAuthError.invalidResponse
        }
        return key
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class AuthWebViewHolder: ObservableObject {
    weak var webView: WKWebView?
}

/// One-time login window: the user signs in on OpenRouter and the app receives
/// its own API key, so nobody has to copy a key out of the OpenRouter console.
struct OpenRouterAuthSheet: View {
    let onAuthorized: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var holder = AuthWebViewHolder()
    @State private var statusText = "在下方窗口中登录 OpenRouter 并授权，密钥会自动保存到钥匙串。"
    @State private var verifier = OpenRouterAuth.makeCodeVerifier()
    @State private var exchanging = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("使用 OpenRouter 登录")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel)
            }
            .padding(16)

            Divider()

            OpenRouterAuthWebView(
                url: OpenRouterAuth.authorizationURL(
                    challenge: OpenRouterAuth.codeChallenge(for: verifier)
                ),
                holder: holder,
                onCallback: handleCallback
            )
            .frame(minWidth: 720, minHeight: 560)
        }
        .frame(width: 760, height: 660)
    }

    private func handleCallback(_ url: URL) {
        guard !exchanging,
              let code = OpenRouterAuth.authorizationCode(from: url) else {
            return
        }
        exchanging = true
        statusText = "正在完成授权…"
        let verifier = self.verifier
        Task {
            do {
                let key = try await OpenRouterAuth.exchange(code: code, verifier: verifier)
                await MainActor.run { onAuthorized(key) }
            } catch {
                await MainActor.run {
                    statusText = "授权失败：\(error.localizedDescription)"
                    exchanging = false
                }
            }
        }
    }
}

struct OpenRouterAuthWebView: NSViewRepresentable {
    let url: URL
    let holder: AuthWebViewHolder
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        holder.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCallback = onCallback
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCallback: (URL) -> Void

        init(onCallback: @escaping (URL) -> Void) {
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               OpenRouterAuth.authorizationCode(from: url) != nil {
                decisionHandler(.cancel)
                onCallback(url)
                return
            }
            decisionHandler(.allow)
        }
    }
}
