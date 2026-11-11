import AppKit
import CoreText
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem!
    private let hotKeyManager = HotKeyManager()
    private let hudController = HUDController()
    private let widthPreviewController = WidthPreviewController()
    private let textPreviewController = TextPreviewController()
    private lazy var overlayManager = OverlayManager(appState: appState, hudController: hudController, widthPreviewController: widthPreviewController, textPreviewController: textPreviewController)
    private var settingsWindowController: NSWindowController?
    private var interactiveModeItem: NSMenuItem!
    private var clearOnDisableItem: NSMenuItem!
    private var showAlwaysTipItem: NSMenuItem!
    private var defaultToolMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundledFonts()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(for: appState.mode)

        let menu = NSMenu()

        interactiveModeItem = NSMenuItem(title: "Enable Interactive Mode", action: #selector(toggleInteractiveMode), keyEquivalent: "")
        interactiveModeItem.target = self
        interactiveModeItem.state = appState.interactiveModeEnabled ? .on : .off
        menu.addItem(interactiveModeItem)

        clearOnDisableItem = NSMenuItem(title: "Clear Drawings When Disabled", action: #selector(toggleClearOnDisable), keyEquivalent: "")
        clearOnDisableItem.target = self
        clearOnDisableItem.state = appState.clearOnDisable ? .on : .off
        menu.addItem(clearOnDisableItem)

        showAlwaysTipItem = NSMenuItem(title: "Always Show Tool Tip", action: #selector(toggleAlwaysTip), keyEquivalent: "")
        showAlwaysTipItem.target = self
        showAlwaysTipItem.state = appState.showAlwaysTip ? .on : .off
        menu.addItem(showAlwaysTipItem)

        let defaultToolItem = NSMenuItem(title: "Default Tool", action: nil, keyEquivalent: "")
        defaultToolMenu = NSMenu()
        let storedPreference = UserDefaults.standard.string(forKey: "defaultToolPreference") ?? "pen"
        let lastUsedItem = NSMenuItem(title: "Last Used Tool", action: #selector(selectDefaultToolPreference(_:)), keyEquivalent: "")
        lastUsedItem.target = self
        lastUsedItem.representedObject = "lastUsed"
        lastUsedItem.state = storedPreference == "lastUsed" ? .on : .off
        defaultToolMenu.addItem(lastUsedItem)
        defaultToolMenu.addItem(.separator())
        for tool in ToolType.allCases {
            let item = NSMenuItem(title: tool.displayName, action: #selector(selectDefaultToolPreference(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tool.rawValue
            item.state = storedPreference == tool.rawValue ? .on : .off
            defaultToolMenu.addItem(item)
        }
        defaultToolItem.submenu = defaultToolMenu
        menu.addItem(defaultToolItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusItem.menu = menu

        hotKeyManager.onTrigger = { [weak self] in
            guard let self else { return }
            self.changeMode(to: self.appState.nextMode())
        }
        appState.setMode = { [weak self] mode in self?.changeMode(to: mode) }
        registerStoredShortcut()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(forName: .shortcutDidChange, object: nil, queue: .main) { [weak self] note in
            guard let keyCode = note.userInfo?["keyCode"] as? UInt32,
                  let modifiers = note.userInfo?["modifiers"] as? UInt32 else { return }
            self?.hotKeyManager.register(keyCode: keyCode, carbonModifiers: modifiers)
        }
        NotificationCenter.default.addObserver(forName: .shortcutRecordingChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, let isRecording = note.userInfo?["isRecording"] as? Bool else { return }
            // Don't let the (still-registered) old shortcut cycle modes out from under the user
            // while they're mid-recording a replacement.
            if isRecording {
                self.hotKeyManager.unregister()
            } else {
                self.registerStoredShortcut()
            }
        }
    }

    @objc private func openSettings() {
        let hosting: NSHostingController<SettingsView>
        if let existing = settingsWindowController?.contentViewController as? NSHostingController<SettingsView> {
            hosting = existing
        } else {
            hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Annotate Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)

            // NSHostingController.sizingOptions (.preferredContentSize) crashes when paired with a
            // Form-based SwiftUI view hosted directly in a plain NSWindow — known bad combination.
            // Track size manually instead: force layout, read the real fitting size, resize the
            // window to match, and keep doing so whenever the content's own size changes (e.g. a
            // toggle reveals another row).
            hosting.view.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: hosting.view, queue: .main) { [weak window, weak view = hosting.view] _ in
                guard let window, let view else { return }
                window.setContentSize(view.fittingSize)
            }
        }
        NSApp.activate()
        hosting.view.layoutSubtreeIfNeeded()
        settingsWindowController?.window?.setContentSize(hosting.view.fittingSize)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func screenParametersChanged() {
        overlayManager.rebuildForCurrentScreensIfNeeded()
    }

    @objc private func toggleInteractiveMode() {
        appState.interactiveModeEnabled.toggle()
        interactiveModeItem.state = appState.interactiveModeEnabled ? .on : .off
    }

    @objc private func toggleClearOnDisable() {
        appState.clearOnDisable.toggle()
        clearOnDisableItem.state = appState.clearOnDisable ? .on : .off
    }

    @objc private func toggleAlwaysTip() {
        appState.showAlwaysTip.toggle()
        showAlwaysTipItem.state = appState.showAlwaysTip ? .on : .off
        overlayManager.refreshCursorTip()
    }

    @objc private func selectDefaultToolPreference(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: "defaultToolPreference")
        for item in defaultToolMenu.items {
            item.state = (item.representedObject as? String == value) ? .on : .off
        }
    }

    private func changeMode(to newMode: AppMode) {
        if newMode == .interactive {
            appState.interactiveEnteredAt = Date()
        }
        if newMode == .enabled, appState.mode == .disabled {
            appState.applyDefaultToolPreference()
        }

        appState.mode = newMode
        overlayManager.applyMode(newMode)
        // After applyMode, so any in-progress text entry is committed (and then wiped) rather than orphaned.
        if newMode == .disabled, appState.clearOnDisable {
            appState.clearAll()
        }
        hudController.show(text: modeDisplayName(newMode))
        updateStatusIcon(for: newMode)
    }

    private func modeDisplayName(_ mode: AppMode) -> String {
        switch mode {
        case .disabled: return "Disabled"
        case .enabled: return "Enabled"
        case .interactive: return "Interactive"
        }
    }

    private func updateStatusIcon(for mode: AppMode) {
        let symbolName = mode == .enabled ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Annotate")
        statusItem.button?.image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
    }

    /// David Libre and Caveat (text-tool serif/handwritten styles) ship as .ttf resources in the
    /// bundle rather than relying on the user having them installed system-wide. `.process` scope
    /// means they're usable via NSFont(name:) for this run without touching Font Book.
    private func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private func registerStoredShortcut() {
        let defaults = UserDefaults.standard
        let keyCode = defaults.object(forKey: "shortcutKeyCode") as? Int ?? Int(HotKeyManager.defaultKeyCode)
        let modifiers = defaults.object(forKey: "shortcutModifiers") as? Int ?? Int(HotKeyManager.defaultModifiers)
        hotKeyManager.register(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
    }
}
