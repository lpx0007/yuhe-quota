import AppKit
import SwiftUI
@preconcurrency import UserNotifications

@main
enum YuheMain {
    static var appDelegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.contains("--status") {
            StatusCommand.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontLoader.register()
        installEditMenu()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        NSApp.setActivationPolicy(.accessory)
        StatusBarController.shared.start(store: store, settings: settings)
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await store.refresh()
        }
    }

    /// 无 Dock 的 accessory App 默认没有 Edit 菜单，Cmd+V 不会进输入框。
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum StatusCommand {
    static func run() {
        let group = DispatchGroup()
        group.enter()
        Task {
            defer { group.leave() }
            let providers: [any QuotaProvider] = [
                CursorProvider(), CodexProvider(), DeepSeekProvider(), GrokProvider(),
            ]
            await withTaskGroup(of: QuotaSnapshot.self) { g in
                for p in providers { g.addTask { await p.fetch() } }
                for await snap in g {
                    let mark = snap.error == nil ? "OK" : "ERR"
                    let extra = snap.error ?? snap.windows.map { "\($0.title) \(YuheFormat.percent($0.displayPercent))" }.joined(separator: ", ")
                    print("\(snap.provider.displayName) \(mark) \(extra)")
                }
            }
        }
        group.wait()
    }
}
