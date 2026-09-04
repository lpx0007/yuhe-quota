import CryptoKit
import Foundation
import Security

enum CursorTokenExchange {
    struct Session {
        var accessToken: String
        var refreshToken: String
        var email: String?
    }

    static func exchange(webCookie: String) async throws -> Session {
        let sessionToken = webCookie
            .replacingOccurrences(of: "%3A%3A", with: "::")
            .replacingOccurrences(of: "%3a%3a", with: "::")
        let (verifier, challenge) = try pkce()
        let uuid = UUID().uuidString.lowercased()

        let authURL = URL(string: "https://cursor.com/api/auth/loginDeepCallbackControl")!
        let auth = try await HTTPClient.postJSON(
            authURL,
            body: ["uuid": uuid, "challenge": challenge],
            headers: [
                "Cookie": "WorkosCursorSessionToken=\(sessionToken.replacingOccurrences(of: "::", with: "%3A%3A"))",
                "Origin": "https://cursor.com",
                "Referer": "https://cursor.com/loginDeepControl",
                "Accept": "application/json",
                "User-Agent": "Mozilla/5.0 Cursor/1.0",
            ]
        )
        guard (200..<300).contains(auth.status) else {
            let body = String(data: auth.data, encoding: .utf8) ?? ""
            throw CursorAuthError.probeFailed("兑换授权失败 HTTP \(auth.status) \(body.prefix(180))")
        }

        let pollURL = URL(string: "https://api2.cursor.sh/auth/poll?uuid=\(uuid)&verifier=\(verifier)")!
        for _ in 0..<60 {
            let poll = try await HTTPClient.get(pollURL, headers: [
                "Accept": "application/json",
                "User-Agent": "Mozilla/5.0 Cursor/1.0",
            ])
            if poll.status == 404 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            if poll.status == 200, let json = JSONValue.object(poll.data) {
                let access = JSONValue.string(json["accessToken"]) ?? JSONValue.string(json["access_token"])
                let refresh = JSONValue.string(json["refreshToken"]) ?? JSONValue.string(json["refresh_token"])
                if let access, !access.isEmpty, let refresh, !refresh.isEmpty {
                    return Session(accessToken: access, refreshToken: refresh, email: nil)
                }
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw CursorAuthError.probeFailed("兑换超时。网页 Token 可能无法换成 Cursor App 会话")
    }

    private static func pkce() throws -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CursorAuthError.probeFailed("无法生成 PKCE")
        }
        let verifier = Data(bytes).base64URL
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URL
        return (verifier, challenge)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
