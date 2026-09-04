import Foundation

struct GLMProvider: QuotaProvider {
    let id: ProviderID = .glm

    func fetch() async -> QuotaSnapshot {
        guard let key = GLMAuth.resolveKey() else {
            return .failed(.glm, message: "未配置 GLM Coding Plan Key，请在设置中填写")
        }
        do {
            let host = GLMAuth.host
            let url = URL(string: "https://\(host)/api/monitor/usage/quota/limit")!
            let response = try await HTTPClient.get(url, headers: [
                "Authorization": "Bearer \(key)",
                "Accept": "application/json",
            ])
            if response.status == 401 || response.status == 403 {
                return .failed(.glm, message: "GLM Key 无效")
            }
            guard response.status == 200, let json = JSONValue.object(response.data) else {
                return .failed(.glm, message: "GLM 接口返回 HTTP \(response.status)")
            }
            if JSONValue.bool(json["success"]) == false {
                let msg = JSONValue.string(json["msg"]) ?? "当前 Key 没有 Coding Plan"
                return .failed(.glm, message: msg)
            }
            return map(json)
        } catch {
            return .failed(.glm, message: error.localizedDescription)
        }
    }

    private func map(_ json: [String: Any]) -> QuotaSnapshot {
        let data = JSONValue.dict(json["data"]) ?? json
        let plan = JSONValue.string(data["planName"])
            ?? JSONValue.string(data["plan"])
            ?? JSONValue.string(data["packageName"])
        let limits = JSONValue.array(data["limits"]) ?? []
        var windows: [QuotaWindow] = []
        for (idx, item) in limits.enumerated() {
            guard let dict = JSONValue.dict(item) else { continue }
            let type = (JSONValue.string(dict["type"]) ?? JSONValue.string(dict["limitType"]) ?? "").uppercased()
            if type.contains("TIME") { continue }
            let percent = usedPercent(dict)
            let reset = resetDate(dict)
            let title = windowTitle(dict, index: idx)
            windows.append(QuotaWindow(
                id: "lim-\(idx)",
                title: title,
                usedPercent: percent,
                resetsAt: reset,
                resetLabel: reset.map { "重置 \(YuheFormat.resetDate($0))" } ?? "",
                showRemaining: true
            ))
        }
        if windows.isEmpty {
            return .failed(.glm, message: "未返回 Coding Plan 额度")
        }
        return QuotaSnapshot(
            id: .glm,
            plan: YuheFormat.planTag(plan),
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

    private func usedPercent(_ dict: [String: Any]) -> Double {
        if let usage = JSONValue.double(dict["usage"]), usage > 0 {
            let current = JSONValue.double(dict["currentValue"]) ?? JSONValue.double(dict["used"])
            if let current { return min(100, max(0, current / usage * 100)) }
            if let remaining = JSONValue.double(dict["remaining"]) {
                return min(100, max(0, (usage - remaining) / usage * 100))
            }
        }
        if let p = JSONValue.double(dict["percentage"]) {
            return p > 1 ? min(100, p) : p * 100
        }
        return 0
    }

    private func windowTitle(_ dict: [String: Any], index: Int) -> String {
        let name = JSONValue.string(dict["name"]) ?? JSONValue.string(dict["label"])
        if let name, !name.isEmpty { return name }
        let unit = (JSONValue.string(dict["durationUnit"]) ?? JSONValue.string(dict["unit"]) ?? "").lowercased()
        let n = JSONValue.double(dict["duration"]) ?? JSONValue.double(dict["window"]) ?? 0
        if unit.contains("hour") && n == 5 { return "5小时额度" }
        if unit.contains("day") && (n == 7 || n == 1) { return n == 7 ? "周额度" : "日额度" }
        return index == 0 ? "5小时额度" : "周额度"
    }

    private func resetDate(_ dict: [String: Any]) -> Date? {
        if let ms = JSONValue.double(dict["nextResetTime"]), ms > 0 {
            return Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000 : ms)
        }
        return nil
    }
}

enum GLMAuth {
    static var host: String {
        if let env = ProcessInfo.processInfo.environment["Z_AI_API_HOST"], !env.isEmpty {
            return env.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        }
        return "open.bigmodel.cn"
    }

    static func resolveKey() -> String? {
        if let saved = KeychainStore.loadGLMKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            return saved
        }
        let env = ProcessInfo.processInfo.environment
        for name in ["Z_AI_API_KEY", "BIGMODEL_API_KEY", "ZHIPU_API_KEY", "ZHIPUAI_API_KEY", "GLM_API_KEY"] {
            if let v = env[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for rel in [".coding-relay/glm-api-key", ".config/bigmodel/api_key", ".config/zhipu/api_key"] {
            let url = home.appendingPathComponent(rel)
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { return key }
            }
        }
        return nil
    }
}
