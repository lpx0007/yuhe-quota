import AppKit
import Foundation
import SQLite3

enum CursorIDEAuth {
    static let accessTokenKey = "cursorAuth/accessToken"
    static let refreshTokenKey = "cursorAuth/refreshToken"
    static let emailKey = "cursorAuth/cachedEmail"
    static let membershipKey = "cursorAuth/stripeMembershipType"
    static let signUpTypeKey = "cursorAuth/cachedSignUpType"

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static let bundleIDs = [
        "com.todesktop.230313mzl4w4u92",
        "dev.cursor.Cursor",
    ]

    struct Snapshot {
        var rows: [String: String]
        var accessToken: String { rows[accessTokenKey] ?? "" }
        var refreshToken: String? { rows[refreshTokenKey].flatMap { $0.isEmpty ? nil : $0 } }
        var email: String? { rows[emailKey].flatMap { $0.isEmpty ? nil : $0 } }
        var canRestoreIDE: Bool { !accessToken.isEmpty && refreshToken != nil }
    }

    static func readSnapshot() -> Snapshot? {
        guard let rows = try? readAuthRows(),
              let access = rows[accessTokenKey], !access.isEmpty
        else { return nil }
        return Snapshot(rows: rows)
    }

    static func restore(rows: [String: String]) throws {
        guard let access = rows[accessTokenKey], !access.isEmpty,
              let refresh = rows[refreshTokenKey], !refresh.isEmpty
        else {
            throw CursorAuthError.probeFailed("这个号没有 Cursor App 会话（缺 refreshToken），不能写入 IDE")
        }
        let running = isRunning
        if running {
            guard quitAndWait() else {
                throw CursorAuthError.probeFailed("无法退出 Cursor，换号已取消")
            }
        }
        try writeAuthRows(rows)
        writeKeychain(accessToken: access, refreshToken: refresh)
        launchCursor()
    }

    static func restoreOffMain(rows: [String: String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try restore(rows: rows)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    static var isRunning: Bool {
        runningApps().isEmpty == false
    }

    private static func runningApps() -> [NSRunningApplication] {
        bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }

    @discardableResult
    static func quitAndWait(timeout: TimeInterval = 20) -> Bool {
        let apps = runningApps()
        guard !apps.isEmpty else { return true }
        for app in apps { app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        var forced = false
        while Date() < deadline {
            let still = runningApps()
            if still.isEmpty { return true }
            if !forced, Date() > deadline.addingTimeInterval(-timeout / 2) {
                still.forEach { $0.forceTerminate() }
                forced = true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return runningApps().isEmpty
    }

    static func launchCursor() {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Cursor.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Cursor.app"),
        ]
        let url = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIDs[0])
        guard let url else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }

    static func readAuthRows() throws -> [String: String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw CursorAuthError.notFound
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT key, value FROM ItemTable WHERE key LIKE 'cursorAuth/%'"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CursorAuthError.notFound
        }
        defer { sqlite3_finalize(statement) }
        var rows: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyC = sqlite3_column_text(statement, 0) else { continue }
            let key = String(cString: keyC)
            let value = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            rows[key] = value
        }
        return rows
    }

    private static func writeAuthRows(_ rows: [String: String]) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CursorAuthError.notFound
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw CursorAuthError.probeFailed("无法写入 Cursor 登录库")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        try exec(db, "BEGIN IMMEDIATE;")
        do {
            try exec(db, "DELETE FROM ItemTable WHERE key LIKE 'cursorAuth/%';")
            for (key, value) in rows {
                try insert(db, key: key, value: value)
            }
            try exec(db, "COMMIT;")
        } catch {
            try? exec(db, "ROLLBACK;")
            throw error
        }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    private static func insert(_ db: OpaquePointer, key: String, value: String) throws {
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CursorAuthError.probeFailed("写入 Cursor 登录失败")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CursorAuthError.probeFailed("写入 Cursor 登录失败")
        }
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw CursorAuthError.probeFailed(message)
        }
    }

    private static func writeKeychain(accessToken: String, refreshToken: String) {
        setPassword(service: "cursor-access-token", value: accessToken)
        setPassword(service: "cursor-refresh-token", value: refreshToken)
    }

    private static func setPassword(service: String, value: String) {
        let exists = runSecurity(["find-generic-password", "-a", "cursor-user", "-s", service]).status == 0
        var args = [
            "add-generic-password",
            "-a", "cursor-user",
            "-s", service,
            "-w", value,
            "-U",
        ]
        if !exists {
            args += ["-T", "/usr/bin/security"]
            if FileManager.default.fileExists(atPath: "/Applications/Cursor.app") {
                args += ["-T", "/Applications/Cursor.app"]
            }
        }
        _ = runSecurity(args)
    }

    private static func runSecurity(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
