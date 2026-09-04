import AppKit
import Foundation

@MainActor
final class AppUpdate: ObservableObject {
    static let shared = AppUpdate()
    static let githubRepo = "lpx0007/yuhe-quota"

    @Published var status = "未检查"
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var busy = false
    @Published var available = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check(quiet: Bool = false) async {
        if busy { return }
        busy = true
        if !quiet { status = "正在检查…" }
        defer { busy = false }
        do {
            let url = URL(string: "https://api.github.com/repos/\(Self.githubRepo)/releases/latest")!
            let response = try await HTTPClient.get(url, headers: [
                "Accept": "application/vnd.github+json",
                "User-Agent": "Yuhe/\(Self.currentVersion)",
            ])
            guard response.status == 200, let json = JSONValue.object(response.data) else {
                status = response.status == 404 ? "还没有发布更新源" : "检查失败 HTTP \(response.status)"
                available = false
                return
            }
            let tag = (JSONValue.string(json["tag_name"]) ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let assets = JSONValue.array(json["assets"]) ?? []
            var zipURL: URL?
            for asset in assets {
                guard let dict = JSONValue.dict(asset) else { continue }
                let name = JSONValue.string(dict["name"]) ?? ""
                if name.hasSuffix(".zip"), name.contains("macos") || name.contains("余核") {
                    if let raw = JSONValue.string(dict["browser_download_url"]) {
                        zipURL = URL(string: raw)
                        break
                    }
                }
            }
            latestVersion = tag
            downloadURL = zipURL
            if isNewer(tag, than: Self.currentVersion) {
                available = true
                status = "发现 \(tag)"
            } else {
                available = false
                status = "已是最新 \(Self.currentVersion)"
            }
        } catch {
            available = false
            status = error.localizedDescription
        }
    }

    func install() async {
        guard let latestVersion, let downloadURL else {
            await check()
            return
        }
        busy = true
        status = "正在下载 \(latestVersion)…"
        defer { busy = false }
        do {
            let (tmpURL, response) = try await URLSession.shared.download(from: downloadURL)
            let http = response as? HTTPURLResponse
            guard http?.statusCode == 200 else {
                status = "下载失败 HTTP \(http?.statusCode ?? 0)"
                return
            }
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("yuhe-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            if FileManager.default.fileExists(atPath: zip.path) {
                try FileManager.default.removeItem(at: zip)
            }
            try FileManager.default.moveItem(at: tmpURL, to: zip)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, work.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                status = "解压失败"
                return
            }

            guard let newApp = findApp(in: work) else {
                status = "压缩包里没有 余核.app"
                return
            }
            let dest = Bundle.main.bundleURL
            guard dest.pathExtension == "app" else {
                status = "当前不是安装好的 App，无法覆盖更新"
                return
            }

            status = "正在安装…"
            let script = """
            sleep 1
            /usr/bin/ditto --rsrc "\(newApp.path)" "\(dest.path)"
            /usr/bin/xattr -cr "\(dest.path)"
            /usr/bin/codesign --force --deep --sign - "\(dest.path)" >/dev/null 2>&1 || true
            open "\(dest.path)"
            """
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-lc", script]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            status = error.localizedDescription
        }
    }

    private func findApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        if let direct = items.first(where: { $0.pathExtension == "app" }) { return direct }
        for item in items where item.hasDirectoryPath {
            if let nested = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil),
               let app = nested.first(where: { $0.pathExtension == "app" }) {
                return app
            }
        }
        return nil
    }

    private func isNewer(_ latest: String, than current: String) -> Bool {
        let a = latest.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
