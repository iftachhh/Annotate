import AppKit

/// A circle that tracks the cursor for 2 seconds after a width shortcut, previewing the stroke's
/// on-canvas size (diameter = width) in the tool's current color at low opacity.
///
/// Two mouse-move monitors cover both states the overlay windows can be in: a local one for while
/// the overlay itself is receiving events (Enabled mode), a global one for everywhere else
/// (Interactive mode passes events through to whatever's beneath, which AppKit treats as "outside
/// our app" for monitor purposes).
final class WidthPreviewController {
    private var window: NSWindow?
    private var circleView: CircleView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?
    private var currentDiameter: CGFloat = 0

    func show(color: NSColor, width: CGFloat, persistent: Bool = false) {
        show(color: color, diameter: max(width, 2), strokeWidth: nil, persistent: persistent)
    }

    /// Same tracking circle, but an outline instead of a fill — the counter tool's preview, since
    /// a counter renders as a stroked ring (see AnnotationRenderer's `.counter` case), not a solid
    /// dot.
    func showRing(color: NSColor, diameter: CGFloat, strokeWidth: CGFloat, persistent: Bool = false) {
        show(color: color, diameter: diameter, strokeWidth: strokeWidth, persistent: persistent)
    }

    /// `persistent` skips the 1s auto-hide (Always Show Tool Tip mode) — the cursor-tracking
    /// monitors below keep it following the pointer indefinitely until `dismiss()` is called.
    private func show(color: NSColor, diameter: CGFloat, strokeWidth: CGFloat?, persistent: Bool) {
        hideWorkItem?.cancel()
        // AnnotationRenderer strokes a `diameter`-wide circle with a centered stroke, so the
        // outermost visible edge actually reaches diameter + strokeWidth — size the window to
        // that so the preview's outer edge matches the real thing, not just its nominal diameter.
        currentDiameter = diameter + (strokeWidth ?? 0)

        let win = window ?? makeWindow()
        window = win
        let view = circleView ?? CircleView(frame: .zero)
        circleView = view
        view.color = color.withAlphaComponent(0.5)
        view.strokeWidth = strokeWidth
        win.contentView = view
        win.setContentSize(NSSize(width: currentDiameter, height: currentDiameter))
        reposition()
        win.orderFrontRegardless()

        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.reposition()
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.reposition()
            }
        }

        guard !persistent else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Called the instant the user actually starts drawing/erasing — the preview has done its job
    /// once real ink is going down, so it shouldn't linger on top of it.
    func dismiss() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hide()
    }

    private func reposition() {
        guard let win = window else { return }
        let loc = NSEvent.mouseLocation
        // 1px above the cursor's own center, not dead-centered on it — matches where a real
        // pen nib sits relative to the pointer hotspot instead of sitting exactly under it.
        win.setFrameOrigin(NSPoint(x: loc.x - currentDiameter / 2, y: loc.y - currentDiameter / 2 + 1))
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = NSWindow.Level(rawValue: OverlayWindow.maxCoveringWindowLevel.rawValue + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .transient]
        win.ignoresMouseEvents = true
        return win
    }

    private func hide() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        window?.orderOut(nil)
    }
}

private final class CircleView: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    /// nil draws a filled dot (width preview); a value draws a stroked ring of that width instead
    /// (counter preview, matching its stroked-circle rendering).
    var strokeWidth: CGFloat? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.set()
        guard let strokeWidth else {
            NSBezierPath(ovalIn: bounds).fill()
            return
        }
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2))
        path.lineWidth = strokeWidth
        path.stroke()
    }
}
