import AppKit

final class OverlayManager {
    private let appState: AppState
    private let hudController: HUDController
    private let widthPreviewController: WidthPreviewController
    private let textPreviewController: TextPreviewController
    private var windows: [OverlayWindow] = []

    init(appState: AppState, hudController: HUDController, widthPreviewController: WidthPreviewController, textPreviewController: TextPreviewController) {
        self.appState = appState
        self.hudController = hudController
        self.widthPreviewController = widthPreviewController
        self.textPreviewController = textPreviewController
        appState.contentDidChange = { [weak self] in
            self?.windows.forEach { $0.contentView?.needsDisplay = true }
        }
        // Mission Control / Launchpad / Space switches can reorder windows above ours; when we come
        // back and we're still meant to be capturing input, reassert ourselves on top.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.appState.mode == .enabled else { return }
            self.focusWindowUnderMouse()
        }
    }

    func applyMode(_ mode: AppMode) {
        if mode != .enabled {
            // Leaving Enabled: don't strand a half-typed, orphaned text field behind, and don't
            // leave a Cmd/Option temporary-select override stuck active — see
            // revertAnyActiveModifierOverride's doc comment.
            windows.forEach {
                ($0.contentView as? OverlayView)?.finishAnyActiveTextEntry()
                ($0.contentView as? OverlayView)?.revertAnyActiveModifierOverride()
            }
        }
        switch mode {
        case .disabled:
            teardown()
        case .enabled:
            if windows.isEmpty { buildWindows() }
            windows.forEach { $0.ignoresMouseEvents = false }
            focusWindowUnderMouse()
        case .interactive:
            if windows.isEmpty { buildWindows() }
            windows.forEach { $0.ignoresMouseEvents = true }
        }
        refreshCursorTip()
    }

    /// Re-evaluates the "Always Show Tool Tip" preview — called on every mode change and whenever
    /// the toggle itself flips. Any live OverlayView can do the actual work (it only reads shared
    /// appState/controllers, not per-window geometry); teardown leaves no window at all, so fall
    /// back to dismissing directly.
    func refreshCursorTip() {
        guard let view = windows.first?.contentView as? OverlayView else {
            widthPreviewController.dismiss()
            textPreviewController.dismiss()
            return
        }
        view.refreshCursorTip()
    }

    func rebuildForCurrentScreensIfNeeded() {
        guard !windows.isEmpty else { return }
        let mode = appState.mode
        teardown()
        guard mode != .disabled else { return }
        buildWindows()
        windows.forEach { $0.ignoresMouseEvents = (mode == .interactive) }
        if mode == .enabled { focusWindowUnderMouse() }
    }

    private func buildWindows() {
        windows = NSScreen.screens.map { OverlayWindow(screen: $0, appState: appState, hudController: hudController, widthPreviewController: widthPreviewController, textPreviewController: textPreviewController) }
        windows.forEach { $0.orderFront(nil) }
    }

    private func focusWindowUnderMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let target = windows.first { $0.frame.contains(mouseLocation) } ?? windows.first
        target?.makeKeyAndOrderFront(nil)
    }

    private func teardown() {
        // close() (not orderOut) cleanly resigns key/main status before the window is released.
        windows.forEach { $0.close() }
        windows = []
    }
}
