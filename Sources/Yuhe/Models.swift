import Foundation

enum ProviderID: String, CaseIterable, Identifiable, Codable {
    case cursor
    case codex
    case claude
    case kimi
    case glm
    case deepseek
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: "CURSOR"
        case .codex: "CODEX"
        case .claude: "CLAUDE"
        case .kimi: "KIMI"
        case .glm: "GLM"
        case .deepseek: "DEEPSEEK"
        case .grok: "GROK"
        }
    }
}

enum AlertLevel: Int, Comparable {
    case ok = 0
    case warn = 1
    case hot = 2
    case stale = 3
    case offline = 4

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    static func from(percent: Double) -> AlertLevel {
        if percent >= 90 { return .hot }
        if percent >= 70 { return .warn }
        return .ok
    }
}

struct QuotaWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let resetLabel: String
    /// 条和数字按剩余展示时为 true（Codex 套餐窗口）。
    var showRemaining: Bool = false

    var displayPercent: Double {
        showRemaining ? max(0, 100 - usedPercent) : usedPercent
    }

    var level: AlertLevel { .from(percent: usedPercent) }
}

struct QuotaTotal: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}

struct QuotaProduct: Identifiable, Equatable {
    let id: String
    let name: String
    let usedPercent: Double
    var showRemaining: Bool = false

    var displayPercent: Double {
        showRemaining ? max(0, 100 - usedPercent) : usedPercent
    }

    var level: AlertLevel { .from(percent: usedPercent) }
}

struct QuotaSnapshot: Identifiable, Equatable {
    let id: ProviderID
    var provider: ProviderID { id }
    var plan: String?
    var identity: String?
    var available: Bool?
    var headline: String?
    var headlineSecondary: String?
    var windows: [QuotaWindow]
    var products: [QuotaProduct]
    var totals: [QuotaTotal]
    var fetchedAt: Date
    var error: String?
    var warning: String?
    var isStale: Bool

    var peakPercent: Double {
        let w = windows.map(\.usedPercent)
        let p = products.map(\.usedPercent)
        return (w + p).max() ?? 0
    }

    var level: AlertLevel {
        if error != nil { return .offline }
        if isStale { return .stale }
        if let available, available == false { return .hot }
        if let headline, headline.contains("¥0.00") || headline == "$0.00" { return .hot }
        return .from(percent: peakPercent)
    }

    static func pending(_ provider: ProviderID) -> QuotaSnapshot {
        QuotaSnapshot(
            id: provider,
            plan: nil,
            identity: nil,
            available: nil,
            headline: nil,
            headlineSecondary: "等待同步",
            windows: [],
            products: [],
            totals: [],
            fetchedAt: Date.distantPast,
            error: nil,
            warning: nil,
            isStale: false
        )
    }

    static func failed(_ provider: ProviderID, message: String, at date: Date = Date()) -> QuotaSnapshot {
        QuotaSnapshot(
            id: provider,
            plan: nil,
            identity: nil,
            available: nil,
            headline: nil,
            headlineSecondary: nil,
            windows: [],
            products: [],
            totals: [],
            fetchedAt: date,
            error: message,
            warning: nil,
            isStale: false
        )
    }
}

protocol QuotaProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> QuotaSnapshot
}
