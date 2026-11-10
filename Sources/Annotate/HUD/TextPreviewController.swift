import AppKit

/// The word "Text" that tracks the cursor for 2 seconds after a text-tool font shortcut (size,
/// style, or color), previewing what the next typed layer will look like — 50% opacity, next to
/// (not on top of) the pointer. Same tracking approach as WidthPreviewController: a local monitor
/// for while the overlay itself receives events, a global one for everywhere else.
final class TextPreviewController {
    private var window: NSWindow?
    private var textView: PreviewTextView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?

    /// `persistent` skips the 1s auto-hide (Always Show Tool Tip mode) — the cursor-tracking
    /// monitors below keep it following the pointer indefinitely until `dismiss()` is called.
    func show(color: NSColor, font: NSFont, persistent: Bool = false) {
        hideWorkItem?.cancel()

        let win = window ?? makeWindow()
        window = win
        let view = textView ?? PreviewTextView(frame: .zero)
        textView = view
        view.textColor = color.withAlphaComponent(0.5)
        view.font = font
        let size = view.fittingSize
        win.contentView = view
        win.setContentSize(size)
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

    /// Called the instant the user actually starts drawing/typing — the preview has done its job
    /// once real work is happening, so it shouldn't linger on top of it.
    func dismiss() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hide()
    }

    /// Matches AnnotationRenderer's `.text` case exactly: the click point IS the text's bottom-left
    /// origin, growing up-right from there — so the preview's window origin is just the raw cursor
    /// location, no offset.
    private func reposition() {
        window?.setFrameOrigin(NSEvent.mouseLocation)
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

private final class PreviewTextView: NSView {
    private let label = "Text"
    var textColor: NSColor = .clear { didSet { needsDisplay = true } }
    var font: NSFont = .systemFont(ofSize: 20) { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }

    override var fittingSize: NSSize { (label as NSString).size(withAttributes: [.font: font]) }
    override var intrinsicContentSize: NSSize { fittingSize }

    override func draw(_ dirtyRect: NSRect) {
        // draw(in:) with a fully-specified rect (not draw(at:)) — same call AnnotationRenderer
        // uses for the real annotation, anchoring the text's bottom-left at the origin exactly
        // like the committed text does, instead of draw(at:)'s ambiguous vertical anchor.
        NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: textColor])
            .draw(in: CGRect(origin: .zero, size: bounds.size))
    }
}
