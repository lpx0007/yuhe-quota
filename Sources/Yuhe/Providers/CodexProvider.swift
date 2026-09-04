import Foundation

struct CodexProvider: QuotaProvider {
    let id: ProviderID = .codex

    func fetch() async -> QuotaSnapshot {
        do {
            var creds = try CodexAuth.load()
            if CodexAuth.shouldRefresh(creds) {
                if let refreshed = try? await CodexAuth.refresh(creds) {
                    creds = refreshed
                }
            }
            var snapshot = try await request(creds)
            if snapshot.error != nil, snapshot.error?.contains("401") == true || snapshot.error?.contains("过期") == true {
                if let refreshed = try? await CodexAuth.refresh(creds) {
                    snapshot = try await request(refreshed)
                }
            }
            return snapshot
        } catch {
            return .failed(.codex, message: error.localizedDescription)
        }
    }

    private func request(_ creds: CodexAuth.Credentials) async throws -> QuotaSnapshot {
        var headers = [
            "Authorization": "Bearer \(creds.accessToken)",
            "Accept": "application/json",
        ]
        if let account = creds.accountID, !account.isEmpty {
            headers["ChatGPT-Account-Id"] = account
        }
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        let response = try await HTTPClient.get(url, headers: headers)
        if response.status == 401 || response.status == 403 {
            return .failed(.codex, message: "Codex 会话过期，请在终端执行 codex login")
        }
        guard response.status == 200, let json = JSONValue.object(response.data) else {
            return .failed(.codex, message: "Codex 接口返回 HTTP \(response.status)")
        }
        return map(
            json,
            email: JSONValue.string(json["email"]) ?? creds.email,
            subscriptionUntil: CodexAuth.subscriptionUntil(creds.idToken)
        )
    }

    private func map(_ json: [String: Any], email: String?, subscriptionUntil: Date?) -> QuotaSnapshot {
        let plan = YuheFormat.planTag(Self.displayPlan(JSONValue.string(json["plan_type"])))
        let rate = JSONValue.dict(json["rate_limit"])
        var windows: [QuotaWindow] = []

        if let primary = JSONValue.dict(rate?["primary_window"]) {
            windows.append(window(id: "5h", title: "5小时额度", dict: primary))
        }
        if let secondary = JSONValue.dict(rate?["secondary_window"]) {
            windows.append(window(id: "week", title: "周额度", dict: secondary))
        }
        if let extras = JSONValue.array(json["additional_rate_limits"]) {
            for (idx, item) in extras.enumerated() {
                guard let dict = JSONValue.dict(item) else { continue }
                let name = JSONValue.string(dict["limit_name"])
                    ?? JSONValue.string(dict["metered_feature"])
                    ?? "额外限额 \(idx + 1)"
                let title = sparkTitle(name)
                if let w = JSONValue.dict(dict["primary_window"]) {
                    windows.append(window(id: "extra-\(idx)-p", title: title, dict: w))
                }
                if let w = JSONValue.dict(dict["secondary_window"]) {
                    windows.append(window(id: "extra-\(idx)-s", title: "\(title) · 周", dict: w))
                }
            }
        }

        var totals: [QuotaTotal] = []
        if let n = JSONValue.int(JSONValue.dict(json["rate_limit_reset_credits"])?["available_count"]), n > 0 {
            totals.append(QuotaTotal(id: "reset-credits", label: "重置券", value: "\(n) 张"))
        }
        if let credits = JSONValue.dict(json["credits"]),
           let balance = JSONValue.string(credits["balance"]), Double(balance) ?? 0 > 0 {
            totals.append(QuotaTotal(id: "credits", label: "积分余额", value: balance))
        }
        if let until = subscriptionUntil {
            let days = YuheFormat.daysLeft(until: until)
            totals.append(QuotaTotal(
                id: "sub",
                label: "订阅有效期",
                value: "\(days)天 · \(YuheFormat.resetDate(until))"
            ))
        }

        return QuotaSnapshot(
            id: .codex,
            plan: plan,
            identity: nil,
            available: JSONValue.bool(rate?["allowed"]),
            headline: nil,
            headlineSecondary: nil,
            windows: windows,
            products: [],
            totals: totals,
            fetchedAt: Date(),
            error: windows.isEmpty ? "未返回窗口额度" : nil,
            warning: nil,
            isStale: false
        )
    }

