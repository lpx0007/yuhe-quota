import AppKit
import SwiftUI

struct HUDView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updater = AppUpdate.shared

    private var theme: YuhePalette { settings.palette }

    var body: some View {
        Group {
            if store.showSettings {
                SettingsView(store: store, settings: settings)
            } else {
                mainPanel
            }
        }
        .padding(14)
        .background(panelBackground)
        .frame(width: YuhePalette.panelWidth, height: YuhePalette.panelHeight)
        .clipShape(theme.shape(.panel))
        .overlay(theme.shape(.panel).stroke(theme.line, lineWidth: theme.skin == .apple ? 1.2 : theme.strokeWidth))
        .shadow(color: theme.glow ? theme.accent.opacity(0.12) : Color.black.opacity(theme.skin == .blush ? 0.08 : 0.22), radius: theme.skin == .apple ? 12 : 24)
        .environment(\.yuhe, theme)
        .preferredColorScheme(theme.preferredScheme)
        .task {
            await updater.check(quiet: true)
        }
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.line)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: theme.skin == .apple ? 10 : 8) {
                    if visibleSnapshots.isEmpty {
                        Text("设置里至少打开一家")
                            .font(theme.mono(11))
                            .foregroundStyle(theme.mute)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ForEach(visibleSnapshots) { snap in
                            ProviderCard(snapshot: snap, now: store.now)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Divider().overlay(theme.line)
            footer
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        switch theme.skin {
        case .mech:
            LinearGradient(colors: [theme.panelTop, theme.panelBottom], startPoint: .top, endPoint: .bottom)
                .overlay(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.05), .clear, theme.accent.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .blush:
            LinearGradient(colors: [theme.panelTop, theme.panelBottom], startPoint: .top, endPoint: .bottom)
                .overlay(
                    RadialGradient(
                        colors: [theme.accent.opacity(0.14), .clear],
                        center: .topTrailing,
                        startRadius: 8,
                        endRadius: 220
                    )
                )
        case .apple:
            Rectangle().fill(theme.panelTop)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.skin == .blush ? "Yuhe" : "YUHE")
                    .font(theme.display(theme.skin == .apple ? 17 : 15))
                    .foregroundStyle(theme.accent)
                    .shadow(color: theme.glow ? theme.accent.opacity(0.45) : .clear, radius: 8)
                    .kerning(theme.skin == .mech ? 4 : theme.titleKerning)
                Text(headerSubtitle)
                    .font(theme.mono(10))
                    .foregroundStyle(theme.mute)
                    .kerning(theme.skin == .mech ? 1.6 : 0)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: theme.glow ? dotColor : .clear, radius: 6)
                    Text(statusLabel)
                        .font(theme.mono(9))
                        .foregroundStyle(theme.amber)
                        .kerning(theme.skin == .mech ? 1.8 : 0)
                }
                Text(YuheFormat.clock(store.now))
                    .font(theme.mono(11))
                    .foregroundStyle(theme.accent)
                    .monospacedDigit()
                if updater.available, let latest = updater.latestVersion {
                    Text("可更新 \(latest)")
                        .font(theme.mono(9))
                        .foregroundStyle(theme.amber)
                } else {
                    Text(YuheFormat.syncAgo(store.lastSync))
                        .font(theme.mono(9))
                        .foregroundStyle(theme.mute)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var headerSubtitle: String {
        switch theme.skin {
        case .mech: "额度 HUD  //  NODE-07"
        case .blush: "额度小窗"
        case .apple: "用量"
        }
    }

    private var statusLabel: String {
        theme.skin == .mech ? store.liveLabel.uppercased() : store.liveLabel
    }

    private var dotColor: Color {
        switch store.worstLevel {
        case .ok: theme.accent
        case .warn, .stale: theme.amber
        case .hot, .offline: theme.rose
        }
    }

    private var footer: some View {
        HStack {
            Text(footerStatus)
                .font(theme.mono(10))
                .foregroundStyle(theme.mute)
                .kerning(theme.skin == .mech ? 1.4 : 0)
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
                .font(theme.mono(10, weight: theme.skin == .apple ? .medium : .regular))
                .foregroundStyle(theme.accent)
                .kerning(theme.skin == .mech ? 2 : 0)
                .shadow(color: theme.glow ? theme.accent.opacity(0.4) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

struct ProviderCard: View {
    @Environment(\.yuhe) private var theme
    let snapshot: QuotaSnapshot
    let now: Date
    private var brand: Color { theme.accent(for: snapshot.provider) }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(brand)
                .frame(width: theme.skin == .apple ? 3 : 2)
                .shadow(color: theme.glow ? brand : .clear, radius: 6)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.provider.displayName)
                        .font(theme.display(12, weight: theme.skin == .apple ? .semibold : .semibold))
                        .foregroundStyle(titleColor)
                        .kerning(theme.skin == .mech ? 2.2 : 0)
                    if let plan = snapshot.plan {
                        tag(plan, color: theme.mute)
                    }
                    if snapshot.error != nil {
                        tag("失效", color: theme.rose)
                    } else if snapshot.warning != nil {
                        tag("超额", color: theme.amber)
                    }
                    Spacer()
                    Text(rightMeta)
                        .font(theme.mono(10))
                        .foregroundStyle(theme.mute)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let error = snapshot.error {
                    Text(error)
                        .font(theme.mono(11))
                        .foregroundStyle(theme.rose)
                } else if snapshot.windows.isEmpty, snapshot.headline == nil, snapshot.totals.isEmpty {
                    Text(snapshot.headlineSecondary ?? "等待同步")
                        .font(theme.mono(11))
                        .foregroundStyle(theme.mute)
                }
                if let warning = snapshot.warning {
                    Text(warning)
                        .font(theme.mono(10))
                        .foregroundStyle(theme.amber)
                }

                if let headline = snapshot.headline {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(headline)
                            .font(theme.mono(22, weight: theme.skin == .apple ? .semibold : .regular))
                            .foregroundStyle(brand)
                            .shadow(color: theme.glow ? brand.opacity(0.45) : .clear, radius: 10)
                        if let secondary = snapshot.headlineSecondary {
                            Text(secondary)
                                .font(theme.mono(10))
                                .foregroundStyle(theme.mute)
                        }
                    }
                }

                ForEach(snapshot.windows) { window in
                    meter(
                        title: window.title,
                        percent: window.displayPercent,
                        trailing: uniqueWindowTrailing(window),
                        brand: brand,
                        level: window.level
                    )
                }
                ForEach(snapshot.products) { product in
                    meter(
                        title: product.name,
                        percent: product.displayPercent,
                        trailing: nil,
                        brand: brand,
                        level: product.level
                    )
                }

                if !snapshot.totals.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(snapshot.totals) { total in
                            HStack {
                                Text(total.label)
                                    .font(theme.mono(9))
                                    .foregroundStyle(theme.mute)
                                Spacer()
                                Text(total.value)
                                    .font(theme.mono(10))
                                    .foregroundStyle(theme.ink)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(cardBackground)
        .clipShape(theme.shape(.card))
        .overlay(theme.shape(.card).stroke(cardStroke, lineWidth: theme.strokeWidth))
        .shadow(color: theme.skin == .blush ? theme.accent.opacity(0.08) : .clear, radius: 10, y: 2)
    }

    private var titleColor: Color {
        switch theme.skin {
        case .mech: Color(red: 0.84, green: 1, blue: 0.96)
        case .blush, .apple: theme.ink
        }
    }

    private var cardStroke: Color {
        switch theme.skin {
        case .mech: theme.accent.opacity(0.18)
        case .blush: theme.line
        case .apple: theme.line.opacity(0.7)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch theme.skin {
        case .mech:
            LinearGradient(
                colors: [brand.opacity(0.06), brand.opacity(0.015)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .blush:
            LinearGradient(
                colors: [Color.white.opacity(0.86), brand.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .apple:
            theme.cardFill
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(theme.mono(9))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(theme.shape(.chip).stroke(color.opacity(0.55), lineWidth: theme.strokeWidth))
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
        let color = theme.barColor(level: level, brand: brand)
        return VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(theme.mono(10))
                    .foregroundStyle(theme.mute)
                Spacer()
                Text(YuheFormat.percent(percent))
                    .font(theme.mono(11))
                    .foregroundStyle(theme.ink)
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.skin == .blush ? Color.white.opacity(0.55) : Color.primary.opacity(theme.skin == .apple ? 0.08 : 0.05))
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: theme.glow ? [color.opacity(0.55), color] : [color.opacity(0.78), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: max(0.02, clamped / 100), y: 1, anchor: .leading)
                    .shadow(color: theme.glow ? color.opacity(0.7) : .clear, radius: 5)
                if theme.hatch {
                    HatchOverlay()
                }
            }
            .frame(height: theme.meterHeight)
            .clipShape(theme.shape(.chip))
            .clipped()
            if let trailing, !trailing.isEmpty {
                HStack {
                    Spacer()
                    Text(trailing)
                        .font(theme.mono(9))
                        .foregroundStyle(theme.mute)
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
    var skin: AppSkin = .mech
    func path(in rect: CGRect) -> Path { ThemeShape(skin: skin, kind: .panel).path(in: rect) }
}

struct CardShape: Shape {
    var cut: CGFloat = 8
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = min(cut, min(rect.width, rect.height) / 4)
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
