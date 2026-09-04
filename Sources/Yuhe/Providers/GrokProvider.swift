import Foundation

struct GrokProvider: QuotaProvider {
    let id: ProviderID = .grok

    func fetch() async -> QuotaSnapshot {
        do {
            var creds = try GrokAuth.load()
            if GrokAuth.shouldRefresh(creds) {
                if let refreshed = try? await GrokAuth.refresh(creds) {
                    creds = refreshed
                }
            }
            var snapshot = try await request(creds)
            if snapshot.error?.contains("过期") == true || snapshot.error?.contains("401") == true {
                if let refreshed = try? await GrokAuth.refresh(creds) {
                    snapshot = try await request(refreshed)
                }
            }
            return snapshot
        } catch {
            return .failed(.grok, message: error.localizedDescription)
        }
    }

    private func request(_ creds: GrokAuth.Credentials) async throws -> QuotaSnapshot {
        let headers = [
            "Authorization": "Bearer \(creds.token)",
            "x-xai-token-auth": "xai-grok-cli",
            "Accept": "application/json",
        ]
        let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
        let billing = try await HTTPClient.get(billingURL, headers: headers)
        if billing.status == 401 || billing.status == 403 {
            return .failed(.grok, message: "Grok 会话过期")
        }
        guard billing.status == 200, let json = JSONValue.object(billing.data) else {
            return .failed(.grok, message: "Grok 接口返回 HTTP \(billing.status)")
        }

        var plan = creds.planHint
        if let settingsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/settings"),
           let settings = try? await HTTPClient.get(settingsURL, headers: headers),
           settings.status == 200,
           let sjson = JSONValue.object(settings.data),
           let tier = JSONValue.string(sjson["subscription_tier_display"]) {
            plan = tier
        }
        return map(json, email: creds.email, plan: plan)
    }

    private func map(_ json: [String: Any], email: String?, plan: String?) -> QuotaSnapshot {
        let config = JSONValue.dict(json["config"]) ?? json
        let period = JSONValue.dict(config["currentPeriod"]) ?? JSONValue.dict(config["current_period"])
        let end = parseISO(JSONValue.string(period?["end"]) ?? JSONValue.string(config["billingPeriodEnd"]))
        let start = parseISO(JSONValue.string(period?["start"]))

        var percent = JSONValue.double(config["creditUsagePercent"]) ?? JSONValue.double(config["credit_usage_percent"])
        if percent == nil {
            let used = money(config["onDemandUsed"])
            let cap = money(config["onDemandCap"])
            if let used, let cap, cap > 0 { percent = used / cap * 100 }
        }

        var windows: [QuotaWindow] = []
        if let percent {
            windows.append(QuotaWindow(
                id: "week",
                title: "周额度",
                usedPercent: percent,
                resetsAt: end,
                resetLabel: end.map { "到期 \(YuheFormat.resetDate($0))" } ?? "到期时间未知",
                showRemaining: true
            ))
        }

        var products: [QuotaProduct] = []
        if let list = JSONValue.array(config["productUsage"]) ?? JSONValue.array(json["productUsage"]) {
            for (idx, item) in list.enumerated() {
                guard let dict = JSONValue.dict(item) else { continue }
                let name = JSONValue.string(dict["product"]) ?? JSONValue.string(dict["name"]) ?? "产品 \(idx + 1)"
                if let p = JSONValue.double(dict["usagePercent"]) ?? JSONValue.double(dict["percent"]) {
                    products.append(QuotaProduct(id: "p-\(idx)", name: productTitle(name), usedPercent: p, showRemaining: true))
                }
            }
        }

        var totals: [QuotaTotal] = []
        if let prepaid = money(config["prepaidBalance"] ?? json["prepaidBalance"]), prepaid > 0 {
            totals.append(QuotaTotal(id: "prepaid", label: "预付余额", value: YuheFormat.usdFromCents(Int(prepaid))))
        }
        if let cap = money(config["onDemandCap"]), cap > 0 {
            let used = money(config["onDemandUsed"]) ?? 0
            totals.append(QuotaTotal(id: "ondemand", label: "按需额度", value: "\(YuheFormat.usdFromCents(Int(used))) / \(YuheFormat.usdFromCents(Int(cap)))"))
        }
        if let start, let end {
            totals.append(QuotaTotal(id: "period", label: "周期", value: "\(YuheFormat.resetDate(start)) → \(YuheFormat.resetDate(end))"))
        } else if let end {
            totals.append(QuotaTotal(id: "end", label: "到期时间", value: YuheFormat.resetDate(end)))
        }
        if let email {
            totals.append(QuotaTotal(id: "email", label: "账号", value: email))
        }

        return QuotaSnapshot(
            id: .grok,
            plan: YuheFormat.planTag(Self.displayPlan(plan)),
            identity: nil,
            available: true,
            headline: nil,
            headlineSecondary: nil,
            windows: windows,
            products: products,
            totals: totals,
            fetchedAt: Date(),
            error: windows.isEmpty ? "未返回周额度百分比" : nil,
            warning: nil,
            isStale: false
        )
    }

