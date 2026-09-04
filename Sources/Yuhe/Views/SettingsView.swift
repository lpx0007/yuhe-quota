import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updater = AppUpdate.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YUHE · 设置")
                    .font(.custom("Tektur", size: 15))
                    .foregroundStyle(YuheTheme.cyan)
                    .kerning(3)
                    .shadow(color: YuheTheme.cyan.opacity(0.45), radius: 8)
                Spacer()
                Button("返回") { backToHUD() }
                    .buttonStyle(.plain)
                    .font(.custom("Share Tech Mono", size: 11))
                    .foregroundStyle(YuheTheme.cyan)
                    .kerning(2)
            }

            section("显示") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    visibilityRow("Cursor", brand: YuheTheme.accent(for: .cursor), isOn: $settings.cursorEnabled)
                    visibilityRow("Codex", brand: YuheTheme.accent(for: .codex), isOn: $settings.codexEnabled)
                    visibilityRow("DeepSeek", brand: YuheTheme.accent(for: .deepseek), isOn: $settings.deepseekEnabled)
                    visibilityRow("Grok", brand: YuheTheme.accent(for: .grok), isOn: $settings.grokEnabled)
                }
            }

            section("更新") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前 \(AppUpdate.currentVersion)")
                            .font(.custom("Share Tech Mono", size: 10))
                            .foregroundStyle(YuheTheme.ink)
                        Text(updater.status)
                            .font(.custom("Share Tech Mono", size: 9))
                            .foregroundStyle(updater.available ? YuheTheme.amber : YuheTheme.mute)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(updater.busy ? "…" : (updater.available ? "安装" : "检查")) {
                        Task {
                            if updater.available {
                                await updater.install()
                            } else {
                                await updater.check()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(updater.busy)
                    .font(.custom("Share Tech Mono", size: 11))
                    .foregroundStyle(YuheTheme.void)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(updater.available ? YuheTheme.amber : YuheTheme.cyan)
                }
            }

            section("同步 / 预警") {
                HStack(spacing: 6) {
                    ForEach([1, 2, 5, 15], id: \.self) { minutes in
                        intervalChip(minutes)
                    }
                }
                nodeRow("登录时启动", brand: YuheTheme.cyan, isOn: $settings.launchAtLogin)
                nodeRow("用量 ≥ 80% 弹出提醒", brand: YuheTheme.amber, isOn: $settings.notify80)
                nodeRow("用量 ≥ 90% 弹出提醒", brand: YuheTheme.rose, isOn: $settings.notify90)
            }

            section("Cursor 一键换号") {
                CursorSwitchSection(store: store)
            }

            section("DeepSeek") {
                HStack(spacing: 8) {
                    SecureField("sk-…", text: $settings.deepseekKeyDraft)
                        .textFieldStyle(.plain)
                        .font(.custom("Share Tech Mono", size: 11))
                        .foregroundStyle(YuheTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .overlay(Rectangle().stroke(YuheTheme.line, lineWidth: 1))
                    Button("保存") {
                        settings.saveDeepSeekKey()
                        backToHUD()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Share Tech Mono", size: 11))
                    .foregroundStyle(YuheTheme.void)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(YuheTheme.cyan)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(width: 368, alignment: .top)
    }

    private func backToHUD() {
        store.showSettings = false
        Task { await store.refresh() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.custom("Share Tech Mono", size: 10))
                .foregroundStyle(YuheTheme.cyan.opacity(0.85))
                .kerning(2)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(8)
            .overlay(Rectangle().stroke(YuheTheme.line, lineWidth: 1))
            .background(YuheTheme.cyan.opacity(0.04))
        }
    }

    private func visibilityRow(_ title: String, brand: Color, isOn: Binding<Bool>) -> some View {
        Button {
            if isOn.wrappedValue, settings.enabledProviders.count <= 1 { return }
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(brand.opacity(0.7), lineWidth: 1)
                        .frame(width: 14, height: 14)
                    if isOn.wrappedValue {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(brand)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(title)
                    .font(.custom("Share Tech Mono", size: 12))
                    .foregroundStyle(YuheTheme.ink)
                Spacer()
                Text(isOn.wrappedValue ? "显示" : "隐藏")
                    .font(.custom("Share Tech Mono", size: 10))
                    .foregroundStyle(isOn.wrappedValue ? brand : YuheTheme.mute)
                    .kerning(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isOn.wrappedValue && settings.enabledProviders.count <= 1 ? 0.55 : 1)
    }

    private func nodeRow(_ title: String, brand: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(brand.opacity(0.7), lineWidth: 1)
                        .frame(width: 14, height: 14)
                    if isOn.wrappedValue {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(brand)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(title)
                    .font(.custom("Share Tech Mono", size: 12))
                    .foregroundStyle(YuheTheme.ink)
                Spacer()
                Text(isOn.wrappedValue ? "ON" : "OFF")
                    .font(.custom("Share Tech Mono", size: 10))
                    .foregroundStyle(isOn.wrappedValue ? brand : YuheTheme.mute)
                    .kerning(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func intervalChip(_ minutes: Int) -> some View {
        let selected = settings.refreshMinutes == minutes
        return Button {
            settings.refreshMinutes = minutes
            store.rebuildTimer()
        } label: {
            Text("\(minutes) 分钟")
                .font(.custom("Share Tech Mono", size: 11))
                .foregroundStyle(selected ? YuheTheme.void : YuheTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? YuheTheme.cyan : Color.white.opacity(0.06))
                .overlay(Rectangle().stroke(selected ? YuheTheme.cyan : YuheTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CursorSwitchSection: View {
    @ObservedObject var store: UsageStore
    @State private var tokenDraft = ""
    @State private var file = CursorSessionStore.load()
    @State private var queryID = CursorSessionStore.currentQueryAccountID()
    @State private var status = "贴网页 Token，兑换成 Cursor App 会话后写入并重启。和 Cockpit 同一套接口。"
    @State private var busy = false
    @State private var ok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status)
                .font(.custom("Share Tech Mono", size: 9))
                .foregroundStyle(ok ? YuheTheme.cyan : YuheTheme.mute)
                .lineLimit(2)

            ZStack(alignment: .topLeading) {
                if tokenDraft.isEmpty {
                    Text("完整 Token：user_xxx%3A%3AeyJ...")
                        .font(.custom("Share Tech Mono", size: 10))
                        .foregroundStyle(YuheTheme.mute)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $tokenDraft)
                    .font(.custom("Share Tech Mono", size: 10))
                    .foregroundStyle(YuheTheme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 72)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
            .background(Color.white.opacity(0.06))
            .overlay(Rectangle().stroke(YuheTheme.line, lineWidth: 1))

            HStack {
                Text(CursorIDEAuth.isRunning ? "会先退出再打开 Cursor" : "写入后打开 Cursor")
                    .font(.custom("Share Tech Mono", size: 9))
                    .foregroundStyle(YuheTheme.mute)
                Spacer()
                Button(busy ? "换号中" : "一键换号") {
                    Task { await switchIDE() }
                }
                .buttonStyle(.plain)
                .disabled(busy || tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.custom("Share Tech Mono", size: 11))
                .foregroundStyle(YuheTheme.void)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(YuheTheme.cyan)
            }

            Button("改回 Cursor 当前登录") {
                CursorSessionStore.selectQuery(id: nil)
                queryID = CursorSessionStore.currentQueryAccountID()
                status = "已改回 Cursor 当前号"
                ok = true
                Task { await store.refresh() }
            }
            .buttonStyle(.plain)
            .font(.custom("Share Tech Mono", size: 10))
            .foregroundStyle(YuheTheme.cyan)

            Group {
                if file.accounts.count > 4 {
                    ScrollView(.vertical, showsIndicators: false) {
                        accountList
                    }
                    .frame(maxHeight: 88)
                } else {
                    accountList
                }
            }
        }
    }

    private var accountList: some View {
        VStack(spacing: 4) {
            ForEach(file.accounts) { account in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.email ?? account.id)
                            .font(.custom("Share Tech Mono", size: 10))
                            .foregroundStyle(YuheTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(account.canRestoreIDE ? "可写入 App" : "仅查询")
                            .font(.custom("Share Tech Mono", size: 8))
                            .foregroundStyle(account.canRestoreIDE ? YuheTheme.cyan : YuheTheme.mute)
                    }
                    Spacer()
                    if account.canRestoreIDE {
                        Button("写入") {
                            Task { await restoreSaved(account) }
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .font(.custom("Share Tech Mono", size: 9))
                        .foregroundStyle(YuheTheme.amber)
                    }
                    Button("删") {
                        CursorSessionStore.remove(id: account.id)
                        file = CursorSessionStore.load()
                        queryID = CursorSessionStore.currentQueryAccountID()
                    }
                    .buttonStyle(.plain)
                    .font(.custom("Share Tech Mono", size: 9))
                    .foregroundStyle(YuheTheme.rose)
                }
            }
        }
    }

    private func switchIDE() async {
        busy = true
        ok = false
        status = "正在兑换 Cursor App 会话…"
        do {
            let account = try await CursorSessionStore.importAndSwitchIDE(tokenDraft)
            file = CursorSessionStore.load()
            queryID = CursorSessionStore.currentQueryAccountID()
            tokenDraft = ""
            status = "Cursor 已换成 \(account.email ?? account.id)"
            ok = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await store.refresh()
        } catch {
            status = error.localizedDescription
            ok = false
        }
        busy = false
    }

    private func restoreSaved(_ account: CursorAccount) async {
        busy = true
        ok = false
        status = CursorIDEAuth.isRunning ? "正在退出 Cursor 并写入…" : "正在写入 Cursor…"
        do {
            try await CursorSessionStore.restoreIDE(account)
            file = CursorSessionStore.load()
            queryID = CursorSessionStore.currentQueryAccountID()
            status = "Cursor 已换成 \(account.email ?? account.id)"
            ok = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await store.refresh()
        } catch {
            status = error.localizedDescription
            ok = false
        }
        busy = false
    }
}
