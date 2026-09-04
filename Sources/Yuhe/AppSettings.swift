import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var cursorEnabled: Bool { didSet { defaults.set(cursorEnabled, forKey: Keys.cursor) } }
    @Published var codexEnabled: Bool { didSet { defaults.set(codexEnabled, forKey: Keys.codex) } }
    @Published var claudeEnabled: Bool { didSet { defaults.set(claudeEnabled, forKey: Keys.claude) } }
    @Published var kimiEnabled: Bool { didSet { defaults.set(kimiEnabled, forKey: Keys.kimi) } }
    @Published var glmEnabled: Bool { didSet { defaults.set(glmEnabled, forKey: Keys.glm) } }
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
    @Published var glmKeyDraft: String = ""
    @Published var providerOrder: [ProviderID] {
        didSet { defaults.set(providerOrder.map(\.rawValue), forKey: Keys.order) }
    }
    @Published var skin: AppSkin {
        didSet { defaults.set(skin.rawValue, forKey: Keys.skin) }
    }

    var palette: YuhePalette { YuhePalette.named(skin) }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let cursor = "yuhe.cursor.enabled"
        static let codex = "yuhe.codex.enabled"
        static let claude = "yuhe.claude.enabled"
        static let kimi = "yuhe.kimi.enabled"
        static let glm = "yuhe.glm.enabled"
        static let deepseek = "yuhe.deepseek.enabled"
        static let grok = "yuhe.grok.enabled"
        static let refresh = "yuhe.refresh.minutes"
        static let n80 = "yuhe.notify.80"
        static let n90 = "yuhe.notify.90"
        static let login = "yuhe.launch.at.login"
        static let order = "yuhe.provider.order"
        static let skin = "yuhe.skin"
    }

    var enabledProviders: [ProviderID] {
        providerOrder.filter { isOn($0) }
    }

    func isOn(_ id: ProviderID) -> Bool {
        switch id {
        case .cursor: cursorEnabled
        case .codex: codexEnabled
        case .claude: claudeEnabled
        case .kimi: kimiEnabled
        case .glm: glmEnabled
        case .deepseek: deepseekEnabled
        case .grok: grokEnabled
        }
    }

    func moveProvider(id: ProviderID, up: Bool) {
        guard let idx = providerOrder.firstIndex(of: id) else { return }
        let target = up ? idx - 1 : idx + 1
        guard providerOrder.indices.contains(target) else { return }
        providerOrder.swapAt(idx, target)
    }

    private init() {
        let d = UserDefaults.standard
        cursorEnabled = d.object(forKey: Keys.cursor) as? Bool ?? true
        codexEnabled = d.object(forKey: Keys.codex) as? Bool ?? true
        claudeEnabled = d.object(forKey: Keys.claude) as? Bool ?? false
        kimiEnabled = d.object(forKey: Keys.kimi) as? Bool ?? true
        glmEnabled = d.object(forKey: Keys.glm) as? Bool ?? false
        deepseekEnabled = d.object(forKey: Keys.deepseek) as? Bool ?? true
        grokEnabled = d.object(forKey: Keys.grok) as? Bool ?? true
        let minutes = d.object(forKey: Keys.refresh) as? Int ?? 5
        refreshMinutes = [1, 2, 5, 15].contains(minutes) ? minutes : 5
        notify80 = d.object(forKey: Keys.n80) as? Bool ?? true
        notify90 = d.object(forKey: Keys.n90) as? Bool ?? true
        launchAtLogin = d.object(forKey: Keys.login) as? Bool ?? false
        deepseekKeyDraft = KeychainStore.loadDeepSeekKey() ?? ""
        glmKeyDraft = KeychainStore.loadGLMKey() ?? ProcessInfo.processInfo.environment["ZHIPU_API_KEY"] ?? ProcessInfo.processInfo.environment["GLM_API_KEY"] ?? ""
        let saved = d.stringArray(forKey: Keys.order) ?? []
        var order = saved.compactMap(ProviderID.init(rawValue:))
        for id in ProviderID.allCases where !order.contains(id) { order.append(id) }
        providerOrder = order
        skin = AppSkin(rawValue: d.string(forKey: Keys.skin) ?? "") ?? .mech
    }

    func saveDeepSeekKey() {
        let trimmed = deepseekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.deleteDeepSeekKey()
        } else {
            KeychainStore.saveDeepSeekKey(trimmed)
        }
    }

    func saveGLMKey() {
        let trimmed = glmKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.deleteSecret(account: "glm.api-key", fileName: "glm.key")
        } else {
            KeychainStore.saveSecret(trimmed, account: "glm.api-key", fileName: "glm.key")
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
