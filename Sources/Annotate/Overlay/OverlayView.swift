import AppKit

/// Core of the overlay: stored state, view lifecycle, coordinate conversion, drawing, and the main
/// mouse-event dispatch. Everything else (eraser/rasterization, the text tool, keyboard shortcuts,
/// the Cmd/Option temporary-select override, and the context menu trigger) lives in the
/// OverlayView+*.swift extensions alongside this file — split out since each area changes for its
/// own reason and together they'd made this one file unreadably large.
///
/// Properties below are `internal` (no `private`) wherever an extension in another file needs them
/// — Swift's `private` is scoped to the file it's declared in, not the type, and stored properties
/// must live in this primary declaration (extensions can't add stored properties). Only the four
/// marked `private` are touched exclusively by mouseDown/mouseDragged/mouseUp right here.
final class OverlayView: NSView, NSTextFieldDelegate {
    let appState: AppState
    let hudController: HUDController
    let widthPreviewController: WidthPreviewController
    let textPreviewController: TextPreviewController

    private var dragStartGlobal: CGPoint = .zero
    var selectedAnnotationID: UUID?
    private var selectedEndpointIndex: Int?
    private var didDragSelection = false
    private var pendingTextEdit: Annotation?

    var activeTextField: NSTextField?
    var isBoldTextEntry = true
    var textEntryFontSize: CGFloat = 20
    var textFontStyle: TextFontStyle = .sansSerif
    var isEditingExistingText = false
    var textAnchorLocal: CGPoint = .zero
    var textEditMonitor: Any?
    /// The native insertion point renders unreliably right when a field first becomes first
    /// responder (before any typing). This is a static (non-blinking) stand-in shown only for that
    /// initial gap — the moment the user types their first character, the native (now correctly
    /// colored) caret has caught up and this is torn down for good.
    var caretIndicatorView: NSView?

    /// True right after this view becomes key while Cmd/Option is still physically down — see
    /// viewDidMoveToWindow. Cleared the first time both are observed fully released.
    var suppressModifierOverrideUntilRelease = false
    var isCommandTemporarySelect = false
    var toolBeforeCommandOverride: ToolType?
    var pendingCommandRevert = false
    var isOptionTemporarySelect = false
    var toolBeforeOptionOverride: ToolType?
    var pendingOptionRevert = false

    var lastEraseGlobal: CGPoint?
    /// Tracks whether the cursor tip is currently hidden because the cursor is hovering an
    /// existing annotation — see mouseMoved. Only toggled on actual hover transitions, not every
    /// pixel of movement, so it doesn't fight the tracking monitors' own repositioning.
    var isCursorTipSuppressedByHover = false

