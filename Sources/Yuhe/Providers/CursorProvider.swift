import Foundation
import SQLite3

struct CursorProvider: QuotaProvider {
    let id: ProviderID = .cursor

    func fetch() async -> QuotaSnapshot {
        do {
            let cookie = try CursorAuth.loadCookie()
            let headers = [
                "Cookie": "WorkosCursorSessionToken=\(cookie)",
                "Origin": "https://cursor.com",
            ]
            let url = URL(string: "https://cursor.com/api/usage-summary")!
            let response = try await HTTPClient.get(url, headers: headers)
            if let failure = Self.accountFailure(status: response.status, data: response.data) {
                return .failed(.cursor, message: failure)
            }
            guard let json = JSONValue.object(response.data) else {
                return .failed(.cursor, message: "Cursor 额度数据无法解析")
            }
            if json["error"] != nil,
               let failure = Self.accountFailure(status: response.status, data: response.data) {
                return .failed(.cursor, message: failure)
            }
            var snapshot = Self.map(json)
            if snapshot.identity == nil,
               let meURL = URL(string: "https://cursor.com/api/auth/me"),
               let me = try? await HTTPClient.get(meURL, headers: headers),
               me.status == 200,
               let meJSON = JSONValue.object(me.data) {
                snapshot.identity = JSONValue.string(meJSON["email"])
            }
            if let sandURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status"),
               let sand = try? await HTTPClient.postJSON(sandURL, body: [:], headers: headers),
               sand.status == 200,
               let sandJSON = JSONValue.object(sand.data) {
                snapshot = Self.mergeGrokBot(snapshot, sand: sandJSON)
            }
            return snapshot
        } catch let error as CursorAuthError {
            return .failed(.cursor, message: error.localizedDescription)
        } catch {
            return .failed(.cursor, message: "Cursor 查询失败：\(error.localizedDescription)")
        }
    }

    private static func map(_ json: [String: Any]) -> QuotaSnapshot {
        let individual = JSONValue.dict(json["individualUsage"])
        let plan = JSONValue.dict(individual?["plan"])
        let onDemand = JSONValue.dict(individual?["onDemand"])
            ?? JSONValue.dict(JSONValue.dict(json["teamUsage"])?["onDemand"])
        let overall = JSONValue.dict(individual?["overall"])

        let membership = JSONValue.string(json["membershipType"])
        let limitType = JSONValue.string(json["limitType"])
        let planTag: String? = {
            if limitType?.lowercased() == "team" { return "TEAM" }
            return YuheFormat.planTag(membership)
        }()
        let cycleEnd = parseISO(JSONValue.string(json["billingCycleEnd"]))

        let usedCents = JSONValue.int(plan?["used"]) ?? JSONValue.int(overall?["used"])
        let limitCents = JSONValue.int(plan?["limit"]) ?? JSONValue.int(overall?["limit"])

        var windows: [QuotaWindow] = []

        // Cursor 的 *PercentUsed 已经是 0–100（0.45 表示 0.45%），不要当 0–1 再乘 100。
        // 另一款面板用向上取整，所以 0.45% → 1%，2.46% → 3%。
        let totalPercent: Double? = {
            if let p = percent(plan?["totalPercentUsed"]) { return p }
            return percent(json["serverPercentUsed"])
        }()
        if let totalPercent {
            windows.append(QuotaWindow(
                id: "total",
                title: "总用量",
                usedPercent: totalPercent,
                resetsAt: cycleEnd,
                resetLabel: cycleEnd.map { "重置 \(YuheFormat.resetDate($0))" } ?? "账单周期未知"
            ))
        }

        if let auto = percent(plan?["autoPercentUsed"]) {
            windows.append(QuotaWindow(
                id: "auto",
                title: "Auto + Composer",
                usedPercent: auto,
                resetsAt: cycleEnd,
                resetLabel: cycleEnd.map { "重置 \(YuheFormat.resetDate($0))" } ?? "账单周期未知"
            ))
        }
        if let api = percent(plan?["apiPercentUsed"]) {
            windows.append(QuotaWindow(
                id: "api",
                title: "API 用量",
                usedPercent: api,
                resetsAt: cycleEnd,
                resetLabel: cycleEnd.map { "重置 \(YuheFormat.resetDate($0))" } ?? "账单周期未知"
            ))
        }

        var totals: [QuotaTotal] = []
        if let used = usedCents, let limit = limitCents, limit > 0 {
            totals.append(QuotaTotal(id: "plan", label: "套餐额度", value: "\(YuheFormat.usdFromCents(used)) / \(YuheFormat.usdFromCents(limit))"))
        } else if let used = usedCents {
            totals.append(QuotaTotal(id: "overall", label: "已用", value: YuheFormat.usdFromCents(used)))
            totals.append(QuotaTotal(id: "nolimit", label: "上限", value: "无个人上限"))
        }
        if let bonus = JSONValue.int(JSONValue.dict(plan?["breakdown"])?["bonus"]), bonus > 0 {
            totals.append(QuotaTotal(id: "bonus", label: "奖励额度", value: YuheFormat.usdFromCents(bonus)))
        }

        let onDemandEnabled = JSONValue.bool(onDemand?["enabled"]) == true
        let onDemandUsed = JSONValue.int(onDemand?["used"]) ?? 0
        let onDemandLimit = JSONValue.int(onDemand?["limit"])
        if onDemandEnabled || onDemandUsed > 0 {
            let value: String
            if let limit = onDemandLimit, limit > 0 {
                value = "\(YuheFormat.usdFromCents(onDemandUsed)) / \(YuheFormat.usdFromCents(limit))"
            } else if onDemandEnabled {
                value = "\(YuheFormat.usdFromCents(onDemandUsed)) · Unlimited"
            } else {
                value = YuheFormat.usdFromCents(onDemandUsed)
            }
            totals.append(QuotaTotal(id: "ondemand", label: "按需超额", value: value))
        } else {
            totals.append(QuotaTotal(id: "ondemand", label: "按需超额", value: "已禁用"))
        }

        if let end = cycleEnd {
            totals.append(QuotaTotal(
                id: "reset",
                label: "重置",
                value: "\(YuheFormat.countdown(until: end)) · \(YuheFormat.resetDate(end))"
            ))
        }

        if windows.isEmpty, JSONValue.bool(json["isUnlimited"]) == true {
            windows.append(QuotaWindow(id: "unl", title: "总用量", usedPercent: 0, resetsAt: cycleEnd, resetLabel: "不限量"))
        }

        var warning: String?
        // Team 座位的 plan.used/limit 经常是 $20/$20 占位，真正用量看百分比。
        let usedUpByPercent = windows.contains { $0.id == "total" && $0.usedPercent >= 99.5 }
        if onDemandUsed > 0 {
            warning = "已产生按需超额 \(YuheFormat.usdFromCents(onDemandUsed))"
        } else if usedUpByPercent && onDemandEnabled {
            warning = "套餐额度已用完，超额将按需计费（Unlimited）"
        } else if usedUpByPercent {
            warning = "套餐额度已用完"
        }

        return QuotaSnapshot(
            id: .cursor,
            plan: planTag,
            identity: nil,
            available: true,
            headline: nil,
            headlineSecondary: nil,
            windows: windows,
            products: [],
            totals: totals,
            fetchedAt: Date(),
            error: windows.isEmpty && totals.isEmpty ? "额度查询失败，未返回可用字段" : nil,
            warning: warning,
            isStale: false
        )
    }

