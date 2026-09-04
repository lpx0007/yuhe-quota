import AppKit
import CoreText
import SwiftUI

enum AppSkin: String, CaseIterable, Identifiable {
    case mech
    case blush
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mech: "机甲"
        case .blush: "浪漫"
        case .apple: "苹果"
        }
    }
}

struct YuhePalette {
    var skin: AppSkin
    var void: Color
    var panelTop: Color
    var panelBottom: Color
    var line: Color
    var accent: Color
    var amber: Color
    var rose: Color
    var ink: Color
    var mute: Color
    var cardFill: Color
    var fieldFill: Color
    var buttonInk: Color
    var hatch: Bool
    var glow: Bool
    var titleKerning: CGFloat
    var strokeWidth: CGFloat
    var meterHeight: CGFloat
    var preferredScheme: ColorScheme?

    static let panelWidth: CGFloat = 396
    static let panelHeight: CGFloat = 640

    func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        switch skin {
        case .mech: Font.custom("Tektur", size: size).weight(weight)
        case .blush: Font.system(size: size, weight: weight, design: .serif)
        case .apple: Font.system(size: size, weight: weight)
        }
    }

    func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch skin {
        case .mech: Font.custom("Share Tech Mono", size: size)
        case .blush: Font.system(size: size, weight: weight, design: .rounded)
        case .apple: Font.system(size: size, weight: weight).monospacedDigit()
        }
    }

    func sectionTitle(_ raw: String) -> String {
        skin == .mech ? raw.uppercased() : raw
    }

    func accent(for id: ProviderID) -> Color {
        switch skin {
        case .mech:
            switch id {
            case .cursor: Color(red: 0.910, green: 0.957, blue: 1.0)
            case .codex: Color(red: 0.365, green: 1.0, blue: 0.604)
            case .claude: Color(red: 0.85, green: 0.55, blue: 0.38)
            case .kimi: Color(red: 0.45, green: 0.78, blue: 1.0)
            case .glm: Color(red: 0.35, green: 0.72, blue: 0.62)
            case .deepseek: Color(red: 0.290, green: 0.659, blue: 1.0)
            case .grok: Color(red: 0.949, green: 0.961, blue: 0.941)
            }
        case .blush:
            switch id {
            case .cursor: Color(red: 0.86, green: 0.52, blue: 0.62)
            case .codex: Color(red: 0.92, green: 0.48, blue: 0.58)
            case .claude: Color(red: 0.90, green: 0.62, blue: 0.46)
            case .kimi: Color(red: 0.78, green: 0.50, blue: 0.68)
            case .glm: Color(red: 0.84, green: 0.46, blue: 0.56)
            case .deepseek: Color(red: 0.72, green: 0.46, blue: 0.70)
            case .grok: Color(red: 0.80, green: 0.44, blue: 0.54)
            }
        case .apple:
            switch id {
            case .cursor: Color(nsColor: .labelColor)
            case .codex: Color(nsColor: .systemGreen)
            case .claude: Color(nsColor: .systemOrange)
            case .kimi: Color(nsColor: .systemBlue)
            case .glm: Color(nsColor: .systemTeal)
            case .deepseek: Color(nsColor: .systemBlue)
            case .grok: Color(nsColor: .labelColor)
            }
        }
    }

    func barColor(level: AlertLevel, brand: Color) -> Color {
        switch level {
        case .ok: brand
        case .warn, .stale: amber
        case .hot, .offline: rose
        }
    }

    func shape(_ kind: ThemeShape.Kind) -> ThemeShape {
        ThemeShape(skin: skin, kind: kind)
    }

    static func named(_ skin: AppSkin) -> YuhePalette {
        switch skin {
        case .mech: .mech
        case .blush: .blush
        case .apple: .apple
        }
    }

    static let mech = YuhePalette(
        skin: .mech,
        void: Color(red: 0.008, green: 0.016, blue: 0.039),
        panelTop: Color(red: 0.039, green: 0.094, blue: 0.149),
        panelBottom: Color(red: 0.016, green: 0.039, blue: 0.071),
        line: Color(red: 0.31, green: 1.0, blue: 0.82).opacity(0.18),
        accent: Color(red: 0.239, green: 1.0, blue: 0.824),
        amber: Color(red: 1.0, green: 0.690, blue: 0.125),
        rose: Color(red: 1.0, green: 0.239, blue: 0.431),
        ink: Color(red: 0.620, green: 0.910, blue: 0.839),
        mute: Color(red: 0.357, green: 0.486, blue: 0.455),
        cardFill: Color(red: 0.239, green: 1.0, blue: 0.824).opacity(0.04),
        fieldFill: Color.white.opacity(0.06),
        buttonInk: Color(red: 0.008, green: 0.016, blue: 0.039),
        hatch: true,
        glow: true,
        titleKerning: 2,
        strokeWidth: 1,
        meterHeight: 6,
        preferredScheme: .dark
    )

    static let blush = YuhePalette(
        skin: .blush,
        void: Color(red: 1.0, green: 0.98, blue: 0.97),
        panelTop: Color(red: 1.0, green: 0.965, blue: 0.945),
        panelBottom: Color(red: 0.988, green: 0.910, blue: 0.910),
        line: Color(red: 0.89, green: 0.62, blue: 0.68).opacity(0.42),
        accent: Color(red: 0.86, green: 0.40, blue: 0.54),
        amber: Color(red: 0.90, green: 0.55, blue: 0.36),
        rose: Color(red: 0.80, green: 0.26, blue: 0.40),
        ink: Color(red: 0.36, green: 0.22, blue: 0.26),
        mute: Color(red: 0.64, green: 0.50, blue: 0.54),
        cardFill: Color.white.opacity(0.62),
        fieldFill: Color.white.opacity(0.72),
        buttonInk: Color(red: 1.0, green: 0.98, blue: 0.97),
        hatch: false,
        glow: false,
        titleKerning: 0.4,
        strokeWidth: 1,
        meterHeight: 7,
        preferredScheme: .light
    )

    static let apple = YuhePalette(
        skin: .apple,
        void: Color(nsColor: .textBackgroundColor),
        panelTop: Color(nsColor: .windowBackgroundColor),
        panelBottom: Color(nsColor: .windowBackgroundColor),
        line: Color.primary.opacity(0.16),
        accent: Color.accentColor,
        amber: Color(nsColor: .systemOrange),
        rose: Color(nsColor: .systemRed),
        ink: Color.primary,
        mute: Color.secondary,
        cardFill: Color(nsColor: .controlBackgroundColor),
        fieldFill: Color(nsColor: .textBackgroundColor),
        buttonInk: .white,
        hatch: false,
        glow: false,
        titleKerning: 0,
        strokeWidth: 1,
        meterHeight: 5,
        preferredScheme: nil
    )
}

