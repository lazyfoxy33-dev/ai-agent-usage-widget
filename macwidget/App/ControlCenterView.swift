import SwiftUI
import WebKit

// Providers: Claude, Codex, Kimi Code, DeepSeek, SiliconFlow, OpenRouter

// MARK: - 设置窗口

struct ControlCenterView: View {
    @ObservedObject var accountViewModel: AccountSettingsViewModel
    let displayStore: DisplayLayerStore
    let refreshNow: () -> Void
    let displayActions: DisplayLayerActions

    @State private var showingSiliconFlowConsoleLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(
                model: accountViewModel.model,
                isTesting: accountViewModel.isTesting,
                refreshNow: refreshNow,
                onTest: { accountViewModel.testProviders() }
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProviderSection(title: "本地客户端", subtitle: "从本机官方客户端读取") {
                        ForEach(accountViewModel.model.rows.filter { $0.kind == .localAgent }) { row in
                            ProviderRow(
                                row: row,
                                onToggleProbe: row.id == .codex ? { accountViewModel.toggleCodexProbe() } : nil,
                                onLoginHelp: row.id != .codex ? { accountViewModel.openLoginHelp(for: row.id) } : nil
                            )
                        }
                    }

                    ProviderSection(title: "API 余额", subtitle: "密钥保存在 macOS 钥匙串") {
                        ForEach(accountViewModel.model.rows.filter { $0.kind == .apiKey }) { row in
                            if row.id == .siliconflow {
                                SiliconFlowProviderRow(
                                    row: row,
                                    consoleConfigured: accountViewModel.model.siliconFlowConsoleConfigured,
                                    onConnectConsole: { showingSiliconFlowConsoleLogin = true },
                                    onDisconnectConsole: { accountViewModel.deleteSiliconFlowConsoleSession() }
                                )
                            } else {
                                ProviderRow(
                                    row: row,
                                    onAddKey: row.id.apiKeyID.map { id in { accountViewModel.beginEdit(id) } },
                                    onRemoveKey: row.id.apiKeyID.map { id in { accountViewModel.deleteKey(id) } },
                                    onTest: { accountViewModel.testProviders() }
                                )
                            }
                        }

                        if let editingProvider = accountViewModel.editingProvider {
                            APIKeyInlineEditor(
                                provider: editingProvider,
                                keyInput: $accountViewModel.keyInput,
                                errorText: accountViewModel.saveErrorText,
                                onSave: { accountViewModel.saveKey() },
                                onCancel: { accountViewModel.cancelEdit() }
                            )
                            .padding(12)
                        }
                    }

                    ProviderSection(title: "Touch Bar", subtitle: "装到这台 Mac 的 Touch Bar 上") {
                        TouchBarRow(displayStore: displayStore, actions: displayActions)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(isPresented: $showingSiliconFlowConsoleLogin) {
            SiliconFlowConsoleLoginSheet(
                onSave: { session in
                    if accountViewModel.saveSiliconFlowConsoleSession(
                        cookieHeader: session.cookieHeader,
                        subjectID: session.subjectID
                    ) {
                        showingSiliconFlowConsoleLogin = false
                        refreshNow()
                    }
                },
                onCancel: { showingSiliconFlowConsoleLogin = false }
            )
        }
        .onAppear {
            accountViewModel.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quotaWidgetUsagePayloadDidRefresh)) { _ in
            accountViewModel.reload()
        }
    }
}

struct SettingsHeader: View {
    let model: AccountSettingsModel
    let isTesting: Bool
    let refreshNow: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Agent 用量组件")
                    .font(.title2.bold())
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("测试全部", action: onTest)
                    .disabled(isTesting)
                Button("立即刷新", action: refreshNow)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(height: 78)
    }

    private var summaryText: String {
        let connected = model.rows.filter(\.configured).count
        return "已连接 \(connected)/\(model.rows.count) 个提供商"
    }
}