    private static func mergeGrokBot(_ snapshot: QuotaSnapshot, sand: [String: Any]) -> QuotaSnapshot {
        var next = snapshot
        let used = JSONValue.double(sand["usagePercent"]) ?? 0
        let available = JSONValue.bool(sand["hasAvailableUsage"])
        let included = JSONValue.bool(sand["hasNonZeroIncludedLimit"]) == true
        guard included || used > 0 || available != nil else { return snapshot }
        if !next.windows.contains(where: { $0.id == "grokbot" }) {
            next.windows.append(QuotaWindow(
                id: "grokbot",
                title: "Grok Bot",
                usedPercent: ceil(max(0, used)),
                resetsAt: nil,
                resetLabel: ""
            ))
        }
        return next
    }

    /// Cursor 的 *PercentUsed 已经是百分数。小于 1 也是 0.xx%，不是 0–1 比例。
    private static func percent(_ any: Any?) -> Double? {
        guard let raw = JSONValue.double(any) else { return nil }
        if raw <= 0 { return 0 }
        return ceil(raw)
    }

    static func accountFailure(status: Int, data: Data) -> String? {
        let text = (String(data: data, encoding: .utf8) ?? "").uppercased()
        let closed = text.contains("ACCOUNT_CLOSED") || text.contains("ACCOUNT CLOSED")
            || text.contains("ERROR_ACCOUNT_CLOSED")
        let banned = text.contains("BANNED") || text.contains("SUSPENDED")
            || text.contains("DISABLED") || text.contains("REVOKED")
            || text.contains("ACCOUNT_LOCKED")
        if closed { return "Cursor 账号已关闭或被封禁" }
        if banned { return "Cursor 账号已被封禁或停用" }
        if status == 200 || status == 204 { return nil }
        if status == 401 || text.contains("UNAUTHENTICATED") || text.contains("UNAUTHORIZED") {
            return "Cursor 登录已失效，请重新登录 IDE"
        }
        if status == 403 {
            return "Cursor 账号无权限或已被限制"
        }
        if status == 0 {
            return "Cursor 网络请求失败"
        }
        return "Cursor 额度查询失败（HTTP \(status)）"
    }

    private static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

enum CursorAuth {
    static func loadCookie() throws -> String {
        if let pasted = CursorSessionStore.activeCookie() {
            return pasted
        }
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: db.path) else {
            throw CursorAuthError.notFound
        }
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let encoded = db.path.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? db.path
        let uri = "file:\(encoded)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw CursorAuthError.notFound
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CursorAuthError.noToken
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { throw CursorAuthError.noToken }

        let token: String
        if let cString = sqlite3_column_text(statement, 0) {
            token = String(cString: cString)
        } else {
            throw CursorAuthError.noToken
        }
        let userID = try extractUserID(from: token)
        return "\(userID)%3A%3A\(token)"
    }

    static func extractUserID(from jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        let payload = parts.count >= 2 ? String(parts[1]) : jwt
        guard let userID = userIDFromPayload(payload) else { throw CursorAuthError.badToken }
        return userID
    }

    static func userIDFromPayload(_ payload: String) -> String? {
        var text = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - text.count % 4) % 4
        if pad > 0 { text += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: text),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String
        else { return nil }
        if let idx = subject.lastIndex(of: "|") {
            return String(subject[subject.index(after: idx)...])
        }
        return subject
    }
}

