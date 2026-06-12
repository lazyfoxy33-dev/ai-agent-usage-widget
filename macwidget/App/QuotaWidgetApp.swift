import AppKit
import SwiftUI
import WidgetKit

@MainActor
final class QuotaWidgetModel: ObservableObject {
    @Published var status = "等待首次刷新"
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        status = "正在刷新…"
        Task.detached {
            do {
                let json = try UsageFetcher.fetch()
                try UsageStore().write(json)
                await MainActor.run {
                    WidgetCenter.shared.reloadAllTimelines()
                    self.status = "已刷新 \(Date().formatted(date: .omitted, time: .shortened))"
                }
            } catch {
                await MainActor.run {
                    self.status = "刷新失败 · 保留上次数据"
                }
            }
        }
    }
}

@main
struct QuotaWidgetApp: App {
    @StateObject private var model = QuotaWidgetModel()

    var body: some Scene {
        MenuBarExtra("QuotaWidget", systemImage: "gauge.with.dots.needle.67percent") {
            Text(model.status)
            Divider()
            Button("立即刷新") { model.refresh() }
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .onChange(of: model.status, initial: true) {
            if model.status == "等待首次刷新" { model.start() }
        }
    }
}