    private func window(id: String, title: String, dict: [String: Any]) -> QuotaWindow {
        let percent = JSONValue.double(dict["used_percent"]) ?? 0
        let resetAt = epoch(dict["reset_at"])
        let label: String
        if let resetAt {
            label = "到期 \(YuheFormat.countdown(until: resetAt))"
        } else if let after = JSONValue.double(dict["reset_after_seconds"]) {
            label = "到期 \(YuheFormat.countdown(until: Date().addingTimeInterval(after)))"
        } else {
            label = "到期时间未知"
        }
        return QuotaWindow(id: id, title: title, usedPercent: percent, resetsAt: resetAt, resetLabel: label, showRemaining: true)
    }

    private func epoch(_ any: Any?) -> Date? {
        if let n = JSONValue.double(any) {
            if n > 10_000_000_000 { return Date(timeIntervalSince1970: n / 1000) }
            return Date(timeIntervalSince1970: n)
        }
        return nil
    }

    private func sparkTitle(_ name: String) -> String {
        if name.lowercased().contains("spark") { return "Spark 额外额度" }
        return name
    }

    private static func displayPlan(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "prolite": return "PRO 5X"
        case "pro": return "PRO"
        case "plus": return "PLUS"
        default: return raw
        }
    }
}

enum CodexAuth {
    struct Credentials {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var accountID: String?
        var email: String?
        var lastRefresh: Date?
    }

    static func load() throws -> Credentials {
        let candidates: [URL] = {
            var urls: [URL] = []
            if let home = ProcessInfo.processInfo.environment["CODEX_HOME"] {
                urls.append(URL(fileURLWithPath: home).appendingPathComponent("auth.json"))
            }
            let user = FileManager.default.homeDirectoryForCurrentUser
            urls.append(user.appendingPathComponent(".codex/auth.json"))
            urls.append(user.appendingPathComponent(".config/codex/auth.json"))
            return urls
        }()
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CodexAuthError.missing
        }
        let data = try Data(contentsOf: path)
        guard let json = JSONValue.object(data) else { throw CodexAuthError.missing }
        if JSONValue.dict(json["tokens"]) == nil, JSONValue.string(json["OPENAI_API_KEY"]) != nil {
            throw CodexAuthError.apiKeyOnly
        }
        let tokens = JSONValue.dict(json["tokens"]) ?? [:]
        guard let access = JSONValue.string(tokens["access_token"]), !access.isEmpty else {
            throw CodexAuthError.missing
        }
        let last = JSONValue.string(json["last_refresh"]).flatMap(parseISO)
        return Credentials(
            accessToken: access,
            refreshToken: JSONValue.string(tokens["refresh_token"]),
            idToken: JSONValue.string(tokens["id_token"]),
            accountID: JSONValue.string(tokens["account_id"]),
            email: nil,
            lastRefresh: last
        )
    }

    static func subscriptionUntil(_ idToken: String?) -> Date? {
        guard let idToken, let json = decodeJWT(idToken) else { return nil }
        let auth = JSONValue.dict(json["https://api.openai.com/auth"])
        guard let raw = JSONValue.string(auth?["chatgpt_subscription_active_until"]), !raw.isEmpty else { return nil }
        return parseISO(raw)
    }

    static func shouldRefresh(_ creds: Credentials) -> Bool {
        if let exp = jwtExp(creds.accessToken) {
            return exp.timeIntervalSinceNow < 5 * 60
        }
        if let last = creds.lastRefresh {
            return Date().timeIntervalSince(last) > 8 * 24 * 3600
        }
        return false
    }

    static func refresh(_ creds: Credentials) async throws -> Credentials {
        guard let refresh = creds.refreshToken, !refresh.isEmpty else { throw CodexAuthError.expired }
        let url = URL(string: "https://auth.openai.com/oauth/token")!
        let response = try await HTTPClient.postForm(url, fields: [
            "grant_type": "refresh_token",
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "refresh_token": refresh,
        ])
        guard response.status == 200, let json = JSONValue.object(response.data),
              let access = JSONValue.string(json["access_token"])
        else { throw CodexAuthError.expired }
        var next = creds
        next.accessToken = access
        if let r = JSONValue.string(json["refresh_token"]) { next.refreshToken = r }
        next.lastRefresh = Date()
        return next
    }

    private static func jwtExp(_ token: String) -> Date? {
        guard let json = decodeJWT(token), let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func decodeJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = payload.count % 4
        if pad > 0 { payload += String(repeating: "=", count: 4 - pad) }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func parseISO(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

enum CodexAuthError: LocalizedError {
    case missing, apiKeyOnly, expired
    var errorDescription: String? {
        switch self {
        case .missing: "未找到 Codex 登录，请先执行 codex login"
        case .apiKeyOnly: "当前是 API Key 登录，无法读取 ChatGPT 套餐额度"
        case .expired: "Codex 令牌刷新失败，请重新 login"
        }
    }
}
