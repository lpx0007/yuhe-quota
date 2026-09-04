import Foundation

struct DeepSeekProvider: QuotaProvider {
    let id: ProviderID = .deepseek

    func fetch() async -> QuotaSnapshot {
        guard let key = DeepSeekAuth.resolveKey() else {
            return .failed(.deepseek, message: "未配置 API Key，请在设置中填写")
        }
        do {
            let url = URL(string: "https://api.deepseek.com/user/balance")!
            let response = try await HTTPClient.get(url, headers: [
                "Authorization": "Bearer \(key)",
                "Accept": "application/json",
            ])
            if response.status == 401 || response.status == 403 {
                return .failed(.deepseek, message: "API Key 无效")
            }
            guard response.status == 200, let json = JSONValue.object(response.data) else {
                return .failed(.deepseek, message: "DeepSeek 接口返回 HTTP \(response.status)")
            }
            return map(json)
        } catch {
            return .failed(.deepseek, message: error.localizedDescription)
        }
    }

    private func map(_ json: [String: Any]) -> QuotaSnapshot {
        let available = JSONValue.bool(json["is_available"])
        let infos = JSONValue.array(json["balance_infos"]) ?? []
        var cny: [String: Any]?
        var usd: [String: Any]?
        for item in infos {
            guard let dict = JSONValue.dict(item) else { continue }
            switch JSONValue.string(dict["currency"])?.uppercased() {
            case "CNY": cny = dict
            case "USD": usd = dict
            default: break
            }
        }
        let primary = cny ?? usd
        let currency = cny != nil ? "CNY" : "USD"
        let format: (String?) -> String = { raw in
            guard let raw else { return currency == "CNY" ? "¥0.00" : "$0.00" }
            return currency == "CNY" ? YuheFormat.yuan(raw) : YuheFormat.usd(raw)
        }

        let total = format(JSONValue.string(primary?["total_balance"]))
        let granted = format(JSONValue.string(primary?["granted_balance"]))
        let topped = format(JSONValue.string(primary?["topped_up_balance"]))

        var totals = [
            QuotaTotal(id: "topped", label: "充值余额", value: topped),
            QuotaTotal(id: "granted", label: "赠送余额", value: granted),
        ]
        if let other = (cny != nil ? usd : nil), let otherTotal = JSONValue.string(other["total_balance"]) {
            totals.append(QuotaTotal(id: "usd", label: "美元余额", value: YuheFormat.usd(otherTotal)))
        }

        return QuotaSnapshot(
            id: .deepseek,
            plan: "API",
            identity: nil,
            available: available,
            headline: total,
            headlineSecondary: available == false ? "余额不可用于调用" : "可用",
            windows: [],
            products: [],
            totals: totals,
            fetchedAt: Date(),
            error: nil,
            warning: available == false ? "余额不可用于调用" : nil,
            isStale: false
        )
    }
}

enum DeepSeekAuth {
    static func resolveKey() -> String? {
        if let key = KeychainStore.loadDeepSeekKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? ProcessInfo.processInfo.environment["DEEPSEEK_KEY"]
        let trimmed = env?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