    private func money(_ any: Any?) -> Double? {
        if let n = JSONValue.double(any) { return n }
        if let dict = JSONValue.dict(any) { return JSONValue.double(dict["val"]) }
        return nil
    }

    private func productTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "grokbuild", "build": return "Build 产品"
        case "chat", "grokchat": return "Chat 产品"
        default: return name
        }
    }

    private static func displayPlan(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "supergrok_heavy", "heavy": return "SUPERGROK HEAVY"
        case "supergrok": return "SUPERGROK"
        default: return raw
        }
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

enum GrokAuth {
    struct Credentials {
        var token: String
        var refreshToken: String?
        var clientID: String?
        var email: String?
        var planHint: String?
        var expiresAt: Date?
        var sourceURL: URL
    }

    static var importedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yuhe/grok.json")
    }

    static func load() throws -> Credentials {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            importedURL,
            home.appendingPathComponent(".grok/auth.json"),
            home.appendingPathComponent(".config/grok/auth.json"),
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path.path) {
            if let creds = try? parseFile(path) { return creds }
        }
        throw GrokAuthError.missing
    }

    static func shouldRefresh(_ creds: Credentials) -> Bool {
        guard creds.refreshToken != nil else { return false }
        if let exp = creds.expiresAt { return exp.timeIntervalSinceNow < 5 * 60 }
        if let exp = jwtExp(creds.token) { return exp.timeIntervalSinceNow < 5 * 60 }
        return false
    }

    static func refresh(_ creds: Credentials) async throws -> Credentials {
        guard let refresh = creds.refreshToken, !refresh.isEmpty else { throw GrokAuthError.expired }
        let clientID = creds.clientID ?? "b1a00492-073a-47ea-816f-4c329264a828"
        let url = URL(string: "https://auth.x.ai/oauth2/token")!
        let response = try await HTTPClient.postForm(url, fields: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refresh,
        ])
        guard response.status == 200, let json = JSONValue.object(response.data),
              let access = JSONValue.string(json["access_token"]), !access.isEmpty
        else { throw GrokAuthError.expired }

        var next = creds
        next.token = access
        if let r = JSONValue.string(json["refresh_token"]) { next.refreshToken = r }
        if let seconds = JSONValue.double(json["expires_in"]) {
            next.expiresAt = Date().addingTimeInterval(seconds)
        }
        persist(next)
        return next
    }

    static func importSub2API(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = JSONValue.object(data) else { throw GrokAuthError.missing }
        let accounts = JSONValue.array(root["accounts"]) ?? []
        var chosen: [String: Any]?
        for item in accounts {
            guard let acc = JSONValue.dict(item) else { continue }
            let platform = JSONValue.string(acc["platform"])?.lowercased()
            if platform == "grok" || platform == nil {
                chosen = acc
                if JSONValue.string(acc["name"]) != nil { break }
            }
        }
        guard let acc = chosen, let creds = JSONValue.dict(acc["credentials"]) else {
            throw GrokAuthError.missing
        }
        try writeImported(fromCredentials: creds, extra: JSONValue.dict(acc["extra"]))
    }

    private static func parseFile(_ path: URL) throws -> Credentials {
        let data = try Data(contentsOf: path)
        guard let root = JSONValue.object(data) else { throw GrokAuthError.missing }

        if JSONValue.string(root["access_token"]) != nil || JSONValue.string(root["token"]) != nil {
            let token = JSONValue.string(root["access_token"]) ?? JSONValue.string(root["token"]) ?? ""
            guard !token.isEmpty else { throw GrokAuthError.missing }
            return Credentials(
                token: token,
                refreshToken: JSONValue.string(root["refresh_token"]),
                clientID: JSONValue.string(root["client_id"]),
                email: JSONValue.string(root["email"]),
                planHint: JSONValue.string(root["subscription_tier"]) ?? JSONValue.string(root["plan"]),
                expiresAt: parse(JSONValue.string(root["expires_at"]) ?? ""),
                sourceURL: path
            )
        }

        if let accounts = JSONValue.array(root["accounts"]) {
            for item in accounts {
                guard let acc = JSONValue.dict(item),
                      let creds = JSONValue.dict(acc["credentials"]),
                      let token = JSONValue.string(creds["access_token"])
                else { continue }
                return Credentials(
                    token: token,
                    refreshToken: JSONValue.string(creds["refresh_token"]),
                    clientID: JSONValue.string(creds["client_id"]),
                    email: JSONValue.string(creds["email"]),
                    planHint: JSONValue.string(creds["subscription_tier"]),
                    expiresAt: parse(JSONValue.string(creds["expires_at"]) ?? ""),
                    sourceURL: path
                )
            }
        }

        var best: [String: Any]?
        for (key, value) in root {
            guard let dict = JSONValue.dict(value), JSONValue.string(dict["key"]) != nil else { continue }
            if key.contains("auth.x.ai") { best = dict; break }
            if best == nil { best = dict }
        }
        guard let dict = best, let token = JSONValue.string(dict["key"]), !token.isEmpty else {
            throw GrokAuthError.missing
        }
        return Credentials(
            token: token,
            refreshToken: JSONValue.string(dict["refresh_token"]),
            clientID: nil,
            email: JSONValue.string(dict["email"]),
            planHint: JSONValue.string(dict["auth_mode"]),
            expiresAt: parse(JSONValue.string(dict["expires_at"]) ?? ""),
            sourceURL: path
        )
    }

    private static func persist(_ creds: Credentials) {
        var json: [String: Any] = [
            "access_token": creds.token,
        ]
        if let email = creds.email { json["email"] = email }
        if let plan = creds.planHint { json["subscription_tier"] = plan }
        if let client = creds.clientID { json["client_id"] = client }
        if let refresh = creds.refreshToken { json["refresh_token"] = refresh }
        if let exp = creds.expiresAt {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            json["expires_at"] = iso.string(from: exp)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) else { return }
        let dest = importedURL
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: dest, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
    }

    private static func writeImported(fromCredentials creds: [String: Any], extra: [String: Any]?) throws {
        var json: [String: Any] = [:]
        json["access_token"] = creds["access_token"]
        json["refresh_token"] = creds["refresh_token"]
        json["client_id"] = creds["client_id"]
        json["email"] = creds["email"]
        json["expires_at"] = creds["expires_at"]
        json["subscription_tier"] = creds["subscription_tier"] ?? extra?["subscription_tier"]
        let dest = importedURL
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: dest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
    }

    private static func jwtExp(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = payload.count % 4
        if pad > 0 { payload += String(repeating: "=", count: 4 - pad) }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func parse(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

enum GrokAuthError: LocalizedError {
    case missing, expired
    var errorDescription: String? {
        switch self {
        case .missing: "未找到 Grok 登录，请导入账号或执行 grok login"
        case .expired: "Grok 令牌已过期"
        }
    }
}
