import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderID: QuotaSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSync: Date?
    @Published var showSettings = false
    @Published var now = Date()

    private var timer: Timer?
    private var clock: Timer?
    private var notified: Set<String> = []

    var ordered: [QuotaSnapshot] {
        AppSettings.shared.enabledProviders.map { snapshot(for: $0) }
    }

    func snapshot(for id: ProviderID) -> QuotaSnapshot {
        snapshots[id] ?? .pending(id)
    }

    var worstLevel: AlertLevel {
        ordered.map(\.level).max() ?? .offline
    }

    var liveLabel: String {
        if isRefreshing { return "同步中" }
        if ordered.contains(where: { $0.error != nil && $0.fetchedAt != Date.distantPast }) {
            return "部分离线"
        }
        if ordered.contains(where: { $0.isStale }) { return "数据过期" }
        return "链路在线"
    }

    init() {
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        if let clock { RunLoop.main.add(clock, forMode: .common) }
        rebuildTimer()
    }

    func rebuildTimer() {
        timer?.invalidate()
        let minutes = AppSettings.shared.refreshMinutes
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers: [any QuotaProvider] = AppSettings.shared.enabledProviders.map { id in
            switch id {
            case .cursor: CursorProvider()
            case .codex: CodexProvider()
            case .deepseek: DeepSeekProvider()
            case .grok: GrokProvider()
            }
        }

        await withTaskGroup(of: QuotaSnapshot.self) { group in
            for provider in providers {
                group.addTask { await provider.fetch() }
            }
            for await snap in group {
                merge(snap)
            }
        }
        lastSync = Date()
        evaluateNotifications()
    }

    private func merge(_ incoming: QuotaSnapshot) {
        if incoming.error != nil, let old = snapshots[incoming.id], old.error == nil {
            var stale = old
            stale.isStale = true
            snapshots[incoming.id] = stale
            return
        }
        snapshots[incoming.id] = incoming
    }

    private func evaluateNotifications() {
        let settings = AppSettings.shared
        for snap in ordered {
            for window in snap.windows {
                maybeNotify(snap: snap, title: window.title, percent: window.usedPercent, settings: settings)
            }
            for product in snap.products {
                maybeNotify(snap: snap, title: product.name, percent: product.usedPercent, settings: settings)
            }
        }
    }

    private func maybeNotify(snap: QuotaSnapshot, title: String, percent: Double, settings: AppSettings) {
        let key90 = "\(snap.id.rawValue)-\(title)-90"
        let key80 = "\(snap.id.rawValue)-\(title)-80"
        if settings.notify90, percent >= 90, !notified.contains(key90) {
            notified.insert(key90)
            notify("\(snap.provider.displayName) \(title) 已用 \(YuheFormat.percent(percent))", body: "额度即将用尽")
        } else if settings.notify80, percent >= 80, percent < 90, !notified.contains(key80) {
            notified.insert(key80)
            notify("\(snap.provider.displayName) \(title) 已用 \(YuheFormat.percent(percent))", body: "额度预警")
        }
        if percent < 80 {
            notified.remove(key80)
            notified.remove(key90)
        } else if percent < 90 {
            notified.remove(key90)
        }
    }

    private func notify(_ title: String, body: String) {
        Task { await NotificationPresenter.post(title: title, body: body) }
    }
}
