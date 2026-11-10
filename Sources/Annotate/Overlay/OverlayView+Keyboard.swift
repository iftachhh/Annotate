import AppKit

/// Keyboard shortcuts: tool switching, digit/Option+digit setting shortcuts, width/size nudging,
/// undo/redo/clear, and Esc. Split out of OverlayView.swift.
extension OverlayView {
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isBackspace = event.keyCode == 51

        if flags == [.command, .option], isBackspace {
            appState.clearAll()
            appState.setMode?(.disabled)
            return
        }

        if flags.contains(.command) {
            if isBackspace {
                appState.clearAll()
                hudController.show(text: "Canvas Cleared")
                redrawAll()
                return
            }
            if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "z" {
                flags.contains(.shift) ? appState.redo() : appState.undo()
                redrawAll()
                return
            }
        }

        if isBackspace {
            appState.undo(); redrawAll(); return
        }

        if event.keyCode == 53 { // esc
            appState.setMode?(.disabled); return
        }

        if let tool = ToolType.from(keyCode: event.keyCode) {
            selectTool(tool)
            return
        }

        if handleToolSettingShortcut(event) { return }

        super.keyDown(with: event)
    }

    /// Holding Cmd (see flagsChanged) overrides `appState.currentTool` to `.select` for the
    /// Cmd-drag-to-move feature, but Cmd+digit is also the color shortcut — so shortcut resolution
    /// needs the tool from BEFORE that override, or Cmd+1 would silently target Select (no color)
    /// instead of whatever tool was actually active.
    private var effectiveShortcutTool: ToolType {
        if isCommandTemporarySelect { return toolBeforeCommandOverride ?? appState.currentTool }
        if isOptionTemporarySelect { return toolBeforeOptionOverride ?? appState.currentTool }
        return appState.currentTool
    }

    /// Digit picks a color, Option+digit picks a line/shape style, -/+ adjusts width-or-size. The
    /// popup (if open) closes on use, matching how clicking a color swatch already dismisses it.
    @discardableResult
    func handleToolSettingShortcut(_ event: NSEvent) -> Bool {
        let tool = effectiveShortcutTool
        if event.modifierFlags.contains(.option), let index = PhysicalKeyCode.digits.firstIndex(of: event.keyCode) {
            if tool.usesFontStyle {
                guard index < TextFontStyle.allCases.count else { return false }
                let style = TextFontStyle.allCases[index]
                appState.toolSettings.setFontStyle(for: tool, style)
                hudController.show(text: style.displayName)
                if tool == .text {
                    textPreviewController.show(color: NSColor(hex: appState.toolSettings.color(for: tool)), font: textPreviewFont(for: tool), persistent: appState.showAlwaysTip)
                }
                return true
            }
            guard tool.usesLineStyle || tool.usesShapeStyle else { return false }
            let options = LineStyle.options(allowsFilled: tool.usesShapeStyle)
            guard index < options.count else { return false }
            let style = options[index]
            appState.toolSettings.setLineStyle(for: tool, style)
            hudController.show(text: style.displayName)
            return true
        }
        if tool.usesColor, let index = PhysicalKeyCode.digits.firstIndex(of: event.keyCode),
           index < ColorPalette.entries.count {
            let entry = ColorPalette.entries[index]
            appState.toolSettings.setColor(for: tool, entry.color.hexString)
            hudController.show(text: entry.name)
            if tool.usesWidth {
                widthPreviewController.show(color: widthPreviewColor(for: tool), width: widthPreviewDiameter(for: tool, appState.toolSettings.width(for: tool)), persistent: appState.showAlwaysTip)
            } else if tool == .text {
                textPreviewController.show(color: entry.color, font: textPreviewFont(for: tool), persistent: appState.showAlwaysTip)
            } else if tool == .counter {
                showCounterPreview(color: entry.color)
            }
            return true
        }
        if event.keyCode == PhysicalKeyCode.minus || event.keyCode == PhysicalKeyCode.leftBracket {
            adjustCurrentSetting(by: -1); return true
        }
        if event.keyCode == PhysicalKeyCode.equal || event.keyCode == PhysicalKeyCode.rightBracket {
            adjustCurrentSetting(by: 1); return true
        }
        return false
    }

    /// Eraser has no real user-facing color (it's transparent on canvas) — the tip previews white
    /// instead of whatever `sharedColorHex` happens to hold.
    private func widthPreviewColor(for tool: ToolType) -> NSColor {
        tool == .eraser ? .white : NSColor(hex: appState.toolSettings.color(for: tool))
    }

    /// AnnotationRenderer draws the highlighter 3x thicker than its stored width (see .highlighter
    /// case) — the preview needs the same multiplier or it undersells the actual stroke.
    private func widthPreviewDiameter(for tool: ToolType, _ width: CGFloat) -> CGFloat {
        tool == .highlighter ? width * 3 : width
    }

    /// Mirrors AnnotationRenderer's `.counter` case exactly: diameter = fontSize * 1.6, stroke
    /// width = max(2, diameter * 0.14) — reuses WidthPreviewController's ring mode rather than a
    /// separate controller since it's the same tracking-circle machinery.
    private func showCounterPreview(color: NSColor) {
        let diameter = appState.toolSettings.fontSize(for: .counter) * 1.6
        widthPreviewController.showRing(color: color, diameter: diameter, strokeWidth: max(2, diameter * 0.14), persistent: appState.showAlwaysTip)
    }

    private func adjustCurrentSetting(by delta: CGFloat) {
        let tool = effectiveShortcutTool
        if tool.usesWidth {
            let newValue = min(15, max(1, appState.toolSettings.width(for: tool) + delta))
            appState.toolSettings.setWidth(for: tool, newValue)
            hudController.show(text: "Width \(Int(newValue))")
            widthPreviewController.show(color: widthPreviewColor(for: tool), width: widthPreviewDiameter(for: tool, newValue), persistent: appState.showAlwaysTip)
        } else if tool.usesFontSize {
            let newValue = min(48, max(8, appState.toolSettings.fontSize(for: tool) + delta))
            appState.toolSettings.setFontSize(for: tool, newValue)
            hudController.show(text: "Size \(Int(newValue))")
            if tool == .text {
                textPreviewController.show(color: NSColor(hex: appState.toolSettings.color(for: tool)), font: textPreviewFont(for: tool), persistent: appState.showAlwaysTip)
            } else if tool == .counter {
                showCounterPreview(color: NSColor(hex: appState.toolSettings.color(for: tool)))
            }
        }
    }

    private func textPreviewFont(for tool: ToolType) -> NSFont {
        appState.toolSettings.fontStyle(for: tool).font(size: appState.toolSettings.fontSize(for: tool), bold: appState.toolSettings.bold(for: tool))
    }

    func selectTool(_ tool: ToolType) {
        appState.currentTool = tool
        // "Filled" only exists for rectangle/circle — a line-based tool inheriting it from the
        // shared style sync group would show no style selected at all, so drop it back to solid.
        if tool.usesLineStyle, !tool.usesShapeStyle, appState.toolSettings.lineStyle(for: tool) == .filled {
            appState.toolSettings.setLineStyle(for: tool, .solid)
        }
        hudController.show(text: tool.displayName)
        refreshCursorTip()
    }

    /// "Always Show Tool Tip" mode: (re)shows the cursor-tracking width/size preview for whatever
    /// tool is now current, or hides it — called on tool switch, mode change, and after every draw
    /// finishes. Always dismisses first so switching tools (or turning the setting off) doesn't
    /// leave the previous tool's preview stuck on screen.
    func refreshCursorTip() {
        isCursorTipSuppressedByHover = false
        widthPreviewController.dismiss()
        textPreviewController.dismiss()
        guard appState.showAlwaysTip, appState.mode == .enabled, activeTextField == nil else { return }
        let tool = appState.currentTool
        if tool.usesWidth {
            widthPreviewController.show(color: widthPreviewColor(for: tool), width: widthPreviewDiameter(for: tool, appState.toolSettings.width(for: tool)), persistent: true)
        } else if tool == .counter {
            showCounterPreview(color: NSColor(hex: appState.toolSettings.color(for: tool)))
        } else if tool == .text {
            textPreviewController.show(color: NSColor(hex: appState.toolSettings.color(for: tool)), font: textPreviewFont(for: tool), persistent: true)
        }
    }

    @objc func contextMenuSelectTool(_ sender: NSMenuItem) {
        guard let tool = sender.representedObject as? ToolType else { return }
        selectTool(tool)
    }

    @objc func deleteHitLayer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        appState.pushUndoSnapshot()
        appState.annotations.removeAll { $0.id == id }
        redrawAll()
    }
}
