import Foundation
import Security

struct ClaudeProvider: QuotaProvider {
    let id: ProviderID = .claude

    func fetch() async -> QuotaSnapshot {
        do {
            var creds = try ClaudeAuth.load()
            if ClaudeAuth.shouldRefresh(creds), let refreshed = try? await ClaudeAuth.refresh(creds) {
                creds = refreshed
            }
            var snapshot = try await request(creds)
            if snapshot.error != nil, let refreshed = try? await ClaudeAuth.refresh(creds) {
                snapshot = try await request(refreshed)
            }
            return snapshot
        } catch {
            return .failed(.claude, message: error.localizedDescription)
        }
    }

    private func request(_ creds: ClaudeAuth.Credentials) async throws -> QuotaSnapshot {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let response = try await HTTPClient.get(url, headers: [
            "Authorization": "Bearer \(creds.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
            "User-Agent": "claude-code/2.1.69",
        ])
        if response.status == 401 || response.status == 403 {
            return .failed(.claude, message: "Claude 会话过期，请执行 claude 登录")
        }
        guard response.status == 200, let json = JSONValue.object(response.data) else {
            return .failed(.claude, message: "Claude 接口返回 HTTP \(response.status)")
        }
        return map(json)
    }

    private func map(_ json: [String: Any]) -> QuotaSnapshot {
        var windows: [QuotaWindow] = []
        if let five = JSONValue.dict(json["five_hour"]) {
            windows.append(window(id: "5h", title: "5小时额度", dict: five, remainingStyle: true))
        }
        if let week = JSONValue.dict(json["seven_day"]) {
            windows.append(window(id: "week", title: "周额度", dict: week, remainingStyle: true))
        }
        if let sonnet = JSONValue.dict(json["seven_day_sonnet"]) {
            windows.append(window(id: "sonnet", title: "Sonnet 周额度", dict: sonnet, remainingStyle: true))
        }
        if let opus = JSONValue.dict(json["seven_day_opus"]) {
            windows.append(window(id: "opus", title: "Opus 周额度", dict: opus, remainingStyle: true))
        }

        var totals: [QuotaTotal] = []
        if let extra = JSONValue.dict(json["extra_usage"]) {
            if let used = JSONValue.double(extra["used"]), let limit = JSONValue.double(extra["limit"]), limit > 0 {
                totals.append(QuotaTotal(id: "extra", label: "额外用量", value: String(format: "$%.2f / $%.2f", used, limit)))
            }
        }
        let plan = JSONValue.string(json["subscriptionType"]) ?? JSONValue.string(json["rate_limit_tier"])
        if windows.isEmpty {
            return .failed(.claude, message: "未返回额度窗口")
        }
        return QuotaSnapshot(
            id: .claude,
            plan: YuheFormat.planTag(plan),
            identity: nil,
            available: true,
            headline: nil,
            headlineSecondary: nil,
            windows: windows,
            products: [],
            totals: totals,
            fetchedAt: Date(),
            error: nil,
            warning: nil,
            isStale: false
        )
    }

    private func window(id: String, title: String, dict: [String: Any], remainingStyle: Bool) -> QuotaWindow {
        let used = JSONValue.double(dict["utilization"]) ?? JSONValue.double(dict["percent"]) ?? 0
        let percent = used <= 1 ? used * 100 : used
        let reset = parseReset(dict["resets_at"] ?? dict["resetsAt"])
        return QuotaWindow(
            id: id,
            title: title,
            usedPercent: percent,
            resetsAt: reset,
            resetLabel: reset.map { "重置 \(YuheFormat.resetDate($0))" } ?? "",
            showRemaining: remainingStyle
        )
    }

    private func parseReset(_ any: Any?) -> Date? {
        if let s = JSONValue.string(any) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: s)
        }
        if let n = JSONValue.double(any) {
            return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
        }
        return nil
    }
}

enum ClaudeAuth {
    struct Credentials {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
    }

    static func load() throws -> Credentials {
        if let json = readKeychainJSON() ?? readFileJSON() {
            let oauth = JSONValue.dict(json["claudeAiOauth"]) ?? json
            guard let access = JSONValue.string(oauth["accessToken"]) ?? JSONValue.string(oauth["access_token"]),
                  !access.isEmpty else {
                throw ClaudeAuthError.missing
            }
            let scopes = JSONValue.array(oauth["scopes"])?.compactMap { JSONValue.string($0) } ?? []
            if !scopes.isEmpty, !scopes.contains(where: { $0.contains("user:profile") }) {
                throw ClaudeAuthError.scope
            }
            let exp: Date?
            if let ms = JSONValue.double(oauth["expiresAt"]) {
                exp = Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000 : ms)
            } else {
                exp = nil
            }
            return Credentials(
                accessToken: access,
                refreshToken: JSONValue.string(oauth["refreshToken"]) ?? JSONValue.string(oauth["refresh_token"]),
                expiresAt: exp
            )
        }
        throw ClaudeAuthError.missing
    }

    static func shouldRefresh(_ creds: Credentials) -> Bool {
        guard creds.refreshToken != nil else { return false }
        if let exp = creds.expiresAt { return exp.timeIntervalSinceNow < 5 * 60 }
        return false
    }

    static func refresh(_ creds: Credentials) async throws -> Credentials {
        guard let refresh = creds.refreshToken, !refresh.isEmpty else { throw ClaudeAuthError.expired }
        let url = URL(string: "https://platform.claude.com/v1/oauth/token")!
        let response = try await HTTPClient.postJSON(url, body: [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload",
        ])
        guard response.status == 200, let json = JSONValue.object(response.data),
              let access = JSONValue.string(json["access_token"]) else {
            throw ClaudeAuthError.expired
        }
        var next = creds
        next.accessToken = access
        if let r = JSONValue.string(json["refresh_token"]) { next.refreshToken = r }
        if let sec = JSONValue.double(json["expires_in"]) {
            next.expiresAt = Date().addingTimeInterval(sec)
        }
        return next
    }

    private static func readFileJSON() -> [String: Any]? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [home.appendingPathComponent(".claude/.credentials.json")]
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            paths.insert(URL(fileURLWithPath: dir).appendingPathComponent(".credentials.json"), at: 0)
        }
        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            if let data = try? Data(contentsOf: path), let json = JSONValue.object(data) {
                return json
            }
        }
        return nil
    }

    private static func readKeychainJSON() -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let json = JSONValue.object(data) else {
            return nil
        }
        return json
    }
}

enum ClaudeAuthError: LocalizedError {
    case missing, scope, expired
    var errorDescription: String? {
        switch self {
        case .missing: "未找到 Claude Code 登录，请先在终端执行 claude 并完成登录"
        case .scope: "当前 Claude 令牌没有额度权限，请重新登录 Claude Code"
        case .expired: "Claude 令牌已过期，请重新登录"
        }
    }
}
