import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updater = AppUpdate.shared
    @Environment(\.yuhe) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(theme.skin == .blush ? "Yuhe · 设置" : "YUHE · 设置")
                    .font(theme.display(15))
                    .foregroundStyle(theme.accent)
                    .kerning(theme.skin == .mech ? 3 : theme.titleKerning)
                    .shadow(color: theme.glow ? theme.accent.opacity(0.45) : .clear, radius: 8)
                Spacer()
                Button("返回") { backToHUD() }
                    .buttonStyle(.plain)
                    .font(theme.mono(11, weight: theme.skin == .apple ? .medium : .regular))
                    .foregroundStyle(theme.accent)
                    .kerning(theme.skin == .mech ? 2 : 0)
            }

            section("皮肤") {
                HStack(spacing: 6) {
                    ForEach(AppSkin.allCases) { skin in
                        skinChip(skin)
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                section("显示 / 顺序", fill: true) {
                    ForEach(Array(settings.providerOrder.enumerated()), id: \.element) { idx, id in
                        orderRow(id, index: idx)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 8) {
                    section("更新") {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("v\(AppUpdate.currentVersion)")
                                    .font(theme.mono(10))
                                    .foregroundStyle(theme.ink)
                                Text(updater.status)
                                    .font(theme.mono(8))
                                    .foregroundStyle(updater.available ? theme.amber : theme.mute)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
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
                            .font(theme.mono(11, weight: .medium))
                            .foregroundStyle(theme.buttonInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .yuheChrome(
                                fill: updater.available ? theme.amber : theme.accent,
                                stroke: updater.available ? theme.amber : theme.accent
                            )
                        }
                    }
                    section("预警", fill: true) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach([1, 2, 5, 15], id: \.self) { minutes in
                                intervalChip(minutes)
                            }
                        }
                        nodeRow("登录启动", brand: theme.accent, isOn: $settings.launchAtLogin)
                        nodeRow("80% 提醒", brand: theme.amber, isOn: $settings.notify80)
                        nodeRow("90% 提醒", brand: theme.rose, isOn: $settings.notify90)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)

            section("Cursor 一键换号") {
                CursorSwitchSection(store: store)
            }

            section("GLM Coding Plan Key") {
                HStack(spacing: 8) {
                    SecureField("国内 ZHIPU / GLM Key", text: $settings.glmKeyDraft)
                        .textFieldStyle(.plain)
                        .font(theme.mono(11))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .yuheChrome(fill: theme.fieldFill, stroke: theme.line)
                    Button("保存") {
                        settings.saveGLMKey()
                        backToHUD()
                    }
                    .buttonStyle(.plain)
                    .font(theme.mono(11, weight: .medium))
                    .foregroundStyle(theme.buttonInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .yuheChrome(fill: theme.accent, stroke: theme.accent)
                }
            }

            section("DeepSeek") {
                HStack(spacing: 8) {
                    SecureField("sk-…", text: $settings.deepseekKeyDraft)
                        .textFieldStyle(.plain)
                        .font(theme.mono(11))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .yuheChrome(fill: theme.fieldFill, stroke: theme.line)
                    Button("保存") {
                        settings.saveDeepSeekKey()
                        backToHUD()
                    }
                    .buttonStyle(.plain)
                    .font(theme.mono(11, weight: .medium))
                    .foregroundStyle(theme.buttonInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .yuheChrome(fill: theme.accent, stroke: theme.accent)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func backToHUD() {
        store.showSettings = false
        Task { await store.refresh() }
    }

    private func section<Content: View>(_ title: String, fill: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.sectionTitle(title))
                .font(theme.mono(10, weight: theme.skin == .apple ? .medium : .regular))
                .foregroundStyle(theme.accent.opacity(0.85))
                .kerning(theme.skin == .mech ? 2 : 0)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .top)
            .background(theme.cardFill)
            .clipShape(theme.shape(.card))
            .overlay(theme.shape(.card).stroke(theme.line, lineWidth: theme.strokeWidth))
        }
        .frame(maxHeight: fill ? .infinity : nil, alignment: .top)
    }

    private func skinChip(_ skin: AppSkin) -> some View {
        let selected = settings.skin == skin
        return Button {
            settings.skin = skin
        } label: {
            Text(skin.title)
                .font(theme.mono(10, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? theme.buttonInk : theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .yuheChrome(
                    fill: selected ? theme.accent : theme.fieldFill,
                    stroke: selected ? theme.accent : theme.line
                )
        }
        .buttonStyle(.plain)
    }

    private func binding(for id: ProviderID) -> Binding<Bool> {
        switch id {
        case .cursor: $settings.cursorEnabled
        case .codex: $settings.codexEnabled
        case .claude: $settings.claudeEnabled
        case .kimi: $settings.kimiEnabled
        case .glm: $settings.glmEnabled
        case .deepseek: $settings.deepseekEnabled
        case .grok: $settings.grokEnabled
        }
    }

    private func orderRow(_ id: ProviderID, index: Int) -> some View {
        let on = binding(for: id)
        let brand = theme.accent(for: id)
        return HStack(spacing: 8) {
            Button {
                if on.wrappedValue, settings.enabledProviders.count <= 1 { return }
                on.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    tick(on: on.wrappedValue, brand: brand)
                    Text(id.displayName.capitalized)
                        .font(theme.mono(11))
                        .foregroundStyle(theme.ink)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .opacity(on.wrappedValue && settings.enabledProviders.count <= 1 ? 0.55 : 1)

            VStack(spacing: 0) {
                Button { settings.moveProvider(id: id, up: true) } label: {
                    Text("▲").font(.system(size: 8)).foregroundStyle(index == 0 ? theme.mute : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                Button { settings.moveProvider(id: id, up: false) } label: {
                    Text("▼").font(.system(size: 8)).foregroundStyle(index == settings.providerOrder.count - 1 ? theme.mute : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(index == settings.providerOrder.count - 1)
            }
        }
    }

    private func nodeRow(_ title: String, brand: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                tick(on: isOn.wrappedValue, brand: brand)
                Text(title)
                    .font(theme.mono(12))
                    .foregroundStyle(theme.ink)
                Spacer()
                Text(isOn.wrappedValue ? "ON" : "OFF")
                    .font(theme.mono(10))
                    .foregroundStyle(isOn.wrappedValue ? brand : theme.mute)
                    .kerning(theme.skin == .mech ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tick(on: Bool, brand: Color) -> some View {
        ZStack {
            theme.shape(.tick)
                .stroke(brand.opacity(0.7), lineWidth: 1)
                .frame(width: 14, height: 14)
            if on {
                theme.shape(.tick)
                    .fill(brand)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func intervalChip(_ minutes: Int) -> some View {
        let selected = settings.refreshMinutes == minutes
        return Button {
            settings.refreshMinutes = minutes
            store.rebuildTimer()
        } label: {
            Text("\(minutes)分")
                .font(theme.mono(10, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? theme.buttonInk : theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .yuheChrome(
                    fill: selected ? theme.accent : theme.fieldFill,
                    stroke: selected ? theme.accent : theme.line
                )
        }
        .buttonStyle(.plain)
    }
}

struct CursorSwitchSection: View {
    @ObservedObject var store: UsageStore
    @Environment(\.yuhe) private var theme
    @State private var tokenDraft = ""
    @State private var file = CursorSessionStore.load()
    @State private var queryID = CursorSessionStore.currentQueryAccountID()
    @State private var status = "贴网页 Token，兑换成 Cursor App 会话后写入并重启。和 Cockpit 同一套接口。"
    @State private var busy = false
    @State private var ok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(status)
                .font(theme.mono(9))
                .foregroundStyle(ok ? theme.accent : theme.mute)
                .lineLimit(2)

            ZStack(alignment: .topLeading) {
                if tokenDraft.isEmpty {
                    Text("完整 Token：user_xxx%3A%3AeyJ...")
                        .font(theme.mono(10))
                        .foregroundStyle(theme.mute)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $tokenDraft)
                    .font(theme.mono(10))
                    .foregroundStyle(theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 36, maxHeight: 36)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
            .yuheChrome(fill: theme.fieldFill, stroke: theme.line)

            HStack {
                Text(CursorIDEAuth.isRunning ? "会先退出再打开 Cursor" : "写入后打开 Cursor")
                    .font(theme.mono(9))
                    .foregroundStyle(theme.mute)
                Spacer()
                Button(busy ? "换号中" : "一键换号") {
                    Task { await switchIDE() }
                }
                .buttonStyle(.plain)
                .disabled(busy || tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(theme.mono(11, weight: .medium))
                .foregroundStyle(theme.buttonInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .yuheChrome(fill: theme.accent, stroke: theme.accent)
            }

            Button("改回 Cursor 当前登录") {
                CursorSessionStore.selectQuery(id: nil)
                queryID = CursorSessionStore.currentQueryAccountID()
                status = "已改回 Cursor 当前号"
                ok = true
                Task { await store.refresh() }
            }
            .buttonStyle(.plain)
            .font(theme.mono(10))
            .foregroundStyle(theme.accent)

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
                            .font(theme.mono(10))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(account.canRestoreIDE ? "可写入 App" : "仅查询")
                            .font(theme.mono(8))
                            .foregroundStyle(account.canRestoreIDE ? theme.accent : theme.mute)
                    }
                    Spacer()
                    if account.canRestoreIDE {
                        Button("写入") {
                            Task { await restoreSaved(account) }
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .font(theme.mono(9))
                        .foregroundStyle(theme.amber)
                    }
                    Button("删") {
                        CursorSessionStore.remove(id: account.id)
                        file = CursorSessionStore.load()
                        queryID = CursorSessionStore.currentQueryAccountID()
                    }
                    .buttonStyle(.plain)
                    .font(theme.mono(9))
                    .foregroundStyle(theme.rose)
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
