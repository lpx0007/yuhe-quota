import AppKit
import Combine
import SwiftUI

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hosting: NSHostingView<HUDView>?
    private var store: UsageStore?
    private var settings: AppSettings?
    private var bag = Set<AnyCancellable>()
    private var settingsWatch: AnyCancellable?
    private var globalMouse: Any?
    private var localKeys: Any?

    func start(store: UsageStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "余核"
            item.button?.target = self
            item.button?.action = #selector(toggleHUD)
            item.button?.sendAction(on: [.leftMouseUp])
            statusItem = item
        }
        updateIcon()

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.resizePanelIfNeeded()
            }
            .store(in: &bag)
        settingsWatch = store.$showSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.resizePanelIfNeeded() }
            }
    }

    @objc private func toggleHUD() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        guard let store, let settings else { return }
        let hud = HUDView(store: store, settings: settings)
        let view: NSHostingView<HUDView>
        if let hosting {
            hosting.rootView = hud
            view = hosting
        } else {
            let created = NSHostingView(rootView: hud)
            created.sizingOptions = [.intrinsicContentSize]
            created.wantsLayer = true
            created.layer?.backgroundColor = NSColor.clear.cgColor
            hosting = created
            view = created
        }

        let panel = self.panel ?? makePanel()
        panel.contentView = view
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        resizePanelIfNeeded()
        positionPanel()
        installMonitors()
        Task { await store.refresh() }
    }

    private func hide() {
        removeMonitors()
        panel?.orderOut(nil)
        store?.showSettings = false
    }

    private func makePanel() -> NSPanel {
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 368, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.sharingType = .readOnly
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func updateIcon() {
        statusItem?.button?.image = ReactorIcon.image(level: store?.worstLevel ?? .ok)
    }

    private func resizePanelIfNeeded() {
        guard let panel, panel.isVisible, let hosting else { return }
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        size.width = 368
        if !size.height.isFinite || size.height < 80 { size.height = 200 }
        panel.setContentSize(size)
        positionPanel()
    }

    private func positionPanel() {
        guard let panel, let button = statusItem?.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        var x = buttonRect.midX - panel.frame.width / 2
        let gap: CGFloat = 6
        var y = buttonRect.minY - panel.frame.height - gap
        if let screen {
            let maxX = screen.frame.maxX - 8
            let minX = screen.frame.minX + 8
            x = min(max(x, minX), max(minX, maxX - panel.frame.width))
            if y < screen.frame.minY + 8 {
                y = buttonRect.maxY + gap
            }
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installMonitors() {
        removeMonitors()
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "v" {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    return nil
                }
                if chars == "c" {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    return nil
                }
                if chars == "x" {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    return nil
                }
                if chars == "a" {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    return nil
                }
            }
            if event.keyCode == 53 {
                Task { @MainActor in self?.hide() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMouse {
            NSEvent.removeMonitor(globalMouse)
            self.globalMouse = nil
        }
        if let localKeys {
            NSEvent.removeMonitor(localKeys)
            self.localKeys = nil
        }
    }
}