    init(frame: NSRect, appState: AppState, hudController: HUDController, widthPreviewController: WidthPreviewController, textPreviewController: TextPreviewController) {
        self.appState = appState
        self.hudController = hudController
        self.widthPreviewController = widthPreviewController
        self.textPreviewController = textPreviewController
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        // The global activation shortcut's default modifiers are Cmd+Option — if either is still
        // physically held right as this freshly-built view becomes key, releasing it moments later
        // fires a genuine flagsChanged transition that flagsChanged would otherwise misread as the
        // user invoking the Cmd/Option temporary-select-tool gesture, silently switching off the
        // configured default tool. Ignore modifier state until a full release is observed once.
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.option) {
            suppressModifierOverrideUntilRelease = true
        }
    }

    // MARK: - Coordinate conversion

    private var windowOrigin: CGPoint { window?.frame.origin ?? .zero }

    func toGlobal(_ local: CGPoint) -> CGPoint {
        CGPoint(x: local.x + windowOrigin.x, y: local.y + windowOrigin.y)
    }

    func toLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - windowOrigin.x, y: global.y - windowOrigin.y)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let offset = windowOrigin
        for annotation in appState.annotations {
            AnnotationRenderer.draw(annotation, in: ctx, offset: offset)
        }
        if let inProgress = appState.inProgress {
            AnnotationRenderer.draw(inProgress, in: ctx, offset: offset)
        }
    }

    func redrawAll() {
        appState.contentDidChange?()
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        widthPreviewController.dismiss()
        textPreviewController.dismiss()
        let local = convert(event.locationInWindow, from: nil)
        let global = toGlobal(local)
        dragStartGlobal = global

        switch appState.currentTool {
        case .pen, .highlighter:
            let kind: AnnotationKind = appState.currentTool == .pen ? .pen : .highlighter
            appState.inProgress = Annotation(kind: kind, points: [global], color: currentColor(), lineWidth: currentWidth(), lineStyle: currentLineStyle())
        case .line, .arrow, .rectangle, .circle:
            appState.inProgress = Annotation(kind: annotationKind(for: appState.currentTool), points: [global, global], color: currentColor(), lineWidth: currentWidth(), lineStyle: currentLineStyle())
        case .text:
            guard activeTextField == nil else { return }
            // Defer the decision: a plain click-release (no drag) on existing text opens the editor;
            // an actual drag moves it instead. Both start the same way — select + remember the candidate.
            if let hit = appState.annotations.last(where: { $0.hitTest(global) }) {
                selectedAnnotationID = hit.id
                selectedEndpointIndex = nearestEndpointIndex(of: hit, to: global)
                pendingTextEdit = hit.kind == .text ? hit : nil
                didDragSelection = false
            } else {
                beginTextEntry(at: local)
            }
        case .counter:
            appState.pushUndoSnapshot()
            let annotation = Annotation(kind: .counter, points: [global], color: currentColor(), lineWidth: currentWidth(), counterValue: appState.nextCounterValue, fontSize: currentFontSize())
            appState.nextCounterValue += 1
            appState.annotations.append(annotation)
            redrawAll()
        case .select:
            if let hit = appState.annotations.last(where: { $0.hitTest(global) }) {
                selectedEndpointIndex = nearestEndpointIndex(of: hit, to: global)
                // Option-drag on the shape's body (not a resize handle) duplicates it in place and
                // drags the copy, leaving the original untouched — endpoint drags never duplicate.
                if event.modifierFlags.contains(.option), selectedEndpointIndex == nil {
                    appState.pushUndoSnapshot()
                    let duplicate = Annotation(kind: hit.kind, points: hit.points, color: hit.color, lineWidth: hit.lineWidth, text: hit.text, counterValue: hit.counterValue, fontSize: hit.fontSize, isBold: hit.isBold, lineStyle: hit.lineStyle, fontStyle: hit.fontStyle, image: hit.image)
                    appState.annotations.append(duplicate)
                    selectedAnnotationID = duplicate.id
                    didDragSelection = true // snapshot already pushed above — mouseDragged shouldn't push another
                } else {
                    selectedAnnotationID = hit.id
                    didDragSelection = false
                }
            } else {
                selectedAnnotationID = nil
                selectedEndpointIndex = nil
            }
        case .eraser:
            appState.pushUndoSnapshot()
            lastEraseGlobal = global
            eraseHit(at: global)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let global = toGlobal(local)

        switch appState.currentTool {
        case .pen, .highlighter:
            // Shift collapses the stroke-so-far into a straight 45°-snapped segment from the
            // stroke's start, same snapping as the line tool — releasing shift resumes freehand
            // from wherever that segment currently ends.
            if event.modifierFlags.contains(.shift) {
                appState.inProgress?.points = [dragStartGlobal, Self.constrainedEndpoint(from: dragStartGlobal, to: global, tool: .line, shiftHeld: true)]
            } else if appState.inProgress?.points.last?.distance(to: global) ?? .infinity > 1 {
                // Skip near-duplicate points — a zero/near-zero-length leading segment (the first
                // mouseDragged event often lands right on top of mouseDown's point) has an undefined
                // cap direction, which flares out oddly now that highlighter/pen use a flat cap.
                appState.inProgress?.points.append(global)
            }
            redrawAll()
        case .line, .arrow, .rectangle, .circle:
            guard let start = appState.inProgress?.points.first else { return }
            let shiftHeld = event.modifierFlags.contains(.shift)
            appState.inProgress?.points[1] = Self.constrainedEndpoint(from: start, to: global, tool: appState.currentTool, shiftHeld: shiftHeld)
            redrawAll()
        case .select, .text:
            guard let id = selectedAnnotationID,
                  let index = appState.annotations.firstIndex(where: { $0.id == id }) else { return }
            if !didDragSelection {
                appState.pushUndoSnapshot()
                didDragSelection = true
            }
            if let endpointIndex = selectedEndpointIndex {
                appState.annotations[index].points[endpointIndex] = global
            } else {
                let delta = CGVector(dx: global.x - dragStartGlobal.x, dy: global.y - dragStartGlobal.y)
                appState.annotations[index].translate(by: delta)
                dragStartGlobal = global
            }
            redrawAll()
        case .eraser:
            eraseAlongPath(to: global)
        default:
            break
        }
    }

    /// Text-tool-only: the cursor tip normally tracks the pointer everywhere, but sitting right at
    /// the cursor when it's hovering an existing text layer visually collides with it — obscuring
    /// exactly the target the user is about to click, and misleading them about where its real
    /// hitbox is. Suppress it for that hover, restore it once the cursor moves off again.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard appState.showAlwaysTip, appState.mode == .enabled, appState.currentTool == .text, activeTextField == nil else { return }
        let global = toGlobal(convert(event.locationInWindow, from: nil))
        let hovering = appState.annotations.contains { $0.hitTest(global) }
        if hovering, !isCursorTipSuppressedByHover {
            isCursorTipSuppressedByHover = true
            widthPreviewController.dismiss()
            textPreviewController.dismiss()
        } else if !hovering, isCursorTipSuppressedByHover {
            isCursorTipSuppressedByHover = false
            refreshCursorTip()
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch appState.currentTool {
        case .pen, .highlighter, .line, .arrow, .rectangle, .circle:
            if let annotation = appState.inProgress {
                appState.pushUndoSnapshot()
                appState.annotations.append(annotation)
            }
            appState.inProgress = nil
            redrawAll()
        case .select, .text:
            if appState.currentTool == .text, !didDragSelection, let pending = pendingTextEdit {
                beginTextEntry(at: convert(event.locationInWindow, from: nil), editing: pending)
            }
            selectedAnnotationID = nil
            selectedEndpointIndex = nil
            pendingTextEdit = nil
            didDragSelection = false
            // A Cmd/Option-release arrived mid-drag (see flagsChanged) — the drag just finished, safe now.
            if pendingCommandRevert { revertCommandTemporarySelect() }
            if pendingOptionRevert { revertOptionTemporarySelect() }
        default:
            break
        }
        refreshCursorTip()
    }

    private func annotationKind(for tool: ToolType) -> AnnotationKind {
        switch tool {
        case .line: return .line
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        default: return .circle
        }
    }

    /// Shift constrains: line/arrow snap to 45° increments (same drag length, clamped angle);
    /// rectangle/circle snap to a 1:1 aspect ratio (square bounding box) anchored at `start`.
    private static func constrainedEndpoint(from start: CGPoint, to point: CGPoint, tool: ToolType, shiftHeld: Bool) -> CGPoint {
        guard shiftHeld else { return point }
        let dx = point.x - start.x, dy = point.y - start.y
        switch tool {
        case .line, .arrow:
            let distance = hypot(dx, dy)
            guard distance > 0 else { return point }
            let step = CGFloat.pi / 4
            let snappedAngle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: start.x + distance * cos(snappedAngle), y: start.y + distance * sin(snappedAngle))
        case .rectangle, .circle:
            let size = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -size : size), y: start.y + (dy < 0 ? -size : size))
        default:
            return point
        }
    }

    private func nearestEndpointIndex(of annotation: Annotation, to point: CGPoint) -> Int? {
        guard [.line, .arrow, .rectangle, .circle].contains(annotation.kind), annotation.points.count == 2 else { return nil }
        for (index, p) in annotation.points.enumerated() where p.distance(to: point) <= 12 {
            return index
        }
        return nil
    }

    // MARK: - Settings helpers

    func currentColor() -> NSColor { NSColor(hex: appState.toolSettings.color(for: appState.currentTool)) }
    func currentWidth() -> CGFloat { appState.toolSettings.width(for: appState.currentTool) }
    func currentFontSize() -> CGFloat { appState.toolSettings.fontSize(for: appState.currentTool) }
    private func currentLineStyle() -> LineStyle { appState.toolSettings.lineStyle(for: appState.currentTool) }
}
