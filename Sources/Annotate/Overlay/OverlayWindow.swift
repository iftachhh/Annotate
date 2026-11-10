import AppKit
import CoreGraphics

/// A non-activating panel: it can become key (so mouse + keyboard reach OverlayView)
/// without ever making our app the frontmost application, so whatever app the user
/// was in keeps its focus the entire time this overlay is up.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen, appState: AppState, hudController: HUDController, widthPreviewController: WidthPreviewController, textPreviewController: TextPreviewController) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.maxCoveringWindowLevel
        // .fullScreenAuxiliary specifically means "auxiliary palette that coexists with fullscreen
        // apps" — that semantic appears to keep it below the menu bar/Dock's own compositing no
        // matter how high the window level is set. Dropped in favor of the plain combination a
        // working reference overlay app (epilande/Annotate) actually uses successfully.
        collectionBehavior = [.canJoinAllSpaces, .transient]
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        // Without this, AppKit only generates mouseMoved while a button is down — in Enabled mode
        // this window owns the whole screen, so the cursor-tip preview would only reposition on
        // whatever other event happened to fire, reading as laggy/stuck instead of tracking live.
        acceptsMouseMovedEvents = true
        contentView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), appState: appState, hudController: hudController, widthPreviewController: widthPreviewController, textPreviewController: textPreviewController)
    }

    override var canBecomeKey: Bool { true }
    // Some AppKit chrome — notably the text-insertion-point blink — is tied to "main window"
    // status rather than just "key window", and can render unreliably without it.
    override var canBecomeMain: Bool { true }

    /// A single "highest" level constant isn't reliably above the Dock/menu bar across macOS
    /// versions (confirmed: assistiveTechHighWindow alone wasn't enough here) — the relative
    /// ordering of these CG level keys isn't guaranteed monotonic, so take the max of every
    /// plausibly-high one and go one above that instead of betting on a single key.
    static var maxCoveringWindowLevel: NSWindow.Level {
        let levels = [
            CGWindowLevelForKey(.mainMenuWindow),
            CGWindowLevelForKey(.statusWindow),
            CGWindowLevelForKey(.popUpMenuWindow),
            CGWindowLevelForKey(.assistiveTechHighWindow),
            CGWindowLevelForKey(.screenSaverWindow)
        ]
        let maxLevel = levels.map { Int($0) + 1 }.max() ?? Int(CGWindowLevelForKey(.statusWindow)) + 1
        return NSWindow.Level(rawValue: maxLevel)
    }
}
