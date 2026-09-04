import Foundation

struct KimiProvider: QuotaProvider {
    let id: ProviderID = .kimi

    func fetch() async -> QuotaSnapshot {
        guard var token = KimiAuth.loadToken() else {
            return .failed(.kimi, message: "未找到 Kimi Code 登录，请先执行 kimi login")
        }
        do {
            if KimiAuth.needsRefresh() {
                token = (try? await KimiAuth.refreshedAccessToken()) ?? token
            }
            let url = URL(string: "https://api.kimi.com/coding/v1/usages")!
            var response = try await HTTPClient.get(url, headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ])
            if response.status == 401 || response.status == 403,
               let fresh = try? await KimiAuth.refreshedAccessToken() {
                token = fresh
                response = try await HTTPClient.get(url, headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json",
                ])
            }
            if response.status == 401 || response.status == 403 {
                return .failed(.kimi, message: "Kimi 会话过期，请重新 kimi login")
            }
            guard response.status == 200, let json = JSONValue.object(response.data) else {
                return .failed(.kimi, message: "Kimi 接口返回 HTTP \(response.status)")
            }
            return map(json)
        } catch {
            return .failed(.kimi, message: error.localizedDescription)
        }
    }

    private func map(_ json: [String: Any]) -> QuotaSnapshot {
        var windows: [QuotaWindow] = []
        if let usage = JSONValue.dict(json["usage"]) {
            windows.append(countWindow(id: "week", title: "周额度", dict: usage, remainingStyle: true))
        }
        if let limits = JSONValue.array(json["limits"]) {
            for (idx, item) in limits.enumerated() {
                guard let dict = JSONValue.dict(item) else { continue }
                let windowMeta = JSONValue.dict(dict["window"])
                let duration = JSONValue.double(windowMeta?["duration"]) ?? 0
                let unit = JSONValue.string(windowMeta?["timeUnit"]) ?? ""
                let isFiveHour = duration == 300 && unit.contains("MINUTE")
                let detail = JSONValue.dict(dict["detail"]) ?? dict
                windows.append(countWindow(
                    id: isFiveHour ? "5h" : "lim-\(idx)",
                    title: isFiveHour ? "5小时额度" : "限额 \(idx + 1)",
                    dict: detail,
                    remainingStyle: true
                ))
            }
        }
        let level = JSONValue.string(JSONValue.dict(JSONValue.dict(json["user"])?["membership"])?["level"])
        if windows.isEmpty {
            return .failed(.kimi, message: "未返回额度窗口")
        }
        return QuotaSnapshot(
            id: .kimi,
            plan: YuheFormat.planTag(level),
            identity: nil,
            available: true,
            headline: nil,
            headlineSecondary: nil,
            windows: windows,
            products: [],
            totals: [],
            fetchedAt: Date(),
            error: nil,
            warning: nil,
            isStale: false
        )
    }

    private func countWindow(id: String, title: String, dict: [String: Any], remainingStyle: Bool) -> QuotaWindow {
        let limit = JSONValue.double(dict["limit"]) ?? 0
        let used = JSONValue.double(dict["used"])
        let remaining = JSONValue.double(dict["remaining"])
        let percent: Double
        if limit > 0, let used {
            percent = used / limit * 100
        } else if limit > 0, let remaining {
            percent = max(0, (limit - remaining) / limit * 100)
        } else {
            percent = 0
        }
        let reset = parseISO(JSONValue.string(dict["resetTime"]))
        return QuotaWindow(
            id: id,
            title: title,
            usedPercent: percent,
            resetsAt: reset,
            resetLabel: reset.map { "重置 \(YuheFormat.resetDate($0))" } ?? "",
            showRemaining: remainingStyle
        )
    }

    private func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

enum KimiAuth {
    private static var memoryToken: String?

    static func loadToken() -> String? {
        if let memoryToken, !memoryToken.isEmpty { return memoryToken }
        if let env = ProcessInfo.processInfo.environment["KIMI_CODE_API_KEY"], !env.isEmpty { return env }
        return loadFile()?.token
    }

    static func needsRefresh() -> Bool {
        guard let file = loadFile(), file.refresh != nil else { return false }
        if let exp = file.expiresAt { return exp.timeIntervalSinceNow < 5 * 60 }
        return false
    }

    static func refreshedAccessToken() async throws -> String {
        guard let file = loadFile(), let refresh = file.refresh, !refresh.isEmpty else {
            throw KimiAuthError.expired
        }
        let url = URL(string: "https://auth.kimi.com/api/oauth/token")!
        let response = try await HTTPClient.postForm(url, fields: [
            "client_id": "17e5f671-d194-4dfb-9706-5516cb48c098",
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        guard response.status == 200, let json = JSONValue.object(response.data),
              let access = JSONValue.string(json["access_token"]), !access.isEmpty else {
            throw KimiAuthError.expired
        }
        memoryToken = access
        return access
    }

    private struct FileCreds {
        var token: String
        var refresh: String?
        var expiresAt: Date?
    }

    private static func loadFile() -> FileCreds? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            home.appendingPathComponent(".kimi-code/credentials/kimi-code.json"),
            home.appendingPathComponent(".kimi/credentials/kimi-code.json"),
        ]
        if let custom = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"] {
            paths.insert(URL(fileURLWithPath: custom).appendingPathComponent("credentials/kimi-code.json"), at: 0)
        }
        for path in paths {
            guard let data = try? Data(contentsOf: path), let json = JSONValue.object(data),
                  let token = JSONValue.string(json["access_token"]), !token.isEmpty else { continue }
            let exp: Date?
            if let n = JSONValue.double(json["expires_at"]) {
                exp = Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
            } else { exp = nil }
            return FileCreds(token: token, refresh: JSONValue.string(json["refresh_token"]), expiresAt: exp)
        }
        return nil
    }
}

enum KimiAuthError: LocalizedError {
    case expired
    var errorDescription: String? { "Kimi 令牌刷新失败，请重新 kimi login" }
}