struct ProviderRow: View {
    let row: AccountRowState
    var onAddKey: (() -> Void)?
    var onRemoveKey: (() -> Void)?
    var onTest: (() -> Void)?
    var onToggleProbe: (() -> Void)?
    var onLoginHelp: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(id: row.id)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .bold))
                    if let detailText = row.detailText {
                        Tag(text: detailText)
                    }
                }
                Text(row.balanceSummary ?? row.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ProviderStatus(configured: row.configured)

            HStack(spacing: 8) {
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 68)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.04)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch row.id.kind {
        case .localAgent:
            if row.id == .codex {
                Button(row.configured ? "关闭主动探测" : "开启主动探测") {
                    onToggleProbe?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("打开客户端") {
                    onLoginHelp?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .apiKey:
            if row.configured {
                Button("更换密钥") { onAddKey?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("测试") { onTest?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("移除") { onRemoveKey?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("添加密钥") { onAddKey?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("测试") { onTest?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct TouchBarRow: View {
    let displayStore: DisplayLayerStore
    let actions: DisplayLayerActions

    @State private var status = DisplayLayerStatus.checking
    @State private var busy = false
    @State private var resultText: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black)
                Text("T")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text("Touch Bar 组件")
                    .font(.system(size: 14, weight: .bold))
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let resultText {
                Text(resultText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProviderStatus(configured: status.installed)

            HStack(spacing: 8) {
                Button("安装 / 更新") {
                    run("Touch Bar 组件已更新", actions.installTouchBar)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("打开") {
                    run("已打开 Touch Bar 组件", actions.openTouchBar)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .disabled(busy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 68)
        .background(Color.white)
        .onAppear(perform: refreshStatus)
    }

    private var statusText: String {
        guard status.installed else { return "未安装" }
        return status.running ? "已安装 · 运行中" : "已安装"
    }

    private func run(_ success: String, _ action: @escaping @Sendable () throws -> Void) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: String
            do {
                try action()
                result = success
            } catch {
                result = error.localizedDescription
            }
            DispatchQueue.main.async {
                resultText = result
                busy = false
                refreshStatus()
            }
        }
    }

    private func refreshStatus() {
        let store = displayStore
        DispatchQueue.global(qos: .userInitiated).async {
            let updated = store.touchBarStatus()
            DispatchQueue.main.async {
                status = updated
            }
        }
    }
}

struct ProviderSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct ProviderLogo: View {
    let id: AccountProviderID

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(logoColor)
            Text(logoText)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.white)
        }
    }

    private var logoColor: Color {
        switch id {
        case .claude: return Color(red: 0.851, green: 0.467, blue: 0.341)
        case .codex: return Color(red: 0.482, green: 0.514, blue: 0.961)
        case .kimi: return Color(red: 0.067, green: 0.067, blue: 0.067)
        case .deepseek: return Color(red: 0.310, green: 0.427, blue: 0.478)
        case .siliconflow: return Color(red: 0.961, green: 0.424, blue: 0.424)
        case .openrouter: return Color(red: 0.545, green: 0.361, blue: 0.965)
        }
    }

    private var logoText: String {
        switch id {
        case .claude: return "✳"
        case .codex: return "◆"
        case .kimi: return "K"
        case .deepseek: return "D"
        case .siliconflow: return "S"
        case .openrouter: return "O"
        }
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(.secondary)
            .cornerRadius(5)
    }
}

struct ProviderStatus: View {
    let configured: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(configured ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(configured ? "已连接" : "未配置")
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct APIKeyInlineEditor: View {
    let provider: APIKeyProviderID
    @Binding var keyInput: String
    let errorText: String?
    let onSave: () -> Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(provider.name) API 密钥")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API 密钥", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("取消", action: onCancel)
            Button("保存") {
                _ = onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SiliconFlowProviderRow: View {
    let row: AccountRowState
    let consoleConfigured: Bool
    let onConnectConsole: () -> Void
    let onDisconnectConsole: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProviderLogo(id: .siliconflow)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .bold))
                    Tag(text: sourceLabel)
                }
                Text(row.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let balanceSummary = row.balanceSummary {
                Text(balanceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProviderStatus(configured: row.configured)

            HStack(spacing: 8) {
                if consoleConfigured {
                    Button("重新登录", action: onConnectConsole)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("登录控制台", action: onConnectConsole)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                if consoleConfigured {
                    Button("退出登录", action: onDisconnectConsole)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 78)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.04)),
            alignment: .bottom
        )
    }

    private var sourceLabel: String {
        "控制台登录"
    }
}

final class SiliconFlowWebViewHolder: ObservableObject {
    weak var webView: WKWebView?
}

struct SiliconFlowConsoleSessionSnapshot {
    let cookieHeader: String
    let subjectID: String
}

struct SiliconFlowConsoleLoginSheet: View {
    let onSave: (SiliconFlowConsoleSessionSnapshot) -> Void
    let onCancel: () -> Void
    @StateObject private var holder = SiliconFlowWebViewHolder()
    @State private var statusText = "登录 SiliconFlow 后保存当前会话。"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SiliconFlow 控制台")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel)
                Button("保存会话") {
                    saveCurrentSession()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)

            Divider()

            SiliconFlowConsoleWebView(holder: holder)
                .frame(width: 920, height: 640)
        }
    }

    private func saveCurrentSession() {
        let script = """
        (() => {
          const candidates = [];
          const valid = (value) => /^[A-Za-z0-9_-]{8,80}$/.test(String(value || "").trim());
          const push = (value) => {
            const trimmed = String(value || "").trim();
            if (valid(trimmed) && !candidates.includes(trimmed)) candidates.push(trimmed);
          };
          const visit = (value, seen = new Set(), trusted = false) => {
            if (!value || seen.has(value)) return;
            seen.add(value);
            if (typeof value === "string") {
              if (trusted) push(value);
              try {
                const url = new URL(value, location.href);
                push(url.searchParams.get("SubjectId") || url.searchParams.get("subjectId"));
              } catch {}
              return;
            }
            if (Array.isArray(value)) {
              value.forEach((item) => visit(item, seen, trusted));
              return;
            }
            if (typeof value === "object") {
              Object.entries(value).forEach(([key, nested]) => {
                if (/^subject_?id$/i.test(key)) push(nested);
                visit(nested, seen, trusted || /^subjectInfo$/i.test(key));
              });
            }
          };
          const collect = (value) => {
            try {
              const url = new URL(value, location.href);
              push(url.searchParams.get("SubjectId") || url.searchParams.get("subjectId"));
              const parts = url.pathname.split("/").filter(Boolean);
              const meIndex = parts.indexOf("me");
              if (meIndex >= 0) push(parts[meIndex + 1]);
            } catch {}
          };
          push(window.SF_SUBJECT_ID);
          try { push(window.subjectInfo && window.subjectInfo.subjectId); } catch {}
          collect(location.href);
          try { (window.__quotaWidgetSubjectCandidates || []).forEach((item) => visit(item)); } catch {}
          try {
            performance.getEntriesByType("resource").forEach((entry) => {
              collect(entry.name);
            });
          } catch {}
          document.querySelectorAll("a[href]").forEach((anchor) => collect(anchor.href));
          const scanStorage = (storage) => {
            Object.keys(storage).forEach((key) => {
              const raw = storage.getItem(key);
              visit(raw);
              try { visit(JSON.parse(raw)); } catch {}
            });
          };
          try { scanStorage(localStorage); } catch {}
          try { scanStorage(sessionStorage); } catch {}
          visit(window.__NEXT_DATA__);
          return candidates[0] || "";
        })()
        """
        holder.webView?.evaluateJavaScript(script) { value, _ in
            let subjectID = (value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                saveSession(cookies: cookies, subjectID: subjectID)
            }
        } ?? WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            saveSession(cookies: cookies, subjectID: "")
        }
    }

    private func saveSession(cookies: [HTTPCookie], subjectID: String) {
            let siliconFlowCookies = cookies.filter { cookie in
                let domain = cookie.domain.lowercased()
                return domain == "siliconflow.cn" || domain.hasSuffix(".siliconflow.cn")
            }
            let header = HTTPCookie.requestHeaderFields(with: siliconFlowCookies)["Cookie"] ?? ""
            DispatchQueue.main.async {
                if header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    statusText = "尚未找到 SiliconFlow 会话。"
                } else if !StoredSiliconFlowConsoleSession.isValidSubjectID(
                    subjectID.trimmingCharacters(in: .whitespacesAndNewlines)
                ) {
                    statusText = "尚未找到 SiliconFlow 账号 ID。"
                } else {
                    onSave(SiliconFlowConsoleSessionSnapshot(
                        cookieHeader: header,
                        subjectID: subjectID
                    ))
                }
            }
    }
}

struct SiliconFlowConsoleWebView: NSViewRepresentable {
    @ObservedObject var holder: SiliconFlowWebViewHolder

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(Self.subjectCaptureScript())
        let webView = WKWebView(frame: .zero, configuration: configuration)
        holder.webView = webView
        if let url = URL(string: "https://cloud.siliconflow.cn/me/expensebill?tab=balance") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private static func subjectCaptureScript() -> WKUserScript {
        let source = """
        (() => {
          if (window.__quotaWidgetSubjectCaptureInstalled) return;
          window.__quotaWidgetSubjectCaptureInstalled = true;
          window.__quotaWidgetSubjectCandidates = window.__quotaWidgetSubjectCandidates || [];
          const valid = (value) => /^[A-Za-z0-9_-]{8,80}$/.test(String(value || "").trim());
          const push = (value) => {
            const trimmed = String(value || "").trim();
            if (valid(trimmed) && !window.__quotaWidgetSubjectCandidates.includes(trimmed)) {
              window.__quotaWidgetSubjectCandidates.push(trimmed);
            }
          };
          const visit = (value, seen = new Set(), trusted = false) => {
            if (!value || seen.has(value)) return;
            seen.add(value);
            if (typeof value === "string") {
              try {
                const url = new URL(value, location.href);
                push(url.searchParams.get("SubjectId") || url.searchParams.get("subjectId"));
              } catch {
                if (trusted) push(value);
              }
              return;
            }
            if (Array.isArray(value)) {
              value.forEach((item) => visit(item, seen, trusted));
              return;
            }
            if (typeof value === "object") {
              Object.entries(value).forEach(([key, nested]) => {
                if (/^subject_?id$/i.test(key)) push(nested);
                visit(nested, seen, trusted || /^subjectInfo$/i.test(key));
              });
            }
          };
          const pushGlobals = () => {
            push(window.SF_SUBJECT_ID);
            try { push(window.subjectInfo && window.subjectInfo.subjectId); } catch {}
          };
          pushGlobals();
          setTimeout(pushGlobals, 500);
          const originalFetch = window.fetch;
          if (typeof originalFetch === "function") {
            window.fetch = function(...args) {
              visit(args[0]);
              return originalFetch.apply(this, args).then((response) => {
                try {
                  response.clone().json().then((json) => visit(json)).catch(() => {});
                } catch {}
                return response;
              });
            };
          }
          const originalOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url, ...rest) {
            visit(url);
            return originalOpen.call(this, method, url, ...rest);
          };
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}

// MARK: - Refresh Page

struct DisplayLayerActions {
    let installTouchBar: @Sendable () throws -> Void
    let openTouchBar: @Sendable () throws -> Void
}

#Preview("设置") {
    let viewModel = AccountSettingsViewModel(
        apiKeyStore: APIKeyStore(backend: InMemoryCredentialBackend()),
        configStore: AppConfigStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    )
    let displayStore = DisplayLayerStore()
    return ControlCenterView(
        accountViewModel: viewModel,
        displayStore: displayStore,
        refreshNow: {},
        displayActions: DisplayLayerActions(
            installTouchBar: {},
            openTouchBar: {}
        )
    )
    .frame(width: 900, height: 620)
}
