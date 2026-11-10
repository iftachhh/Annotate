import AppKit

/// Text tool: inline editing, RTL support, font-style/size/bold live shortcuts, and the pre-typing
/// caret stand-in. Split out of OverlayView.swift.
extension OverlayView {
    private func currentTextFont(for text: String) -> NSFont {
        textFontStyle.font(size: textEntryFontSize, bold: isBoldTextEntry, text: text)
    }

    /// Same raw string measurement AnnotationRenderer uses for the final draw — the live editor is
    /// sized tightly to this (not a fixed box), so editing and final rendering agree by construction.
    private static func measureText(_ text: String, font: NSFont) -> CGSize {
        let s = text.isEmpty ? " " : text
        let size = (s as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width) + 4, height: ceil(size.height))
    }

    /// NSTextFieldCell insets its drawn text a little from the field's own bounds (for cursor
    /// room), and that inset isn't included in `measureText`. AnnotationRenderer draws the raw
    /// string with no inset at all, so without correcting for it, committed text lands a few
    /// points off from where it visibly sat while editing. `titleRect(forBounds:)` reports the
    /// cell's actual on-screen text sub-rect, which is exactly what we need to correct against.
    private func textInset(for field: NSTextField) -> CGPoint {
        let bounds = CGRect(origin: .zero, size: field.frame.size)
        let rect = (field.cell as? NSTextFieldCell)?.titleRect(forBounds: bounds) ?? bounds
        return rect.origin
    }

    /// Repositions the field so its visible text (not its bounding box) sits at `textAnchorLocal`.
    /// Called after every resize (typing, bold toggle, font-size change) so the glyphs never
    /// visibly drift from the point the user actually clicked or the original annotation sat at.
    /// RTL (Hebrew) text anchors from its RIGHT edge instead, so it grows leftward as typed —
    /// matching AnnotationRenderer/Annotation.boundingBox, which use the same convention.
    private func repositionActiveTextField() {
        guard let field = activeTextField else { return }
        let inset = textInset(for: field)
        let x = field.stringValue.isRTLText
            ? textAnchorLocal.x - field.frame.width + inset.x
            : textAnchorLocal.x - inset.x
        field.setFrameOrigin(NSPoint(x: x, y: textAnchorLocal.y - inset.y))
    }

    /// Only touches the live field EDITOR's alignment/direction, never the NSTextField cell's —
    /// reassigning the cell's own `.alignment` while a field editor is actively attached mid-keystroke
    /// makes AppKit resynchronize the editing session, which was dropping the just-typed character to
    /// `doCommandBy:` (default handler beeps) and briefly resigning first responder. That's exactly
    /// what broke Hebrew: the very first RTL character flips this for the first time.
    private func updateTextDirection(for field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let rtl = field.stringValue.isRTLText
        editor.alignment = rtl ? .right : .left
        editor.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
    }

    private func updateActiveTextFieldSize() {
        guard let field = activeTextField else { return }
        let font = currentTextFont(for: field.stringValue)
        field.font = font
        field.setFrameSize(Self.measureText(field.stringValue, font: font))
        updateTextDirection(for: field)
        repositionActiveTextField()
        positionCaretIndicator()
    }

    /// Pure geometry — repositions the static pre-typing caret stand-in to match the current
    /// end-of-text point (RTL grows left, LTR grows right, same convention as
    /// repositionActiveTextField). No-ops once the indicator has been torn down after first typing.
    private func positionCaretIndicator() {
        guard let field = activeTextField, let caret = caretIndicatorView else { return }
        let font = currentTextFont(for: field.stringValue)
        let textWidth = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
        let height = Self.measureText("", font: font).height
        // Small manual nudge — lines this up with where the native caret actually renders (a pixel
        // or two off otherwise, which read as one oddly-thick caret during the handoff).
        let nudge: CGFloat = 1
        let width: CGFloat = 3
        let x = field.stringValue.isRTLText ? textAnchorLocal.x - textWidth - width - nudge : textAnchorLocal.x + textWidth + nudge
        caret.frame = NSRect(x: x, y: textAnchorLocal.y, width: width, height: height)
    }

    func beginTextEntry(at local: CGPoint, editing existing: Annotation? = nil) {
        isBoldTextEntry = existing?.isBold ?? appState.toolSettings.bold(for: .text)
        textEntryFontSize = existing?.fontSize ?? currentFontSize()
        textFontStyle = existing?.fontStyle ?? appState.toolSettings.fontStyle(for: .text)
        isEditingExistingText = existing != nil
        let entryColor = existing?.color ?? currentColor()
        let initialText = existing?.text ?? ""
        let font = currentTextFont(for: initialText)
        let size = Self.measureText(initialText, font: font)
        textAnchorLocal = existing.flatMap { $0.points.first.map(toLocal) } ?? local

        let field = NSTextField(frame: NSRect(origin: .zero, size: size))
        field.stringValue = initialText
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = entryColor
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        activeTextField = field
        repositionActiveTextField()
        window?.makeKey()
        window?.makeFirstResponder(field)
        // Default first-responder behavior selects the whole string (a highlighted block) instead
        // of a plain caret at the end — force that explicitly when re-opening existing text.
        if let editor = field.currentEditor() as? NSTextView {
            let end = (field.stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
            editor.insertionPointColor = entryColor
        }
        updateTextDirection(for: field)

        let caret = NSView()
        caret.wantsLayer = true
        caret.layer?.backgroundColor = entryColor.cgColor
        addSubview(caret)
        caretIndicatorView = caret
        positionCaretIndicator()

        if let existing {
            appState.pushUndoSnapshot()
            appState.annotations.removeAll { $0.id == existing.id }
            redrawAll()
        }

        textEditMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.activeTextField != nil else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command] || flags == [.option] else { return event }

            if flags == [.option], let index = PhysicalKeyCode.digits.firstIndex(of: event.keyCode),
               index < TextFontStyle.allCases.count {
                let style = TextFontStyle.allCases[index]
                self.textFontStyle = style
                self.appState.toolSettings.setFontStyle(for: .text, style)
                self.updateActiveTextFieldSize()
                self.hudController.show(text: style.displayName)
                return nil
            }

            guard flags == [.command] else { return event }

            if event.keyCode == PhysicalKeyCode.b {
                self.isBoldTextEntry.toggle()
                self.updateActiveTextFieldSize()
                return nil
            }
            if event.keyCode == PhysicalKeyCode.minus || event.keyCode == PhysicalKeyCode.equal {
                let delta: CGFloat = event.keyCode == PhysicalKeyCode.minus ? -1 : 1
                self.textEntryFontSize = min(48, max(8, self.textEntryFontSize + delta))
                self.appState.toolSettings.setFontSize(for: .text, self.textEntryFontSize)
                self.updateActiveTextFieldSize()
                self.hudController.show(text: "Size \(Int(self.textEntryFontSize))")
                return nil
            }
            if let index = PhysicalKeyCode.digits.firstIndex(of: event.keyCode), index < ColorPalette.entries.count {
                let entry = ColorPalette.entries[index]
                self.appState.toolSettings.setColor(for: .text, entry.color.hexString)
                self.activeTextField?.textColor = entry.color
                (self.activeTextField?.currentEditor() as? NSTextView)?.insertionPointColor = entry.color
                self.caretIndicatorView?.layer?.backgroundColor = entry.color.cgColor
                self.hudController.show(text: entry.name)
                return nil
            }
            return event
        }
    }

    /// Called by OverlayManager when leaving Enabled mode, so a half-typed annotation isn't lost/orphaned.
    func finishAnyActiveTextEntry() {
        finishTextEntry()
    }

    private func finishTextEntry() {
        guard let field = activeTextField else { return }
        if let monitor = textEditMonitor { NSEvent.removeMonitor(monitor); textEditMonitor = nil }

        let text = field.stringValue
        if !text.isEmpty {
            // textAnchorLocal IS the field's visible-text position at all times (repositionActiveTextField
            // keeps it that way), and AnnotationRenderer draws its rect from exactly this same point —
            // so editing and final rendering agree by construction, not by re-deriving the offset here.
            let global = toGlobal(textAnchorLocal)
            // Editing an existing annotation already took its undo snapshot before removing it —
            // one user action (the edit) should be one undo step, not two.
            if !isEditingExistingText { appState.pushUndoSnapshot() }
            let annotation = Annotation(kind: .text, points: [global], color: field.textColor ?? currentColor(), lineWidth: currentWidth(), text: text, fontSize: textEntryFontSize, isBold: isBoldTextEntry, fontStyle: textFontStyle)
            appState.annotations.append(annotation)
            // Editing an existing text annotation's current style becomes the base for new text
            // going forward, even if nothing was actually changed this round (color/font-style also
            // do this live via their keyboard shortcuts above, but syncing all of it here too covers
            // "opened it, didn't touch the shortcut, just retyped the words" edits).
            if isEditingExistingText {
                appState.toolSettings.setFontSize(for: .text, textEntryFontSize)
                appState.toolSettings.setBold(for: .text, isBoldTextEntry)
                appState.toolSettings.setFontStyle(for: .text, textFontStyle)
                appState.toolSettings.setColor(for: .text, annotation.color.hexString)
            }
        }
        field.removeFromSuperview()
        activeTextField = nil
        isEditingExistingText = false
        caretIndicatorView?.removeFromSuperview()
        caretIndicatorView = nil
        window?.makeFirstResponder(self)
        redrawAll()
        refreshCursorTip()
    }

    func controlTextDidChange(_ obj: Notification) {
        // The user just typed/deleted something for the first time this session — the native caret
        // has caught up by now, so the static stand-in has done its job and can go for good.
        caretIndicatorView?.removeFromSuperview()
        caretIndicatorView = nil
        updateActiveTextFieldSize()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEntry()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishTextEntry()
            return true
        }
        return false
    }
}
