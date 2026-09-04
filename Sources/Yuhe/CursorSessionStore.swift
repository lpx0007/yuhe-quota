import Foundation

struct CursorAccount: Codable, Identifiable, Equatable {
    var id: String
    var email: String?
    var jwt: String
    var refreshToken: String?
    var authRows: [String: String]?
    var addedAt: Date

    var canRestoreIDE: Bool {
        if let rows = authRows,
           let access = rows["cursorAuth/accessToken"], !access.isEmpty,
           let refresh = rows["cursorAuth/refreshToken"], !refresh.isEmpty {
            return true
        }
        return !(refreshToken ?? "").isEmpty
    }
}

struct CursorAccountFile: Codable, Equatable {
    var queryID: String?
    var accounts: [CursorAccount]
}

enum CursorSessionStore {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yuhe/cursor-accounts.json")
    }

    static func load() -> CursorAccountFile {
        guard let data = try? Data(contentsOf: fileURL) else {
            return CursorAccountFile(queryID: nil, accounts: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(CursorAccountFile.self, from: data) {
            return file
        }
        struct Legacy: Codable {
            var activeID: String?
            var accounts: [LegacyAccount]?
        }
        struct LegacyAccount: Codable {
            var id: String
            var email: String?
            var cookie: String?
            var jwt: String?
            var refreshToken: String?
        }
        if let legacy = try? decoder.decode(Legacy.self, from: data) {
            let accounts = (legacy.accounts ?? []).compactMap { item -> CursorAccount? in
                let jwt = item.jwt ?? jwtFromCookie(item.cookie)
                guard let jwt else { return nil }
                return CursorAccount(id: item.id, email: item.email, jwt: jwt, refreshToken: item.refreshToken, authRows: nil, addedAt: Date())
            }
            return CursorAccountFile(queryID: legacy.activeID, accounts: accounts)
        }
        return CursorAccountFile(queryID: nil, accounts: [])
    }

    static func save(_ file: CursorAccountFile) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func remove(id: String) {
        var file = load()
        file.accounts.removeAll { $0.id == id }
        if file.queryID == id { file.queryID = nil }
        save(file)
    }

    static func selectQuery(id: String?) {
        var file = load()
        file.queryID = id
        save(file)
    }

    static func activeCookie() -> String? {
        let file = load()
        guard let id = file.queryID,
              let account = file.accounts.first(where: { $0.id == id })
        else { return nil }
        return "\(account.id)%3A%3A\(account.jwt)"
    }

    static func currentQueryAccountID() -> String? {
        if let id = load().queryID { return id }
        return currentIDEAccountID()
    }

    static func currentIDEAccountID() -> String? {
        guard let snap = CursorIDEAuth.readSnapshot() else { return nil }
        return try? CursorAuth.extractUserID(from: snap.accessToken)
    }

    static func captureCurrentIDE() throws -> CursorAccount {
        guard let snap = CursorIDEAuth.readSnapshot(), !snap.accessToken.isEmpty else {
            throw CursorAuthError.probeFailed("Cursor App 当前没有登录")
        }
        guard snap.canRestoreIDE else {
            throw CursorAuthError.probeFailed("当前登录缺 refreshToken，不能用来一键写入 Cursor。请先在 Cursor App 里正常登录一次再保存。")
        }
        let userID = try CursorAuth.extractUserID(from: snap.accessToken)
        var file = load()
        let account = CursorAccount(
            id: userID,
            email: snap.email,
            jwt: snap.accessToken,
            refreshToken: snap.refreshToken,
            authRows: snap.rows,
            addedAt: Date()
        )
        if let idx = file.accounts.firstIndex(where: { $0.id == userID }) {
            file.accounts[idx] = account
        } else {
            file.accounts.append(account)
        }
        save(file)
        return account
    }

    static func importPasted(_ raw: String) async throws -> CursorAccount {
        let parsed = try CursorToken.parse(raw)
        let email = try await probe(cookie: parsed.cookie)
        var file = load()
        var account = CursorAccount(
            id: parsed.userID,
            email: email,
            jwt: parsed.jwt,
            refreshToken: nil,
            authRows: nil,
            addedAt: Date()
        )
        if let idx = file.accounts.firstIndex(where: { $0.id == parsed.userID }) {
            let old = file.accounts[idx]
            account.refreshToken = old.refreshToken
            account.authRows = old.authRows
            file.accounts[idx] = account
        } else {
            file.accounts.append(account)
        }
        file.queryID = parsed.userID
        save(file)
        return account
    }

    /// Cockpit 同款：网页 Token → PKCE 兑换 IDE 会话 → 写入 Cursor App。
    static func importAndSwitchIDE(_ raw: String) async throws -> CursorAccount {
        let parsed = try CursorToken.parse(raw)
        let webEmail = try? await probe(cookie: parsed.cookie)
        let session = try await CursorTokenExchange.exchange(webCookie: parsed.cookie)
        let userID = (try? CursorAuth.extractUserID(from: session.accessToken)) ?? parsed.userID
        let email = session.email ?? webEmail
        var rows: [String: String] = [
            CursorIDEAuth.accessTokenKey: session.accessToken,
            CursorIDEAuth.refreshTokenKey: session.refreshToken,
        ]
        if let email, !email.isEmpty {
            rows[CursorIDEAuth.emailKey] = email
        }
        let account = CursorAccount(
            id: userID,
            email: email,
            jwt: session.accessToken,
            refreshToken: session.refreshToken,
            authRows: rows,
            addedAt: Date()
        )
        var file = load()
        if let idx = file.accounts.firstIndex(where: { $0.id == userID }) {
            file.accounts[idx] = account
        } else {
            file.accounts.append(account)
        }
        file.queryID = nil
        save(file)
        try await CursorIDEAuth.restoreOffMain(rows: rows)
        return account
    }

    static func restoreIDE(_ account: CursorAccount) async throws {
        if let rows = account.authRows,
           let access = rows[CursorIDEAuth.accessTokenKey], !access.isEmpty,
           let refresh = rows[CursorIDEAuth.refreshTokenKey], !refresh.isEmpty {
            try await CursorIDEAuth.restoreOffMain(rows: rows)
            selectQuery(id: nil)
            return
        }
        if let refresh = account.refreshToken, !refresh.isEmpty {
            var rows = [
                CursorIDEAuth.accessTokenKey: account.jwt,
                CursorIDEAuth.refreshTokenKey: refresh,
            ]
            if let email = account.email { rows[CursorIDEAuth.emailKey] = email }
            try await CursorIDEAuth.restoreOffMain(rows: rows)
            selectQuery(id: nil)
            return
        }
        throw CursorAuthError.probeFailed("这个号还没有 Cursor App 会话。请用「一键换号」从网页 Token 兑换。")
    }

    private static func jwtFromCookie(_ cookie: String?) -> String? {
        guard var text = cookie, !text.isEmpty else { return nil }
        if let decoded = text.removingPercentEncoding { text = decoded }
        if let sep = text.range(of: "::") {
            return String(text[sep.upperBound...])
        }
        return text
    }

    private static func probe(cookie: String) async throws -> String? {
        let url = URL(string: "https://cursor.com/api/auth/me")!
        let response = try await HTTPClient.get(url, headers: [
            "Cookie": "WorkosCursorSessionToken=\(cookie)",
            "Origin": "https://cursor.com",
            "Accept": "application/json",
        ])
        if let failure = CursorProvider.accountFailure(status: response.status, data: response.data) {
            throw CursorAuthError.rejected(failure)
        }
        if response.status == 204 { return nil }
        guard (200..<300).contains(response.status), let json = JSONValue.object(response.data) else {
            throw CursorAuthError.rejected("Token 无效或已过期")
        }
        return JSONValue.string(json["email"])
    }
}

enum CursorToken {
    struct Parsed {
        let userID: String
        let jwt: String
        var cookie: String { "\(userID)%3A%3A\(jwt)" }
    }

    static func parse(_ raw: String) throws -> Parsed {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "WorkosCursorSessionToken=", options: .caseInsensitive) {
            text = String(text[range.upperBound...])
            if let end = text.firstIndex(of: ";") {
                text = String(text[..<end])
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = text.removingPercentEncoding {
            text = decoded
        }
        if let sep = text.range(of: "::") {
            let jwt = String(text[sep.upperBound...])
            guard jwt.split(separator: ".").count >= 2 else { throw CursorAuthError.badToken }
            let userID = try CursorAuth.extractUserID(from: jwt)
            return Parsed(userID: userID, jwt: jwt)
        }
        if text.split(separator: ".").count >= 2 {
            let userID = try CursorAuth.extractUserID(from: text)
            return Parsed(userID: userID, jwt: text)
        }
        // 只贴了 JWT payload（中间那段），从 sub 还原 user id，cookie 仍用这段拼。
        throw CursorAuthError.badToken
    }
}

extension CursorAuthError {
    static func rejected(_ message: String) -> CursorAuthError { .probeFailed(message) }
}

enum CursorAuthError: LocalizedError {
    case notFound, noToken, badToken, probeFailed(String)
    var errorDescription: String? {
        switch self {
        case .notFound: "未找到 Cursor 登录库，请先安装并登录 Cursor"
        case .noToken: "Cursor 未登录或登录已失效"
        case .badToken: "请粘贴完整 WorkosCursorSessionToken（以 user_ 开头、含 %3A%3AeyJ 的整段），不要只复制中间那段"
        case .probeFailed(let message): message
        }
    }
}
