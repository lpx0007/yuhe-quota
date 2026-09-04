import AppKit
import CoreText
import SwiftUI

enum YuheTheme {
    static let void = Color(red: 0.008, green: 0.016, blue: 0.039)
    static let panelTop = Color(red: 0.039, green: 0.094, blue: 0.149)
    static let panelBottom = Color(red: 0.016, green: 0.039, blue: 0.071)
    static let line = Color(red: 0.31, green: 1.0, blue: 0.82).opacity(0.18)
    static let cyan = Color(red: 0.239, green: 1.0, blue: 0.824)
    static let amber = Color(red: 1.0, green: 0.690, blue: 0.125)
    static let rose = Color(red: 1.0, green: 0.239, blue: 0.431)
    static let ink = Color(red: 0.620, green: 0.910, blue: 0.839)
    static let mute = Color(red: 0.357, green: 0.486, blue: 0.455)

    static func accent(for id: ProviderID) -> Color {
        switch id {
        case .cursor: Color(red: 0.910, green: 0.957, blue: 1.0)
        case .codex: Color(red: 0.365, green: 1.0, blue: 0.604)
        case .deepseek: Color(red: 0.290, green: 0.659, blue: 1.0)
        case .grok: Color(red: 0.949, green: 0.961, blue: 0.941)
        }
    }

    static func barColor(level: AlertLevel, brand: Color) -> Color {
        switch level {
        case .ok: brand
        case .warn, .stale: amber
        case .hot, .offline: rose
        }
    }

    static var displayFont: Font { Font.custom("Tektur", size: 15) }
    static var mono: Font { Font.custom("Share Tech Mono", size: 11) }
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
