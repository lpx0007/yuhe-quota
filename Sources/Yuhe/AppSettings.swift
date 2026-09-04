import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var cursorEnabled: Bool { didSet { defaults.set(cursorEnabled, forKey: Keys.cursor) } }
    @Published var codexEnabled: Bool { didSet { defaults.set(codexEnabled, forKey: Keys.codex) } }
    @Published var deepseekEnabled: Bool { didSet { defaults.set(deepseekEnabled, forKey: Keys.deepseek) } }
    @Published var grokEnabled: Bool { didSet { defaults.set(grokEnabled, forKey: Keys.grok) } }
    @Published var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: Keys.refresh) } }
    @Published var notify80: Bool { didSet { defaults.set(notify80, forKey: Keys.n80) } }
    @Published var notify90: Bool { didSet { defaults.set(notify90, forKey: Keys.n90) } }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.login)
            Self.applyLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var deepseekKeyDraft: String = ""

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let cursor = "yuhe.cursor.enabled"
        static let codex = "yuhe.codex.enabled"
        static let deepseek = "yuhe.deepseek.enabled"
        static let grok = "yuhe.grok.enabled"
        static let refresh = "yuhe.refresh.minutes"
        static let n80 = "yuhe.notify.80"
        static let n90 = "yuhe.notify.90"
        static let login = "yuhe.launch.at.login"
    }

    var enabledProviders: [ProviderID] {
        var ids: [ProviderID] = []
        if cursorEnabled { ids.append(.cursor) }
        if codexEnabled { ids.append(.codex) }
        if deepseekEnabled { ids.append(.deepseek) }
        if grokEnabled { ids.append(.grok) }
        return ids
    }

    private init() {
        let d = UserDefaults.standard
        cursorEnabled = d.object(forKey: Keys.cursor) as? Bool ?? true
        codexEnabled = d.object(forKey: Keys.codex) as? Bool ?? true
        deepseekEnabled = d.object(forKey: Keys.deepseek) as? Bool ?? true
        grokEnabled = d.object(forKey: Keys.grok) as? Bool ?? true
        let minutes = d.object(forKey: Keys.refresh) as? Int ?? 5
        refreshMinutes = [1, 2, 5, 15].contains(minutes) ? minutes : 5
        notify80 = d.object(forKey: Keys.n80) as? Bool ?? true
        notify90 = d.object(forKey: Keys.n90) as? Bool ?? true
        launchAtLogin = d.object(forKey: Keys.login) as? Bool ?? false
        deepseekKeyDraft = KeychainStore.loadDeepSeekKey() ?? ""
    }

    func saveDeepSeekKey() {
        let trimmed = deepseekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.deleteDeepSeekKey()
        } else {
            KeychainStore.saveDeepSeekKey(trimmed)
        }
    }

    func isEnabled(_ id: ProviderID) -> Bool {
        switch id {
        case .cursor: cursorEnabled
        case .codex: codexEnabled
        case .deepseek: deepseekEnabled
        case .grok: grokEnabled
        }
    }

    private static func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Yuhe launch-at-login: \(error.localizedDescription)")
            }
        }
    }
}