private struct YuhePaletteKey: EnvironmentKey {
    static let defaultValue = YuhePalette.mech
}

extension EnvironmentValues {
    var yuhe: YuhePalette {
        get { self[YuhePaletteKey.self] }
        set { self[YuhePaletteKey.self] = newValue }
    }
}

struct ThemeShape: Shape {
    enum Kind {
        case panel, card, chip, tick
    }

    var skin: AppSkin
    var kind: Kind = .card

    func path(in rect: CGRect) -> Path {
        switch skin {
        case .mech:
            let cut: CGFloat
            switch kind {
            case .panel: cut = 14
            case .card: cut = 8
            case .chip: cut = 4
            case .tick: cut = 2
            }
            return CardShape(cut: cut).path(in: rect)
        case .blush, .apple:
            let radius: CGFloat
            switch (skin, kind) {
            case (.blush, .panel): radius = 22
            case (.blush, .card): radius = 16
            case (.blush, .chip): radius = 10
            case (.blush, .tick): radius = 4
            case (.apple, .panel): radius = 16
            case (.apple, .card): radius = 10
            case (.apple, .chip): radius = 7
            case (.apple, .tick): radius = 3.5
            default: radius = 10
            }
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
    }
}

struct YuheChrome: ViewModifier {
    @Environment(\.yuhe) private var theme
    var fill: Color
    var stroke: Color
    var kind: ThemeShape.Kind

    func body(content: Content) -> some View {
        let shape = ThemeShape(skin: theme.skin, kind: kind)
        content
            .background(fill)
            .clipShape(shape)
            .overlay(shape.stroke(stroke, lineWidth: theme.strokeWidth))
    }
}

extension View {
    func yuheChrome(fill: Color, stroke: Color, kind: ThemeShape.Kind = .chip) -> some View {
        modifier(YuheChrome(fill: fill, stroke: stroke, kind: kind))
    }
}

enum YuheTheme {
    static let panelWidth: CGFloat = YuhePalette.panelWidth
    static let panelHeight: CGFloat = YuhePalette.panelHeight
}

enum FontLoader {
    static func register() {
        let names = ["ShareTechMono-Regular", "Tektur"]
        for name in names {
            for url in fontURLs(named: name) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    private static func fontURLs(named name: String) -> [URL] {
        var urls: [URL] = []
        if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") {
            urls.append(url)
        }
        let extra = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Fonts")
            .appendingPathComponent("\(name).ttf")
        if FileManager.default.fileExists(atPath: extra.path) {
            urls.append(extra)
        }
        return urls
    }
}

enum YuheFormat {
    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value.clamped(to: 0...999))
    }

    static func clock(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static func syncAgo(_ date: Date?) -> String {
        guard let date else { return "尚未同步" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "刚刚同步" }
        if s < 60 { return "同步于 \(s) 秒前" }
        if s < 3600 { return "同步于 \(s / 60) 分钟前" }
        return "同步于 \(s / 3600) 小时前"
    }

    static func resetDate(_ date: Date) -> String {
        dateTime.string(from: date)
    }

    static func countdown(until date: Date) -> String {
        let remain = date.timeIntervalSinceNow
        if remain <= 0 { return "已到期" }
        let total = Int(remain)
        if total < 24 * 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days >= 1 {
            return "\(days)天\(hours)小时"
        }
        if hours >= 1 {
            return minutes == 0 ? "\(hours)小时" : "\(hours)小时\(minutes)分"
        }
        return dateTime.string(from: date)
    }

    static func daysLeft(until date: Date) -> Int {
        max(0, Int((date.timeIntervalSinceNow / 86_400).rounded(.up)))
    }

    static func yuan(_ raw: String) -> String {
        guard let n = Double(raw) else { return "¥\(raw)" }
        return String(format: "¥%.2f", n)
    }

    static func usdFromCents(_ cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100.0)
    }

    static func usd(_ raw: String) -> String {
        guard let n = Double(raw) else { return "$\(raw)" }
        return String(format: "$%.2f", n)
    }

    static func planTag(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
