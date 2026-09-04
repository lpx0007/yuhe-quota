import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updater = AppUpdate.shared

    var body: some View {
        Group {
            if store.showSettings {
                SettingsView(store: store, settings: settings)
            } else {
                mainPanel
            }
        }
        .background(panelBackground)
        .frame(width: 368)
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(HUDShape())
        .overlay(HUDShape().stroke(YuheTheme.line, lineWidth: 1))
        .shadow(color: YuheTheme.cyan.opacity(0.12), radius: 24)
        .preferredColorScheme(.dark)
        .onChange(of: store.showSettings) { _, _ in }
        .task {
            await updater.check(quiet: true)
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(YuheTheme.line)
            VStack(spacing: 8) {
                if visibleSnapshots.isEmpty {
                    Text("设置里至少打开一家")
                        .font(.custom("Share Tech Mono", size: 11))
                        .foregroundStyle(YuheTheme.mute)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ForEach(visibleSnapshots) { snap in
                        ProviderCard(snapshot: snap, now: store.now)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 120, alignment: .top)
            Divider().overlay(YuheTheme.line)
            footer
        }
    }

    private var panelBackground: some View {
        LinearGradient(colors: [YuheTheme.panelTop, YuheTheme.panelBottom], startPoint: .top, endPoint: .bottom)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [YuheTheme.cyan.opacity(0.05), .clear, YuheTheme.cyan.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YUHE")
                    .font(.custom("Tektur", size: 15).weight(.semibold))
                    .foregroundStyle(YuheTheme.cyan)
                    .shadow(color: YuheTheme.cyan.opacity(0.45), radius: 8)
                    .kerning(4)
                Text("额度 HUD  //  NODE-07")
                    .font(.custom("Share Tech Mono", size: 10))
                    .foregroundStyle(YuheTheme.mute)
                    .kerning(1.6)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: dotColor, radius: 6)
                    Text(store.liveLabel.uppercased())
                        .font(.custom("Share Tech Mono", size: 9))
                        .foregroundStyle(YuheTheme.amber)
                        .kerning(1.8)
                }
                Text(YuheFormat.clock(store.now))
                    .font(.custom("Share Tech Mono", size: 11))
                    .foregroundStyle(YuheTheme.cyan)
                    .monospacedDigit()
                if updater.available, let latest = updater.latestVersion {
                    Text("可更新 \(latest)")
                        .font(.custom("Share Tech Mono", size: 9))
                        .foregroundStyle(YuheTheme.amber)
                } else {
                    Text(YuheFormat.syncAgo(store.lastSync))
                        .font(.custom("Share Tech Mono", size: 9))
                        .foregroundStyle(YuheTheme.mute)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var dotColor: Color {
        switch store.worstLevel {
        case .ok: YuheTheme.cyan
        case .warn, .stale: YuheTheme.amber
        case .hot, .offline: YuheTheme.rose
        }
    }

    private var footer: some View {
        HStack {
            Text(footerStatus)
                .font(.custom("Share Tech Mono", size: 10))
                .foregroundStyle(YuheTheme.mute)
                .kerning(1.4)
            Spacer()
            HStack(spacing: 14) {
                footerButton(store.isRefreshing ? "同步中" : "同步") {
                    Task { await store.refresh() }
                }
                footerButton("设置") { store.showSettings = true }
                footerButton("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var visibleSnapshots: [QuotaSnapshot] {
        settings.enabledProviders.map { store.snapshot(for: $0) }
    }

    private var footerStatus: String {
        let n = visibleSnapshots.count
        if store.isRefreshing { return "同步中 · \(n) 节点" }
        let failed = visibleSnapshots.filter { $0.error != nil }.count
        if failed > 0 { return "部分离线 · \(n - failed)/\(n) 在线" }
        return "系统正常 · \(n) 节点"
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Share Tech Mono", size: 10))
                .foregroundStyle(YuheTheme.cyan)
                .kerning(2)
                .shadow(color: YuheTheme.cyan.opacity(0.4), radius: 6)
        }
        .buttonStyle(.plain)
    }
}

struct ProviderCard: View {
    let snapshot: QuotaSnapshot
    let now: Date
    private var accent: Color { YuheTheme.accent(for: snapshot.provider) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 2)
                .shadow(color: accent, radius: 6)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.provider.displayName)
                        .font(.custom("Tektur", size: 12))
                        .foregroundStyle(Color(red: 0.84, green: 1, blue: 0.96))
                        .kerning(2.2)
                    if let plan = snapshot.plan {
                        Text(plan)
                            .font(.custom("Share Tech Mono", size: 9))
                            .foregroundStyle(YuheTheme.mute)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(YuheTheme.mute.opacity(0.45), lineWidth: 1))
                    }
                    if snapshot.error != nil {
                        Text("失效")
                            .font(.custom("Share Tech Mono", size: 9))
                            .foregroundStyle(YuheTheme.rose)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(YuheTheme.rose.opacity(0.7), lineWidth: 1))
                    } else if snapshot.warning != nil {
                        Text("超额")
                            .font(.custom("Share Tech Mono", size: 9))
                            .foregroundStyle(YuheTheme.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(YuheTheme.amber.opacity(0.7), lineWidth: 1))
                    }
                    Spacer()
                    Text(rightMeta)
                        .font(.custom("Share Tech Mono", size: 10))
                        .foregroundStyle(YuheTheme.mute)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let error = snapshot.error {
                    Text(error)
                        .font(.custom("Share Tech Mono", size: 11))
                        .foregroundStyle(YuheTheme.rose)
                } else if snapshot.windows.isEmpty, snapshot.headline == nil, snapshot.totals.isEmpty {
                    Text(snapshot.headlineSecondary ?? "等待同步")
                        .font(.custom("Share Tech Mono", size: 11))
                        .foregroundStyle(YuheTheme.mute)
                }
                if let warning = snapshot.warning {
                    Text(warning)
                        .font(.custom("Share Tech Mono", size: 10))
                        .foregroundStyle(YuheTheme.amber)
                }

                if let headline = snapshot.headline {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(headline)
                            .font(.custom("Share Tech Mono", size: 22))
                            .foregroundStyle(accent)
                            .shadow(color: accent.opacity(0.45), radius: 10)
                        if let secondary = snapshot.headlineSecondary {
                            Text(secondary)
                                .font(.custom("Share Tech Mono", size: 10))
                                .foregroundStyle(YuheTheme.mute)
                        }
                    }
                }

                ForEach(snapshot.windows) { window in
                    meter(
                        title: window.title,
                        percent: window.displayPercent,
                        trailing: uniqueWindowTrailing(window),
                        brand: accent,
                        level: window.level
                    )
                }
                ForEach(snapshot.products) { product in
                    meter(
                        title: product.name,
                        percent: product.displayPercent,
                        trailing: nil,
                        brand: accent,
                        level: product.level
                    )
                }

                if !snapshot.totals.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(snapshot.totals) { total in
                            HStack {
                                Text(total.label)
                                    .font(.custom("Share Tech Mono", size: 9))
                                    .foregroundStyle(YuheTheme.mute)
                                Spacer()
                                Text(total.value)
                                    .font(.custom("Share Tech Mono", size: 10))
                                    .foregroundStyle(YuheTheme.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            LinearGradient(
                colors: [accent.opacity(0.06), accent.opacity(0.015)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Rectangle().stroke(YuheTheme.cyan.opacity(0.12), lineWidth: 1))
    }

    private var rightMeta: String {
        if snapshot.isStale { return "过期缓存" }
        if let identity = snapshot.identity { return identity }
        if snapshot.provider == .deepseek { return snapshot.headlineSecondary ?? "" }
        if let first = snapshot.windows.first { return first.resetLabel }
        return ""
    }

    private func uniqueWindowTrailing(_ window: QuotaWindow) -> String? {
        guard let date = window.resetsAt else { return nil }
        let stamp = Int(date.timeIntervalSince1970)
        let same = snapshot.windows.filter { $0.resetsAt.map { Int($0.timeIntervalSince1970) } == stamp }.count
        if same > 1 { return nil }
        return YuheFormat.countdown(until: date)
    }

    private func meter(title: String, percent: Double, trailing: String?, brand: Color, level: AlertLevel) -> some View {
        let clamped = min(max(percent, 0), 100)
        let color = YuheTheme.barColor(level: level, brand: brand)
        return VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.custom("Share Tech Mono", size: 10))
                    .foregroundStyle(YuheTheme.mute)
                Spacer()
                Text(YuheFormat.percent(percent))
                    .font(.custom("Share Tech Mono", size: 11))
                    .foregroundStyle(YuheTheme.ink)
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.05))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.55), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: max(0.02, clamped / 100), y: 1, anchor: .leading)
                    .shadow(color: color.opacity(0.7), radius: 5)
                HatchOverlay()
            }
            .frame(height: 6)
            .clipped()
            if let trailing, !trailing.isEmpty {
                HStack {
                    Spacer()
                    Text(trailing)
                        .font(.custom("Share Tech Mono", size: 9))
                        .foregroundStyle(YuheTheme.mute)
                }
            }
        }
    }
}

private struct HatchOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                let rect = CGRect(x: x + 7, y: 0, width: 1, height: size.height)
                ctx.fill(Path(rect), with: .color(.black.opacity(0.28)))
                x += 8
            }
        }
        .allowsHitTesting(false)
    }
}

struct HUDShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c: CGFloat = 14
        p.move(to: CGPoint(x: c, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: c, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: 0, y: c))
        p.closeSubpath()
        return p
    }
}
